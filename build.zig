const std = @import("std");
const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;

const KC85Model = enum {
    KC85_2,
    KC85_3,
    KC85_4,
};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });
    addKC85(b, target, optimize, dep_sokol, .KC85_2);
    addKC85(b, target, optimize, dep_sokol, .KC85_3);
    addKC85(b, target, optimize, dep_sokol, .KC85_4);
    addZ80Test(b, target, optimize);
    addZ80ZEXDOC(b, target, optimize);
    addZ80ZEXALL(b, target, optimize);
    addTests(b);
}

fn addKC85(b: *Build, target: Build.ResolvedTarget, optimize: OptimizeMode, dep_sokol: *Build.Dependency, comptime kc85_model: KC85Model) void {
    const name = switch (kc85_model) {
        .KC85_2 => "kc852",
        .KC85_3 => "kc853",
        .KC85_4 => "kc854",
    };
    const exe = b.addExecutable(.{
        .name = name,
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/main.zig" },
    });

    const options = b.addOptions();
    options.addOption(KC85Model, "kc85_model", kc85_model);

    exe.root_module.addOptions("build_options", options);
    exe.root_module.addImport("sokol", dep_sokol.module("sokol"));

    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run.addArgs(args);
    }
    b.step("run-" ++ name, "Run " ++ name).dependOn(&run.step);
}

fn addTests(b: *Build) void {
    const tests_exe = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
    });
    const run = b.addRunArtifact(tests_exe);
    b.step("tests", "Run all tests").dependOn(&run.step);
}

fn addZ80Test(b: *Build, target: Build.ResolvedTarget, optimize: OptimizeMode) void {
    const exe = b.addExecutable(.{
        .name = "z80test",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/z80test.zig" },
    });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run.addArgs(args);
    }
    b.step("z80test", "Run the Z80 CPU test").dependOn(&run.step);
}

fn addZ80ZEXDOC(b: *Build, target: Build.ResolvedTarget, optimize: OptimizeMode) void {
    const exe = b.addExecutable(.{
        .name = "z80zexdoc",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/z80zex.zig" },
    });
    const options = b.addOptions();
    exe.root_module.addOptions("build_options", options);
    options.addOption(bool, "zexdoc", true);
    options.addOption(bool, "zexall", false);

    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run.addArgs(args);
    }
    b.step("z80zexdoc", "Run the Z80 ZEXDOC test").dependOn(&run.step);
}

fn addZ80ZEXALL(b: *Build, target: Build.ResolvedTarget, optimize: OptimizeMode) void {
    const exe = b.addExecutable(.{
        .name = "z80zexall",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/z80zex.zig" },
    });
    const options = b.addOptions();
    exe.root_module.addOptions("build_options", options);
    options.addOption(bool, "zexdoc", true);
    options.addOption(bool, "zexall", false);

    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run.addArgs(args);
    }
    b.step("z80zexall", "Run the Z80 ZEXALL test").dependOn(&run.step);
}
