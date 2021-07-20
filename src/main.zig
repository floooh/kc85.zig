//
//  KC85 emulator main loop and host bindings
//  

const build_options = @import("build_options");
const std   = @import("std");
const sapp  = @import("sokol").app;
const KC85  = @import("emu").kc85.KC85;
const Model = @import ("emu").kc85.Model;
const gfx   = @import("host").gfx;
const audio = @import("host").audio;
const time  = @import("host").time;

var kc85: *KC85 = undefined;

const kc85_model: Model = switch (build_options.kc85_model) {
    .KC85_2 => .KC85_2,
    .KC85_3 => .KC85_3,
    .KC85_4 => .KC85_4,
};

pub fn main() !void {
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
    kc85 = KC85.create(std.heap.c_allocator, .{
        .pixel_buffer = gfx.pixel_buffer[0..],
        .audio_func  = .{ .func = audio.push },
        .audio_sample_rate = audio.sampleRate(),
        .rom_caos22  = @embedFile("roms/caos22.852"),
        .rom_caos31  = @embedFile("roms/caos31.853"),
        .rom_caos42c = @embedFile("roms/caos42c.854"),
        .rom_caos42e = @embedFile("roms/caos42e.854"),
        .rom_kcbasic = @embedFile("roms/basic_c0.853")
    }) catch unreachable;
}

export fn frame() void {
    const frame_time_us = time.frameTime();
    kc85.exec(frame_time_us);
    gfx.draw();
}

export fn cleanup() void {
    audio.shutdown();
    gfx.shutdown();
    kc85.destroy();
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
                kc85.keyDown(key);
                kc85.keyUp(key);
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
                    .KEY_DOWN => kc85.keyDown(key),
                    .KEY_UP => kc85.keyUp(key),
                    else => unreachable,
                }
            }
        },
        else => { },
    }
}
