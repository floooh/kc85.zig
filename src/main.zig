const std = @import("std");
const KC85 = @import("kc85.zig").KC85;

var kc85: *KC85 = undefined;

pub fn main() !void {
    kc85 = try KC85.create(std.heap.c_allocator, .{
        .rom_caos22  = @embedFile("roms/caos22.852"),
        .rom_caos31  = @embedFile("roms/caos31.853"),
        .rom_caos42c = @embedFile("roms/caos42c.854"),
        .rom_caos42e = @embedFile("roms/caos42e.854"),
        .rom_kcbasic = @embedFile("roms/basic_c0.853")
    });
    defer kc85.destroy(std.heap.c_allocator);
}
