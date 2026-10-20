const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("cli", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
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

    const exe = b.addExecutable(.{
        .name = "cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "cli", .module = mod }},
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the demo");
    run_step.dependOn(&run_cmd.step);

    const examples_step = b.step("examples", "Build the example programs");
    const examples = [_]struct { file: []const u8, name: []const u8 }{
        .{ .file = "ls", .name = "cli-ls" },
        .{ .file = "tar", .name = "cli-tar" },
        .{ .file = "verbose", .name = "cli-verbose" },
        .{ .file = "codec", .name = "cli-codec" },
    };
    for (examples) |example| {
        const example_exe = b.addExecutable(.{
            .name = example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example.file})),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "cli", .module = mod }},
            }),
        });
        b.installArtifact(example_exe);
        examples_step.dependOn(&example_exe.step);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
        .test_runner = test_runner,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    run_mod_tests.addArg(b.fmt("--seed=0x{x}", .{b.graph.random_seed}));
    if (b.args) |args| run_mod_tests.addArgs(args);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(examples_step);
}
