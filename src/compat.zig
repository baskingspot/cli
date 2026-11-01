//! Shims for the Zig 0.16 and 0.17 APIs. Private to the module.

const std = @import("std");
const mem = std.mem;

// `std.fmt.allocPrint`/`bufPrint` are the only spelling that compiles on
// 0.16; 0.17 moved them to `Allocator.print` and `mem.print`. Lint runs
// against the 0.16 std (`ziglint-0-16`), so the fallback is not deprecated.
// ziglint-ignore: Z023 -- mirrors the std.fmt argument order
pub fn allocPrint(a: mem.Allocator, comptime format: []const u8, args: anytype) ![]u8 {
    if (comptime @hasDecl(mem.Allocator, "print")) return a.print(format, args);
    return std.fmt.allocPrint(a, format, args);
}

// ziglint-ignore: Z023 -- mirrors the std.fmt argument order
pub fn bufPrint(buf: []u8, comptime format: []const u8, args: anytype) ![]u8 {
    if (comptime @hasDecl(mem, "print")) return mem.print(buf, format, args);
    return std.fmt.bufPrint(buf, format, args);
}
