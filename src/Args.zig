//! A cursor over command-line arguments: classifies tokens into options and
//! positionals, but never decides what an option means.
//!
//! The grammar is deliberately small:
//!
//!   --name           long option, no inline value
//!   --name=value     long option with an inline value
//!   -n               short option
//!   -abc             three short options, in order
//!   -ovalue          short option with an attached value (the rest)
//!   -n value         short option whose value is the next token
//!   --               ends option parsing; every later token is positional
//!   -                positional (the conventional stdin marker)
//!
//! `-n=value` is not special. The value of `n` is `=value`, which is the
//! usual getopt behavior.
//!
//! The `--` token itself is not returned. The cursor swallows it and flips
//! to positional mode.
//!
//! Options are recognized after positionals. A command that wants POSIX
//! stop-at-first-positional switches to `nextRaw` after the first one.
//!
//! Short options are yielded one at a time. `Option.attached` is the rest of
//! the same token. If the app calls `takeValue`, that rest becomes the value
//! and the cluster ends; if it does not, the cursor yields the next short
//! option. The cursor never needs to know which options take values.
//!
//! `Args` does not allocate an argv slice, print, or exit. It either owns a
//! `process.Args.Iterator` (built with `init` or `initAllocator`) or
//! borrows a slice of tokens (built with `fromSlice`, for tests and
//! embedding).

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const process = std.process;
const Io = std.Io;
const testing = std.testing;
const assert = std.debug.assert;
pub const InitError = process.Args.Iterator.InitError;

const Args = @This();

source: Source,
/// The program name, the first argv token. `init` and `initAllocator`
/// capture it before advancing the iterator. A slice cursor leaves it
/// empty; set the field directly when the name matters. It is invalid
/// after `deinit`.
program_name: []const u8 = "",
/// The raw token that produced the current short-option cluster.
current: []const u8 = &.{},
/// The unconsumed short-option bytes in `current`.
pending: []const u8 = &.{},
options_done: bool = false,
peeked: ?[]const u8 = null,

pub const Source = union(enum) {
    process: process.Args.Iterator,
    slice: Slice,
};

pub const Slice = struct {
    tokens: []const []const u8,
    index: usize = 0,
};

/// Build a cursor over the process arguments. The cursor captures the
/// first token as `program_name`, then owns the iterator; call `deinit`.
///
/// This is the allocation-free constructor. Like
/// `process.Args.Iterator.init`, it does not compile on Windows or
/// WASI; use `initAllocator` there. On POSIX it allocates nothing.
///
/// The returned slices point into the iterator's buffer and remain valid
/// until `deinit`.
pub fn init(raw: process.Args) Args {
    var it: process.Args.Iterator = .init(raw);
    return .{
        .program_name = it.next() orelse "",
        .source = .{ .process = it },
    };
}

/// Build a cursor over the process arguments, with an allocator for the
/// platforms whose iterator needs a buffer. The cursor captures the first
/// token as `program_name`, then owns the iterator; call `deinit`.
///
/// `Args` reads one argument at a time; it does not build an argv slice.
/// The allocator is used only where the platform iterator needs a buffer
/// (Windows and WASI); POSIX allocates nothing.
///
/// The returned slices point into the iterator's buffer and remain valid
/// until `deinit`.
pub fn initAllocator(raw: process.Args, gpa: Allocator) InitError!Args {
    var it: process.Args.Iterator = try .initAllocator(raw, gpa);
    return .{
        .program_name = it.next() orelse "",
        .source = .{ .process = it },
    };
}

/// Build a cursor over a literal token slice, for tests and embedding.
/// `program_name` starts empty.
pub fn fromSlice(tokens: []const []const u8) Args {
    return .{ .source = .{ .slice = .{ .tokens = tokens } } };
}

/// Release the process iterator, if this cursor owns one. A slice cursor
/// has nothing to release.
pub fn deinit(self: *Args) void {
    switch (self.source) {
        .process => self.source.process.deinit(),
        .slice => {},
    }
    self.* = undefined;
}

/// Return the next classified token, or null at the end.
pub fn next(self: *Args) ?Token {
    if (self.pending.len > 0) return self.nextShort();

    const raw = self.nextArg() orelse return null;
    self.current = raw;

    if (self.options_done) return .{ .positional = raw };

    if (mem.eql(u8, raw, "--")) {
        self.options_done = true;
        return self.next();
    }

    if (raw.len < 2 or raw[0] != '-') return .{ .positional = raw };

    if (raw[1] == '-') {
        const body = raw[2..];
        if (mem.findScalar(u8, body, '=')) |eq| {
            return .{ .option = .{
                .text = raw,
                .kind = .long,
                .name = body[0..eq],
                .inline_value = body[eq + 1 ..],
                .attached = &.{},
            } };
        }
        return .{ .option = .{
            .text = raw,
            .kind = .long,
            .name = body,
            .inline_value = null,
            .attached = &.{},
        } };
    }

    self.pending = raw[1..];
    return self.nextShort();
}

fn nextShort(self: *Args) Token {
    const name = self.pending[0..1];
    const attached = self.pending[1..];
    self.pending = attached;
    return .{ .option = .{
        .text = self.current,
        .kind = .short,
        .name = name,
        .inline_value = null,
        .attached = attached,
    } };
}

/// The value for `opt`: the inline `--name=value`, the rest of a short
/// cluster, or the next raw token. Returns null if there is no next token.
///
/// The next token is consumed even when it starts with a dash, so
/// `--message -oops` gives the message `-oops`. The app decides whether
/// that is valid.
///
/// Call this at most once per option. A boolean option must not call it;
/// the cursor then keeps yielding the rest of the cluster. For an
/// optional value, use `peekRaw` and `isOption` first.
pub fn takeValue(self: *Args, opt: Option) ?[]const u8 {
    if (opt.inline_value) |value| return value;
    if (opt.attached.len > 0) {
        self.pending = &.{};
        return opt.attached;
    }
    return self.nextArg();
}

/// Return the next raw argv token without classifying it. This is the
/// escape hatch for token streams that deliberately bypass option
/// parsing. Do not call it while a short cluster is pending; use
/// `takeValue` or keep calling `next`.
pub fn nextRaw(self: *Args) ?[]const u8 {
    assert(self.pending.len == 0);
    return self.nextArg();
}

/// Look at the next raw argv token without consuming it. Do not call
/// while a short cluster is pending.
pub fn peekRaw(self: *Args) ?[]const u8 {
    assert(self.pending.len == 0);
    if (self.peeked == null) self.peeked = self.readArg();
    return self.peeked;
}

fn nextArg(self: *Args) ?[]const u8 {
    if (self.peeked) |tok| {
        self.peeked = null;
        return tok;
    }
    return self.readArg();
}

fn readArg(self: *Args) ?[]const u8 {
    switch (self.source) {
        .process => return self.source.process.next(),
        .slice => {
            const slice = &self.source.slice;
            if (slice.index >= slice.tokens.len) return null;
            defer slice.index += 1;
            return slice.tokens[slice.index];
        },
    }
}

pub const Token = union(enum) {
    /// A token that is not option syntax. The slice points into the source
    /// tokens and lives as long as they do.
    positional: []const u8,
    option: Option,
};

pub const Option = struct {
    /// The exact argv token that carried this option, for diagnostics.
    text: []const u8,
    kind: Kind,
    /// The option name without dashes. For a short option this is one byte.
    name: []const u8,
    /// The part after `=` in `--name=value`, if any. Long options only.
    inline_value: ?[]const u8,
    /// The rest of a short cluster after this option. `-abc` yields `a` with
    /// `attached = "bc"`, then `b` with `attached = "c"`.
    attached: []const u8,

    pub const Kind = enum { long, short };

    pub fn is(self: *const Option, long: []const u8, short: ?u8) bool {
        if (self.isLong(long)) return true;
        if (short) |c| return self.isShort(c);
        return false;
    }

    pub fn isLong(self: *const Option, long: []const u8) bool {
        return self.kind == .long and mem.eql(u8, self.name, long);
    }

    pub fn isShort(self: *const Option, char: u8) bool {
        return self.kind == .short and self.name.len == 1 and self.name[0] == char;
    }

    /// Match a switch: a long option with no inline value, or a short option.
    /// A short option in a cluster still matches; the attached tail is the
    /// rest of the cluster, not a value.
    pub fn isSwitch(self: *const Option, long: []const u8, short: ?u8) bool {
        if (self.isLong(long)) return self.inline_value == null;
        if (short) |c| return self.isShort(c);
        return false;
    }

    /// Format the option for a diagnostic: `--name`, `--name=value`, or
    /// `-n`. A short cluster prints only the current letter, and a short
    /// attached value stays out of the spelling. Use `{f}` with a writer.
    pub fn format(self: *const Option, writer: *Io.Writer) Io.Writer.Error!void {
        switch (self.kind) {
            .long => {
                try writer.print("--{s}", .{self.name});
                if (self.inline_value) |value| try writer.print("={s}", .{value});
            },
            .short => try writer.print("-{c}", .{self.name[0]}),
        }
    }
};

/// True when the token starts option syntax: a dash followed by at least one
/// byte. `-` is positional; `--` is the separator and counts as option syntax
/// so optional-value logic does not swallow it.
pub fn isOption(token: []const u8) bool {
    return token.len > 1 and token[0] == '-';
}

fn expectPositional(args: *Args, expected: []const u8) !void {
    const tok = args.next() orelse return error.TestExpectedToken;
    switch (tok) {
        .positional => |value| try testing.expectEqualStrings(expected, value),
        .option => return error.TestExpectedPositional,
    }
}

fn expectOption(args: *Args, kind: Option.Kind, name: []const u8) !Option {
    const tok = args.next() orelse return error.TestExpectedToken;
    return switch (tok) {
        .option => |opt| {
            try testing.expectEqual(kind, opt.kind);
            try testing.expectEqualStrings(name, opt.name);
            return opt;
        },
        .positional => error.TestExpectedOption,
    };
}

fn expectFormatted(expected: []const u8, opt: Option) !void {
    const actual = try std.fmt.allocPrint(testing.allocator, "{f}", .{opt});
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(expected, actual);
}

test "positionals and the lone dash" {
    var args: Args = .fromSlice(&.{ "build", "-", "file" });
    try expectPositional(&args, "build");
    try expectPositional(&args, "-");
    try expectPositional(&args, "file");
    try testing.expectEqual(@as(?Token, null), args.next());
}

test "long option without a value" {
    var args: Args = .fromSlice(&.{"--verbose"});
    const opt = try expectOption(&args, .long, "verbose");
    try testing.expect(opt.isLong("verbose"));
    try testing.expect(opt.inline_value == null);
    try expectFormatted("--verbose", opt);
    try testing.expectEqual(@as(?Token, null), args.next());
}

test "long option with an inline value" {
    var args: Args = .fromSlice(&.{"--output=out.bin"});
    const opt = try expectOption(&args, .long, "output");
    try testing.expectEqualStrings("out.bin", opt.inline_value.?);
    try testing.expectEqualStrings("out.bin", args.takeValue(opt).?);
    try expectFormatted("--output=out.bin", opt);
}

test "long value in the next token" {
    var args: Args = .fromSlice(&.{ "--output", "out.bin" });
    const opt = try expectOption(&args, .long, "output");
    try testing.expectEqualStrings("out.bin", args.takeValue(opt).?);
    try testing.expectEqual(@as(?Token, null), args.next());
}

test "empty inline value and equals in the value" {
    var args: Args = .fromSlice(&.{ "--name=", "--query=a=b" });
    const name = try expectOption(&args, .long, "name");
    try testing.expectEqualStrings("", name.inline_value.?);
    try expectFormatted("--name=", name);
    const query = try expectOption(&args, .long, "query");
    try testing.expectEqualStrings("a=b", query.inline_value.?);
    try expectFormatted("--query=a=b", query);
}

test "format drops the short cluster tail" {
    var args: Args = .fromSlice(&.{"-ofile"});
    const opt = try expectOption(&args, .short, "o");
    try expectFormatted("-o", opt);
}

test "short options and clusters" {
    var args: Args = .fromSlice(&.{"-lah"});

    const l = try expectOption(&args, .short, "l");
    try testing.expect(l.is("long", 'l'));
    try testing.expectEqualStrings("ah", l.attached);
    try expectFormatted("-l", l);

    const a = try expectOption(&args, .short, "a");
    try testing.expect(a.is("all", 'a'));
    try testing.expectEqualStrings("h", a.attached);
    try expectFormatted("-a", a);

    const h = try expectOption(&args, .short, "h");
    try testing.expect(h.is("human-readable", 'h'));
    try testing.expectEqualStrings("", h.attached);
    try expectFormatted("-h", h);

    try testing.expectEqual(@as(?Token, null), args.next());
}

test "short cluster with an attached value" {
    var args: Args = .fromSlice(&.{ "-xzfarchive.tar.gz", "member" });

    _ = try expectOption(&args, .short, "x");
    _ = try expectOption(&args, .short, "z");
    const f = try expectOption(&args, .short, "f");
    try testing.expectEqualStrings("archive.tar.gz", f.attached);
    try testing.expectEqualStrings("archive.tar.gz", args.takeValue(f).?);
    try expectPositional(&args, "member");
}

test "short option with a value in the next token" {
    var args: Args = .fromSlice(&.{ "-f", "archive.tar.gz" });
    const f = try expectOption(&args, .short, "f");
    try testing.expectEqualStrings("archive.tar.gz", args.takeValue(f).?);
    try testing.expectEqual(@as(?Token, null), args.next());
}

test "short option values are attached, not equals-separated" {
    var args: Args = .fromSlice(&.{"-o=out.bin"});
    const opt = try expectOption(&args, .short, "o");
    try testing.expectEqualStrings("=out.bin", opt.attached);
    try testing.expectEqualStrings("=out.bin", args.takeValue(opt).?);
}

test "double dash ends option parsing" {
    var args: Args = .fromSlice(&.{ "--verbose", "--", "--help", "-x", "--", "file" });

    const verbose = try expectOption(&args, .long, "verbose");
    try testing.expect(verbose.is("verbose", null));
    try expectPositional(&args, "--help");
    try expectPositional(&args, "-x");
    try expectPositional(&args, "--");
    try expectPositional(&args, "file");
    try testing.expectEqual(@as(?Token, null), args.next());
}

test "double dash with nothing after it" {
    var args: Args = .fromSlice(&.{"--"});
    try testing.expectEqual(@as(?Token, null), args.next());
}

test "everything after double dash is positional even when it looks like a flag" {
    var args: Args = .fromSlice(&.{ "--", "--some-folder", "-l", "--" });
    try expectPositional(&args, "--some-folder");
    try expectPositional(&args, "-l");
    try expectPositional(&args, "--");
    try testing.expectEqual(@as(?Token, null), args.next());
}

test "takeValue does not consume past an inline or attached value" {
    var inline_args: Args = .fromSlice(&.{ "--output=out.bin", "file" });
    const inline_opt = try expectOption(&inline_args, .long, "output");
    try testing.expectEqualStrings("out.bin", inline_args.takeValue(inline_opt).?);
    try expectPositional(&inline_args, "file");

    var attached: Args = .fromSlice(&.{ "-ofile", "next" });
    const attached_opt = try expectOption(&attached, .short, "o");
    try testing.expectEqualStrings("file", attached.takeValue(attached_opt).?);
    try expectPositional(&attached, "next");
}

test "takeValue at the end returns null" {
    var args: Args = .fromSlice(&.{"-f"});
    const opt = try expectOption(&args, .short, "f");
    try testing.expect(args.takeValue(opt) == null);
    try testing.expectEqual(@as(?Token, null), args.next());
}

test "takeValue consumes a double dash as a value" {
    var args: Args = .fromSlice(&.{ "-f", "--", "-x" });
    const opt = try expectOption(&args, .short, "f");
    try testing.expectEqualStrings("--", args.takeValue(opt).?);
    _ = try expectOption(&args, .short, "x");
}

test "peek then next classifies the peeked token" {
    var args: Args = .fromSlice(&.{"--verbose"});
    try testing.expectEqualStrings("--verbose", args.peekRaw().?);
    const opt = try expectOption(&args, .long, "verbose");
    try testing.expect(opt.isLong("verbose"));
}

test "peek then next sees the terminator" {
    var args: Args = .fromSlice(&.{ "--", "-l" });
    try testing.expectEqualStrings("--", args.peekRaw().?);
    try expectPositional(&args, "-l");
}

test "nextRaw bypasses cluster classification" {
    var args: Args = .fromSlice(&.{ "-lah", "file" });
    try testing.expectEqualStrings("-lah", args.nextRaw().?);
    try testing.expectEqualStrings("file", args.nextRaw().?);
    try testing.expect(args.nextRaw() == null);
}

test "peek and raw token access" {
    var args: Args = .fromSlice(&.{ "first", "second" });
    try testing.expectEqualStrings("first", args.peekRaw().?);
    try testing.expectEqualStrings("first", args.peekRaw().?);
    try testing.expectEqualStrings("first", args.nextRaw().?);
    try testing.expectEqualStrings("second", args.nextRaw().?);
    try testing.expect(args.peekRaw() == null);
}

test "takeValue consumes a peeked token" {
    var args: Args = .fromSlice(&.{ "--output", "out.bin" });
    const opt = try expectOption(&args, .long, "output");
    try testing.expectEqualStrings("out.bin", args.peekRaw().?);
    try testing.expectEqualStrings("out.bin", args.takeValue(opt).?);
    try testing.expectEqual(@as(?Token, null), args.next());
}

test "isOption" {
    try testing.expect(!isOption("file"));
    try testing.expect(!isOption("-"));
    try testing.expect(isOption("--"));
    try testing.expect(isOption("-l"));
    try testing.expect(isOption("--long"));
}

test "unknown short option keeps the cluster" {
    var args: Args = .fromSlice(&.{"-xyz"});
    const x = try expectOption(&args, .short, "x");
    try testing.expectEqualStrings("yz", x.attached);
    _ = try expectOption(&args, .short, "y");
    _ = try expectOption(&args, .short, "z");
    try testing.expectEqual(@as(?Token, null), args.next());
}

test "weird tokens do not panic" {
    var args: Args = .fromSlice(&.{
        "--",      "-",    "---", "--=", "-=", "-abc",
        "--a=b=c", "-a=b", "",    "--",  "--",
    });

    while (args.next()) |tok| switch (tok) {
        .positional => {},
        .option => |opt| {
            var buf: [64]u8 = undefined;
            _ = std.fmt.bufPrint(&buf, "{f}", .{opt}) catch |err| switch (err) {
                error.NoSpaceLeft => unreachable,
            };
        },
    };
}
