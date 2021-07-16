test "memory tests" {
    const mem = @import("memory.zig");
}

test "cpu" {
    const z80 = @import("z80.zig");
}

test "ctc" {
    const z80ctc = @import("z80ctc.zig");
}

test "pio" {
    const z80pio = @import("z80pio.zig");
}