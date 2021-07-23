//
//  KC85 emulator main loop and host bindings
//  

const build_options = @import("build_options");
const std   = @import("std");
const warn  = std.debug.warn;
const mem   = std.mem;
const fs    = std.fs;
const sapp  = @import("sokol").app;
const host  = @import("host");
const gfx   = host.gfx;
const audio = host.audio;
const time  = host.time;
const Args  = host.args.Args;
const kc85  = @import("emu").kc85;
const KC85       = kc85.KC85;
const Model      = kc85.Model;
const ModuleType = kc85.ModuleType;

const state = struct {
    var kc: *KC85 = undefined;
    var args: Args = undefined;
    var arena: std.heap.ArenaAllocator = undefined;
};

const kc85_model: Model = switch (build_options.kc85_model) {
    .KC85_2 => .KC85_2,
    .KC85_3 => .KC85_3,
    .KC85_4 => .KC85_4,
};

pub fn main() !void {
    state.arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer state.arena.deinit();
    
    // parse arguments
    state.args = Args.parse(&state.arena.allocator) catch |err| {
        warn("Failed to parse arguments\n", .{});
        return;
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
            .KC85_4 => "KC85/4"
        }
    });
}

export fn init() void {
    gfx.setup();
    audio.setup();
    time.setup();
    
    // setup KC85 emulator instance
    state.kc = KC85.create(&state.arena.allocator, .{
        .pixel_buffer = gfx.pixel_buffer[0..],
        .audio_func  = .{ .func = audio.push },
        .audio_sample_rate = audio.sampleRate(),
        .rom_caos22  = if (kc85_model == .KC85_2) @embedFile("roms/caos22.852") else null,
        .rom_caos31  = if (kc85_model == .KC85_3) @embedFile("roms/caos31.853") else null,
        .rom_caos42c = if (kc85_model == .KC85_4) @embedFile("roms/caos42c.854") else null,
        .rom_caos42e = if (kc85_model == .KC85_4) @embedFile("roms/caos42e.854") else null,
        .rom_kcbasic = if (kc85_model != .KC85_2) @embedFile("roms/basic_c0.853") else null,
    }) catch unreachable;

    // insert any modules defined on the command line
    for (state.args.slots) |slot| {
        if (slot.mod_name) |mod_name| {
            const max_file_size = 64 * 1024;
            var mod_type = moduleNameToType(mod_name);
            var rom_image: ?[]const u8 = null;
            if (slot.mod_path) |path| {
                rom_image = fs.cwd().readFileAlloc(&state.arena.allocator, path, max_file_size) catch |err| blk:{
                    warn("Failed to load file '{s}' with: {}\n", .{ path, err });
                    mod_type = .NONE;
                    break :blk null;
                };
            }
            _ = state.kc.insertModule(slot.addr, mod_type, rom_image);
        }
    }
}

export fn frame() void {
    const frame_time_us = time.frameTime();
    state.kc.exec(frame_time_us);
    gfx.draw();
}

export fn cleanup() void {
    state.kc.destroy(&state.arena.allocator);
    audio.shutdown();
    gfx.shutdown();
}

export fn input(event: ?*const sapp.Event) void {
    const ev = event.?;
    var shift = 0 != (ev.modifiers & sapp.modifier_shift);
    switch (ev.type) {
        .CHAR => {
            var char = ev.char_code;
            if ((char > 0x20) and (char < 0x7F)) {
                // need to invert case
                if ((char >= 'A') and (char <= 'Z')) {
                    char |= 0x20;
                }
                else if ((char >= 'a') and (char <= 'z')) {
                    char &= ~@as(u8,0x20);
                }
                const key = @truncate(u8, char);
                state.kc.keyDown(key);
                state.kc.keyUp(key);
            }
        },
        .KEY_DOWN, .KEY_UP => {
            const key: u8 = switch (ev.key_code) {
                .SPACE      => 0x20,
                .ENTER      => 0x0D,
                .RIGHT      => 0x09,
                .LEFT       => 0x08,
                .DOWN       => 0x0A,
                .UP         => 0x0B,
                .HOME       => 0x10,
                .INSERT     => 0x1A,
                .BACKSPACE  => 0x01,
                .ESCAPE     => 0x03,
                .F1         => 0xF1,
                .F2         => 0xF2,
                .F3         => 0xF3,
                .F4         => 0xF4,
                .F5         => 0xF5,
                .F6         => 0xF6,
                .F7         => 0xF7,
                .F8         => 0xF8,
                .F9         => 0xF9,
                .F10        => 0xFA,
                .F11        => 0xFB,
                .F12        => 0xFC,
                else        => 0,
            };
            if (0 != key) {
                switch (ev.type) {
                    .KEY_DOWN => state.kc.keyDown(key),
                    .KEY_UP => state.kc.keyUp(key),
                    else => unreachable,
                }
            }
        },
        else => { },
    }
}

fn moduleNameToType(name: []const u8) kc85.ModuleType {
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
    }
    else {
        return .NONE;
    }
}
