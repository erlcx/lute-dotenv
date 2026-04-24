# lute-dotenv [![CI](https://github.com/erlcx/lute-dotenv/actions/workflows/ci.yaml/badge.svg)](https://github.com/erlcx/lute-dotenv/actions/workflows/ci.yaml)

`lute-dotenv` is a dotenv-style package for Luau projects running on Lute.

It provides helpers for parsing `.env` files, loading them from disk, applying
them to `process.env`, and serializing them back to text.

## Install

Add a dependency to your project's `loom.config.luau`:

```luau
return {
    package = {
        name = "my-project",
        version = "0.1.0",
        dependencies = {
            dotenv = {
                sourceKind = "github",
                source = "https://github.com/erlcx/lute-dotenv",
                rev = "v0.1.0",
            },
        },
    },
}
```

Then install it with:

```sh
lute pkg install
```

## Usage

```luau
local dotenv = require("@dotenv")
local process = require("@std/process")

dotenv.config()
print(process.env.YOUR_ENV_VAR)
```

`config()` loads `.env` from the current working directory by default, applies
the parsed values to `process.env`, and returns the parsed table.

## API

- `dotenv.parse(input, options?)`
- `dotenv.load(path, options?)`
- `dotenv.apply(values, options?)`
- `dotenv.serialize(values, options?)`
- `dotenv.config(options?)`

## Options

`parse` and `load` support:

- `expand`: expand `$VAR` and `${VAR}` style references
- `strict`: error on invalid assignment lines
- `env`: base environment table used during expansion
- `override`: when loading multiple files, let later files replace earlier values

`apply` and `config` support:

- `path`: use a single path or an array of paths
- `target`: environment table to write into
- `override`: replace existing values instead of preserving them

## Examples

See the [`examples`](./examples) directory for:

- [`basic`](./examples/basic): load a sibling `.env` file and print values
- [`config`](./examples/config): load environment variables into a small config table
- [`functions`](./examples/functions): use `load`, `apply`, and `serialize` directly
- [`multiple-files`](./examples/multiple-files): merge `.env` and `.env.local` in order

## Benchmarks

Parse-only benchmarks live in [`benchmarks`](./benchmarks). They compare this
package against the JavaScript `dotenv` package using equivalent generated
fixtures and no file I/O.

```sh
npm --prefix benchmarks install
luu run bench
```

Run one side at a time with `luu run bench:luau` or `luu run bench:js`.

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.
