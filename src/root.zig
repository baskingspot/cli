//! `cli`: command-line argument parsing for Zig.
//!
//! The parser is a cursor over argv, not a schema. It classifies tokens into
//! options and positionals and leaves every semantic decision, including the
//! help text and the error messages, to the command. The library owns no
//! streams; diagnostics take a caller-provided `*std.Io.Writer`.

pub const Args = @import("Args.zig");
pub const Option = Args.Option;
pub const Token = Args.Token;
pub const isOption = Args.isOption;
const diag = @import("diag.zig");
pub const fail = diag.fail;
pub const help = diag.help;

test {
    _ = @import("Args.zig");
    _ = @import("diag.zig");
}
