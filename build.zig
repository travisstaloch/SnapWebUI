const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("snap", .{ .root_source_file = b.path("src/snap.zig"), .target = target, .optimize = optimize });
    const exe = b.addExecutable(.{
        .name = "snap-demo",
        .root_source_file = b.path("src/snap-demo.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = optimize,
    });
    exe.root_module.addImport("snap", mod);
    exe.entry = .disabled;
    exe.rdynamic = true;
    b.installArtifact(exe);

    // Copy wasm artifact to public/ directory
    const copy_wasm = b.addInstallBinFile(exe.getEmittedBin(), "../../public/snap-demo.wasm");
    b.getInstallStep().dependOn(&copy_wasm.step);
    const tests_run = addTest(b, "src/tests.zig", "test", target, optimize, mod);
    const snap_test_run = addTest(b, "src/snap.zig", "test-snap-lib", target, optimize, mod);
    tests_run.step.dependOn(&snap_test_run.step);
    const e2e_test_cmd = b.addSystemCommand(&.{ "bun", "test" });
    e2e_test_cmd.step.dependOn(&copy_wasm.step);
    const run_step = b.step("test-e2e", "run browser tests.  depends on bun, puppeteer and puppeteer chrome being installed.");
    run_step.dependOn(&e2e_test_cmd.step);
}

fn addTest(b: *std.Build, path: []const u8, name: []const u8, target: anytype, optimize: anytype, mod: anytype) *std.Build.Step.Run {
    const tests = b.addTest(.{ .root_source_file = b.path(path), .target = target, .optimize = optimize });
    tests.root_module.addImport("snap", mod);
    const run_tests = b.addRunArtifact(tests);
    const run_step = b.step(name, "run tests");
    run_step.dependOn(&run_tests.step);
    b.installArtifact(tests);
    return run_tests;
}
