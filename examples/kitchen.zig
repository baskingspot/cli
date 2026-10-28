//! The kitchen sink: every feature in one program.
//!
//!   cli-kitchen -vv build -rj4 -o app --feature serde src/main.zig
//!   cli-kitchen run -- ls -lah
//!   cli-kitchen config set color always
//!   cli-kitchen build -- -weird-source
//!
//! Global flags come before the command. Command flags come after. `--` ends
//! option parsing, so the rest is positional.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const stringToEnum = std.meta.stringToEnum;

const cli = @import("cli");

const Cmd = enum { build, run, config, help };
const ConfigCmd = enum { get, set, remove, list };
const Color = enum { auto, always, never };

const Globals = struct {
    verbose: u8 = 0,
    quiet: bool = false,
    color: Color = .auto,
};

const Ctx = struct {
    stdout: *Io.Writer,
    stderr: *Io.Writer,
    args: *cli.Args,
    arena: Allocator,
    prog: []const u8,
    global: Globals = .{},
};

const top_usage =
    \\usage: kitchen [global options] <command> [args]
    \\
    \\global options:
    \\  -v, --verbose       increase verbosity (repeatable)
    \\  -q, --quiet         suppress normal output
    \\  --color WHEN        auto, always, or never (default: auto)
    \\  -h, --help          show this help
    \\
    \\commands:
    \\  build [options] [--] <source...>   compile sources
    \\  run [options] [--] <program>...    run a program
    \\  config <get|set|remove|list> ...   read or write config
    \\  help [command]                     show help
    \\
;

const build_usage =
    \\usage: kitchen build [options] [--] <source...>
    \\  -o, --output <path>    output path (default: a.out)
    \\  -j, --jobs <n>         jobs (default: 1)
    \\  -r, --release          build with optimizations
    \\  --feature <name>       enable a feature (repeatable)
    \\  -h, --help             show this help
    \\
;

const run_usage =
    \\usage: kitchen run [options] [--] <program> [arg...]
    \\  --dry-run    print the command instead of running it
    \\  -h, --help   show this help
    \\
    \\Put `--` before the program when its arguments start with a dash:
    \\  kitchen run -- ls -lah
    \\
;

const config_usage =
    \\usage: kitchen config <command> [args]
    \\  kitchen config get <key>            read a value
    \\  kitchen config set <key> <value>    write a value
    \\  kitchen config remove <key>         remove a key
    \\  kitchen config list                 list values
    \\
;

const config_get_usage = "usage: kitchen config get <key>\n";
const config_set_usage = "usage: kitchen config set <key> <value>\n";
const config_remove_usage = "usage: kitchen config remove <key>\n";
const config_list_usage = "usage: kitchen config list\n";

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file: Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_file.interface;
    defer flushQuietly(stdout);

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file: Io.File.Writer = .initStreaming(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_file.interface;
    defer flushQuietly(stderr);

    var args = cli.Args.initAllocator(init.minimal.args, arena) catch |err| {
        try stderr.print("kitchen: cannot read arguments: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer args.deinit();

    const prog = if (args.program_name.len > 0)
        std.Io.Dir.path.basename(args.program_name)
    else
        "kitchen";

    var ctx: Ctx = .{
        .stdout = stdout,
        .stderr = stderr,
        .args = &args,
        .arena = arena,
        .prog = prog,
    };
    return run(&ctx);
}

fn run(ctx: *Ctx) !u8 {
    var command: ?[]const u8 = null;

    while (ctx.args.next()) |tok| switch (tok) {
        .positional => |name| {
            command = name;
            break;
        },
        .option => |opt| {
            if (opt.isSwitch("verbose", 'v')) {
                ctx.global.verbose = ctx.global.verbose +| 1;
            } else if (opt.isSwitch("quiet", 'q')) {
                ctx.global.quiet = true;
            } else if (opt.is("color", null)) {
                const raw = ctx.args.takeValue(opt) orelse
                    return usageError(ctx, top_usage, "{f} needs a value", .{opt});
                ctx.global.color = cli.parse(Color, raw) catch
                    return usageError(
                        ctx,
                        top_usage,
                        "{f}: expected auto, always, or never, got '{s}'",
                        .{ opt, raw },
                    );
            } else if (opt.isSwitch("help", 'h')) {
                return showHelp(ctx, top_usage);
            } else {
                return usageError(ctx, top_usage, "unknown option '{f}'", .{opt});
            }
        },
    };

    const name = command orelse {
        try ctx.stderr.writeAll(top_usage);
        return 2;
    };

    const cmd = stringToEnum(Cmd, name) orelse
        return usageError(ctx, top_usage, "unknown command '{s}'", .{name});

    return switch (cmd) {
        .build => build(ctx),
        .run => runCommand(ctx),
        .config => config(ctx),
        .help => helpCommand(ctx),
    };
}

fn build(ctx: *Ctx) !u8 {
    var output: []const u8 = "a.out";
    var jobs: u16 = 1;
    var release = false;
    var features: std.ArrayList([]const u8) = .empty;
    var sources: std.ArrayList([]const u8) = .empty;

    while (ctx.args.next()) |tok| switch (tok) {
        .positional => |source| try sources.append(ctx.arena, source),
        .option => |opt| {
            if (opt.is("output", 'o')) {
                output = ctx.args.takeValue(opt) orelse
                    return usageError(ctx, build_usage, "{f} needs a value", .{opt});
            } else if (opt.is("jobs", 'j')) {
                const raw = ctx.args.takeValue(opt) orelse
                    return usageError(ctx, build_usage, "{f} needs a value", .{opt});
                jobs = cli.parse(u16, raw) catch
                    return usageError(
                        ctx,
                        build_usage,
                        "{f}: expected a number, got '{s}'",
                        .{ opt, raw },
                    );
            } else if (opt.isSwitch("release", 'r')) {
                release = true;
            } else if (opt.is("feature", null)) {
                const feature = ctx.args.takeValue(opt) orelse
                    return usageError(ctx, build_usage, "{f} needs a value", .{opt});
                try features.append(ctx.arena, feature);
            } else if (opt.isSwitch("help", 'h')) {
                return showHelp(ctx, build_usage);
            } else {
                return usageError(ctx, build_usage, "unknown option '{f}'", .{opt});
            }
        },
    };

    if (!ctx.global.quiet) {
        try ctx.stdout.print(
            "build: output={s} jobs={d} release={} color={s} features={d} sources={d}\n",
            .{
                output,
                jobs,
                release,
                @tagName(ctx.global.color),
                features.items.len,
                sources.items.len,
            },
        );
        if (ctx.global.verbose > 0) {
            for (features.items) |feature| {
                try ctx.stdout.print("feature: {s}\n", .{feature});
            }
        }
        if (ctx.global.verbose > 1) {
            for (sources.items) |source| {
                try ctx.stdout.print("source: {s}\n", .{source});
            }
        }
    }
    return 0;
}

fn runCommand(ctx: *Ctx) !u8 {
    var dry_run = false;
    var argv: std.ArrayList([]const u8) = .empty;

    while (ctx.args.next()) |tok| switch (tok) {
        .positional => |arg| try argv.append(ctx.arena, arg),
        .option => |opt| {
            if (opt.isSwitch("dry-run", null)) {
                dry_run = true;
            } else if (opt.isSwitch("help", 'h')) {
                return showHelp(ctx, run_usage);
            } else {
                return usageError(ctx, run_usage, "unknown option '{f}'", .{opt});
            }
        },
    };

    if (argv.items.len == 0) {
        return usageError(ctx, run_usage, "expected a program to run", .{});
    }

    if (!ctx.global.quiet) {
        try ctx.stdout.writeAll(if (dry_run) "dry-run:" else "run:");
        for (argv.items) |arg| try ctx.stdout.print(" {s}", .{arg});
        try ctx.stdout.writeAll("\n");
    }
    return 0;
}

fn config(ctx: *Ctx) !u8 {
    const tok = ctx.args.next() orelse return showHelp(ctx, config_usage);

    const name = switch (tok) {
        .positional => |value| value,
        .option => |opt| {
            if (opt.isSwitch("help", 'h')) return showHelp(ctx, config_usage);
            return usageError(ctx, config_usage, "unknown option '{f}'", .{opt});
        },
    };

    const cmd = stringToEnum(ConfigCmd, name) orelse
        return usageError(ctx, config_usage, "unknown command '{s}'", .{name});

    return switch (cmd) {
        .get => configGet(ctx),
        .set => configSet(ctx),
        .remove => configRemove(ctx),
        .list => configList(ctx),
    };
}

fn configGet(ctx: *Ctx) !u8 {
    if (helpRequested(ctx.args)) return showHelp(ctx, config_get_usage);

    const key = (try takePositional(ctx, config_get_usage)) orelse return 2;
    if (ctx.args.next()) |extra| return extraArgument(ctx, extra, config_get_usage);

    if (!ctx.global.quiet) try ctx.stdout.print("{s}=demo\n", .{key});
    return 0;
}

fn configSet(ctx: *Ctx) !u8 {
    if (helpRequested(ctx.args)) return showHelp(ctx, config_set_usage);

    const key = (try takePositional(ctx, config_set_usage)) orelse return 2;
    const value = (try takePositional(ctx, config_set_usage)) orelse return 2;
    if (ctx.args.next()) |extra| return extraArgument(ctx, extra, config_set_usage);

    if (!ctx.global.quiet) try ctx.stdout.print("set {s}={s}\n", .{ key, value });
    return 0;
}

fn configRemove(ctx: *Ctx) !u8 {
    if (helpRequested(ctx.args)) return showHelp(ctx, config_remove_usage);

    const key = (try takePositional(ctx, config_remove_usage)) orelse return 2;
    if (ctx.args.next()) |extra| return extraArgument(ctx, extra, config_remove_usage);

    if (!ctx.global.quiet) try ctx.stdout.print("removed {s}\n", .{key});
    return 0;
}

fn configList(ctx: *Ctx) !u8 {
    if (helpRequested(ctx.args)) return showHelp(ctx, config_list_usage);
    if (ctx.args.next()) |extra| return extraArgument(ctx, extra, config_list_usage);

    if (!ctx.global.quiet) {
        try ctx.stdout.writeAll("color=auto\n");
        try ctx.stdout.writeAll("jobs=1\n");
    }
    return 0;
}

fn helpCommand(ctx: *Ctx) !u8 {
    const tok = ctx.args.next() orelse return showHelp(ctx, top_usage);

    const name = switch (tok) {
        .positional => |value| value,
        .option => |opt| {
            if (opt.isSwitch("help", 'h')) return showHelp(ctx, top_usage);
            return usageError(ctx, top_usage, "unknown option '{f}'", .{opt});
        },
    };

    const cmd = stringToEnum(Cmd, name) orelse
        return usageError(ctx, top_usage, "unknown command '{s}'", .{name});

    if (ctx.args.next()) |extra| return extraArgument(ctx, extra, top_usage);

    return showHelp(ctx, usageFor(cmd));
}

fn usageFor(cmd: Cmd) []const u8 {
    return switch (cmd) {
        .build => build_usage,
        .run => run_usage,
        .config => config_usage,
        .help => top_usage,
    };
}

fn usageError(ctx: *Ctx, usage: []const u8, comptime fmt: []const u8, args: anytype) !u8 {
    try ctx.stderr.print("{s}: " ++ fmt ++ "\n", .{ctx.prog} ++ args);
    try ctx.stderr.writeAll(usage);
    return 2;
}

fn showHelp(ctx: *Ctx, usage: []const u8) !u8 {
    try ctx.stdout.writeAll(usage);
    return 0;
}

fn helpRequested(args: *cli.Args) bool {
    const next = args.peekRaw() orelse return false;
    if (std.mem.eql(u8, next, "-h") or std.mem.eql(u8, next, "--help")) {
        _ = args.nextRaw();
        return true;
    }
    return false;
}

fn takePositional(ctx: *Ctx, usage: []const u8) !?[]const u8 {
    const tok = ctx.args.next() orelse {
        try ctx.stderr.writeAll(usage);
        return null;
    };
    return switch (tok) {
        .positional => |value| value,
        .option => |opt| {
            try ctx.stderr.print("{s}: unexpected option '{f}'\n", .{ ctx.prog, opt });
            try ctx.stderr.writeAll(usage);
            return null;
        },
    };
}

fn extraArgument(ctx: *Ctx, tok: cli.Token, usage: []const u8) !u8 {
    return switch (tok) {
        .positional => |value| usageError(ctx, usage, "unexpected argument '{s}'", .{value}),
        .option => |opt| usageError(ctx, usage, "unexpected option '{f}'", .{opt}),
    };
}

fn flushQuietly(writer: *Io.Writer) void {
    writer.flush() catch |err| {
        std.debug.print("kitchen: flush failed: {s}\n", .{@errorName(err)});
    };
}
