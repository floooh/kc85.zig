const std = @import("std");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;
const Pkg = std.build.Pkg;
const CrossTarget = std.zig.CrossTarget;
const Mode = std.builtin.Mode;

const KC85Model = enum {
    KC85_2,
    KC85_3,
    KC85_4,
};

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const sokol = buildSokol(b, target, mode, "");
    addKC85(b, sokol, target, mode, .KC85_2);
    addKC85(b, sokol, target, mode, .KC85_3);
    addKC85(b, sokol, target, mode, .KC85_4);
    addZ80Test(b, target, mode);
    addZ80ZEXDOC(b, target, mode);
    addZ80ZEXALL(b, target, mode);
    addTests(b);
}

fn addKC85(b: *Builder, sokol: *LibExeObjStep, target: CrossTarget, mode: Mode, comptime kc85_model: KC85Model) void {
    const name = switch (kc85_model) {
        .KC85_2 => "kc852",
        .KC85_3 => "kc853",
        .KC85_4 => "kc854"
    };
    const exe = b.addExecutable(name, "src/main.zig");
    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    exe_options.addOption(KC85Model, "kc85_model", kc85_model);
    
    const pkg_sokol = Pkg{
        .name = "sokol",
        .path = .{ .path = "src/sokol/sokol.zig" },
    };
    const pkg_host = Pkg{
        .name = "host",
        .path = .{ .path = "src/host/host.zig" },
        .dependencies = &[_]Pkg{ pkg_sokol }
    };
    const pkg_emu = Pkg{
        .name = "emu",
        .path = .{ .path = "src/emu/emu.zig" },
        .dependencies = &[_]Pkg{ exe_options.getPackage("build_options") }
    };
    exe.addPackage(pkg_sokol);
    exe.addPackage(pkg_emu);
    exe.addPackage(pkg_host);
    exe.linkLibrary(sokol);
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();
    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run-" ++ name, "Run " ++ name);
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
    exe.addPackagePath("emu", "src/emu/emu.zig");
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
    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    exe_options.addOption(bool, "zexdoc", true);
    exe_options.addOption(bool, "zexall", false);
    exe.addPackagePath("emu", "src/emu/emu.zig");
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
    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    exe_options.addOption(bool, "zexdoc", true);
    exe_options.addOption(bool, "zexall", false);
    exe.addPackagePath("emu", "src/emu/emu.zig");
    exe.install();
    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("z80zexall", "Run the Z80 ZEXALL test");
    run_step.dependOn(&run_cmd.step);
}

fn buildSokol(b: *Builder, target: CrossTarget, mode: Mode, comptime prefix_path: []const u8) *LibExeObjStep {
    const lib = b.addStaticLibrary("sokol", null);
    lib.setTarget(target);
    lib.setBuildMode(mode);
    lib.linkLibC();
    const sokol_path = prefix_path ++ "src/sokol/c/";
    const csources = [_][]const u8 {
        "sokol_app.c",
        "sokol_gfx.c",
        "sokol_time.c",
        "sokol_audio.c",
    };
    if (lib.target.isDarwin()) {
        inline for (csources) |csrc| {
            lib.addCSourceFile(sokol_path ++ csrc, &[_][]const u8{"-ObjC", "-DIMPL"});
        }
        lib.linkFramework("MetalKit");
        lib.linkFramework("Metal");
        lib.linkFramework("Cocoa");
        lib.linkFramework("QuartzCore");
        lib.linkFramework("AudioToolbox");
    } else {
        inline for (csources) |csrc| {
            lib.addCSourceFile(sokol_path ++ csrc, &[_][]const u8{"-DIMPL"});
        }
        if (lib.target.isLinux()) {
            lib.linkSystemLibrary("X11");
            lib.linkSystemLibrary("Xi");
            lib.linkSystemLibrary("Xcursor");
            lib.linkSystemLibrary("GL");
            lib.linkSystemLibrary("asound");
        }
        else if (lib.target.isWindows()) {
            lib.linkSystemLibrary("kernel32");
            lib.linkSystemLibrary("user32");
            lib.linkSystemLibrary("gdi32");
            lib.linkSystemLibrary("ole32");
            lib.linkSystemLibrary("d3d11");
            lib.linkSystemLibrary("dxgi");
        }
    }
    return lib;
}
