local dotenv = require("@dotenv")
local path = require("@std/path")

local source = debug.info(1, "s")
assert(source, "unable to determine the example source path")

local exampleDir = path.dirname(source)

local values = dotenv.config({
	path = {
		path.join(exampleDir, ".env"),
		path.join(exampleDir, ".env.local"),
	},
	expand = true,
	override = true,
})

print("Merged values:")
print("APP_NAME=", values.APP_NAME)
print("HOST=", values.HOST)
print("PORT=", values.PORT)
print("BASE_URL=", values.BASE_URL)
print("LOG_LEVEL=", values.LOG_LEVEL)
