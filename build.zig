const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("cli", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Only the exported module matters to a consumer. The demo, examples, and
    // test runner are developer-only.
    if (b.pkg_hash.len != 0) return;

    // testingx provides the test runner. It is lazy because only the root
    // build uses it; a consumer never fetches it. On the first configure pass
    // it is not fetched yet, `lazyDependency` returns null, and the build
    // runner fetches it and reruns this script.
    const testingx_dep = b.lazyDependency("testingx", .{ .target = target });
    const test_runner: ?std.Build.Step.Compile.TestRunner = if (testingx_dep) |dep|
        .{ .path = dep.path("src/runner.zig"), .mode = .simple }
    else
        null;

    const kitchen = addExample(b, mod, target, optimize, "kitchen", "cli-kitchen");
    b.installArtifact(kitchen);

    const run_cmd = b.addRunArtifact(kitchen);
    passthruArgs(b, run_cmd);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the kitchen-sink demo");
    run_step.dependOn(&run_cmd.step);

    const examples_step = b.step("examples", "Build the example programs");
    examples_step.dependOn(&kitchen.step);
    const examples = [_]struct { file: []const u8, name: []const u8 }{
        .{ .file = "git", .name = "cli-git" },
        .{ .file = "ls", .name = "cli-ls" },
        .{ .file = "tar", .name = "cli-tar" },
        .{ .file = "verbose", .name = "cli-verbose" },
        .{ .file = "codec", .name = "cli-codec" },
    };
    for (examples) |example| {
        const example_exe = addExample(b, mod, target, optimize, example.file, example.name);
        b.installArtifact(example_exe);
        examples_step.dependOn(&example_exe.step);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
        .test_runner = test_runner,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    passthruArgs(b, run_mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(examples_step);
}

fn addExample(
    b: *std.Build,
    mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    file: []const u8,
    name: []const u8,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{file})),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "cli", .module = mod }},
        }),
    });
}

/// `b.args` (removed in Zig 0.17) and `Run.addPassthruArgs` are the same
/// feature on either side of the split. Probe the build API, not the version.
fn passthruArgs(b: *std.Build, run: *std.Build.Step.Run) void {
    if (comptime @hasDecl(std.Build.Step.Run, "addPassthruArgs")) {
        run.addPassthruArgs();
    } else if (b.args) |args| {
        run.addArgs(args);
    }
}
