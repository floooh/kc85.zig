//
//  The KC85 system emulator which integrates the various chip emulators.
//
//
//  ## The KC85/2
//
//  This was the ur-model of the KC85 family designed and manufactured
//  by VEB Mikroelektronikkombinat Muehlhausen. The KC85/2 was introduced
//  in 1984 as HC-900, and renamed to KC85/2 in 1985 (at the same time
//  when the completely unrelated Z9001 was renamed to KC85/1).
//
//      - U880 CPU @ 1.75 MHz (the U880 was an "unlicensed" East German Z80 clone)
//      - 1x U855 (clone of the Z80-PIO)
//      - 1x U857 (clone of the Z80-CTC)
//      - 16 KByte RAM at 0000..3FFF
//      - 16 KByte video RAM (IRM) at 8000..BFFF
//      - 4 KByte ROM in 2 sections (E000..E800 and F000..F800)
//      - the operating system was called CAOS (Cassette Aided Operating System)
//      - 50 Hz PAL video at 320x256 pixels
//      - Speccy-like color attributes (1 color byte per 8x4 pixels)
//      - fixed palette of 16 foreground and 8 background colors
//      - square-wave-beeper sound
//      - separate keyboard with a serial-encoder chip to transfer
//        key strokes to the main unit
//      - flexible expansion module system (2 slots in the base units,
//        4 additional slots per 'BUSDRIVER' units)
//      - a famously bizarre video memory layout, consisting of a
//        256x256 chunk on the left, and a separate 64x256 chunk on the right,
//        with vertically 'interleaved' vertical addressing similar to the
//        ZX Spectrum but with different offsets
//
//  ### Memory Map:
//      - 0000..01FF:   OS variables, interrupt vectors, and stack
//      - 0200..3FFF:   usable RAM
//      - 8000..A7FF:   pixel video RAM (1 byte => 8 pixels)
//      - A800..B1FF:   color video RAM (1 byte => 8x4 color attribute block)
//      - B200..B6FF:   ASCII backing buffer
//      - B700..B77F:   cassette tape buffer
//      - B780..B8FF:   more OS variables
//      - B800..B8FF:   backing buffer for expansion module control bytes
//      - B900..B97F:   buffer for actions assigned to function keys
//      - B980..B9FF:   window attributes buffers
//      - BA00..BBFF:   "additional programs"
//      - BC00..BFFF:   usable 'slow-RAM'
//      - E000..E7FF:   2 KB ROM
//      - F000..F7FF:   2 KB ROM
//
//      The video memory from A000..BFFF has slow CPU access (2.4us) because
//      it needs to share memory accesses with the video system. Also, CPU
//      accesses to this RAM block are visible as 'display needling' artefacts.
//
//      (NOTE: the slow video memory access is not emulation, display needling
//      is emulated, but I haven't verified against real hardware
//      whether it actually looks correct)
//
//  ### Special Operating System Conditions
//
//      - the index register IX is reserved for operating system use
//        and must not be changed while interrupts are enabled
//      - only interrupt mode IM2 is supported
//
//  ### Interrupt Vectors:
//      - 01E4:     PIO-A (cassette tape input)
//      - 01E6:     PIO-B (keyboard input)
//      - 01E8:     CTC-0 (free)
//      - 01EA:     CTC-1 (cassette tape output)
//      - 01EC:     CTC-2 (timer interrupt used for sound length)
//
//  ## IO Port Map:
//      - 80:   Expansion module control (OUT: write module control byte,
//              IN: read module id in slot). The upper 8 bits on the
//              address bus identify the module slot (in the base
//              unit the two slot addresses are 08 and 0C).
//      - 88:   PIO port A, data
//      - 89:   PIO port B, data
//      - 8A:   PIO port A, control
//      - 8B:   PIO port B, control
//      - 8C:   CTC channel 0
//      - 8D:   CTC channel 1
//      - 8E:   CTC channel 2
//      - 8F:   CTC channel 3
//
//      The PIO port A and B bits are used to control bank switching and
//      other hardware features:
//
//      - PIO-A:
//          - bit 0:    switch ROM at E000..FFFF on/off
//          - bit 1:    switch RAM at 0000..3FFF on/off
//          - bit 2:    switch video RAM (IRM) at 8000..BFFF on/off
//          - bit 3:    write-protect RAM at 0000
//          - bit 4:    unused
//          - bit 5:    switch the front-plate LED on/off
//          - bit 6:    cassette tape player motor control
//          - bit 7:    expansion ROM at C000 on/off
//      - PIO-B:
//          - bits 0..4:    sound volume (currently not implemented)
//          - bits 5/6:     unused
//          - bit 7:        enable/disable the foreground-color blinking
//
//      The CTC channels are used for sound frequency and other timing tasks:
//
//      - CTC-0:    sound output (left?)
//      - CTC-1:    sound output (right?)
//      - CTC-2:    foreground color blink frequency, timer for cassette input
//      - CTC-3:    timer for keyboard input
//
//  ## The Module System:
//
//  The emulator supports the most common RAM- and ROM-modules,
//  but doesn't emulate special-hardware modules like the V24 or
//  A/D converter module.
//
//  The module system works with 4 byte values:
//
//  - The **slot address**, the two base unit slots are at address 08 and 0C
//  - The **module id**, this is a fixed value that identifies a module type.
//    All 16 KByte ROM application modules had the same id.
//    The module id can be queried by reading from port 80, with the
//    slot address in the upper 8 bit of the 16-bit port address (so
//    to query what module is in slot C, you would do an IN A,(C),
//    with the value 0C80 in BC). If no module is in the slot, the value
//    FF would be written to A, otherwise the module's id byte.
//  - The module's **address mask**, this is a byte value that's ANDed
//    against the upper 8 address bytes when mapping the module to memory,
//    this essentially clamps a module's address to a 'round' 8- or
//    16 KByte value (these are the 2 values I've seen in the wild)
//  - The module control byte, this controls whether a module is currently
//    active (bit 0), write-protected (bit 1), and at what address the
//    module is mapped into the 16-bit address space (upper 3 bits)
//
//  The module system is controlled with the SWITCH command, for instance
//  the following command would map a ROM module in slot 8 to address
//  C000:
//
//      SWITCH 8 C1
//
//  A RAM module in slot 0C mapped to address 4000:
//
//      SWITCH C 43
//
//  If you want to write-protect the RAM:
//
//      SWITCH C 41
//
//  ## The KC85/3
//
//  The KC85/3 had the same hardware as the KC85/2 but came with a builtin
//  8 KByte BASIC ROM at address C000..DFFF, and the OS was bumped to
//  CAOS 3.1, now taking up a full 8 KBytes. Despite being just a minor
//  update to the KC85/2, the KC85/3 was (most likely) the most popular
//  model of the KC85/2 family.
//
//  ## The KC85/4
//
//  The KC85/4 was a major upgrade to the KC85/2 hardware architecture:
//
//  - 64 KByte usable RAM
//  - 64 KByte video RAM split up into 4 16-KByte banks
//  - 20 KByte ROM (8 KByte BASIC, and 8+4 KByte OS)
//  - Improved color attribute resolution (8x1 pixels instead of 8x4)
//  - An additional per-pixel color mode which allowed to assign each
//    individual pixel one of 4 hardwired colors at full 320x256
//    resolution, this was realized by using 1 bit from the
//    pixel-bank and the other bit from the color-bank, so setting
//    one pixel required 2 memory accesses and a bank switch. Maybe
//    this was the reason why this mode was hardly used.
//  - Improved '90-degree-rotated' video memory layout, the 320x256
//    pixel video memory was organized as 40 vertical stacks of 256 bytes,
//    and the entire video memory was linear, this was perfectly suited
//    to the Z80's 8+8 bit register pairs. The upper 8-bit register
//    (for instance H) would hold the 'x coordinate' (columns 0 to 39),
//    and the lower 8-bit register (L) the y coordinate (lines 0 to 255).
//  - 64 KByte video memory was organized into 4 16-KByte banks, 2 banks
//    for pixels, and 2 banks for colors. One pixel+color bank pair could
//    be displayed while the other could be accessed by the CPU, this enabled
//    true hardware double-buffering (unfortunately everything else was
//    hardwired, so things like hardware-scrolling were not possible).
//
//  The additional memory bank switching options were realized through
//  previously unused bits in the PIO A/B ports, and 2 additional
//  write-only 8-bit latches at port address 84 and 86:
//
//  New bits in PIO port B:
//      - bit 5:    enable the 2 stacked RAM banks at address 8000
//      - bit 6:    write protect RAM bank at address 8000
//
//  Output port 84:
//      - bit 0:    select  the pixel/color bank pair 0 or 1 for display
//      - bit 1:    select the pixel (0) or color bank (1) for CPU access
//      - bit 2:    select the pixel/color bank pair 0 or 1 for CPU access
//      - bit 3:    active the per-pixel-color-mode
//      - bit 4:    select one of two RAM banks at address 8000
//      - bit 5:    ??? (the docs say "RAM Block Select Bit for RAM8")
//      - bits 6/7: unused
//
//  Output port 86:
//      - bit 0:        enable the 16K RAM bank at address 4000
//      - bit 1:        write-protection for for RAM bank at address 4000
//      - bits 2..6:    unused
//      - bit 7:        enable the 4 KByte CAOS ROM bank at C000
//
//  ## TODO:
//
//  - optionally proper keyboard emulation (the current implementation
//    uses a shortcut to directly write the key code into a memory address)
//  - wait states for video RAM access
//  - audio volume is currently not implemented
//
const std = @import("std");
const CPU = @import("CPU.zig");
const PIO = @import("PIO.zig");
const CTC = @import("CTC.zig");
const Memory = @import("Memory.zig");
const Clock = @import("Clock.zig");
const Beeper = @import("Beeper.zig");
const KeyBuffer = @import("KeyBuffer.zig");

const KC85 = @This();

cpu: CPU,
ctc: CTC,
pio: PIO,

pio_a: u8, // current PIO Port A value, used for bankswitching
pio_b: u8, // current PIO Port B value, used for bankswitching
io84: u8, // byte latch on port 0x84, only on KC85/4
io86: u8, // byte latch on port 0x86, only on KC85/4
blink_flag: bool, // foreground color blinking flag toggled by CTC

h_count: usize, // video timing generator counter
v_count: usize,

clk: Clock,
mem: Memory,
kbd: KeyBuffer,
beeper_1: Beeper,
beeper_2: Beeper,
exp: ExpansionSystem,

pixel_buffer: []u32,
audio_func: ?AudioFunc,
num_samples: usize,
sample_pos: usize,
sample_buffer: [max_audio_samples]f32,
patch_func: ?PatchFunc,

ram: [max_ram_size]u8,
irm: [max_irm_size]u8,
rom_caos_c: [rom_c_size]u8,
rom_caos_e: [rom_e_size]u8,
rom_basic: [rom_basic_size]u8,
exp_buf: [expansion_buffer_size]u8,

pub const Model = enum {
    KC85_2,
    KC85_3,
    KC85_4,
};

// expansion system module types
pub const ModuleType = enum {
    NONE,
    M006_BASIC, // BASIC+CAOS 16K ROM module for the KC85/2 (id=0xFC)
    M011_64KBYTE, // 64 KB RAM expansion (id=0xF6)
    M012_TEXOR, // TEXOR text editing (ix=0xFB)
    M022_16KBYTE, // 16 KB RAM expansion (id=0xF4)
    M026_FORTH, // FORTH IDE (id=0xFB)
    M027_DEVELOPMENT, // Assembler IDE (id=0xFB)
};

pub const Desc = struct {
    pixel_buffer: []u32, // must have room for 320x256 RGBA8 pixels

    audio_func: ?AudioFunc = null,
    audio_num_samples: usize = default_num_audio_samples,
    audio_sample_rate: u32 = 44100,
    audio_volume: f32 = 0.4,

    patch_func: ?PatchFunc = null,

    rom_caos22: ?[]const u8 = null, // CAOS 2.2 ROM image (used in KC85/2)
    rom_caos31: ?[]const u8 = null, // CAOS 3.1 ROM image (used in KC85/3)
    rom_caos42c: ?[]const u8 = null, // CAOS 4.2 at 0xC000 (KC85/4)
    rom_caos42e: ?[]const u8 = null, // CAOS 4.2 at 0xE000 (KC85/4)
    rom_kcbasic: ?[]const u8 = null, // same BASIC version for KC85/3 and KC85/4
};

// create a KC85 instance on the heap
pub fn create(allocator: std.mem.Allocator, desc: KC85.Desc) !*KC85 {
    var self = try allocator.create(KC85);
    const freq_hz = switch (model) {
        .KC85_2, .KC85_3 => 1_750_000,
        .KC85_4 => 1_770_000,
    };
    self.* = .{
        .cpu = .{
            // execution on powerup starts at address 0xF000
            .PC = 0xF000,
        },
        .ctc = .{},
        .pio = .{
            .in_func = .{ .func = pioIn, .userdata = @intFromPtr(self) },
            .out_func = .{ .func = pioOut, .userdata = @intFromPtr(self) },
        },
        .pio_a = PIOABits.RAM | PIOABits.RAM_RO | PIOABits.IRM | PIOABits.CAOS_ROM, // initial memory map
        .pio_b = 0,
        .io84 = 0,
        .io86 = 0,
        .blink_flag = true,
        .h_count = 0,
        .v_count = 0,
        .mem = .{},
        .kbd = .{
            .sticky_duration = 2 * 16667,
        },
        .beeper_1 = Beeper.init(.{ .tick_hz = freq_hz, .sound_hz = desc.audio_sample_rate, .volume = desc.audio_volume }),
        .beeper_2 = Beeper.init(.{ .tick_hz = freq_hz, .sound_hz = desc.audio_sample_rate, .volume = desc.audio_volume }),
        .exp = .{ .slots = .{
            .{ .addr = 0x08 },
            .{ .addr = 0x0C },
        } },
        .clk = .{ .freq_hz = freq_hz },
        .sample_pos = 0,
        .sample_buffer = [_]f32{0.0} ** max_audio_samples,
        .pixel_buffer = desc.pixel_buffer,
        .audio_func = desc.audio_func,
        .num_samples = desc.audio_num_samples,
        .patch_func = desc.patch_func,
        .ram = [_]u8{0} ** max_ram_size,
        .irm = [_]u8{0} ** max_irm_size,
        .rom_caos_c = switch (model) {
            .KC85_4 => desc.rom_caos42c.?[0..rom_c_size].*,
            else => [_]u8{0} ** rom_c_size,
        },
        .rom_caos_e = switch (model) {
            .KC85_2 => desc.rom_caos22.?[0..rom_e_size].*,
            .KC85_3 => desc.rom_caos31.?[0..rom_e_size].*,
            .KC85_4 => desc.rom_caos42e.?[0..rom_e_size].*,
        },
        .rom_basic = switch (model) {
            .KC85_3, .KC85_4 => desc.rom_kcbasic.?[0..rom_basic_size].*,
            else => [_]u8{0} ** rom_basic_size,
        },
        .exp_buf = [_]u8{0} ** expansion_buffer_size,
    };

    // on KC85/2 and KC85/3, memory is initially filled with random noise
    if (model != .KC85_4) {
        var r: u32 = 0x6D98302B;
        for (&self.ram) |*ptr| {
            r = xorshift32(r);
            ptr.* = @truncate(r);
        }
        for (&self.irm) |*ptr| {
            r = xorshift32(r);
            ptr.* = @truncate(r);
        }
    }

    // setup initial memory map
    self.updateMemoryMapping();

    return self;
}

// destroy heap-allocated KC85 instance
pub fn destroy(self: *KC85, allocator: std.mem.Allocator) void {
    allocator.destroy(self);
}

// reset KC85 instance
pub fn reset(self: *KC85) void {
    // FIXME
    _ = self;
    unreachable;
}

// run emulation for given number of microseconds
pub fn exec(self: *KC85, micro_secs: u32) void {
    const ticks_to_run = self.clk.ticksToRun(micro_secs);
    const ticks_executed = self.cpu.exec(ticks_to_run, CPU.TickFunc{ .func = tickFunc, .userdata = @intFromPtr(self) });
    self.clk.ticksExecuted(ticks_executed);
    self.kbd.update(micro_secs);
    self.handleKeyboard();
}

// send a key down
pub fn keyDown(self: *KC85, key_code: u8) void {
    self.kbd.keyDown(key_code);
}

// send a key up
pub fn keyUp(self: *KC85, key_code: u8) void {
    self.kbd.keyUp(key_code);
}

// insert a module into an expansion slot
pub fn insertModule(self: *KC85, slot_addr: u8, mod_type: ModuleType, optional_rom_image: ?[]const u8) !void {
    try self.removeModule(slot_addr);

    if (moduleNeedsROMImage(mod_type) and (optional_rom_image == null)) {
        return error.ModuleTypeExpectsROMImage;
    } else if (!moduleNeedsROMImage(mod_type) and (optional_rom_image != null)) {
        return error.ModuleTypeDoesNotExpectROMImage;
    }

    if (self.slotByAddr(slot_addr)) |slot| {
        slot.module = switch (mod_type) {
            .M006_BASIC => .{
                .type = mod_type,
                .id = 0xFC,
                .writable = false,
                .addr_mask = 0xC0,
                .size = 16 * 1024,
            },
            .M011_64KBYTE => .{
                .type = mod_type,
                .id = 0xF6,
                .writable = true,
                .addr_mask = 0xC0,
                .size = 64 * 1024,
            },
            .M022_16KBYTE => .{
                .type = mod_type,
                .id = 0xF4,
                .writable = true,
                .addr_mask = 0xC0,
                .size = 16 * 1024,
            },
            .M012_TEXOR, .M026_FORTH, .M027_DEVELOPMENT => .{
                .type = mod_type,
                .id = 0xFB,
                .writable = false,
                .addr_mask = 0xE0,
                .size = 8 * 1024,
            },
            else => .{},
        };

        // allocate space in expansion buffer
        self.slotAlloc(slot) catch |err| {
            // not enough space left in buffer
            slot.module = .{};
            return err;
        };

        // copy optional ROM image, or clear RAM
        if (moduleNeedsROMImage(mod_type)) {
            const rom = optional_rom_image.?;
            if (rom.len != slot.module.size) {
                return error.ModuleRomImageSizeMismatch;
            } else {
                for (rom, 0..) |byte, i| {
                    self.exp_buf[slot.buf_offset + i] = byte;
                }
            }
        } else {
            for (self.exp_buf[slot.buf_offset .. slot.buf_offset + slot.module.size]) |*p| {
                p.* = 0;
            }
        }

        // also update memory mapping
        self.updateMemoryMapping();
    } else |err| {
        return err;
    }
}

// remove a module from an expansion slot
pub fn removeModule(self: *KC85, slot_addr: u8) !void {
    var slot = try self.slotByAddr(slot_addr);
    if (slot.module.type == .NONE) {
        return;
    }
    self.slotFree(slot);
    slot.module = .{};
    self.updateMemoryMapping();
}

// load a KCC or TAP file image
pub fn load(self: *KC85, data: []const u8) !void {
    if (checkKCTAPMagic(data)) {
        return self.loadKCTAP(data);
    } else {
        return self.loadKCC(data);
    }
}

const model: Model = switch (@import("build_options").kc85_model) {
    .KC85_2 => .KC85_2,
    .KC85_3 => .KC85_3,
    .KC85_4 => .KC85_4,
};

const max_audio_samples = 1024;
const default_num_audio_samples = 128;
const max_tape_size = 1024;
const num_expansion_slots = 2; // max number of expansion slots
const expansion_buffer_size = num_expansion_slots * 64 * 1024; // expansion system buffer size (64 KB per slot)
const max_ram_size = 4 * 0x4000; // up to 64 KB regular RAM
const max_irm_size = 4 * 0x4000; // up to 64 KB video RAM
const rom_c_size = 0x1000;
const rom_e_size = 0x2000;
const rom_basic_size = 0x2000;

// IO bits
const PIOABits = struct {
    const CAOS_ROM: u8 = 1 << 0;
    const RAM: u8 = 1 << 1;
    const IRM: u8 = 1 << 2;
    const RAM_RO: u8 = 1 << 3;
    const UNUSED: u8 = 1 << 4;
    const TAPE_LED: u8 = 1 << 5;
    const TAPE_MOTOR: u8 = 1 << 6;
    const BASIC_ROM: u8 = 1 << 7;
};

const PIOBBits = struct {
    const VOLUME_MASK: u8 = (1 << 5) - 1;
    const RAM8: u8 = 1 << 5; // KC85/4 only
    const RAM8_RO: u8 = 1 << 6; // KC85/4 only
    const BLINK_ENABLED: u8 = 1 << 7;
};

// KC85/4 only: 8-bit latch at IO port 0x84
const IO84Bits = struct {
    const SEL_VIEW_IMG: u8 = 1 << 0; // 0: display img0, 1: display img1
    const SEL_CPU_COLOR: u8 = 1 << 1; // 0: access pixel plane, 1: access color plane
    const SEL_CPU_IMG: u8 = 1 << 2; // 0: access img0, 1: access img1
    const HICOLOR: u8 = 1 << 3; // 0: hicolor off, 1: hicolor on
    const SEL_RAM8: u8 = 1 << 4; // select RAM8 block 0 or 1
    const BLOCKSEL_RAM8: u8 = 1 << 5; // FIXME: ???
};

// KC85/4 only: 8-bit latch at IO port 0x86
const IO86Bits = struct {
    const RAM4: u8 = 1 << 0;
    const RAM4_RO: u8 = 1 << 1;
    const CAOS_ROM_C: u8 = 1 << 7;
};

// expansion module attributes
const Module = struct {
    type: ModuleType = .NONE,
    id: u8 = 0xFF,
    writable: bool = false,
    addr_mask: u8 = 0,
    size: u32 = 0,
};

// an expansion system slot for inserting modules
const Slot = struct {
    addr: u8, // slot address, 0x0C (left slot) or 0x08 (right slot)
    ctrl: u8 = 0, // current control byte
    buf_offset: u32 = 0, // byte offset in expansion system data buffer
    module: Module = .{}, // attributes of currently inserted module
};

// expansion system state
const ExpansionSystem = struct {
    slots: [num_expansion_slots]Slot, // KC85 main unit has 2 expansion slots builtin
    buf_top: u32 = 0, // top of buffer index in KC85.exp_buf
};

// audio output callback, called to push samples into host audio backend
const AudioFunc = struct {
    func: *const fn (samples: []const f32, userdata: usize) void,
    userdata: usize = 0,
};

// callback to apply patches after a snapshot is loaded
const PatchFunc = struct {
    func: *const fn (snapshot_name: []const u8, userdata: usize) void,
    userdata: usize = 0,
};

// pseudo-rand helper function
fn xorshift32(r: u32) u32 {
    var x = r;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return x;
}

// the system tick function is called from within the CPU emulation
fn tickFunc(num_ticks: u64, pins_in: u64, userdata: usize) u64 {
    var self: *KC85 = @ptrFromInt(userdata);
    var pins = pins_in;

    // memory and IO requests
    if (0 != (pins & CPU.MREQ)) {
        // a memory request machine cycle
        const addr = CPU.getAddr(pins);
        if (0 != (pins & CPU.RD)) {
            pins = CPU.setData(pins, self.mem.r8(addr));
        } else if (0 != (pins & CPU.WR)) {
            self.mem.w8(addr, CPU.getData(pins));
        }
    } else if (0 != (pins & CPU.IORQ)) {
        // IO request machine cycle
        //
        // on the KC85/3, the chips-select signals for the CTC and PIO
        // are generated through logic gates, on KC85/4 this is implemented
        // with a PROM chip (details are in the KC85/3 and KC85/4 service manuals)
        //
        // the I/O addresses are as follows:
        //
        //      0x88:   PIO Port A, data
        //      0x89:   PIO Port B, data
        //      0x8A:   PIO Port A, control
        //      0x8B:   PIO Port B, control
        //      0x8C:   CTC Channel 0
        //      0x8D:   CTC Channel 1
        //      0x8E:   CTC Channel 2
        //      0x8F:   CTC Channel 3
        //
        //      0x80:   controls the expansion module system, the upper
        //              8-bits of the port number address the module slot
        //      0x84:   (KC85/4 only) control the video memory bank switching
        //      0x86:   (KC85/4 only) control RAM block at 0x4000 and ROM switching

        // check if any of the valid port number if addressed (0x80..0x8F)
        if (CPU.A7 == (pins & (CPU.A7 | CPU.A6 | CPU.A5 | CPU.A4))) {
            // check if the PIO or CTC is addressed (0x88..0x8F)
            if (0 != (pins & CPU.A3)) {
                pins &= CPU.PinMask;
                // A2 selects PIO or CTC
                if (0 != (pins & CPU.A2)) {
                    // a CTC IO request
                    pins |= CTC.CE;
                    if (0 != (pins & CPU.A0)) {
                        pins |= CTC.CS0;
                    }
                    if (0 != (pins & CPU.A1)) {
                        pins |= CTC.CS1;
                    }
                    pins = self.ctc.iorq(pins) & CPU.PinMask;
                } else {
                    // a PIO IO request
                    pins |= PIO.CE;
                    if (0 != (pins & CPU.A0)) {
                        pins |= PIO.BASEL;
                    }
                    if (0 != (pins & CPU.A1)) {
                        pins |= PIO.CDSEL;
                    }
                    pins = self.pio.iorq(pins) & CPU.PinMask;
                }
            } else {
                // we're in IO port range 0x80..0x87
                const data = CPU.getData(pins);
                switch (pins & (CPU.A2 | CPU.A1 | CPU.A0)) {
                    0x00 => {
                        // port 0x80: expansion system control
                        const slot_addr: u8 = @truncate(CPU.getAddr(pins) >> 8);
                        if (0 != (pins & CPU.WR)) {
                            // write new module control byte and update memory mapping
                            if (self.slotWriteCtrlByte(slot_addr, data)) {
                                self.updateMemoryMapping();
                            }
                        } else {
                            // read module id in slot
                            pins = CPU.setData(pins, self.slotModuleId(slot_addr));
                        }
                    },
                    0x04 => if (model == .KC85_4) {
                        // KC85/4 specific port 0x84
                        if (0 != (pins & CPU.WR)) {
                            self.io84 = data;
                            self.updateMemoryMapping();
                        }
                    },
                    0x06 => if (model == .KC85_4) {
                        // KC85/4 specific port 0x86
                        if (0 != (pins & CPU.WR)) {
                            self.io86 = data;
                            self.updateMemoryMapping();
                        }
                    },
                    else => {},
                }
            }
        }
    }

    pins = self.tickVideo(num_ticks, pins);

    var tick: u64 = 0;
    while (tick < num_ticks) : (tick += 1) {
        // tick the CTC
        pins = self.ctc.tick(pins);
        // CTC channels 0 and 1 control audio frequency
        if (0 != (pins & CTC.ZCTO0)) {
            // toggle beeper 1
            self.beeper_1.toggle();
        }
        if (0 != (pins & CTC.ZCTO1)) {
            self.beeper_2.toggle();
        }
        // CTC channel 2 trigger controls video blink frequency
        if (0 != (pins & CTC.ZCTO2)) {
            self.blink_flag = !self.blink_flag;
        }
        pins &= CPU.PinMask;
        // tick beepers and update audio
        _ = self.beeper_1.tick();
        if (self.beeper_2.tick()) {
            // new audio sample ready
            self.sample_buffer[self.sample_pos] = self.beeper_1.sample + self.beeper_2.sample;
            self.sample_pos += 1;
            if (self.sample_pos == self.num_samples) {
                // flush sample buffer to audio backend
                self.sample_pos = 0;
                if (self.audio_func) |audio_func| {
                    audio_func.func(self.sample_buffer[0..self.num_samples], audio_func.userdata);
                }
            }
        }
    }

    // interrupt daisychain handling, the CTC is higher priority than the PIO
    if (0 != (pins & CPU.M1)) {
        pins |= CPU.IEIO;
        pins = self.ctc.int(pins);
        pins = self.pio.int(pins);
        pins &= ~CPU.RETI;
    }
    return pins & CPU.PinMask;
}

fn updateMemoryMapping(self: *KC85) void {
    self.mem.unmapBank(0);

    // all models have 16 KB builtin RAM at 0x0000 and 8 KB ROM at 0xE000
    if (0 != (self.pio_a & PIOABits.RAM)) {
        // RAM may be write-protected
        const ram0 = self.ram[0..0x4000];
        if (0 != (self.pio_a & PIOABits.RAM_RO)) {
            self.mem.mapRAM(0, 0x0000, ram0);
        } else {
            self.mem.mapROM(0, 0x0000, ram0);
        }
    }
    if (0 != (self.pio_a & PIOABits.CAOS_ROM)) {
        self.mem.mapROM(0, 0xE000, &self.rom_caos_e);
    }

    // KC85/3 and /4: builtin 8 KB BASIC ROM at 0xC000
    if (model != .KC85_2) {
        if (0 != (self.pio_a & PIOABits.BASIC_ROM)) {
            self.mem.mapROM(0, 0xC000, &self.rom_basic);
        }
    }

    if (model != .KC85_4) {
        // KC 85/2, /3: 16 KB video ram at 0x8000
        if (0 != (self.pio_a & PIOABits.IRM)) {
            self.mem.mapRAM(0, 0x8000, self.irm[0x0000..0x4000]);
        }
    } else {
        // KC85/4 has a much more complex memory map

        // 16 KB RAM at 0x4000, may be write-protected
        if (0 != (self.io86 & IO86Bits.RAM4)) {
            const ram4 = self.ram[0x4000..0x8000];
            if (0 != (self.io86 & IO86Bits.RAM4_RO)) {
                self.mem.mapRAM(0, 0x4000, ram4);
            } else {
                self.mem.mapROM(0, 0x4000, ram4);
            }
        }

        // 16 KB RAM at 0x8000 (2 banks)
        if (0 != (self.pio_b & PIOBBits.RAM8)) {
            const ram8_start: usize = if (0 != (self.io84 & IO84Bits.SEL_RAM8)) 0xC000 else 0x8000;
            const ram8_end = ram8_start + 0x4000;
            const ram8 = self.ram[ram8_start..ram8_end];
            if (0 != (self.pio_b & PIOBBits.RAM8_RO)) {
                self.mem.mapRAM(0, 0x8000, ram8);
            } else {
                self.mem.mapROM(0, 0x8000, ram8);
            }
        }

        // KC85/4 video ram is 4 16KB banks, 2 for pixels, 2 for colors,
        // the area 0xA800 to 0xBFFF is always mapped to IRM0!
        if (0 != (self.pio_a & PIOABits.IRM)) {
            const irm_start = @as(usize, (self.io84 >> 1) & 3) * 0x4000;
            const irm_end = irm_start + 0x2800;
            self.mem.mapRAM(0, 0x8000, self.irm[irm_start..irm_end]);
            self.mem.mapRAM(0, 0xA800, self.irm[0x2800..0x4000]);
        }

        // 4 KB CAOS-C ROM at 0xC000 (on top of BASIC)
        if (0 != (self.io86 & IO86Bits.CAOS_ROM_C)) {
            self.mem.mapROM(0, 0xC000, &self.rom_caos_c);
        }
    }

    // expansion system memory mapping
    for (&self.exp.slots, 0..) |*slot, slot_index| {

        // nothing to do if no module in slot
        if (slot.module.type == .NONE) {
            continue;
        }

        // each slot gets its own memory bank, bank 0 is used by the
        // computer base unit
        const bank_index = slot_index + 1;
        self.mem.unmapBank(bank_index);

        // module is only active if bit 0 in control byte is set
        if (0 != (slot.ctrl & 1)) {
            // compute CPU and host address
            const addr: u16 = @as(u16, (slot.ctrl & slot.module.addr_mask)) << 8;
            const host_start = slot.buf_offset;
            const host_end = host_start + slot.module.size;
            const host_slice = self.exp_buf[host_start..host_end];

            // RAM modules are only writable if bit 1 in control byte is set
            const writable = (0 != (slot.ctrl & 2)) and slot.module.writable;
            if (writable) {
                self.mem.mapRAM(bank_index, addr, host_slice);
            } else {
                self.mem.mapROM(bank_index, addr, host_slice);
            }
        }
    }
}

// PIO port input/output callbacks
fn pioIn(port: u1, userdata: usize) u8 {
    _ = port;
    _ = userdata;
    return 0xFF;
}

fn pioOut(port: u1, data: u8, userdata: usize) void {
    var self: *KC85 = @ptrFromInt(userdata);
    switch (port) {
        PIO.PA => self.pio_a = data,
        PIO.PB => self.pio_b = data,
    }
    self.updateMemoryMapping();
}

// foreground colors
const fg_pal = [16]u32{
    0xFF000000, // black
    0xFFFF0000, // blue
    0xFF0000FF, // red
    0xFFFF00FF, // magenta
    0xFF00FF00, // green
    0xFFFFFF00, // cyan
    0xFF00FFFF, // yellow
    0xFFFFFFFF, // white
    0xFF000000, // black #2
    0xFFFF00A0, // violet
    0xFF00A0FF, // orange
    0xFFA000FF, // purple
    0xFFA0FF00, // blueish green
    0xFFFFA000, // greenish blue
    0xFF00FFA0, // yellow-green
    0xFFFFFFFF, // white #2
};

// background colors
const bg_pal = [8]u32{
    0xFF000000, // black
    0xFFA00000, // dark-blue
    0xFF0000A0, // dark-red
    0xFFA000A0, // dark-magenta
    0xFF00A000, // dark-green
    0xFFA0A000, // dark-cyan
    0xFF00A0A0, // dark-yellow
    0xFFA0A0A0, // gray
};

fn decode8Pixels(dst: []u32, pixel_bits: u8, color_bits: u8, force_bg: bool) void {
    // select foreground- and background color:
    // bit 7: blinking
    // bits 6..3: foreground color
    // bits 2..0: background color
    //
    // index 0 is background color, index 1 is foreground color
    const bg_index = color_bits & 0x7;
    const fg_index = (color_bits >> 3) & 0xF;
    const bg = bg_pal[bg_index];
    const fg = if (force_bg) bg else fg_pal[fg_index];
    dst[0] = if (0 != (pixel_bits & 0x80)) fg else bg;
    dst[1] = if (0 != (pixel_bits & 0x40)) fg else bg;
    dst[2] = if (0 != (pixel_bits & 0x20)) fg else bg;
    dst[3] = if (0 != (pixel_bits & 0x10)) fg else bg;
    dst[4] = if (0 != (pixel_bits & 0x08)) fg else bg;
    dst[5] = if (0 != (pixel_bits & 0x04)) fg else bg;
    dst[6] = if (0 != (pixel_bits & 0x02)) fg else bg;
    dst[7] = if (0 != (pixel_bits & 0x01)) fg else bg;
}

fn tickVideoCounters(self: *KC85, in_pins: u64) u64 {
    var pins = in_pins;
    const h_width = if (model == .KC85_4) 113 else 112;
    self.h_count += 1;
    if (self.h_count >= h_width) {
        self.h_count = 0;
        self.v_count += 1;
        if (self.v_count >= 312) {
            self.v_count = 0;
            // vertical sync, trigger CTC CLKTRG2 input for video blinking effect
            pins |= CTC.CLKTRG2;
        }
    }
    return pins;
}

fn tickVideoKC8523(self: *KC85, num_ticks: u64, in_pins: u64) u64 {
    // FIXME: display needling
    var pins = in_pins;
    const blink_bg = self.blink_flag and (0 != (self.pio_b & PIOBBits.BLINK_ENABLED));
    var tick: u64 = 0;
    while (tick < num_ticks) : (tick += 1) {
        // every 2 ticks 8 pixels are decoded
        if (0 != (self.h_count & 1)) {
            // decode visible 8-pixel group
            const x = self.h_count / 2;
            const y = self.v_count;
            if ((y < 256) and (x < 40)) {
                const dst_index = y * 320 + x * 8;
                const dst = self.pixel_buffer[dst_index .. dst_index + 8];
                var pixel_offset: usize = undefined;
                var color_offset: usize = undefined;
                if (x < 0x20) {
                    // left 256x256 area
                    pixel_offset = x | (((y >> 2) & 0x3) << 5) | ((y & 0x3) << 7) | (((y >> 4) & 0xF) << 9);
                    color_offset = x | (((y >> 2) & 0x3f) << 5);
                } else {
                    // right 64x256 area
                    pixel_offset = 0x2000 + ((x & 0x7) | (((y >> 4) & 0x3) << 3) | (((y >> 2) & 0x3) << 5) | ((y & 0x3) << 7) | (((y >> 6) & 0x3) << 9));
                    color_offset = 0x0800 + ((x & 0x7) | (((y >> 4) & 0x3) << 3) | (((y >> 2) & 0x3) << 5) | (((y >> 6) & 0x3) << 7));
                }
                const pixel_bits = self.irm[pixel_offset];
                const color_bits = self.irm[0x2800 + color_offset];
                const force_bg = blink_bg and (0 != (color_bits & 0x80));
                decode8Pixels(dst, pixel_bits, color_bits, force_bg);
            }
        }
        pins = self.tickVideoCounters(pins);
    }
    return pins;
}

fn tickVideoKC854Std(self: *KC85, num_ticks: u64, in_pins: u64) u64 {
    var pins = in_pins;
    const blink_bg = self.blink_flag and (0 != (self.pio_b & PIOBBits.BLINK_ENABLED));
    var tick: u64 = 0;
    while (tick < num_ticks) : (tick += 1) {
        if (0 != (self.h_count & 1)) {
            const x = self.h_count / 2;
            const y = self.v_count;
            if ((y < 256) and (x < 40)) {
                const dst_index = y * 320 + x * 8;
                const dst = self.pixel_buffer[dst_index .. dst_index + 8];
                const irm_bank_index: usize = (self.io84 & IO84Bits.SEL_VIEW_IMG) * 2;
                const irm_offset: usize = irm_bank_index * 0x4000 + x * 256 + y;
                const pixel_bits = self.irm[irm_offset];
                const color_bits = self.irm[irm_offset + 0x4000];
                const force_bg = blink_bg and (0 != (color_bits & 0x80));
                decode8Pixels(dst, pixel_bits, color_bits, force_bg);
            }
        }
        pins = self.tickVideoCounters(pins);
    }
    return pins;
}

fn tickVideoKC854HiColor(self: *KC85, num_ticks: u64, pins: u64) u64 {
    // FIXME
    _ = self;
    _ = num_ticks;
    return pins;
}

fn tickVideoKC854(self: *KC85, num_ticks: u64, pins: u64) u64 {
    if (0 != (self.io84 & IO84Bits.HICOLOR)) {
        return self.tickVideoKC854Std(num_ticks, pins);
    } else {
        return self.tickVideoKC854HiColor(num_ticks, pins);
    }
}

fn tickVideo(self: *KC85, num_ticks: u64, pins: u64) u64 {
    return switch (model) {
        .KC85_2, .KC85_3 => self.tickVideoKC8523(num_ticks, pins),
        .KC85_4 => self.tickVideoKC854(num_ticks, pins),
    };
}

// helper functions for keyboard handler to directly set and clear bits in memory
fn clearBits(self: *KC85, addr: u16, mask: u8) void {
    self.mem.w8(addr, self.mem.r8(addr) & ~mask);
}

fn setBits(self: *KC85, addr: u16, mask: u8) void {
    self.mem.w8(addr, self.mem.r8(addr) | mask);
}

fn handleKeyboard(self: *KC85) void {
    // KEYBOARD INPUT
    //
    // this is a simplified version of the PIO-B interrupt service routine
    // which is normally triggered when the serial keyboard hardware
    // sends a new pulse (for details, see
    // https://github.com/floooh/yakc/blob/master/misc/kc85_3_kbdint.md )
    //
    // we ignore the whole tricky serial decoding and patch the
    // keycode directly into the right memory locations
    //
    const ready_bit: u8 = (1 << 0);
    const timeout_bit: u8 = (1 << 3);
    const repeat_bit: u8 = (1 << 4);
    const short_repeat_count: u8 = 8;
    const long_repeat_count: u8 = 60;

    // don't do anything if interrupts are disabled, IX might point
    // to the wrong base addess in this case!
    if (!self.cpu.iff1) {
        return;
    }

    // get the most recently pressed key
    const key_code = self.kbd.mostRecentKey();

    // system base address, where CAOS stores important system variables
    // (like the currently pressed key)
    const ix = self.cpu.IX;
    const addr_keystatus = ix +% 0x8;
    const addr_keycode = ix +% 0xD;
    const addr_keyrepeat = ix +% 0xA;

    if (0 == key_code) {
        // if keycode is 0, this basically means the CTC3 timeout was hit
        self.setBits(addr_keystatus, timeout_bit);
        // clear current key code
        self.mem.w8(addr_keycode, 0);
    } else {
        // a valid keycode has been received, clear the timeout bit
        self.clearBits(addr_keystatus, timeout_bit);

        // check for key repeat
        if (key_code != self.mem.r8(addr_keycode)) {
            // no key repeat, write new keycode
            self.mem.w8(addr_keycode, key_code);
            // clear the key-repeat bit and set the key-ready bit
            self.clearBits(addr_keystatus, repeat_bit);
            self.setBits(addr_keystatus, ready_bit);
            // clear the repeat counter
            self.mem.w8(addr_keyrepeat, 0);
        } else {
            // handle key repeat
            // increment repeat-pause counter
            self.mem.w8(addr_keyrepeat, self.mem.r8(addr_keyrepeat) +% 1);
            if (0 != (self.mem.r8(addr_keystatus) & repeat_bit)) {
                // this is a followup, short key repeat
                if (self.mem.r8(addr_keyrepeat) < short_repeat_count) {
                    // wait some more...
                    return;
                }
            } else {
                // this is the first, long key repeat
                if (self.mem.r8(addr_keyrepeat) < long_repeat_count) {
                    // wait some more...
                    return;
                } else {
                    // first key repeat pause over, set first-key-repeat flag
                    self.setBits(addr_keystatus, repeat_bit);
                }
            }
            // key-repeat triggered, just set the key ready flag, and reset repeat count
            self.setBits(addr_keystatus, ready_bit);
            self.mem.w8(addr_keyrepeat, 0);
        }
    }
}

fn slotByAddr(self: *KC85, addr: u8) !*Slot {
    for (&self.exp.slots) |*slot| {
        if (addr == slot.addr) {
            return slot;
        }
    } else {
        return error.InvalidSlotAddress;
    }
}

fn slotModuleId(self: *KC85, addr: u8) u8 {
    const slot = self.slotByAddr(addr) catch {
        return 0xFF;
    };
    return slot.module.id;
}

fn slotWriteCtrlByte(self: *KC85, slot_addr: u8, ctrl_byte: u8) bool {
    var slot = self.slotByAddr(slot_addr) catch {
        return false;
    };
    slot.ctrl = ctrl_byte;
    return true;
}

// allocate expansion buffer space for a module to be inserted
// into a slot, updates exp.buf_top and slot.buf_offset
fn slotAlloc(self: *KC85, slot: *Slot) !void {
    if ((slot.module.size + self.exp.buf_top) > expansion_buffer_size) {
        return error.ExpansionBufferFull;
    }
    slot.buf_offset = self.exp.buf_top;
    self.exp.buf_top += slot.module.size;
}

// free an allocation in the expansion and close the gap
// updates:
//  exp.buf_top
//  exp_buf (gaps are closed)
//  for each slot behind the to be freed slot:
//      slot.buf_offset
fn slotFree(self: *KC85, free_slot: *Slot) void {
    std.debug.assert(free_slot.module.size > 0);
    const bytes_to_free = free_slot.module.size;
    self.exp.buf_top -= bytes_to_free;
    for (&self.exp.slots) |*slot| {
        // skip empty slots
        if (slot.module.type == .NONE) {
            continue;
        }
        // if slot is behind the to be freed slot:
        if (slot.buf_offset > free_slot.buf_offset) {
            // move data backward to close the hole
            const src_start = slot.buf_offset;
            const src_end = slot.buf_offset + bytes_to_free;
            const dst_start = slot.buf_offset - bytes_to_free;
            for (self.exp_buf[src_start..src_end], 0..) |byte, i| {
                self.exp_buf[dst_start + i] = byte;
            }
            slot.buf_offset -= bytes_to_free;
        }
    }
}

fn moduleNeedsROMImage(mod_type: ModuleType) bool {
    return switch (mod_type) {
        .M011_64KBYTE, .M022_16KBYTE => false,
        else => true,
    };
}

// common autostart function for all loaders
fn loadStart(self: *KC85, exec_addr: u16) void {
    // reset register values
    self.cpu.setR8(CPU.A, 0);
    self.cpu.setR8(CPU.F, 0x10);
    self.cpu.setR16(CPU.BC, 0);
    self.cpu.setR16(CPU.DE, 0);
    self.cpu.setR16(CPU.HL, 0);
    self.cpu.ex[CPU.BC] = 0;
    self.cpu.ex[CPU.DE] = 0;
    self.cpu.ex[CPU.HL] = 0;
    self.cpu.ex[CPU.FA] = 0;
    var addr: u16 = 0xB200;
    while (addr < 0xB700) : (addr += 1) {
        self.mem.w8(addr, 0);
    }
    self.mem.w8(0xB7A0, 0);
    if (model == .KC85_3) {
        _ = tickFunc(1, CPU.setAddrData(CPU.IORQ | CPU.WR, 0x0089, 0x9F), @intFromPtr(self));
        self.mem.w16(self.cpu.SP, 0xF15C);
    } else if (model == .KC85_4) {
        _ = tickFunc(1, CPU.setAddrData(CPU.IORQ | CPU.WR, 0x0089, 0xFF), @intFromPtr(self));
        self.mem.w16(self.cpu.SP, 0xF17E);
    }
    self.cpu.PC = exec_addr;
}

// FIXME: this should "packed struct", but this results in a struct size
// of 135 bytes for some reason
const KCCHeader = extern struct {
    name: [16]u8,
    num_addr: u8,
    load_addr_l: u8,
    load_addr_h: u8,
    end_addr_l: u8,
    end_addr_h: u8,
    exec_addr_l: u8,
    exec_addr_h: u8,
    pad: [105]u8, // pads to 128 byte
};

const KCTAPHeader = extern struct {
    magic: [16]u8, // "\xC3KC-TAPE by AF. "
    type: u8, // 00: KCTAP_Z9001, 01: KCTAP_KC85, else KCTAP_SYS
    kcc: KCCHeader,
};

// invoke the post-loading patch callback function
fn invokePatchCallback(self: *KC85, header: *const KCCHeader) void {
    if (self.patch_func) |patch_func| {
        patch_func.func(header.name[0..], patch_func.userdata);
    }
}

fn makeU16(hi: u8, lo: u8) u16 {
    return (@as(u16, hi) << 8) | lo;
}

fn validateKCC(data: []const u8) !void {
    if (data.len < @sizeOf(KCCHeader)) {
        return error.KCCWrongHeaderSize;
    }
    const hdr: *const KCCHeader = @ptrCast(data);
    if (hdr.num_addr > 3) {
        return error.KCCNumAddrTooBig;
    }
    const load_addr = makeU16(hdr.load_addr_h, hdr.load_addr_l);
    const end_addr = makeU16(hdr.end_addr_h, hdr.end_addr_l);
    if (end_addr <= load_addr) {
        return error.KCCEndAddrBeforeLoadAddr;
    }
    if (hdr.num_addr > 2) {
        const exec_addr = makeU16(hdr.exec_addr_h, hdr.exec_addr_l);
        if ((exec_addr < load_addr) or (exec_addr > end_addr)) {
            return error.KCCExecAddrOutOfRange;
        }
    }
    const expected_data_size = (end_addr - load_addr) + @sizeOf(KCCHeader);
    if (expected_data_size > data.len) {
        return error.KCCNotEnoughData;
    }
}

fn loadKCC(self: *KC85, data: []const u8) !void {
    try validateKCC(data);
    const hdr: *const KCCHeader = @ptrCast(data);
    var addr = makeU16(hdr.load_addr_h, hdr.load_addr_l);
    const end_addr = makeU16(hdr.end_addr_h, hdr.end_addr_l);
    const payload = data[@sizeOf(KCCHeader)..];
    for (payload) |byte| {
        if (addr < end_addr) {
            self.mem.w8(addr, byte);
        }
        addr +%= 1;
    }
    self.invokePatchCallback(hdr);
    // if file has an exec address, start the program
    if (hdr.num_addr > 2) {
        const exec_addr = makeU16(hdr.exec_addr_h, hdr.exec_addr_l);
        self.loadStart(exec_addr);
    }
}

// this only checks the KCTAP header
fn checkKCTAPMagic(data: []const u8) bool {
    if (data.len <= @sizeOf(KCTAPHeader)) {
        return false;
    }
    const hdr: *const KCTAPHeader = @ptrCast(data);
    const magic = [16]u8{ 0xC3, 'K', 'C', '-', 'T', 'A', 'P', 'E', 0x20, 'b', 'y', 0x20, 'A', 'F', '.', 0x20 };
    return std.mem.eql(u8, magic[0..], hdr.magic[0..]);
}

fn validateKCTAP(data: []const u8) !void {
    if (!checkKCTAPMagic(data)) {
        return error.NoKCTAPMagicNumber;
    }
    const hdr: *const KCTAPHeader = @ptrCast(data);
    if (hdr.kcc.num_addr > 3) {
        return error.KCTAPNumAddrTooBig;
    }
    const load_addr = makeU16(hdr.kcc.load_addr_h, hdr.kcc.load_addr_l);
    const end_addr = makeU16(hdr.kcc.end_addr_h, hdr.kcc.end_addr_l);
    if (end_addr <= load_addr) {
        return error.KCTAPEndAddrBeforeLoadAddr;
    }
    if (hdr.kcc.num_addr > 2) {
        const exec_addr = makeU16(hdr.kcc.exec_addr_h, hdr.kcc.exec_addr_l);
        if ((exec_addr < load_addr) or (exec_addr > end_addr)) {
            return error.KCTAPExecAddrOutOfRange;
        }
    }
    const expected_data_size = (end_addr - load_addr) + @sizeOf(KCTAPHeader);
    if (expected_data_size > data.len) {
        return error.KCCNotEnoughData;
    }
}

fn loadKCTAP(self: *KC85, data: []const u8) !void {
    try validateKCTAP(data);
    const hdr: *const KCTAPHeader = @ptrCast(data);
    var addr = makeU16(hdr.kcc.load_addr_h, hdr.kcc.load_addr_l);
    const end_addr = makeU16(hdr.kcc.end_addr_h, hdr.kcc.end_addr_l);
    const payload = data[@sizeOf(KCTAPHeader)..];
    for (payload, 0..) |byte, i| {
        // each block is one lead byte and 128 byte data
        if ((i % 129) != 0) {
            if (addr < end_addr) {
                self.mem.w8(addr, byte);
            }
            addr +%= 1;
        }
    }
    self.invokePatchCallback(&hdr.kcc);
    // if file has an exec address, start the program
    if (hdr.kcc.num_addr > 2) {
        const exec_addr = makeU16(hdr.kcc.exec_addr_h, hdr.kcc.exec_addr_l);
        self.loadStart(exec_addr);
    }
}
