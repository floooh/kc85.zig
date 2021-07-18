const std = @import("std");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;
const Pkg = std.build.Pkg;
const CrossTarget = std.zig.CrossTarget;
const Mode = std.builtin.Mode;

const KC85Model = enum {
    KC85_2 = 0,
    KC85_3 = 1,
    KC85_4 = 2,
};

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    addKC85(b, target, mode, .KC85_2);
    addKC85(b, target, mode, .KC85_3);
    addKC85(b, target, mode, .KC85_4);
    addZ80Test(b, target, mode);
    addZ80ZEXDOC(b, target, mode);
    addZ80ZEXALL(b, target, mode);
    addTests(b);
}

fn addKC85(b: *Builder, target: CrossTarget, mode: Mode, comptime kc85_model: KC85Model) void {
    const name = switch (kc85_model) {
        .KC85_2 => "kc852",
        .KC85_3 => "kc853",
        .KC85_4 => "kc854"
    };
    const sokol = buildSokol(b, "");
    const exe = b.addExecutable(name, "src/main.zig");
    exe.addBuildOption(KC85Model, "kc85_model", kc85_model);
    
    // FIXME: HACK to make buildoptions available to other packages than root
    // see: https://github.com/ziglang/zig/issues/5375
    const pkg_buildoptions = Pkg{
        .name = "build_options", 
        .path = switch (kc85_model) {
            .KC85_2 => "zig-cache/kc852_build_options.zig",
            .KC85_3 => "zig-cache/kc853_build_options.zig",
            .KC85_4 => "zig-cache/kc854_build_options.zig"
        },
    };
    const pkg_sokol = Pkg{
        .name = "sokol",
        .path = "src/sokol/sokol.zig"
    };
    const pkg_emu = Pkg{
        .name = "emu",
        .path = "src/emu/emu.zig", 
        .dependencies = &[_]Pkg{ pkg_buildoptions}
    };
    const pkg_host = Pkg{
        .name = "host",
        .path = "src/host/host.zig",
        .dependencies = &[_]Pkg{ pkg_sokol}
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
    exe.addBuildOption(bool, "zexdoc", true);
    exe.addBuildOption(bool, "zexall", false);
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
    exe.addBuildOption(bool, "zexdoc", false);
    exe.addBuildOption(bool, "zexall", true);
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

fn buildSokol(b: *Builder, comptime prefix_path: []const u8) *LibExeObjStep {
    const lib = b.addStaticLibrary("sokol", null);
    lib.linkLibC();
    lib.setBuildMode(b.standardReleaseOptions());
    const sokol_path = prefix_path ++ "src/sokol/c/";
    const csources = [_][]const u8 {
        "sokol_app.c",
        "sokol_gfx.c",
        "sokol_time.c",
        "sokol_audio.c",
        "sokol_gl.c",
        "sokol_debugtext.c",
    };
    if (lib.target.isDarwin()) {
        b.env_map.put("ZIG_SYSTEM_LINKER_HACK", "1") catch unreachable;
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
