//! A small git-shaped demo: top-level dispatch, nested dispatch, flags, and
//! fixed arity. The program owns its writers; the library owns none.

const std = @import("std");
const Io = std.Io;
const stringToEnum = std.meta.stringToEnum;

const cli = @import("cli");

const Cmd = enum { remote, commit, status };
const RemoteCmd = enum { add, list, remove };

const top_usage =
    \\usage: cli <command> [args]
    \\  cli remote <add|list|remove> ...   manage remotes
    \\  cli commit [-a] -m <message>       record a commit
    \\  cli status [-s] [-b]               show the worktree state
    \\  -h, --help                         show this help
    \\
;

const remote_usage =
    \\usage: cli remote <command> [args]
    \\  cli remote add <name> <url>   add a remote
    \\  cli remote list              list remotes
    \\  cli remote remove <name>     remove a remote
    \\
;

const remote_add_usage = "usage: cli remote add <name> <url>\n";
const remote_list_usage = "usage: cli remote list\n";
const remote_remove_usage = "usage: cli remote remove <name>\n";

const commit_usage =
    \\usage: cli commit [-a] -m <message>
    \\  -m, --message <message>   the commit message
    \\  -a, --amend               amend the previous commit
    \\  -q, --quiet               do not print the commit summary
    \\  -h, --help                show this help
    \\
;

const status_usage =
    \\usage: cli status [-s] [-b]
    \\  -s, --short    show short format
    \\  -b, --branch   show the branch
    \\  -h, --help     show this help
    \\
;

const Ctx = struct {
    stdout: *Io.Writer,
    stderr: *Io.Writer,
    args: *cli.Args,
    prog: []const u8,
};

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
        try stderr.print("cli: cannot read arguments: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer args.deinit();

    const prog = if (args.program_name.len > 0)
        std.fs.path.basename(args.program_name)
    else
        "cli";

    var ctx: Ctx = .{ .stdout = stdout, .stderr = stderr, .args = &args, .prog = prog };
    return run(&ctx);
}

fn run(ctx: *Ctx) !u8 {
    const tok = ctx.args.next() orelse {
        try ctx.stderr.writeAll(top_usage);
        return 2;
    };

    const command = switch (tok) {
        .positional => |name| name,
        .option => |opt| {
            if (opt.isSwitch("help", 'h')) return showHelp(ctx, top_usage);
            return usageError(ctx, top_usage, "unknown option '{f}'", .{opt});
        },
    };

    const cmd = stringToEnum(Cmd, command) orelse
        return usageError(ctx, top_usage, "unknown command '{s}'", .{command});

    return switch (cmd) {
        .remote => remote(ctx),
        .commit => commit(ctx),
        .status => status(ctx),
    };
}

fn remote(ctx: *Ctx) !u8 {
    const tok = ctx.args.next() orelse {
        try ctx.stderr.writeAll(remote_usage);
        return 2;
    };

    const name = switch (tok) {
        .positional => |value| value,
        .option => |opt| {
            if (opt.isSwitch("help", 'h')) return showHelp(ctx, remote_usage);
            return usageError(ctx, remote_usage, "unknown option '{f}'", .{opt});
        },
    };

    const cmd = stringToEnum(RemoteCmd, name) orelse
        return usageError(ctx, remote_usage, "unknown command '{s}'", .{name});

    return switch (cmd) {
        .add => remoteAdd(ctx),
        .list => remoteList(ctx),
        .remove => remoteRemove(ctx),
    };
}

fn remoteAdd(ctx: *Ctx) !u8 {
    if (helpRequested(ctx.args)) return showHelp(ctx, remote_add_usage);

    const name = (try takePositional(ctx, remote_add_usage)) orelse return 2;
    const url = (try takePositional(ctx, remote_add_usage)) orelse return 2;
    if (ctx.args.next()) |extra| return extraArgument(ctx, extra, remote_add_usage);

    try ctx.stdout.print("added remote {s} -> {s}\n", .{ name, url });
    return 0;
}

fn remoteList(ctx: *Ctx) !u8 {
    if (helpRequested(ctx.args)) return showHelp(ctx, remote_list_usage);
    if (ctx.args.next()) |extra| return extraArgument(ctx, extra, remote_list_usage);

    try ctx.stdout.writeAll("origin\n");
    return 0;
}

fn remoteRemove(ctx: *Ctx) !u8 {
    if (helpRequested(ctx.args)) return showHelp(ctx, remote_remove_usage);

    const name = (try takePositional(ctx, remote_remove_usage)) orelse return 2;
    if (ctx.args.next()) |extra| return extraArgument(ctx, extra, remote_remove_usage);

    try ctx.stdout.print("removed {s}\n", .{name});
    return 0;
}

fn commit(ctx: *Ctx) !u8 {
    var message: ?[]const u8 = null;
    var amend = false;
    var quiet = false;

    while (ctx.args.next()) |tok| switch (tok) {
        .positional => |value| return usageError(ctx, commit_usage, "unexpected argument '{s}'", .{value}),
        .option => |opt| {
            if (opt.is("message", 'm')) {
                message = ctx.args.takeValue(opt) orelse
                    return usageError(ctx, commit_usage, "{f} needs a value", .{opt});
            } else if (opt.isSwitch("amend", 'a')) {
                amend = true;
            } else if (opt.isSwitch("quiet", 'q')) {
                quiet = true;
            } else if (opt.isSwitch("help", 'h')) {
                return showHelp(ctx, commit_usage);
            } else {
                return usageError(ctx, commit_usage, "unknown option '{f}'", .{opt});
            }
        },
    };

    const msg = message orelse
        return usageError(ctx, commit_usage, "--message is required", .{});

    if (!quiet) try ctx.stdout.print("committing: {s}{s}\n", .{ msg, if (amend) " (amend)" else "" });
    return 0;
}

fn status(ctx: *Ctx) !u8 {
    var short = false;
    var branch = false;

    while (ctx.args.next()) |tok| switch (tok) {
        .positional => |value| return usageError(ctx, status_usage, "unexpected argument '{s}'", .{value}),
        .option => |opt| {
            if (opt.isSwitch("short", 's')) {
                short = true;
            } else if (opt.isSwitch("branch", 'b')) {
                branch = true;
            } else if (opt.isSwitch("help", 'h')) {
                return showHelp(ctx, status_usage);
            } else {
                return usageError(ctx, status_usage, "unknown option '{f}'", .{opt});
            }
        },
    };

    try ctx.stdout.print("status: short={} branch={}\n", .{ short, branch });
    return 0;
}

fn usageError(ctx: *Ctx, usage: []const u8, comptime fmt: []const u8, args: anytype) !u8 {
    try cli.fail(ctx.stderr, ctx.prog, usage, fmt, args);
    return 2;
}

fn showHelp(ctx: *Ctx, usage: []const u8) !u8 {
    try cli.help(ctx.stdout, usage);
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
            try cli.fail(ctx.stderr, ctx.prog, usage, "unexpected option '{f}'", .{opt});
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
        std.debug.print("cli: flush failed: {s}\n", .{@errorName(err)});
    };
}
