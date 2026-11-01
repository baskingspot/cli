# AGENTS.md

Working notes for AI coding agents in baskingspot/cli.

## What this is

Command-line argument parsing for Zig. The API is not yet tagged.

## Environment

Zig 0.16 and 0.17. The flake is the tool contract, from `baskingspot/nix`: `nix develop` is the current stable, Zig 0.17, and `nix develop .#zig-old` is Zig 0.16. Both provide `ziglint` and the base tools, and nothing comes from the system PATH. The justfile is the command interface: `just test`, `just check`, `just lint`, `just ci`. CI runs `just ci` on the default shell and `just check` on `zig-old`. Run `just fmt` before you commit.

## Rules

- Lint with `ziglint-0-16`, not `ziglint`: the wrapper points ziglint at the 0.16 std, so 0.17-only deprecations do not fire while 0.16 is supported.
- Commit messages are one line, `area: summary`, and every commit is signed. Do not rewrite pushed history.
- Gate commands on their exit codes, and claim only what you ran.
- Format with `zig fmt` and lint with `ziglint`. `just fmt` and `just lint` run both.
- `build.zig`'s `passthruArgs` helper is the only version shim. Keep `b.args` inside it; Zig 0.17 has `Run.addPassthruArgs` instead.
- This repo's GitHub settings come from `baskingspot/.github`, with `just settings`. Do not change them by hand.
- To graduate the project, follow the `baskingspot-new-repo` skill: logos, a real README, and the audit passing.

## Changelog

`CHANGELOG.md` is one file, Keep a Changelog format, newest first. Add a bullet
under `## [Unreleased]` in the same change that alters something a user can
notice: the public API, expected behavior, performance a benchmark row would
show, a supported backend, or the build requirements. Docs, CI, and internal
refactors do not need one unless they change how someone uses the package.

Write from the user's side: what changed, and what they must do about it. Name
the symbol, flag, or error. One line, under Added, Changed, Fixed, or Removed.

To release, commit the preparation yourself, signed: move the Unreleased
bullets under a `## [X.Y.Z] - YYYY-MM-DD` heading, and set `.version` in
`build.zig.zon`. Push, then dispatch `release.yml` with the version. The
workflow makes no commit. It checks both, tags `main`, and opens the GitHub
release. Do not tag by hand.
