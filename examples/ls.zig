//! `ls`-shaped demo: short-option clusters and the `--` terminator.
//!
//!   ls -lah
//!   ls -lah -- --some-folder
//!   ls -- -l
//!
//! Everything after `--` is a path, even when it starts with a dash.

const std = @import("std");
const Io = std.Io;

const cli = @import("cli");

const usage =
    \\usage: ls [-1ahl] [--] [path...]
    \\  -1   one entry per line
    \\  -a   include hidden entries
    \\  -h   human-readable sizes
    \\  -l   long format
    \\  --help  show this help
    \\
;

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file: Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_file.interface;
    defer stdout.flush() catch {};

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file: Io.File.Writer = .initStreaming(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_file.interface;
    defer stderr.flush() catch {};

    var args: cli.Args = .init(init.minimal.args);
    defer args.deinit();

    var one = false;
    var all = false;
    var human = false;
    var long = false;
    var paths: std.ArrayList([]const u8) = .empty;

    while (args.next()) |tok| switch (tok) {
        .positional => |path| try paths.append(arena, path),
        .option => |opt| {
            if (opt.isSwitch("one", '1')) {
                one = true;
            } else if (opt.isSwitch("all", 'a')) {
                all = true;
            } else if (opt.isSwitch("human-readable", 'h')) {
                human = true;
            } else if (opt.isSwitch("long", 'l')) {
                long = true;
            } else if (opt.isSwitch("help", null)) {
                try stdout.writeAll(usage);
                return 0;
            } else {
                try stderr.print("ls: unknown option '{f}'\n", .{opt});
                try stderr.writeAll(usage);
                return 2;
            }
        },
    };

    try stdout.print("one={} all={} human={} long={}\n", .{ one, all, human, long });
    if (paths.items.len == 0) {
        try stdout.writeAll("path: .\n");
    } else {
        for (paths.items) |path| try stdout.print("path: {s}\n", .{path});
    }
    return 0;
}
