//! `tar`-shaped demo: short clusters where the last flag may take a value.
//!
//!   tar -xzvf archive.tar.gz
//!   tar -xzfarchive.tar.gz
//!   tar -C /tmp -xf a.tar
//!   tar -farchive.tar.gz -x
//!
//! The cursor yields one short option at a time. A flag that takes a value
//! calls `takeValue`, which consumes the rest of the cluster first:
//! `-xzfarchive.tar.gz` gives `f` the value `archive.tar.gz`, and
//! `-xzvf archive.tar.gz` gives `f` the next token.

const std = @import("std");
const Io = std.Io;

const cli = @import("cli");

const usage =
    \\usage: tar [-tzxv] [-f archive] [-C dir] [--] [member...]
    \\  -t   list the archive
    \\  -x   extract
    \\  -z   gzip
    \\  -v   verbose
    \\  -f   archive file
    \\  -C   change directory
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

    var list = false;
    var extract = false;
    var gzip = false;
    var verbose = false;
    var archive: ?[]const u8 = null;
    var directory: ?[]const u8 = null;
    var members: std.ArrayList([]const u8) = .empty;

    while (args.next()) |tok| switch (tok) {
        .positional => |member| try members.append(arena, member),
        .option => |opt| {
            if (opt.isSwitch("list", 't')) {
                list = true;
            } else if (opt.isSwitch("extract", 'x')) {
                extract = true;
            } else if (opt.isSwitch("gzip", 'z')) {
                gzip = true;
            } else if (opt.isSwitch("verbose", 'v')) {
                verbose = true;
            } else if (opt.is("file", 'f')) {
                archive = args.takeValue(opt) orelse {
                    try stderr.print("tar: {f} needs a value\n", .{opt});
                    try stderr.writeAll(usage);
                    return 2;
                };
            } else if (opt.is("directory", 'C')) {
                directory = args.takeValue(opt) orelse {
                    try stderr.print("tar: {f} needs a value\n", .{opt});
                    try stderr.writeAll(usage);
                    return 2;
                };
            } else if (opt.isSwitch("help", null)) {
                try stdout.writeAll(usage);
                return 0;
            } else {
                try stderr.print("tar: unknown option '{f}'\n", .{opt});
                try stderr.writeAll(usage);
                return 2;
            }
        },
    };

    try stdout.print("list={} extract={} gzip={} verbose={}\n", .{ list, extract, gzip, verbose });
    try stdout.print("archive={s} directory={s}\n", .{ archive orelse "-", directory orelse "." });
    for (members.items) |member| try stdout.print("member: {s}\n", .{member});
    return 0;
}
