//! Verbosity counter demo: `-vvvv` and `-v -v -v` both count four.
//!
//!   cli-verbose -vvvv build
//!   cli-verbose --verbose --verbose build
//!
//! The cursor yields one short option at a time, so the counter is just an
//! increment in the `v` branch. A cluster needs no special handling.

const std = @import("std");
const Io = std.Io;

const cli = @import("cli");

const usage =
    \\usage: verbose [-v]... [--] [arg...]
    \\  -v, --verbose   increase verbosity (repeatable)
    \\  --help          show this help
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

    var level: u8 = 0;
    var rest: std.ArrayList([]const u8) = .empty;

    while (args.next()) |tok| switch (tok) {
        .positional => |arg| try rest.append(arena, arg),
        .option => |opt| {
            if (opt.isSwitch("verbose", 'v')) {
                level = level +| 1;
            } else if (opt.isSwitch("help", null)) {
                try cli.help(stdout, usage);
                return 0;
            } else {
                try cli.fail(stderr, "verbose", usage, "unknown option '{f}'", .{opt});
                return 2;
            }
        },
    };

    try stdout.print("verbosity={d}\n", .{level});
    for (rest.items) |arg| try stdout.print("arg: {s}\n", .{arg});
    return 0;
}
