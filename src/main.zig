const std = @import("std");
const Memory = @import("memory.zig").Memory;
const Z80CPU = @import("z80cpu.zig").Z80CPU;

pub fn main() anyerror!void {

    var ram = [_]u8{0} ** 0x10000;
    var mem = Memory{};
    mem.mapRAM(0, 0x0000, &ram);
    mem.w8(0x3FFF, 0x7F);

    const bla = mem.pages[0].read[0];

    std.log.info("All your codebase are belong to us: {X} {X}", .{ mem.r8(0x3FFF), bla });
}
