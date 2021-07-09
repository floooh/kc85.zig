const std = @import("std");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;
const CrossTarget = std.zig.CrossTarget;
const Mode = std.builtin.Mode;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    addKC85(b, target, mode);
    addZ80Test(b, target, mode);
    addTests(b);
}

fn addKC85(b: *Builder, target: CrossTarget, mode: Mode) void {
    const exe = b.addExecutable("kc85", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();
    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn addTests(b: *Builder) void {
    const tests = b.addTest("src/all_tests.zig");
    const test_step = b.step("tests", "Run all tests");
    test_step.dependOn(&tests.step);
}

fn addZ80Test(b: *Builder, target: CrossTarget, mode: Mode) void {
    const exe = b.addExecutable("z80test", "tests/z80test.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackagePath("cpu", "src/cpu.zig");
    exe.install();
    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("z80test", "Run the Z80 CPU test");
    run_step.dependOn(&run_cmd.step);
}
