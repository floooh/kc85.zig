test "memory tests" {
    const mem = @import("emu/memory.zig");
}

test "cpu" {
    const z80 = @import("emu/z80.zig");
}

test "ctc" {
    const z80ctc = @import("emu/z80ctc.zig");
}

test "pio" {
    const z80pio = @import("emu/z80pio.zig");
}