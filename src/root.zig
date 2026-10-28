//! `cli`: command-line argument parsing for Zig.
//!
//! The parser is a cursor over argv, not a schema. It classifies tokens into
//! options and positionals and leaves every semantic decision, including the
//! help text and the error messages, to the command. The library writes
//! nothing; the command owns its writers.
//!
//! `parse` converts one value on request: `cli.parse(u16, raw)`. It covers the
//! primitive types and calls a type's own `parse` function for anything else.
//! It never chooses a flag and never writes text.

pub const Args = @import("Args.zig");
pub const Option = Args.Option;
pub const Token = Args.Token;
pub const isOption = Args.isOption;
pub const parse = @import("codec.zig").parse;

test {
    _ = @import("Args.zig");
    _ = @import("codec.zig");
}
