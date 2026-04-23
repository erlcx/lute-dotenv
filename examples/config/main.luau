local dotenv = require("@dotenv")
local path = require("@std/path")

local source = debug.info(1, "s")
assert(source, "unable to determine the example source path")

local exampleDir = path.dirname(source)
local values = dotenv.config({
	path = path.join(exampleDir, ".env"),
})

local config = {
	appEnv = values.APP_ENV,
	host = values.HOST,
	port = tonumber(values.PORT),
	debug = values.DEBUG == "true",
	posthogApiKey = values.POSTHOG_API_KEY,
}

print("Application config:")
for key, value in config do
	print(`{key}={tostring(value)}`)
end
