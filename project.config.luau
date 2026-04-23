-- To be able to run tasks, you will need to install Luumen
-- For more information, see https://luumen.dev.

return {
    project = {
        name = "lute-dotenv",
        version = "0.1.0",
        description = "A dotenv-style package for Luau projects running on Lute.",
        author = "erlcx",
        license = "MIT"
    },

    install = {
        tools = true,
        packages = true
    },

    tasks = {
        ["lint:lute"] = "lute lint",
        ["lint"] = "selene src tests examples",
        ["test"] = "lute test",
        ["format"] = "stylua src tests examples",
        ["format:check"] = "stylua --check src tests examples",
        ["ci"] = {"luu lint", "luu run lint:lute", "luu test", "luu run format:check"},
        ["gen:types"] = "lute setup --with-luaurc"
    }
}