//
//  KC85 emulator main loop and host bindings
//  

const std   = @import("std");
const gfx   = @import("gfx.zig");
const sapp  = @import("sokol").app;
const KC85  = @import("kc85.zig").KC85;

var kc85: *KC85 = undefined;

pub fn main() !void {
    // setup KC85 emulator instance
    kc85 = try KC85.create(std.heap.c_allocator, .{
        .rom_caos22  = @embedFile("roms/caos22.852"),
        .rom_caos31  = @embedFile("roms/caos31.853"),
        .rom_caos42c = @embedFile("roms/caos42c.854"),
        .rom_caos42e = @embedFile("roms/caos42e.854"),
        .rom_kcbasic = @embedFile("roms/basic_c0.853")
    });
    defer kc85.destroy(std.heap.c_allocator);

    // run sokol-app "game loop"
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .width = gfx.WindowWidth,
        .height = gfx.WindowHeight,
        .icon = .{
            // FIXME: KC85 logo
            .sokol_default = true,
        },
        // FIXME: depending on selected model
        .window_title = "KC85"
    });
}

export fn init() void {
    gfx.setup();
}

export fn frame() void {
    // FIXME: run emulator 
    gfx.draw();
}

export fn cleanup() void {
    gfx.shutdown();
}
