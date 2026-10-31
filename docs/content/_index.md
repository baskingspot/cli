+++
title = "cli"
+++

`cli` parses command-line flags the way getopt_long does, and hands them to a `while` loop you write.

The loop is the part every tool writes by hand, and the part nobody wants to write again. `-lah` is three flags. `-ofile`, `-o file`, and `--out=file` all give `out` the same value. After `--`, `-weird-name` is a path. Each rule is easy, and getting all of them right in every new tool is tedious. `cli` gets them right once.

It stops at tokens. `Args.next()` says whether a token is an option or a positional, and the command decides what it means. The command owns the flag names, the values, the help text, the error text, the writers, and the exit codes. In return there is nothing to declare up front: a new flag is one more `if` in the loop.

- [The cursor](#the-cursor): the model and the first loop.
- [Grammar](#grammar): the forms the cursor accepts.
- [Short clusters](#short-clusters): `-lah`, `-vvvv`, and values inside a cluster.
- [The separator](#the-separator): what `--` does.
- [Subcommands](#subcommands): an enum, a switch, and a cursor that moves down.
- [Values](#values): strings at the boundary, and `cli.parse` at the flag.
- [Help and errors](#help-and-errors): the command writes both.
- [Input and output](#input-and-output): the caller owns the writers.
- [Tests](#tests): `fromSlice` and a parse function.
- [Patterns](#patterns): fixed arity, repeated flags, counters, passthrough.
- [Limits](#limits): what the library leaves to the command.

The [API reference](api/) documents every symbol.

# Getting started

## Install

```sh
zig fetch --save https://baskingspot.dev/cli/v0.3.0.tar.gz
```

`zig fetch` writes the hash into `build.zig.zon`.

Add the module in `build.zig`:

```zig
const cli_dep = b.dependency("cli", .{ .target = target });
exe.root_module.addImport("cli", cli_dep.module("cli"));
```

`cli` builds with Zig 0.16 only.

## Read the examples

[`examples/kitchen.zig`](https://github.com/baskingspot/cli/blob/main/examples/kitchen.zig) is the kitchen sink. It has global flags, `-vvvv`, `-rj4`, repeated `--feature`, integer and enum codecs, `--` for sources and child arguments, nested `config` dispatch, and a help table.

```sh
zig build run -- -vv build -rj4 -o app --feature serde src/main.zig
zig build run -- run -- ls -lah
zig build run -- config set color always
zig build run -- build -- -weird-source
```

The smaller programs each isolate one part:

- [`examples/git.zig`](https://github.com/baskingspot/cli/blob/main/examples/git.zig): nested subcommands, fixed arity, flags with values.
- [`examples/ls.zig`](https://github.com/baskingspot/cli/blob/main/examples/ls.zig): short clusters and `--`.
- [`examples/tar.zig`](https://github.com/baskingspot/cli/blob/main/examples/tar.zig): clusters where a flag takes the rest of the token or the next token.
- [`examples/verbose.zig`](https://github.com/baskingspot/cli/blob/main/examples/verbose.zig): `-vvvv` as a counter.
- [`examples/codec.zig`](https://github.com/baskingspot/cli/blob/main/examples/codec.zig): an integer and an enum parsed with `cli.parse`.

`zig build` installs `cli-kitchen`, `cli-git`, `cli-ls`, `cli-tar`, `cli-verbose`, and `cli-codec` under `zig-out/bin`. `zig build run` runs the kitchen sink. `zig build test` runs the unit tests and builds the examples.

# The cursor

`Args.next()` returns `?Token`. A token is either `.positional` or `.option`. An option carries its kind, its name without dashes, the inline value from `--name=value`, the rest of a short cluster in `attached`, and the original text for diagnostics.

The cursor does not know which options exist. It does not know which ones take values. It does not print. The command loop is the parser:

```zig
while (args.next()) |tok| switch (tok) {
    .positional => |path| try paths.append(arena, path),
    .option => |opt| {
        if (opt.is("output", 'o')) {
            output = args.takeValue(opt) orelse {
                try stderr.print("mytool: {f} needs a value\n", .{opt});
                try stderr.writeAll(usage);
                return 2;
            };
        } else if (opt.isSwitch("verbose", 'v')) {
            verbose = true;
        } else {
            try stderr.print("mytool: unknown option '{f}'\n", .{opt});
            try stderr.writeAll(usage);
            return 2;
        }
    },
};
```

`takeValue` returns the inline value, then the rest of a short cluster, then the next token. It returns null when the option is last and no token follows. A boolean option must not call it; the cursor then keeps yielding the rest of the cluster.

The library does not allocate an argv slice. `Args.init` and `Args.initAllocator` read the process iterator directly. `fromSlice` reads a literal token slice for tests. There is no hidden allocation in the parser.

# Grammar

Long options take `--`. Short options take one `-`.

- `--name`
- `--name=value`
- `-n`
- `-abc`, three options in order
- `-ovalue`, `o` with the attached value `value`
- `-n value`, `n` with the next token
- `--`, the separator
- `-`, a positional, the conventional stdin marker

`-n=value` is not special. The value of `n` is `=value`, as in getopt. Write `-ovalue` or `-o value`.

Options are recognized after positionals. A command that wants POSIX stop-at-first-positional switches to `nextRaw` after the first one.

`Option.is(long, short)`, `isLong`, `isShort`, and `isSwitch` match. `isSwitch` rejects a long option with an inline value, so `--verbose=yes` does not quietly count as `--verbose`. For a short option, `isSwitch` matches even when other letters follow in the cluster.

`Option.format` is the diagnostic spelling: `--name`, `--name=value`, or `-n`. Use `{f}`:

```zig
try stderr.print("unknown option '{f}'\n", .{opt});
```

`isOption(token)` says whether a raw token starts option syntax. It returns true for `--`, because an optional-value check must not swallow the separator. `-` is false.

# Short clusters

`-lah` yields three options, one per `next()` call: `l`, `a`, `h`. `Option.attached` is the rest of the token: `a` has `attached = "h"`.

A flag that takes a value calls `takeValue`, which consumes the rest of the cluster first:

```text
-xzfarchive.tar.gz     x (boolean), z (boolean), f -> "archive.tar.gz"
-xzf archive.tar.gz    x (boolean), z (boolean), f -> the next token
```

A boolean flag must not call `takeValue`; the cursor then yields the next letter. `-vvvv` is four `v` options:

```zig
if (opt.isSwitch("verbose", 'v')) level = level +| 1;
```

`-rj4` is `r`, then `j` with `attached = "4"`. If `j` takes a value, `takeValue` returns `"4"`. If it does not, the cursor treats `4` as another short option.

The cursor never needs a table of which options take values. The command decides by calling `takeValue` or `next`.

# The separator

`--` ends option parsing. The cursor swallows it and returns every later token as positional, even when it starts with `-`.

```sh
mytool -- --some-folder   # --some-folder is a path
mytool run -- ls -lah     # ls and -lah are the child arguments
```

The second `--` is positional: the first one ends options, the next is data.

`-` is positional, so it can mean stdin.

`takeValue` consumes a `--` as a value when it appears where a value is expected. The command decides whether that is valid. If you need the literal separator, read the raw iterator or stop calling `next`.

A command that wants everything after the separator as a list loops `next()` and appends the positionals. There is no `rest()` slice because the source can be an iterator; the command owns the allocation.

# Subcommands

A command set is an enum and a switch. `std.meta.stringToEnum` maps the token. The dispatcher reads the command name, then hands the same cursor to the command.

```zig
const Cmd = enum { build, run };

const cmd = std.meta.stringToEnum(Cmd, name) orelse {
    try stderr.print("{s}: unknown command '{s}'\n", .{ prog, name });
    try stderr.writeAll(top_usage);
    return 2;
};

return switch (cmd) {
    .build => build(&ctx),
    .run => runCommand(&ctx),
};
```

The cursor is already after the command token. Each command reads its own flags and positionals. Nothing in the library sees the enum.

Nested commands repeat the pattern. `config` reads its nested command with `next()`, dispatches, and passes the cursor on.

Fixed arity is a command that reads one positional per argument and then checks that the cursor is empty. `remote add <name> <url>` is an example. Extra tokens are an error the command writes.

Global flags go before the command. Parse them with the same cursor until the first positional, then dispatch. Do not scan the whole argv for global flags; a scan cannot tell a flag from a value without the command's grammar.

# Values

`takeValue` returns a byte slice. `cli.parse(T, raw)` converts it to a value. The command writes the message.

```zig
if (opt.is("port", 'p')) {
    const raw = args.takeValue(opt) orelse {
        try stderr.print("mytool: {f} needs a value\n", .{opt});
        try stderr.writeAll(usage);
        return 2;
    };
    port = cli.parse(u16, raw) catch {
        try stderr.print("mytool: {f}: expected a number, got '{s}'\n", .{ opt, raw });
        try stderr.writeAll(usage);
        return 2;
    };
}
```

The built-in codecs:

- `bool`: the spellings Go's `strconv.ParseBool` accepts: `1`, `t`, `T`, `TRUE`, `true`, `True`, and the false equivalents.
- Integers (`i8` through `i128`, `u8` through `u128`, `isize`, `usize`): base 10, with an optional sign. A number that does not fit returns `error.Overflow`. Other text returns `error.InvalidValue`.
- Floats (`f16` through `f128`): the syntax that `std.fmt.parseFloat` accepts.
- `[]const u8`: the text, borrowed from the argument.
- An enum: the tag name, matched like `std.meta.stringToEnum`.

A struct, union, or opaque type joins the list with a `parse` function in its namespace:

```zig
const Range = struct {
    low: u16,
    high: u16,

    pub fn parse(raw: []const u8) !Range {
        const dash = std.mem.findScalar(u8, raw, '-') orelse return error.InvalidValue;
        const low = try std.fmt.parseInt(u16, raw[0..dash], 10);
        const high = try std.fmt.parseInt(u16, raw[dash + 1 ..], 10);
        if (low > high) return error.InvalidValue;
        return .{ .low = low, .high = high };
    }
};

range = cli.parse(Range, raw) catch {
    try stderr.print("mytool: {f}: expected LOW-HIGH, got '{s}'\n", .{ opt, raw });
    try stderr.writeAll(usage);
    return 2;
};
```

`parse` receives the text and nothing else. It returns the value or an error. An error reaches the command unchanged. It does not receive the option, and it cannot write.

The command keeps the missing-value branch. `takeValue` returns null when no token follows. `cli.parse` handles only the conversion.

An empty inline value is `""`: `--name=` is present, not missing. Decide whether empty is valid.

A value can contain `=`. The cursor splits a long option on the first one. It does not split positionals.

`takeValue` consumes the next token even when it starts with a dash, so `--offset -1` works. A bare `-1` is a short option named `1`; use `--` or a value flag for negative numbers.

Repeated flags are just repeated tokens. Append them to a list, or let the last one win.

# Help and errors

Help is a string. The command writes it. `cli` does not generate it and cannot drift-check it.

Top-level `-h/--help` is a branch before dispatch. Each command also handles its own `-h/--help`. A `help <command>` command is a switch over the same enum and a table of usage strings.

Write usage errors to stderr, then the usage text:

```zig
try stderr.print("{s}: {f} needs a value\n", .{ prog, opt });
try stderr.writeAll(usage);
return 2;
```

Use 0 for success, 1 for a runtime failure, and 2 for a usage error. The library returns none of these.

`args.program_name` is the first argv token, captured by `init` and `initAllocator`. Use `std.fs.path.basename` for the prefix. A slice cursor starts with an empty name; set the field if the code uses it.

The cost of handwritten help is drift. Keep the usage string next to the parser, and cover `--help` in a test. The library will not catch a flag that is missing from the text.

There are no generated completions. If they matter, write an explicit table for them; do not make the parser carry it.

# Input and output

The library has no streams. A command takes a `*std.Io.Writer`, or a context with both stdout and stderr, and the caller creates and flushes them.

```zig
var stdout_buffer: [4096]u8 = undefined;
var stdout_file: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
const stdout = &stdout_file.interface;
defer stdout.flush() catch {};

var stderr_buffer: [4096]u8 = undefined;
var stderr_file: std.Io.File.Writer = .initStreaming(.stderr(), init.io, &stderr_buffer);
const stderr = &stderr_file.interface;
defer stderr.flush() catch {};
```

A writer can fail. The command decides whether to propagate the error, print a second message, or drop it. The library never flushes.

`Args.initAllocator(init.minimal.args, arena)` is the portable constructor. It returns an error union because the platform iterator may need a buffer. `Args.init(init.minimal.args)` is the POSIX form: no allocator, no error union, and it does not compile on Windows or WASI. Both capture `program_name`. Call `deinit` when the cursor owns a process iterator. The tokens point into the iterator and are invalid after `deinit`.

`Args.fromSlice(tokens)` borrows a literal slice and has nothing to release. The tokens are the caller's.

# Tests

`fromSlice` makes the cursor a pure function over tokens. No allocator, no Io, no process.

```zig
test "output and source" {
    var args: cli.Args = .fromSlice(&.{ "-o", "out", "src/main.zig" });
    const opts = try parse(std.testing.allocator, &args);
    try std.testing.expectEqualStrings("out", opts.output);
    try std.testing.expectEqual(1, opts.sources.len);
}
```

Keep parsing separate from running. A `parse` function takes `*cli.Args` and returns a struct; `run` takes the struct and the writers. The parser test never touches a file. The cursor's slices are borrowed from the test's token slice, which lives for the test.

A slice cursor starts with `program_name = ""`. Set it when the parsing code uses the prefix.

# Patterns

A fixed-arity command reads one positional per argument, then rejects anything left:

```zig
const name = (try takePositional(ctx, usage)) orelse return 2;
const url = (try takePositional(ctx, usage)) orelse return 2;
if (ctx.args.next()) |extra| return extraArgument(ctx, extra, usage);
```

A repeated value flag appends at each occurrence:

```zig
} else if (opt.isLong("feature")) {
    const value = args.takeValue(opt) orelse {
        return usageError(ctx, usage, "{f} needs a value", .{opt});
    };
    try features.append(arena, value);
}
```

A counter is a switch plus a saturating add:

```zig
if (opt.isSwitch("verbose", 'v')) level = level +| 1;
```

An optional value uses the inline form, or peeks for a token that cannot be anything else:

```zig
if (opt.inline_value) |raw| {
    color = try parseColor(ctx, opt, raw);
} else if (args.peekRaw()) |next| {
    if (!cli.isOption(next)) {
        const value = args.nextRaw().?;
        color = try parseColor(ctx, opt, value);
    }
}
```

Space-separated optional values are ambiguous. `--color always` can mean the value `always` or the command `always`. Prefer `--color=always`, and use the peek form only when the next token cannot be anything else.

A passthrough command collects the positionals after `--`:

```sh
mytool run -- ls -lah
```

```zig
var argv: std.ArrayList([]const u8) = .empty;
while (args.next()) |tok| switch (tok) {
    .positional => |arg| try argv.append(arena, arg),
    .option => |opt| {
        // The command's own options go here.
    },
};
```

A `help <command>` command maps the same enum to a usage string:

```zig
const cmd = std.meta.stringToEnum(Cmd, name) orelse {
    return usageError(ctx, top_usage, "unknown command '{s}'", .{name});
};
try stdout.writeAll(switch (cmd) {
    .build => build_usage,
    .run => run_usage,
    .help => top_usage,
});
```

# Limits

- No generated help, man pages, or shell completions.
- No typed flag schema or derive. `cli.parse` converts one value; it does not map flags to fields.
- No allocator reaches a codec. A custom `parse` borrows its text.
- No stdio. The caller creates the writers and flushes them.
- No color, TTY detection, or progress output.
- No global flag reordering. Global flags come before the command; command flags come after.
- No config file or environment fallback. The command reads those itself.
- No special `-n=value` form, no long-option abbreviations, and no `--no-` negation.
- No `rest()` slice. The source can be an iterator; the command collects the remainder.
- No shell parsing. The shell already split the tokens.
- `Args.init` is not available on Windows or WASI. Use `initAllocator`.
