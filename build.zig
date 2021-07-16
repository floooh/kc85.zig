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
    addZ80ZEXDOC(b, target, mode);
    addZ80ZEXALL(b, target, mode);
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
    const tests = b.addTest("src/tests.zig");
    const test_step = b.step("tests", "Run all tests");
    test_step.dependOn(&tests.step);
}

fn addZ80Test(b: *Builder, target: CrossTarget, mode: Mode) void {
    const exe = b.addExecutable("z80test", "tests/z80test.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackagePath("z80", "src/z80.zig");
    exe.install();
    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("z80test", "Run the Z80 CPU test");
    run_step.dependOn(&run_cmd.step);
}

fn addZ80ZEXDOC(b: *Builder, target: CrossTarget, mode: Mode) void {
    const exe = b.addExecutable("z80zexdoc", "tests/z80zex.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addBuildOption(bool, "zexdoc", true);
    exe.addBuildOption(bool, "zexall", false);
    exe.addPackagePath("z80", "src/z80.zig");
    exe.install();
    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("z80zexdoc", "Run the Z80 ZEXDOC test");
    run_step.dependOn(&run_cmd.step);
}

fn addZ80ZEXALL(b: *Builder, target: CrossTarget, mode: Mode) void {
    const exe = b.addExecutable("z80zexall", "tests/z80zex.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addBuildOption(bool, "zexdoc", false);
    exe.addBuildOption(bool, "zexall", true);
    exe.addPackagePath("z80", "src/z80.zig");
    exe.install();
    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("z80zexall", "Run the Z80 ZEXALL test");
    run_step.dependOn(&run_cmd.step);
}
