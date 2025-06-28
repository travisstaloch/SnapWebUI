const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("snap", .{ .root_source_file = b.path("src/lib.zig"), .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "snap-demo",
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = optimize,
    });
    exe.root_module.addImport("snap", mod);
    exe.entry = .disabled;
    exe.rdynamic = true;
    b.installArtifact(exe);
    addTest(b, "src/tests.zig", "test", target, optimize, mod);
    addTest(b, "src/lib.zig", "test-lib", target, optimize, mod);
}

fn addTest(b: *std.Build, path: []const u8, name: []const u8, target: anytype, optimize: anytype, mod: anytype) void {
    const tests = b.addTest(.{ .root_source_file = b.path(path), .target = target, .optimize = optimize });
    tests.root_module.addImport("snap", mod);
    const run_tests = b.addRunArtifact(tests);
    const run_step = b.step(name, "run tests");
    run_step.dependOn(&run_tests.step);
}
