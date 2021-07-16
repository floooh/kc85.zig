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
const z80 = @import("z80.zig");
const z80pio = @import("z80pio.zig");
const z80ctc = @import("z80ctc.zig");
const Memory = @import("memory.zig").Memory;

const MaxAudioSamples = 1024;
const DefaultAudioSamples = 128;
const MaxTapeSize = 1024;
const NumExpansionSlots = 2;           // max number of expansion slots
const ExpansionBufferSize = NumExpSlots * 64 * 1024; // expansion system buffer size (64 KB per slot)

// IO bits
const PIOABits = struct {
    const CAOS_ROM:     u8 = 1<<0;
    const RAM:          u8 = 1<<1;
    const IRM:          u8 = 1<<2;
    const RAM_RO:       u8 = 1<<3;
    const UNUSED:       u8 = 1<<4;
    const TAPE_LED:     u8 = 1<<5;
    const TAPE_MOTOR:   u8 = 1<<6;
    const BASIC_ROM:    u8 = 1<<7;
};

const PIOBBits = struct {
    const VOLUME_MASK:      u8 = (1<<5)-1;
    const RAM8:             u8 = 1<<5;      // KC85/4 only
    const RAM8_RO:          u8 = 1<<6;      // KC85/4 only
    const BLINK_ENABLED:    u8 = 1<<7;
};

// KC85/4 only: 8-bit latch at IO port 0x84
const IO84Bits = struct {
    const SEL_VIEW_IMG:     u8 = 1<<0;      // 0: display img0, 1: display img1
    const SEL_CPU_COLOR:    u8 = 1<<1;      // 0: access pixel plane, 1: access color plane
    const SEL_CPU_IMG:      u8 = 1<<2;      // 0: access img0, 1: access img1
    const HICOLOR:          u8 = 1<<3;      // 0: hicolor off, 1: hicolor on
    const SEL_RAM8:         u8 = 1<<4;      // select RAM8 block 0 or 1
    const BLOCKSEL_RAM8:    u8 = 1<<5;      // FIXME: ???
};

// KC85/4 only: 8-bit latch at IO port 0x86
const IO86Bits = struct {
    const RAM4:             u8 = 1<<0;
    const RAM4_RO:          u8 = 1<<1;
    const CAOS_ROM_C:       u8 = 1<<7;
};

const Type = enum {
    KC85_2,
    KC85_3,
    KC85_4,
};

// audio sample callback
const AudioFunc = fn(samples: []const f32);
// callback to apply patches after a snapshot is loaded
const PatchFunc = fn(snapshot_name: []const u8);

// config parameter for KC85.init()
const Desc = struct {
    type: Type = .KC85_2,
    
    pixel_buffer: ?[]u32 = null,    // must have room for 320x256 pixels

    audio_func:         ?AudioFunc = null,
    audio_num_samples:  usize = DefaultAudioSamples,
    audio_sample_rate:  u32 = 44100,
    audio_volume:       f32 = 0.4,

    patch_func: ?PatchFunc = null,

    rom_caos22:     ?[]const u8 = null;     // CAOS 2.2 ROM image (used in KC85/2)
    rom_caos31:     ?[]const u8 = null;     // CAOS 3.1 ROM image (used in KC85/3)
    rom_caos42c:    ?[]const u8 = null;     // CAOS 4.2 at 0xC000 (KC85/4)
    rom_caos42e:    ?[]const u8 = null;     // CAOS 4.2 at 0xE000 (KC85/4)
    rom_kcbasic:    ?[]const u8 = null;     // same BASIC version for KC85/3 and KC85/4
};

// KC85 emulator state
const KC85 = struct {
    cpu: z80.CPU = .{},
    ctc: z80ctc.CTC = .{},
    pio: z80pio.PIO = .{
        .in_func = pioIn,
        .out_func = pioOut,
    },
    // FIXME: 2 beepers

    type: Type = .KC85_2,
    pio_a: u8 = 0,              // current PIO Port A value, used for bankswitching
    pio_b: u8 = 0,              // current PIO Port B value, used for bankswitching
    io84:  u8 = 0,              // byte latch on port 0x84, only on KC85/4
    io86:  u8 = 0,              // byte latch on port 0x86, only on KC85/4
    blink_flag: bool = true;    // foreground color blinking flag toggled by CTC

    h_tick: u32 = 0;            // video timing generator counter
    v_count: u32 = 0;

    // FIXME: clk
    // FIXME: kbd
    mem: Memory = .{},
    // FIXME: expansion system

    pixel_buffer:   ?[]u32 = null,
    audio_func:     ?AudioFunc = null,
    num_samples:    usize = 0,
    sample_pos:     usize = 0,
    sample_buffer:  [MaxAudioSamples]f32 = undefined,
    patch_func:     ?PatchFunc = null,

    ram:        [8][0x4000]u8 = undefined,
    rom_basic:  [0x2000]u8 = undefined,
    rom_caos_c: [0x1000]u8 = undefined,
    rom_caos_e: [0x2000]u8 = undefined,
    exp_buf:    [ExpansionBufferSize]u8 = undefined
    
    // initialize KC85 instance
    pub fn init(sys: *KC85, desc: *Desc) void {
        impl.init(sys, desc);
    }
    // discard KC85 instance
    pub fn discard(sys: *KC85) void {
        impl.discard(sys);
    }
    // reset KC85 instance
    pub fn reset(sys: *KC85) void {
        impl.reset(sys);
    }
    // run emulation for given number of microseconds
    pub fn exec(sys: *KC85, micro_seconds: usize) void {
        impl.exec(sys, micro_seconds);
    }
};