local dotenv = require("@dotenv")
local path = require("@std/path")
local process = require("@std/process")

local source = debug.info(1, "s")
assert(source, "unable to determine the example source path")

local exampleDir = path.dirname(source)
local envFile = path.join(exampleDir, ".env")

local loaded = dotenv.load(envFile, {
	expand = true,
})

print("Loaded value:")
print("BASE_URL=", loaded.BASE_URL)

dotenv.apply(loaded)

print("")
print("After apply:")
print("BASE_URL=", process.env.BASE_URL)

print("")
print("Serialized:")
print(dotenv.serialize(loaded))
