# Changelog

All notable changes to cli are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.2.0] - 2026-10-28

### Added

- `cli.parse(T, raw)`: codecs for `bool`, integers, floats, `[]const u8`, and enums, plus any type with a `parse(raw) !T` function.

## [0.1.0] - 2026-10-20

### Added

- `cli.Args`, a cursor over argv with `std.process.Args.Iterator` support, short-option clusters, `--` handling, and a captured `program_name`.
