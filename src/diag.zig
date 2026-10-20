//! Diagnostic helpers. They write to a caller-provided writer. The library
//! owns no streams, allocates nothing, and flushes nothing.

const std = @import("std");
const Io = std.Io;
const testing = std.testing;

/// Write usage text to `writer`.
pub fn help(writer: *Io.Writer, usage: []const u8) Io.Writer.Error!void {
    try writer.writeAll(usage);
}

/// Write a usage error to `writer`: `prefix: message`, then `usage`.
///
/// The caller supplies the message format and the exit code. The writer can
/// fail, so the caller can propagate the error or drop it with `catch`.
pub fn fail(
    writer: *Io.Writer,
    prefix: []const u8,
    usage: []const u8,
    comptime fmt: []const u8,
    args: anytype,
) Io.Writer.Error!void {
    try writer.print("{s}: " ++ fmt ++ "\n", .{prefix} ++ args);
    try writer.writeAll(usage);
}

test "fail writes the prefix, message, and usage" {
    var buffer: [256]u8 = undefined;
    var writer: Io.Writer = .fixed(&buffer);
    try fail(&writer, "mytool", "usage: mytool\n", "unknown option '{s}'", .{"--wat"});
    try testing.expectEqualStrings(
        "mytool: unknown option '--wat'\nusage: mytool\n",
        writer.buffered(),
    );
}

test "help writes the usage text" {
    var buffer: [64]u8 = undefined;
    var writer: Io.Writer = .fixed(&buffer);
    try help(&writer, "usage: mytool\n");
    try testing.expectEqualStrings("usage: mytool\n", writer.buffered());
}
