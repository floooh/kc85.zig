//
//  KC85 emulator main loop and host bindings
//

const build_options = @import("build_options");
const std = @import("std");
const warn = std.log.warn;
const mem = std.mem;
const fs = std.fs;
const sapp = @import("sokol").app;
const slog = @import("sokol").log;
const host = @import("host");
const gfx = host.gfx;
const audio = host.audio;
const time = host.time;
const Args = host.Args;
const KC85 = @import("emu").KC85;
const Model = KC85.Model;
const ModuleType = KC85.ModuleType;

const state = struct {
    var kc: *KC85 = undefined;
    var args: Args = undefined;
    var file_data: ?[]const u8 = null;
    var arena: std.heap.ArenaAllocator = undefined;
};

const kc85_model: Model = switch (build_options.kc85_model) {
    .KC85_2 => .KC85_2,
    .KC85_3 => .KC85_3,
    .KC85_4 => .KC85_4,
};
const load_delay_us = switch (build_options.kc85_model) {
    .KC85_2, .KC85_3 => 480 * 16_667,
    .KC85_4 => 180 * 16_667,
};
const max_file_size = 64 * 1024;

pub fn main() !void {
    state.arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer state.arena.deinit();

    // parse arguments
    state.args = Args.parse(state.arena.allocator()) catch {
        warn("Failed to parse arguments\n", .{});
        std.process.exit(5);
    };
    if (state.args.help) {
        return;
    }

    // start sokol-app "game loop"
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = input,
        .width = gfx.WindowWidth,
        .height = gfx.WindowHeight,
        .icon = .{
            // FIXME: KC85 logo
            .sokol_default = true,
        },
        .window_title = switch (kc85_model) {
            .KC85_2 => "KC85/2",
            .KC85_3 => "KC85/3",
            .KC85_4 => "KC85/4",
        },
        .logger = .{
            .func = slog.func,
        },
    });
}

export fn init() void {
    gfx.setup();
    audio.setup();
    time.setup();

    // setup KC85 emulator instance
    state.kc = KC85.create(state.arena.allocator(), .{
        .pixel_buffer = gfx.pixel_buffer[0..],
        .audio_func = .{ .func = audio.push },
        .audio_sample_rate = audio.sampleRate(),
        .patch_func = .{ .func = patchFunc },
        .rom_caos22 = if (kc85_model == .KC85_2) @embedFile("roms/caos22.852") else null,
        .rom_caos31 = if (kc85_model == .KC85_3) @embedFile("roms/caos31.853") else null,
        .rom_caos42c = if (kc85_model == .KC85_4) @embedFile("roms/caos42c.854") else null,
        .rom_caos42e = if (kc85_model == .KC85_4) @embedFile("roms/caos42e.854") else null,
        .rom_kcbasic = if (kc85_model != .KC85_2) @embedFile("roms/basic_c0.853") else null,
    }) catch |err| {
        warn("Failed to allocate KC85 instance with: {}\n", .{err});
        std.process.exit(10);
    };

    // insert any modules defined on the command line
    for (state.args.slots) |slot| {
        if (slot.mod_name) |mod_name| {
            var mod_type = moduleNameToType(mod_name);
            var rom_image: ?[]const u8 = null;
            if (slot.mod_path) |path| {
                rom_image = fs.cwd().readFileAlloc(state.arena.allocator(), path, max_file_size) catch |err| blk: {
                    warn("Failed to load ROM file '{s}' with: {}\n", .{ path, err });
                    mod_type = .NONE;
                    break :blk null;
                };
            }
            state.kc.insertModule(slot.addr, mod_type, rom_image) catch |err| {
                warn("Failed to insert module '{s}' with: {}\n", .{ mod_name, err });
            };
        }
    }

    // preload the KCC or TAP file image, this will be loaded later when the
    // system has finished booting
    if (state.args.file) |path| {
        state.file_data = fs.cwd().readFileAlloc(state.arena.allocator(), path, max_file_size) catch |err| blk: {
            warn("Failed to load snapshot file '{s}' with: {}\n", .{ path, err });
            break :blk null;
        };
    } else {
        state.file_data = null;
    }
}

export fn frame() void {
    const frame_time_us = time.frameTime();
    state.kc.exec(frame_time_us);
    gfx.draw();
    // check if KCC or TAP file should be loaded (after giving the system
    // enough time to boot up)
    if ((state.file_data != null) and time.elapsed(load_delay_us)) {
        state.kc.load(state.file_data.?) catch |err| {
            warn("Failed to load snapshot file '{s}' with: {}\n", .{ state.args.file.?, err });
        };
        // arena allocator takes care of deallocation
        state.file_data = null;
    }
}

export fn cleanup() void {
    state.kc.destroy(state.arena.allocator());
    audio.shutdown();
    gfx.shutdown();
}

export fn input(event: ?*const sapp.Event) void {
    const ev = event.?;
    switch (ev.type) {
        .CHAR => {
            var char = ev.char_code;
            if ((char > 0x20) and (char < 0x7F)) {
                // need to invert case
                if ((char >= 'A') and (char <= 'Z')) {
                    char |= 0x20;
                } else if ((char >= 'a') and (char <= 'z')) {
                    char &= ~@as(u8, 0x20);
                }
                const key = @as(u8, @truncate(char));
                state.kc.keyDown(key);
                state.kc.keyUp(key);
            }
        },
        .KEY_DOWN, .KEY_UP => {
            const key: u8 = switch (ev.key_code) {
                .SPACE => 0x20,
                .ENTER => 0x0D,
                .RIGHT => 0x09,
                .LEFT => 0x08,
                .DOWN => 0x0A,
                .UP => 0x0B,
                .HOME => 0x10,
                .INSERT => 0x1A,
                .BACKSPACE => 0x01,
                .ESCAPE => 0x03,
                .F1 => 0xF1,
                .F2 => 0xF2,
                .F3 => 0xF3,
                .F4 => 0xF4,
                .F5 => 0xF5,
                .F6 => 0xF6,
                .F7 => 0xF7,
                .F8 => 0xF8,
                .F9 => 0xF9,
                .F10 => 0xFA,
                .F11 => 0xFB,
                .F12 => 0xFC,
                else => 0,
            };
            if (0 != key) {
                switch (ev.type) {
                    .KEY_DOWN => state.kc.keyDown(key),
                    .KEY_UP => state.kc.keyUp(key),
                    else => unreachable,
                }
            }
        },
        else => {},
    }
}

fn moduleNameToType(name: []const u8) KC85.ModuleType {
    const modules = .{
        .{ "m006", .M006_BASIC },
        .{ "m011", .M011_64KBYTE },
        .{ "m012", .M012_TEXOR },
        .{ "m022", .M022_16KBYTE },
        .{ "m026", .M026_FORTH },
        .{ "m027", .M027_DEVELOPMENT },
    };
    inline for (modules) |module| {
        if (mem.eql(u8, name, module[0])) {
            return module[1];
        }
    } else {
        return .NONE;
    }
}

// this patches some known issues with game images
fn patchFunc(snapshot_name: []const u8, userdata: usize) void {
    _ = userdata;
    if (mem.startsWith(u8, snapshot_name, "JUNGLE     ")) {
        // patch start level 1 into memory
        state.kc.mem.w8(0x36B7, 1);
        state.kc.mem.w8(0x3697, 1);
        var i: u16 = 0;
        while (i < 5) : (i += 1) {
            const b = state.kc.mem.r8(0x36B6 +% i);
            state.kc.mem.w8(0x1770 +% i, b);
        }
    } else if (mem.startsWith(u8, snapshot_name, "DIGGER  COM\x01")) {
        // time for delay loop 0x0160 instead of 0x0260
        state.kc.mem.w16(0x09AA, 0x0160);
        // OR L instead of OR (HL)
        state.kc.mem.w8(0x3D3A, 0xB5);
    } else if (mem.startsWith(u8, snapshot_name, "DIGGERJ")) {
        state.kc.mem.w16(0x09AA, 0x0260);
        state.kc.mem.w8(0x3D3A, 0xB5);
    }
}
