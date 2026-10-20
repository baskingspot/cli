# cli

A cursor over argv for Zig 0.16: short clusters, long options, and no schema.

This project is incubating. It is unstable, its API will change, and it is not ready to depend on.

The guide is at <https://baskingspot.dev/cli/>.

## Shape

`cli.Args` is a cursor over argv. It reads one argument at a time and does not build an argv slice. On POSIX it allocates nothing; the allocator is used only where the platform iterator needs a buffer. It classifies tokens and leaves the meaning to the command. The library owns no streams and writes nothing; help text and error messages stay in the command.

```zig
var stdout_buffer: [4096]u8 = undefined;
var stdout_file: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
const stdout = &stdout_file.interface;
defer stdout.flush() catch {};

var stderr_buffer: [4096]u8 = undefined;
var stderr_file: std.Io.File.Writer = .initStreaming(.stderr(), init.io, &stderr_buffer);
const stderr = &stderr_file.interface;
defer stderr.flush() catch {};

var args = try cli.Args.initAllocator(init.minimal.args, arena);
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

MIT. See `LICENSE`.
