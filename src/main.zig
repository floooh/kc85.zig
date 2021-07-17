//
//  KC85 emulator main loop and host bindings
//  

const std   = @import("std");
const sapp  = @import("sokol").app;
const KC85  = @import("emu").kc85.KC85;
const gfx   = @import("host").gfx;
const time  = @import("host").time;

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

    // start sokol-app "game loop"
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
    time.setup();
}

export fn frame() void {
    // FIXME: run emulator 
    const frame_time_us = time.frameTime();

    // FIXME: debug output
    const sdtx = @import("sokol").debugtext;
    sdtx.canvas(sapp.widthf()*0.5, sapp.heightf()*0.5);
    sdtx.print("Frame time: {}us\n", .{ frame_time_us });

    gfx.draw();
}

export fn cleanup() void {
    gfx.shutdown();
}
