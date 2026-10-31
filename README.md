<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/static/logo-dark.svg">
    <img src="docs/static/logo.svg" alt="cli" height="48">
  </picture>
</h1>

Command-line flags for Zig, the getopt_long way: `-xvf`, `--out=file`, and a `while` loop.

Every command-line tool ends up with the same loop over argv. Writing it isn't hard. It's tedious, and the edges are where it goes wrong: `-xvf` is three flags, `-ofile` and `-o file` mean the same thing, `--out=file` splits on the first `=`, and after `--` a token that starts with a dash is a path. `cli` handles those edges and hands you one token at a time. Which flags exist, what their values mean, and what the help text says stay in your code, where you can read them.

```zig
while (args.next()) |tok| switch (tok) {
    .positional => |path| try paths.append(arena, path),
    .option => |opt| {
        if (opt.is("output", 'o')) {
            output = args.takeValue(opt) orelse return 2;
        } else if (opt.isSwitch("verbose", 'v')) {
            verbose = true;
        } else return 2;
    },
};
```

`cli.Args` reads argv one token at a time and never builds an argv slice. On POSIX it allocates nothing. It writes nothing either: help text and error messages belong to the command.

## What is in it

- [The cursor](https://baskingspot.dev/cli/#the-cursor): `Args.next()` yields `.positional` or `.option`, and `takeValue` reads the value that goes with an option.
- [Grammar](https://baskingspot.dev/cli/#grammar): `--name`, `--name=value`, `-abc`, `-ovalue`, and `-o value`. `-` is positional.
- [Short clusters](https://baskingspot.dev/cli/#short-clusters): `-lah` and `-vvvv`, and a flag that takes the rest of its cluster as a value.
- [The separator](https://baskingspot.dev/cli/#the-separator): after `--`, every token is positional, even `-weird-name`.
- [Subcommands](https://baskingspot.dev/cli/#subcommands): an enum and a switch. `cli.Args` does not see them.
- [Values](https://baskingspot.dev/cli/#values): strings at the boundary, and `cli.parse` for a primitive or a type's own `parse`.
- [Help and errors](https://baskingspot.dev/cli/#help-and-errors), [input and output](https://baskingspot.dev/cli/#input-and-output), [tests](https://baskingspot.dev/cli/#tests), and [patterns](https://baskingspot.dev/cli/#patterns): the command writes the help text, the caller owns the writers, `fromSlice` tests a parse function, and fixed arity, repeated flags, and counters are short loops.

Not implemented:

- Generated help, man pages, and shell completions: the command writes its own help text.
- A typed flag table or derive: a new flag is one more `if` in the loop.
- Long-option abbreviations, `--no-` negation, and a special `-n=value` form.

## Install

```sh
zig fetch --save https://baskingspot.dev/cli/v0.3.0.tar.gz
```

Add the module to your build:

```zig
const cli = b.dependency("cli", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("cli", cli.module("cli"));
```

`Args.init` is the allocation-free POSIX constructor. `Args.initAllocator` is the portable form for Windows and WASI. Both capture the first argv token as `args.program_name`.

`cli` builds with Zig 0.16 only.

## Documentation

- The [guide](https://baskingspot.dev/cli/) says how the cursor works and how to build a command around it, with examples that compile.
- The [API reference](https://baskingspot.dev/cli/api/) documents every symbol.
- [`examples/`](examples/) has a kitchen-sink program and five focused ones: `git`, `ls`, `tar`, `verbose`, and `codec`.

## Work on it

```sh
just ci
```

`nix develop` provides the toolchain. `just` lists the recipes, and `just ci` runs what CI runs.

## License

MIT. See `LICENSE`. The logo files in `docs/static/` are baskingspot marks and
are not covered by it. See `docs/static/LICENSE`.

## How it's made

Built with LLM assistance. [How, in detail](https://github.com/baskingspot/.github/blob/main/docs/AI.md).

<a href="https://github.com/baskingspot"><img src="https://raw.githubusercontent.com/baskingspot/.github/main/brand/assets/badge.svg" alt="baskingspot" height="24"></a>
