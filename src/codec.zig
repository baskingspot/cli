//! Typed values for flag text.
//!
//! `parse` converts the slice that `Args.takeValue` returns into a value. The
//! built-in codecs cover the primitive types. A struct, union, opaque type, or
//! enum joins by declaring a `parse` function in its namespace:
//!
//!     pub fn parse(raw: []const u8) !Self
//!
//! The codec never writes text: the command owns the flag name, the usage
//! string, and the error message.

const std = @import("std");
const ascii = std.ascii;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;

/// The errors the built-in codecs return. A custom `parse` may return its own.
pub const Error = error{
    /// The text is not a value of the requested type.
    InvalidValue,
    /// The text is a number that does not fit in the requested type.
    Overflow,
};

/// Parse `raw` as `T`.
///
/// - `bool`: the spellings Go's `strconv.ParseBool` accepts: `1`, `t`, `T`,
///   `TRUE`, `true`, `True`, and the false equivalents.
/// - `i8`..`i128`, `u8`..`u128`, `isize`, `usize`: base 10, with an optional
///   leading sign. A number that does not fit returns `error.Overflow`.
/// - `f16`..`f128`: the syntax `std.fmt.parseFloat` accepts.
/// - `[]const u8`: the text unchanged, borrowed from `raw`.
/// - an enum: the tag name, matched like `std.meta.stringToEnum`.
/// - a struct, union, or opaque type with `pub fn parse(raw: []const u8) !Self`:
///   that function runs, and its errors pass through.
///
/// Any other type is a compile error.
pub fn parse(comptime T: type, raw: []const u8) !T {
    if (T == []const u8) return raw;

    return switch (@typeInfo(T)) {
        .bool => parseBool(raw) orelse error.InvalidValue,
        .int => std.fmt.parseInt(T, raw, 10) catch |err| switch (err) {
            error.InvalidCharacter => error.InvalidValue,
            error.Overflow => error.Overflow,
        },
        .float => std.fmt.parseFloat(T, raw) catch error.InvalidValue,
        .@"enum" => if (meta.hasFn(T, "parse"))
            T.parse(raw)
        else
            meta.stringToEnum(T, raw) orelse error.InvalidValue,
        .@"struct", .@"union", .@"opaque" => if (meta.hasFn(T, "parse"))
            T.parse(raw)
        else
            @compileError("cli.parse: " ++ @typeName(T) ++ " has no parse function"),
        else => @compileError("cli.parse: " ++ @typeName(T) ++ " is not a codec type"),
    };
}

fn parseBool(raw: []const u8) ?bool {
    return std.StaticStringMap(bool).initComptime(.{
        .{ "true", true },
        .{ "TRUE", true },
        .{ "True", true },
        .{ "t", true },
        .{ "T", true },
        .{ "1", true },
        .{ "false", false },
        .{ "FALSE", false },
        .{ "False", false },
        .{ "f", false },
        .{ "F", false },
        .{ "0", false },
    }).get(raw);
}

test "bool" {
    for ([_][]const u8{ "true", "TRUE", "True", "t", "T", "1" }) |raw| {
        try testing.expectEqual(true, try parse(bool, raw));
    }
    for ([_][]const u8{ "false", "FALSE", "False", "f", "F", "0" }) |raw| {
        try testing.expectEqual(false, try parse(bool, raw));
    }
    try testing.expectError(error.InvalidValue, parse(bool, "yes"));
    try testing.expectError(error.InvalidValue, parse(bool, "tRuE"));
    try testing.expectError(error.InvalidValue, parse(bool, "2"));
    try testing.expectError(error.InvalidValue, parse(bool, ""));
    try testing.expectError(error.InvalidValue, parse(bool, " true"));
}

test "integers" {
    try testing.expectEqual(@as(u16, 8080), try parse(u16, "8080"));
    try testing.expectEqual(@as(i32, -42), try parse(i32, "-42"));
    try testing.expectEqual(@as(i128, -1), try parse(i128, "-1"));
    try testing.expectEqual(@as(usize, 0), try parse(usize, "0"));
    try testing.expectEqual(
        @as(u64, std.math.maxInt(u64)),
        try parse(u64, "18446744073709551615"),
    );

    try testing.expectError(error.Overflow, parse(u8, "256"));
    try testing.expectError(error.Overflow, parse(u32, "-1"));
    try testing.expectError(error.InvalidValue, parse(u16, "0x10"));
    try testing.expectError(error.InvalidValue, parse(u16, ""));
    try testing.expectError(error.InvalidValue, parse(u16, " 1"));
    try testing.expectError(error.InvalidValue, parse(u16, "1 "));
}

test "floats" {
    try testing.expectEqual(@as(f32, 1.5), try parse(f32, "1.5"));
    try testing.expectEqual(@as(f64, -2500.0), try parse(f64, "-2.5e3"));
    try testing.expectError(error.InvalidValue, parse(f64, "pancake"));
    try testing.expectError(error.InvalidValue, parse(f64, ""));
}

test "string" {
    const raw = "hello";
    const value = try parse([]const u8, raw);
    try testing.expectEqualStrings(raw, value);
    try testing.expect(value.ptr == raw.ptr);
    try testing.expectEqualStrings("", try parse([]const u8, ""));
}

test "enum" {
    const Color = enum { auto, always, never };
    try testing.expectEqual(Color.always, try parse(Color, "always"));
    try testing.expectError(error.InvalidValue, parse(Color, "sometimes"));
    try testing.expectError(error.InvalidValue, parse(Color, ""));
}

const Range = struct {
    low: u16,
    high: u16,

    pub fn parse(raw: []const u8) error{InvalidValue}!Range {
        const dash = mem.findScalar(u8, raw, '-') orelse return error.InvalidValue;
        const low = std.fmt.parseInt(u16, raw[0..dash], 10) catch return error.InvalidValue;
        const high = std.fmt.parseInt(u16, raw[dash + 1 ..], 10) catch return error.InvalidValue;
        if (low > high) return error.InvalidValue;
        return .{ .low = low, .high = high };
    }
};

test "custom struct with parse" {
    const range = try parse(Range, "1-4");
    try testing.expectEqual(1, range.low);
    try testing.expectEqual(4, range.high);
    try testing.expectError(error.InvalidValue, parse(Range, "4-1"));
    try testing.expectError(error.InvalidValue, parse(Range, "1:4"));
}

const Reserved = struct {
    pub fn parse(raw: []const u8) error{Reserved}!Reserved {
        _ = raw;
        return error.Reserved;
    }
};

test "custom errors pass through" {
    try testing.expectError(error.Reserved, parse(Reserved, "anything"));
}

test "a std type with parse" {
    const version = try parse(std.SemanticVersion, "1.2.3-beta+build");
    try testing.expectEqual(1, version.major);
    try testing.expectEqual(2, version.minor);
    try testing.expectEqual(3, version.patch);
    try testing.expectEqualStrings("beta", version.pre.?);
    try testing.expectEqualStrings("build", version.build.?);
}
