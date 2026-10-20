# cli

Command-line argument parsing for Zig.

This project is incubating. It is unstable, its API will change, and it is not ready to depend on.

## Shape

`cli.Args` is a cursor over argv. It reads one argument at a time and does not build an argv slice. On POSIX it allocates nothing; the allocator is used only where the platform iterator needs a buffer. It classifies tokens and leaves the meaning to the command. Help text and error messages stay in the command.

The library owns no streams. Diagnostics take a caller-provided `*std.Io.Writer`.

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
                try cli.fail(stderr, "mytool", usage, "{f} needs a value", .{opt});
                return 2;
            };
        } else {
            try cli.fail(stderr, "mytool", usage, "unknown option '{f}'", .{opt});
            return 2;
        }
    },
};
```

`Args.init` is the allocation-free POSIX constructor. `Args.initAllocator` is the portable form for Windows and WASI. Both capture the first argv token as `args.program_name`.

Subcommands are an enum and a switch. `cli.Args` does not see them.

```zig
const cmd = std.meta.stringToEnum(Cmd, name) orelse {
    try cli.fail(stderr, "mytool", usage, "unknown command '{s}'", .{name});
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

`cli.help` and `cli.fail` write to the writer you pass. They do not flush, allocate, or exit.

## Examples

- `src/main.zig`: nested subcommands, fixed arity, flags with values.
- `examples/ls.zig`: short clusters and `--`.
- `examples/tar.zig`: clusters where a flag takes the rest of the token or the next token.
- `examples/verbose.zig`: `-vvvv` as a repeatable counter.
- `examples/codec.zig`: `--port` parsed as an integer and `--color` parsed as an enum.

`zig build` installs `cli`, `cli-ls`, `cli-tar`, `cli-verbose`, and `cli-codec` under `zig-out/bin`.
`zig build test` runs the unit tests and builds the examples.

## Work on it

`nix develop` provides the toolchain, and `just ci` runs what CI runs.

## License

MIT. See `LICENSE`.
