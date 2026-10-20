//! Value codecs stay in the command. The cursor hands over a string, and
//! `std.fmt.parseInt` or `std.meta.stringToEnum` turns it into a typed value.
//!
//!   cli-codec --port 8080 --color always file.txt
//!   cli-codec --port nope
//!   cli-codec --color sometimes
//!
//! The error text names the flag and the bad value because the command owns
//! both. The library only knows that `--port` carried a value.

const std = @import("std");
const Io = std.Io;

const cli = @import("cli");

const Color = enum { auto, always, never };

const usage =
    \\usage: codec [--port n] [--color WHEN] [--] [arg...]
    \\  --port <n>       integer, 0 to 65535
    \\  --color <when>   auto, always, or never
    \\  --help           show this help
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

    var port: u16 = 8080;
    var color: Color = .auto;
    var rest: std.ArrayList([]const u8) = .empty;

    while (args.next()) |tok| switch (tok) {
        .positional => |arg| try rest.append(arena, arg),
        .option => |opt| {
            if (opt.isLong("port")) {
                const raw = args.takeValue(opt) orelse {
                    try stderr.print("codec: {f} needs a value\n", .{opt});
                    try stderr.writeAll(usage);
                    return 2;
                };
                port = std.fmt.parseInt(u16, raw, 10) catch {
                    try stderr.print("codec: {f}: expected 0 to 65535, got '{s}'\n", .{ opt, raw });
                    try stderr.writeAll(usage);
                    return 2;
                };
            } else if (opt.isLong("color")) {
                const raw = args.takeValue(opt) orelse {
                    try stderr.print("codec: {f} needs a value\n", .{opt});
                    try stderr.writeAll(usage);
                    return 2;
                };
                color = std.meta.stringToEnum(Color, raw) orelse {
                    try stderr.print("codec: {f}: expected auto, always, or never, got '{s}'\n", .{ opt, raw });
                    try stderr.writeAll(usage);
                    return 2;
                };
            } else if (opt.isSwitch("help", null)) {
                try stdout.writeAll(usage);
                return 0;
            } else {
                try stderr.print("codec: unknown option '{f}'\n", .{opt});
                try stderr.writeAll(usage);
                return 2;
            }
        },
    };

    try stdout.print("port={d} color={s}\n", .{ port, @tagName(color) });
    for (rest.items) |arg| try stdout.print("arg: {s}\n", .{arg});
    return 0;
}
