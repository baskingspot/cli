<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/static/logo-dark.svg">
    <img src="docs/static/logo.svg" alt="cli" height="48">
  </picture>
</h1>

Command-line flags for Zig, the getopt_long way: `-xvf`, `--out=file`, and a `while` loop.

Every command-line tool ends up with the same loop over argv. Writing it isn't hard. It's tedious, and the edges are where it goes wrong: `-xvf` is three flags, `-ofile` and `-o file` mean the same thing, `--out=file` splits on the first `=`, and after `--` a token that starts with a dash is a path. `cli` handles those edges and hands you one token at a time. Which flags exist, what their values mean, and what the help text says stay in your code, where you can read them.

The guide is at <https://baskingspot.dev/cli/>.

## Shape

`cli.Args` reads argv one token at a time and never builds an argv slice. On POSIX it allocates nothing. It writes nothing either: help text and error messages belong to the command.

```zig
var args: cli.Args = try .initAllocator(init.minimal.args, arena);
defer args.deinit();

while (args.next()) |tok| switch (tok) {
    .positional => |path| try paths.append(arena, path),
    .option => |opt| {
        if (opt.is("output", 'o')) {
            output = args.takeValue(opt) orelse {
                try stderr.print("mytool: {f} needs a value\n", .{opt});
                try stderr.writeAll(usage);
                return 2;
            };
        } else {
            try stderr.print("mytool: unknown option '{f}'\n", .{opt});
            try stderr.writeAll(usage);
            return 2;
        }
    },
};
```

`Args.init` is the allocation-free POSIX constructor. `Args.initAllocator` is the portable form for Windows and WASI. Both capture the first argv token as `args.program_name`.

Subcommands are an enum and a switch. `cli.Args` does not see them.

```zig
const cmd = std.meta.stringToEnum(Cmd, name) orelse {
    try stderr.print("mytool: unknown command '{s}'\n", .{name});
    try stderr.writeAll(usage);
    return 2;
};

return switch (cmd) {
    .build => build(&ctx),
    .serve => serve(&ctx),
};
```

## Install

```sh
zig fetch --save https://baskingspot.dev/cli/v0.1.0.tar.gz
```

Add the module to your build:

```zig
const cli = b.dependency("cli", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("cli", cli.module("cli"));
```

`cli` builds with Zig 0.16 only.

## Grammar

- `--name` and `--name=value`.
- `-n` and `-abc`. A short cluster yields one option at a time.
- `-ovalue` gives `o` the attached value `value`.
- `-o value` gives `o` the next token.
- `--` ends option parsing. Every later token is positional, even when it starts with `-`. `ls -- --some-folder` treats `--some-folder` as a path.
- `-` is positional.

`takeValue` consumes the rest of a short cluster first, then the next token. The next token is consumed even when it starts with a dash. The command decides whether that is valid.

There is no generated help, no typed flag table, and no value codec. The command writes the help text and calls `std.fmt.parseInt` or `std.meta.stringToEnum` at the flag.

## Examples

- `examples/kitchen.zig`: the kitchen sink. Global flags, short clusters,
  repeated values, codecs, `--`, and nested commands.
- `examples/git.zig`: nested subcommands, fixed arity, flags with values.
- `examples/ls.zig`: short clusters and `--`.
- `examples/tar.zig`: clusters where a flag takes the rest of the token or the next token.
- `examples/verbose.zig`: `-vvvv` as a repeatable counter.
- `examples/codec.zig`: `--port` parsed as an integer and `--color` parsed as an enum.

`zig build` installs `cli-kitchen`, `cli-git`, `cli-ls`, `cli-tar`, `cli-verbose`,
and `cli-codec` under `zig-out/bin`.

```sh
zig build run -- -vv build -rj4 -o app --feature serde src/main.zig
zig build run -- run -- ls -lah
zig build run -- config set color always
zig build run -- build -- -weird-source
```

`zig build run` runs the kitchen sink. `zig build test` runs the unit tests and
builds the examples.

## Work on it

`nix develop` provides the toolchain, and `just ci` runs what CI runs.

## License

MIT. See `LICENSE`. The logo files in `docs/static/` are baskingspot marks and
are not covered by it. See `docs/static/LICENSE`.

## How it's made

Built with LLM assistance. [How, in detail](https://github.com/baskingspot/.github/blob/main/docs/AI.md).

<a href="https://github.com/baskingspot"><img src="https://raw.githubusercontent.com/baskingspot/.github/main/brand/assets/badge.svg" alt="baskingspot" height="24"></a>
