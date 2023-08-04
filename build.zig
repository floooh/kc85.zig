const std = @import("std");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;
const CrossTarget = std.zig.CrossTarget;
const Mode = std.builtin.Mode;

const KC85Model = enum {
    KC85_2,
    KC85_3,
    KC85_4,
};

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardOptimizeOption(.{});
    const sokol = buildSokol(b, target, mode, "");
    addKC85(b, sokol, target, mode, .KC85_2);
    addKC85(b, sokol, target, mode, .KC85_3);
    addKC85(b, sokol, target, mode, .KC85_4);
    addZ80Test(b, target, mode);
    addZ80ZEXDOC(b, target, mode);
    addZ80ZEXALL(b, target, mode);
    addTests(b);
}

fn addKC85(b: *Builder, sokol: *LibExeObjStep, target: CrossTarget, optimize: Mode, comptime kc85_model: KC85Model) void {
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

    const mod_options = options.createModule();
    const mod_sokol = b.createModule(.{
        .source_file = .{ .path = "src/sokol/sokol.zig" },
    });
    const mod_host = b.createModule(.{
        .source_file = .{ .path = "src/host/host.zig" },
        .dependencies = &.{
            .{ .name = "sokol", .module = mod_sokol },
        },
    });
    const mod_emu = b.createModule(.{
        .source_file = .{ .path = "src/emu/emu.zig" },
        .dependencies = &.{
            .{ .name = "build_options", .module = mod_options },
        },
    });

    exe.addModule("build_options", mod_options);
    exe.addModule("sokol", mod_sokol);
    exe.addModule("host", mod_host);
    exe.addModule("emu", mod_emu);
    exe.linkLibrary(sokol);
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run.addArgs(args);
    }
    b.step("run-" ++ name, "Run " ++ name).dependOn(&run.step);
}

fn addTests(b: *Builder) void {
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
    });
    const test_step = b.step("tests", "Run all tests");
    test_step.dependOn(&tests.step);
}

fn addZ80Test(b: *Builder, target: CrossTarget, optimize: Mode) void {
    const exe = b.addExecutable(.{
        .name = "z80test",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "tests/z80test.zig" },
    });
    exe.addAnonymousModule("emu", .{ .source_file = .{ .path = "src/emu/emu.zig" } });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run.addArgs(args);
    }
    b.step("z80test", "Run the Z80 CPU test").dependOn(&run.step);
}

fn addZ80ZEXDOC(b: *Builder, target: CrossTarget, optimize: Mode) void {
    const exe = b.addExecutable(.{
        .name = "z80zexdoc",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "tests/z80zex.zig" },
    });
    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    exe_options.addOption(bool, "zexdoc", true);
    exe_options.addOption(bool, "zexall", false);
    exe.addAnonymousModule("emu", .{ .source_file = .{ .path = "src/emu/emu.zig" } });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run.addArgs(args);
    }
    b.step("z80zexdoc", "Run the Z80 ZEXDOC test").dependOn(&run.step);
}

fn addZ80ZEXALL(b: *Builder, target: CrossTarget, optimize: Mode) void {
    const exe = b.addExecutable(.{
        .name = "z80zexall",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "tests/z80zex.zig" },
    });
    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    exe_options.addOption(bool, "zexdoc", true);
    exe_options.addOption(bool, "zexall", false);
    exe.addAnonymousModule("emu", .{ .source_file = .{ .path = "src/emu/emu.zig" } });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run.addArgs(args);
    }
    b.step("z80zexall", "Run the Z80 ZEXALL test").dependOn(&run.step);
}

fn buildSokol(b: *Builder, target: CrossTarget, optimize: Mode, comptime prefix_path: []const u8) *LibExeObjStep {
    const lib = b.addStaticLibrary(.{
        .name = "sokol",
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    const sokol_path = prefix_path ++ "src/sokol/c/";
    const csources = [_][]const u8{
        "sokol_app.c",
        "sokol_gfx.c",
        "sokol_time.c",
        "sokol_audio.c",
        "sokol_log.c",
    };
    if (lib.target.isDarwin()) {
        inline for (csources) |csrc| {
            lib.addCSourceFile(.{
                .file = .{ .path = sokol_path ++ csrc },
                .flags = &[_][]const u8{ "-ObjC", "-DIMPL" },
            });
        }
        lib.linkFramework("MetalKit");
        lib.linkFramework("Metal");
        lib.linkFramework("Cocoa");
        lib.linkFramework("QuartzCore");
        lib.linkFramework("AudioToolbox");
    } else {
        inline for (csources) |csrc| {
            lib.addCSourceFile(.{
                .file = .{ .path = sokol_path ++ csrc },
                .flags = &[_][]const u8{"-DIMPL"},
            });
        }
        if (lib.target.isLinux()) {
            lib.linkSystemLibrary("X11");
            lib.linkSystemLibrary("Xi");
            lib.linkSystemLibrary("Xcursor");
            lib.linkSystemLibrary("GL");
            lib.linkSystemLibrary("asound");
        } else if (lib.target.isWindows()) {
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
