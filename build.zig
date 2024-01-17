const std = @import("std");
const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const sokol = @import("sokol");

const KC85Model = enum {
    KC85_2,
    KC85_3,
    KC85_4,
};

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });
    try addKC85(b, target, optimize, dep_sokol, .KC85_2);
    try addKC85(b, target, optimize, dep_sokol, .KC85_3);
    try addKC85(b, target, optimize, dep_sokol, .KC85_4);
    // don't bother with making the tests run in wasm
    if (!target.result.isWasm()) {
        addZ80Test(b, target, optimize);
        addZ80ZEXDOC(b, target, optimize);
        addZ80ZEXALL(b, target, optimize);
        addTests(b);
    }
}

fn addKC85(b: *Build, target: Build.ResolvedTarget, optimize: OptimizeMode, dep_sokol: *Build.Dependency, comptime kc85_model: KC85Model) !void {
    const name = switch (kc85_model) {
        .KC85_2 => "kc852",
        .KC85_3 => "kc853",
        .KC85_4 => "kc854",
    };
    const options = b.addOptions();
    options.addOption(KC85Model, "kc85_model", kc85_model);

    if (!target.result.isWasm()) {
        // native build
        const kc85 = b.addExecutable(.{
            .name = name,
            .target = target,
            .optimize = optimize,
            .root_source_file = .{ .path = "src/main.zig" },
        });
        kc85.root_module.addOptions("build_options", options);
        kc85.root_module.addImport("sokol", dep_sokol.module("sokol"));

        b.installArtifact(kc85);
        const run = b.addRunArtifact(kc85);
        run.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run.addArgs(args);
        }
        b.step("run-" ++ name, "Run " ++ name).dependOn(&run.step);
    } else {
        // web build, compile the Zig code into a static library, and link with the Emscripten linker
        const kc85 = b.addStaticLibrary(.{
            .name = name,
            .target = target,
            .optimize = optimize,
            .root_source_file = .{ .path = "src/main.zig" },
        });
        kc85.root_module.addOptions("build_options", options);
        kc85.root_module.addImport("sokol", dep_sokol.module("sokol"));

        const emsdk = dep_sokol.builder.dependency("emsdk", .{});
        const link_step = try sokol.emLinkStep(b, .{
            .lib_main = kc85,
            .target = target,
            .optimize = optimize,
            .emsdk = emsdk,
            .use_webgl2 = true,
            .use_emmalloc = true,
            .use_filesystem = false,
            .shell_file_path = dep_sokol.path("src/sokol/web/shell.html").getPath(b),
            // NOTE: This is required to make the Zig @returnAddress() builtin work,
            // which is used heavily in the stdlib allocator code (not just
            // the GeneralPurposeAllocator).
            // The Emscripten runtime error message when the option is missing is:
            // Cannot use convertFrameToPC (needed by __builtin_return_address) without -sUSE_OFFSET_CONVERTER
            .extra_args = &.{"-sUSE_OFFSET_CONVERTER=1"},
        });
        const run = sokol.emRunStep(b, .{ .name = name, .emsdk = emsdk });
        run.step.dependOn(&link_step.step);
        b.step("run-" ++ name, "Run " ++ name).dependOn(&run.step);
    }
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
