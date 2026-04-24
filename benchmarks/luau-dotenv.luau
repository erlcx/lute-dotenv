--!strict

local dotenv = require("@dotenv")

local ITERATIONS = 10000

local function makeBasic(count: number): string
	local lines = table.create(count)

	for index = 1, count do
		table.insert(lines, `KEY_{index}=value_{index}`)
	end

	return table.concat(lines, "\n")
end

local function makeQuoted(count: number): string
	local lines = table.create(count * 3)

	for index = 1, count do
		table.insert(lines, `DOUBLE_{index}="value {index} with spaces and # hash"`)
		table.insert(lines, `SINGLE_{index}='literal {index} # value'`)
		table.insert(lines, `ESCAPED_{index}="line {index}\\nnext\\tvalue"`)
	end

	return table.concat(lines, "\n")
end

local function makeMixed(count: number): string
	local lines = { "# generated benchmark fixture" }

	for index = 1, count do
		table.insert(lines, "")
		table.insert(lines, `# block {index}`)
		table.insert(lines, `export APP_{index}=service_{index}`)
		table.insert(lines, `URL_{index}="https://example.com/{index}?q=value#anchor"`)
		table.insert(lines, `EMPTY_{index}=`)
	end

	return table.concat(lines, "\n")
end

local cases = {
	{ "basic-128", makeBasic(128) },
	{ "quoted-128", makeQuoted(128) },
	{ "mixed-128", makeMixed(128) },
}

local function countKeys(values: dotenv.Environment): number
	local count = 0

	for _name in values do
		count += 1
	end

	return count
end

local function padLeft(value: string, width: number): string
	if #value >= width then
		return value
	end

	return string.rep(" ", width - #value) .. value
end

local function padRight(value: string, width: number): string
	if #value >= width then
		return value
	end

	return value .. string.rep(" ", width - #value)
end

local function runCase(name: string, input: string)
	local checksum = 0

	for _index = 1, 100 do
		checksum += countKeys(dotenv.parse(input))
	end

	local startedAt = os.clock()

	for _index = 1, ITERATIONS do
		checksum += countKeys(dotenv.parse(input))
	end

	local elapsedMs = (os.clock() - startedAt) * 1000
	local opsPerSecond = ITERATIONS / (elapsedMs / 1000)

	print(
		`{padRight(name, 12)} {padLeft(string.format("%.2f", elapsedMs), 10)} ms  {padLeft(
			string.format("%.0f", opsPerSecond),
			10
		)} ops/s  checksum={checksum}`
	)
end

print(`lute-dotenv parse ({ITERATIONS} iterations)`)

for _, case in cases do
	runCase(case[1], case[2])
end
