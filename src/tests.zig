test "memory tests" {
    _ = @import("emu/memory.zig");
}

test "cpu" {
    _ = @import("emu/z80.zig");
}

test "ctc" {
    _ = @import("emu/z80ctc.zig");
}

test "pio" {
    _ = @import("emu/z80pio.zig");
}