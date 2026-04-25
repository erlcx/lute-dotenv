--!strict
-- dotenv-style helpers for loading .env files into process.env

local fs = require("@std/fs")
local path = require("@std/path")
local process = require("@std/process")

local dotenv = {}

export type Environment = { [string]: string }
export type Pathlike = path.Pathlike
export type PathInput = Pathlike | { Pathlike }

export type ParseOptions = {
	expand: boolean?,
	strict: boolean?,
	env: Environment?,
}

export type ApplyOptions = {
	target: Environment?,
	override: boolean?,
}

export type LoadOptions = ParseOptions & {
	override: boolean?,
}

export type ConfigOptions = ParseOptions & ApplyOptions & {
	path: PathInput?,
}

export type SerializeOptions = {
	export: boolean?,
	newline: string?,
}

type QuoteKind = "none" | "single" | "double"

type Entry = {
	line: number,
	value: string,
	quote: QuoteKind,
}

local UTF8_BOM = string.char(239, 187, 191)
local DOLLAR_SENTINEL = "\0"

local function trim(value: string): string
	local start = 1
	local finish = #value

	while start <= finish do
		local byte = string.byte(value, start)
		if byte ~= 32 and byte ~= 9 and byte ~= 10 and byte ~= 13 and byte ~= 11 and byte ~= 12 then
			break
		end
		start += 1
	end

	while finish >= start do
		local byte = string.byte(value, finish)
		if byte ~= 32 and byte ~= 9 and byte ~= 10 and byte ~= 13 and byte ~= 11 and byte ~= 12 then
			break
		end
		finish -= 1
	end

	if start == 1 and finish == #value then
		return value
	end

	return string.sub(value, start, finish)
end

local function normalizeInput(input: string): string
	local normalized = input
	if string.find(normalized, "\r", 1, true) then
		normalized = string.gsub(normalized, "\r\n", "\n")
		normalized = string.gsub(normalized, "\r", "\n")
	end

	if string.sub(normalized, 1, #UTF8_BOM) == UTF8_BOM then
		normalized = string.sub(normalized, #UTF8_BOM + 1)
	end

	return normalized
end

local function splitLines(input: string): { string }
	local lines = {}
	local start = 1

	while true do
		local newline = string.find(input, "\n", start, true)
		if not newline then
			break
		end

		lines[#lines + 1] = string.sub(input, start, newline - 1)
		start = newline + 1
	end

	if start <= #input then
		lines[#lines + 1] = string.sub(input, start)
	else
		lines[#lines + 1] = ""
	end

	return lines
end

local function decodeDoubleQuoted(contents: string): string
	if not string.find(contents, "\\", 1, true) then
		return contents
	end

	return (
		string.gsub(contents, "\\(.)", function(nextCh: string): string
			if nextCh == "n" then
				return "\n"
			elseif nextCh == "r" then
				return "\r"
			elseif nextCh == "t" then
				return "\t"
			elseif nextCh == '"' then
				return '"'
			elseif nextCh == "\\" then
				return "\\"
			elseif nextCh == "$" then
				return DOLLAR_SENTINEL
			end

			return "\\" .. nextCh
		end)
	)
end

local function decodeSingleQuoted(contents: string): string
	if not string.find(contents, "\\", 1, true) then
		return contents
	end

	return (string.gsub(contents, "\\(['\\])", "%1"))
end

local function parseUnquoted(rawValue: string): string
	local commentIndex: number? = nil
	local searchIndex = 1

	while true do
		local index = string.find(rawValue, "#", searchIndex, true)
		if not index then
			break
		end

		local prev = if index > 1 then string.sub(rawValue, index - 1, index - 1) else ""
		if index == 1 or prev == " " or prev == "\t" then
			commentIndex = index
			break
		end

		searchIndex = index + 1
	end

	local value = if commentIndex then string.sub(rawValue, 1, commentIndex - 1) else rawValue
	value = trim(value)

	if string.find(value, "\\", 1, true) then
		value = string.gsub(value, "\\([#$])", function(escaped: string): string
			if escaped == "$" then
				return DOLLAR_SENTINEL
			end

			return escaped
		end)
	end

	return value
end

local function isSpaceByte(byte: number?): boolean
	return byte == 32 or byte == 9 or byte == 10 or byte == 13 or byte == 11 or byte == 12
end

local function isAlphaByte(byte: number?): boolean
	return (byte ~= nil and byte >= 65 and byte <= 90) or (byte ~= nil and byte >= 97 and byte <= 122)
end

local function isDigitByte(byte: number?): boolean
	return byte ~= nil and byte >= 48 and byte <= 57
end

local function isNameStartByte(byte: number?): boolean
	return byte == 95 or isAlphaByte(byte)
end

local function isNameByte(byte: number?): boolean
	return byte == 95 or isAlphaByte(byte) or isDigitByte(byte)
end

local function isBlankOrComment(line: string): boolean
	local length = #line
	local index = 1

	while index <= length do
		local byte = string.byte(line, index)
		if not isSpaceByte(byte) then
			return byte == 35
		end
		index += 1
	end

	return true
end

local function isTrailingQuoteJunk(trailing: string): boolean
	for index = 1, #trailing do
		local byte = string.byte(trailing, index)
		if byte == 35 then
			return false
		end
		if not isSpaceByte(byte) then
			return true
		end
	end

	return false
end

local function parseAssignment(line: string): (string?, string?)
	local length = #line
	local index = 1

	while index <= length and isSpaceByte(string.byte(line, index)) do
		index += 1
	end

	if string.sub(line, index, index + 5) == "export" and isSpaceByte(string.byte(line, index + 6)) then
		index += 7
		while index <= length and isSpaceByte(string.byte(line, index)) do
			index += 1
		end
	end

	local keyStart = index
	if not isNameStartByte(string.byte(line, index)) then
		return nil, nil
	end

	index += 1
	while index <= length and isNameByte(string.byte(line, index)) do
		index += 1
	end

	local key = string.sub(line, keyStart, index - 1)

	while index <= length and isSpaceByte(string.byte(line, index)) do
		index += 1
	end

	if string.byte(line, index) ~= 61 then
		return nil, nil
	end

	index += 1
	while index <= length and isSpaceByte(string.byte(line, index)) do
		index += 1
	end

	return key, string.sub(line, index)
end

local function isEscaped(value: string, index: number): boolean
	if index <= 1 or string.byte(value, index - 1) ~= 92 then
		return false
	end

	local backslashes = 0
	local scan = index - 1
	while scan >= 1 and string.byte(value, scan) == 92 do
		backslashes += 1
		scan -= 1
	end
	return backslashes % 2 == 1
end

local function parseQuotedValue(
	lines: { string },
	lineIndex: number,
	rawValue: string,
	quote: QuoteKind
): (string, number)
	local segments: { string }? = nil
	local currentLineIndex = lineIndex
	local current = string.sub(rawValue, 2)
	local quoteChar = if quote == "single" then "'" else '"'

	while true do
		local searchIndex = 1
		while true do
			local index = string.find(current, quoteChar, searchIndex, true)
			if not index then
				break
			end

			if not isEscaped(current, index) then
				local contents = string.sub(current, 1, index - 1)

				if index < #current then
					local trailing = string.sub(current, index + 1)
					if isTrailingQuoteJunk(trailing) then
						error(`invalid trailing characters after quoted value on line {lineIndex}`)
					end
				end

				local joined: string
				if segments then
					segments[#segments + 1] = contents
					joined = table.concat(segments, "\n")
				else
					joined = contents
				end

				if quote == "single" then
					return decodeSingleQuoted(joined), currentLineIndex
				else
					return decodeDoubleQuoted(joined), currentLineIndex
				end
			end

			searchIndex = index + 1
		end

		if not segments then
			segments = {}
		end

		local currentSegments = segments :: { string }
		currentSegments[#currentSegments + 1] = current
		currentLineIndex += 1
		if currentLineIndex > #lines then
			error(`unterminated quoted value starting on line {lineIndex}`)
		end
		current = lines[currentLineIndex]
	end
end

local function parseEntries(input: string, options: ParseOptions?): { [string]: Entry }
	local strict = if options and options.strict ~= nil then options.strict else true
	local normalized = normalizeInput(input)
	local lines = splitLines(normalized)
	local entries: { [string]: Entry } = {}

	local lineIndex = 1
	while lineIndex <= #lines do
		local line = lines[lineIndex]

		if isBlankOrComment(line) then
			lineIndex += 1
			continue
		end

		local key, rawValue = parseAssignment(line)
		if not key then
			if strict then
				error(`invalid .env assignment on line {lineIndex}`)
			end
			lineIndex += 1
			continue
		end
		assert(rawValue ~= nil, "internal error: expected assignment value capture")

		local value: string
		local quote: QuoteKind = "none"
		local firstChar = string.sub(rawValue, 1, 1)
		if firstChar == '"' then
			quote = "double"
			value, lineIndex = parseQuotedValue(lines, lineIndex, rawValue, quote)
		elseif firstChar == "'" then
			quote = "single"
			value, lineIndex = parseQuotedValue(lines, lineIndex, rawValue, quote)
		else
			value = parseUnquoted(rawValue)
		end

		entries[key] = {
			line = lineIndex,
			value = value,
			quote = quote,
		}

		lineIndex += 1
	end

	return entries
end

local function parseEnvironment(input: string, options: ParseOptions?): Environment
	local strict = if options and options.strict ~= nil then options.strict else true
	local normalized = normalizeInput(input)
	local lines = splitLines(normalized)
	local values: Environment = {}

	local lineIndex = 1
	while lineIndex <= #lines do
		local line = lines[lineIndex]

		if isBlankOrComment(line) then
			lineIndex += 1
			continue
		end

		local key, rawValue = parseAssignment(line)
		if not key then
			if strict then
				error(`invalid .env assignment on line {lineIndex}`)
			end
			lineIndex += 1
			continue
		end
		assert(rawValue ~= nil, "internal error: expected assignment value capture")

		local value: string
		local firstChar = string.sub(rawValue, 1, 1)
		if firstChar == '"' then
			value, lineIndex = parseQuotedValue(lines, lineIndex, rawValue, "double")
		elseif firstChar == "'" then
			value, lineIndex = parseQuotedValue(lines, lineIndex, rawValue, "single")
		else
			value = parseUnquoted(rawValue)
		end

		if string.find(value, DOLLAR_SENTINEL, 1, true) then
			value = string.gsub(value, DOLLAR_SENTINEL, "$")
		end

		values[key] = value

		lineIndex += 1
	end

	return values
end

local function parseExpansionExpression(expression: string): (string, string?, string?)
	local name, operator, rest = string.match(expression, "^([%a_][%w_]*)(:?[-+])(.*)$")
	if name then
		assert(operator ~= nil, "internal error: expected expansion operator capture")
		assert(rest ~= nil, "internal error: expected expansion tail capture")
		return name, operator, rest
	end

	local plainName = string.match(expression, "^([%a_][%w_]*)$")
	if plainName then
		return plainName, nil, nil
	end

	error("invalid expansion expression: ${" .. expression .. "}")
end

local function expandEntries(entries: { [string]: Entry }, baseEnv: Environment): Environment
	local resolved: Environment = {}
	local resolving: { [string]: number } = {}
	local stack = {}

	local resolveReference: ((string) -> (string, boolean))? = nil
	local expandValue: ((string) -> string)? = nil

	local function resolveName(name: string): string
		if resolved[name] ~= nil then
			return resolved[name]
		end

		local entry = entries[name]
		if not entry then
			return baseEnv[name] or ""
		end

		if resolving[name] then
			local cycle = {}
			for _, stackName in stack do
				table.insert(cycle, stackName)
			end
			table.insert(cycle, name)
			error(`circular env expansion detected: {table.concat(cycle, " -> ")}`)
		end

		resolving[name] = #stack + 1
		table.insert(stack, name)

		local value = entry.value
		if entry.quote ~= "single" then
			assert(expandValue ~= nil, "internal error: expandValue not initialized")
			value = expandValue(value)
		end

		resolved[name] = value
		resolving[name] = nil
		table.remove(stack)

		return value
	end

	resolveReference = function(name: string): (string, boolean)
		if entries[name] ~= nil then
			return resolveName(name), true
		end

		local external = baseEnv[name]
		if external ~= nil then
			return external, true
		end

		return "", false
	end

	expandValue = function(value: string): string
		local out = {}
		local index = 1

		while index <= #value do
			local ch = string.sub(value, index, index)

			if ch == DOLLAR_SENTINEL then
				table.insert(out, "$")
				index += 1
				continue
			end

			if ch == "\\" and index < #value and string.sub(value, index + 1, index + 1) == "$" then
				table.insert(out, "$")
				index += 2
				continue
			end

			if ch ~= "$" then
				table.insert(out, ch)
				index += 1
				continue
			end

			local nextCh = if index < #value then string.sub(value, index + 1, index + 1) else ""
			if nextCh == "{" then
				local closeIndex = string.find(value, "}", index + 2, true)
				if not closeIndex then
					error("unterminated expansion expression")
				end

				local expression = string.sub(value, index + 2, closeIndex - 1)
				local name, operator, rest = parseExpansionExpression(expression)
				assert(resolveReference ~= nil, "internal error: resolveReference not initialized")
				local referenced, exists = resolveReference(name)
				local shouldUseRest = false
				local expandedRest = ""

				if rest ~= nil then
					assert(expandValue ~= nil, "internal error: expandValue not initialized")
					expandedRest = expandValue(rest)
					if operator == "-" then
						shouldUseRest = not exists
					elseif operator == ":-" then
						shouldUseRest = (not exists) or referenced == ""
					elseif operator == "+" then
						shouldUseRest = exists
					elseif operator == ":+" then
						shouldUseRest = exists and referenced ~= ""
					end
				end

				table.insert(out, if shouldUseRest then expandedRest else referenced)
				index = closeIndex + 1
				continue
			end

			local name = string.match(string.sub(value, index + 1), "^([%a_][%w_]*)")
			if name then
				assert(resolveReference ~= nil, "internal error: resolveReference not initialized")
				local referenced = resolveReference(name)
				table.insert(out, referenced)
				index += 1 + #name
				continue
			end

			table.insert(out, "$")
			index += 1
		end

		return table.concat(out)
	end

	for name in entries do
		resolveName(name)
	end

	return resolved
end

local function encodeDoubleQuoted(value: string): string
	value = string.gsub(value, "\\", "\\\\")
	value = string.gsub(value, "\n", "\\n")
	value = string.gsub(value, "\r", "\\r")
	value = string.gsub(value, "\t", "\\t")
	value = string.gsub(value, '"', '\\"')
	value = string.gsub(value, "%$", "\\$")
	return value
end

local function serializeValue(value: string): string
	if value == "" then
		return ""
	end

	if string.match(value, [[^[^%s#"'=$]+$]]) then
		return value
	end

	return '"' .. encodeDoubleQuoted(value) .. '"'
end

local function normalizePaths(input: PathInput): { Pathlike }
	if type(input) ~= "table" then
		return { input }
	end

	local candidate = input :: { [any]: any }
	if candidate[1] ~= nil or next(candidate) == nil then
		return input :: { Pathlike }
	end

	return { input :: Pathlike }
end

local function mergeValues(target: Environment, source: Environment, override: boolean): Environment
	for name, value in source do
		if override or target[name] == nil then
			target[name] = value
		end
	end

	return target
end

local function copyEnvironment(values: Environment): Environment
	return table.clone(values)
end

function dotenv.parse(input: string, options: ParseOptions?): Environment
	local shouldExpand = if options and options.expand ~= nil then options.expand else false
	if not shouldExpand then
		return parseEnvironment(input, options)
	end

	local entries = parseEntries(input, options)
	local baseEnv = if options and options.env then options.env else process.env
	return expandEntries(entries, baseEnv)
end

function dotenv.serialize(values: Environment, options: SerializeOptions?): string
	local keys = {}
	for name in values do
		assert(string.match(name, "^[%a_][%w_]*$"), `invalid environment variable name: {name}`)
		table.insert(keys, name)
	end

	table.sort(keys)

	local lines = {}
	local prefix = if options and options.export then "export " else ""
	for _, name in keys do
		table.insert(lines, prefix .. name .. "=" .. serializeValue(values[name]))
	end

	local newline = if options and options.newline then options.newline else "\n"
	return table.concat(lines, newline)
end

function dotenv.load(filepath: PathInput, options: LoadOptions?): Environment
	local values: Environment = {}
	local paths = normalizePaths(filepath)
	local override = if options and options.override ~= nil then options.override else false
	local baseEnv = if options and options.env then options.env else process.env

	for _, currentPath in paths do
		local expansionBase = copyEnvironment(baseEnv)
		mergeValues(expansionBase, values, true)

		local contents = fs.readFileToString(currentPath)
		local parsed = dotenv.parse(contents, {
			expand = if options then options.expand else nil,
			strict = if options then options.strict else nil,
			env = expansionBase,
		})

		mergeValues(values, parsed, override)
	end

	return values
end

function dotenv.apply(values: Environment, options: ApplyOptions?): Environment
	local target = if options and options.target then options.target else process.env
	local override = if options and options.override ~= nil then options.override else false

	return mergeValues(target, values, override)
end

function dotenv.config(options: ConfigOptions?): Environment
	local filepath = if options and options.path then options.path else ".env"
	local baseEnv = if options and options.env
		then options.env
		else if options and options.target then options.target else process.env
	local values = dotenv.load(filepath, {
		expand = if options then options.expand else nil,
		strict = if options then options.strict else nil,
		env = baseEnv,
	})

	local target = if options and options.target then options.target else process.env
	dotenv.apply(values, {
		target = target,
		override = if options then options.override else nil,
	})

	return values
end

return table.freeze(dotenv)
