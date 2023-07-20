test "memory tests" {
    _ = @import("emu/Memory.zig");
}

test "cpu" {
    _ = @import("emu/CPU.zig");
}

test "ctc" {
    _ = @import("emu/CTC.zig");
}

test "pio" {
    _ = @import("emu/PIO.zig");
}
