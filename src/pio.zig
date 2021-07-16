//
//  Z80 PIO emulator
//
const DaisyChain = @import("daisy.zig").DaisyChain;

// data bus pins shared with CPU
pub const D0: u64 = 1<<16;
pub const D1: u64 = 1<<17;
pub const D2: u64 = 1<<18;
pub const D3: u64 = 1<<19;
pub const D4: u64 = 1<<20;
pub const D5: u64 = 1<<21;
pub const D6: u64 = 1<<22;
pub const D7: u64 = 1<<23;
pub const DataPinShift = 16;
pub const DataPinMask: u64 = 0xFF0000;
    
// control pins shared with CPU
pub const M1:       u64 = 1<<24;    // machine cycle 1
pub const IORQ:     u64 = 1<<26;    // IO request
pub const RD:       u64 = 1<<27;    // read request

// PIO specific pins starting at bit 40
pub const CE:       u64 = 1<<40;    // chip enable
pub const BASEL:    u64 = 1<<41;    // port A/B select (0: A, 1: B)
pub const CDSEL:    u64 = 1<<42;    // control/data select (0: data, 1: control)
pub const ARDY:     u64 = 1<<43;    // port A ready
pub const BRDY:     u64 = 1<<44;    // port B ready
pub const ASTB:     u64 = 1<<45;    // port A strobe
pub const BSTB:     u64 = 1<<46;    // port B strobe

pub const BASELPinShift = 41;

// port pins
pub const PA0:      u64 = 1<<48;
pub const PA1:      u64 = 1<<49;
pub const PA2:      u64 = 1<<50;
pub const PA3:      u64 = 1<<51;
pub const PA4:      u64 = 1<<52;
pub const PA5:      u64 = 1<<53;
pub const PA6:      u64 = 1<<54;
pub const PA7:      u64 = 1<<55;

pub const PB0:      u64 = 1<<56;
pub const PB1:      u64 = 1<<57;
pub const PB2:      u64 = 1<<58;
pub const PB3:      u64 = 1<<59;
pub const PB4:      u64 = 1<<60;
pub const PB5:      u64 = 1<<61;
pub const PB6:      u64 = 1<<62;
pub const PB7:      u64 = 1<<63;

pub const PAPinMask = 0x00FF_0000_0000_0000;
pub const PBPinMask = 0xFF00_0000_0000_0000;
pub const PAPinShift = 48;
pub const PBPinShift = 56;

// set data pins in pin mask
pub fn setData(pins: u64, data: u8) u64 {
    return (pins & ~DataPinMask) | (@as(u64, data) << DataPinShift);
}

// get data pins in pin mask
pub fn getData(pins: u64) u8 {
    return @truncate(u8, pins >> DataPinShift);
}

// set port A pins
pub fn setPA(pins: u64, data: u8) u64 {
    return (pins & ~PAPinMask) | ((@as(u64, data)<<PAPinShift) & PAPinMask);
}

// set port B pins
pub fn setPB(pins: u64, data: u8) u64 {
    return (pins & ~PBPinMask) | ((@as(u64, data)<<PBPinShift) & PBPinMask);
}

// set both port A and B pins
pub fn setPAB(pins: u64, pa_data: u8, pb_data) u64 {
    return setPB(setPA(pins, pa_data), pb_data);
}

// port indices
pub const PA: u1 = 0;
pub const PB: u1 = 1;
pub const NumPorts: usize = 2;

//  Operating Modes
//
//  The operating mode of a port is established by writing a control word
//  to the PIO in the following format:
//
//   D7 D6 D5 D4 D3 D2 D1 D0
//  |M1|M0| x| x| 1| 1| 1| 1|
//
//  D7,D6   are the mode word bits
//  D3..D0  set to 1111 to indicate 'Set Mode'
//
pub const Mode = struct {
    pub const OUTPUT:           u2 = 0;
    pub const INPUT:            u2 = 1;
    pub const BIDIRECTIONAL:    u2 = 2;
    pub const BITCONTROL:       u2 = 3;
};

//  Interrupt control word bits.
//
//   D7 D6 D5 D4 D3 D2 D1 D0
//  |EI|AO|HL|MF| 0| 1| 1| 1|
//
//  D7 (EI)             interrupt enabled (1=enabled, 0=disabled)
//  D6 (AND/OR)         logical operation during port monitoring (only Mode 3, AND=1, OR=0)
//  D5 (HIGH/LOW)       port data polarity during port monitoring (only Mode 3)
//  D4 (MASK FOLLOWS)   if set, the next control word are the port monitoring mask (only Mode 3)
//
//  (*) if an interrupt is pending when the enable flag is set, it will then be 
//      enabled on the onto the CPU interrupt request line
//  (*) setting bit D4 during any mode of operation will cause any pending
//      interrupt to be reset
//
//  The interrupt enable flip-flop of a port may be set or reset
//  without modifying the rest of the interrupt control word
//  by the following command:
//
//   D7 D6 D5 D4 D3 D2 D1 D0
//  |EI| x| x| x| 0| 0| 1| 1|
//
pub const IntCtrl = struct {
    pub const EI:    u8 = 1<<7;
    pub const ANDOR: u8 = 1<<6;
    pub const HILO:  u8 = 1<<5;
    pub const MASK_FOLLOWS: u8 = 1<<4;
};

//
//  IO port registers
//
pub const Port = struct {
    input:            u8 = 0,           // data input register
    output:           u8 = 0,           // data output register
    port:             u8 = 0,           // current state of the port I/O pins
    mode:             u2 = Mode.INPUT,  // mode control register (Mode.*)
    io_select:        u8 = 0,           // input/output select register
    int_control:      u8 = 0,           // interrupt control word (IntCtrl.*)
    int_mask:         u8 = 0xFF,        // interrupt control mask
    int_enabled:      bool = false,     // definitive interrupt enabled flag
    expect_io_select: bool = false,     // next control word will be io_select
    expect_int_mask:  bool = false,     // next control word will be int_mask
    bctrl_match:      bool = false,     // bitcontrol logic equation result
    intr:             DaisyChain = .{}, // interrupt daisychain state
};

// Port IO callbacks
const PortInput = fn(port: u1) u8;
const PortOutput = fn(port: u1, data: u8) void;

// PIO state
pub const PIO = struct {
    ports: [NumPorts]Port = [_]Port{.{}} ** NumPorts,
    reset_active: bool = true,  // reset state sticks until first control word received
    in_func: PortInput,         // port-input callback
    out_func: PortOutput,       // port-output callback
    
    // reset the PIO chip
    pub fn reset(pio: *PIO) void {
        impl.reset(pio);
    }
    // perform an IO request
    pub fn iorq(pio: *PIO, pins: u64) u64 {
        return impl.iorq(pio, pins);
    }
    // write value to PIO port, this may trigger an interrupt
    pub fn writePort(pio: *PIO, port: u1, data: u8) void {
        impl.writePort(pio, port, data);
    }
    // call once per CPU machine cycle for interrupt handling
    pub fn int(pio: *PIO, pins: u64) u64 {
        return impl.int(pio, pins);
    } 
};

//=== IMPLEMENTATION ===========================================================

const impl = struct {

fn reset(pio: *PIO) void {
    for (pio.ports) |*p| {
        p.mode = Mode.INPUT;
        p.output = 0;
        p.io_select = 0;
        p.int_control &= ~IntCtrl.EI;
        p.int_mask = 0xFF;
        p.int_enabled = false;
        p.expect_int_mask = false;
        p.expect_io_select = false;
        p.bctrl_match = false;
        p.intrp.reset();
    }
    pio.reset_active = true;
}

fn int(pio: *PIO, in_pins: u64) u64 {
    var pins = in_pins;
    for (pio.ports) |*p| {
        pins = p.intr.int(pins);
    }
    return pins;
}

fn iorq(pio: *PIO, in_pins: u64) u64 {
    var pins = in_pins;
    if ((pins & (CE|IORQ|M1)) == (CE|IORQ)) {
        const port_index = @truncate(u1, (pins & BASEL) >> BASELPinShift);
        if (0 != (pins & RD)) {
            // an IO read request
            const data = if (0 != (pins & CDSEL)) {
                readCtrl(pio);
            }
            else {
                readData(pio, port_index);
            };
            pins = setData(pins, data);
        }
        else {
            // an IO write request
            const data = getData(pins);
            if (0 != (pins & CDSEL)) {
                writeCtrl(pio, port_index, data);
            }
            else {
                writeData(pio, port_index, data);
            }
        }
        pins = setPAB(pins, pio.ports[PA].port, pio.ports[PB].port);
    }
    return pins;
}

fn writePort(pio: *PIO, port_index: u1, data: u8) void {
    var p = &pio.ports[port_index];
    if (Mode.BITCONTROL == p.mode) {
        p.input = data;
        const val = (p.input & p.io_select) | (p.output & ~p.io_select);
        p.port = val;
        const mask = ~p.int_mask;
        var match = false;
        val &= mask;

        const ictrl = p.int_control & 0x60;    
        if ((ictrl == 0) and (val != mask)) { match = true; }
        else if ((ictrl == 0x20) and (val != 0)) { match = true; }
        else if ((ictrl == 0x40) and (val == 0)) { match = true; }
        else if ((ictrl == 0x60) and (val == mask)) { match = true; }
        if (!p.bctrl_match and match and (0 != (p.int_control & 0x80))) {
            // request interrupt
            p.intr.irq();
        }
        p.bctrl_match = match;
    }
}

// new control word received from CPU
fn writeCtrl(pio: *PIO, port_index: u1, data: u8) void {
    pio.reset_active = false;
    var p = &pio.ports[port_index];
    if (p.expect_io_select) {
        // followup io select mask
        p.expect_io_select = false;
        p.io_select = data;
        p.int_enabled = 0 != (p.int_control & IntCtrl.EI);
    }
    else if (p.expect_int_mask) {
        // followup interrupt mask
        p.expect_int_mask = false;
        p.int_mask = data;
        p.int_enabled = 0 != (p.int_control & IntCtrl.EI);
    }
    else switch (data & 0x0F) {
        0x0F => {
            // set operating mode (Mode.*)
            p.mode = @truncate(u2, data >> 6);
            switch (p.mode) {
                Mode.OUTPUT => {
                    // make output visible on port pins
                    p.port = p.output;
                    pio.out_func(port_index, p.port);
                },
                Mode.BITCONTROL => {
                    // next control word is the io_select mask
                    p.expect_io_select = true;
                    // temporarily disable interrupts until io_select mask written
                    p.int_enabled = false;
                    p.bctrl_match = false;
                },
                else => { },
            }
        },
        0x07 => {
            // set interrupt control word (IntCtrl.*)
            p.int_control = data & 0xF0;
            if (0 != (data & IntCtrl.MASK_FOLLOWS)) {
                // next control word is the interrupt control mask
                p.expect_int_mask = true;
                // temporarily disable interrupts until mask written
                p.int_enabled = false;
                // reset pending interrupt
                p.intr.state = 0;
                p.bctrl_match = false;
            }
            else {
                p.int_enabled = 0 != (p.int_control & IntCtrl.EI);
            }
        },
        0x03 => {
            // only set interrupt enable bit
            p.int_control = (data & IntCtrl.EI) | (p.int_control & ~IntCtrl.EI);
            p.int_enabled = 0 != (p.int_control & IntCtrl.EI);
        },
        else => if (0 == (data & 1)) {
            // set interrupt vector
            p.intr.vector = data;
            // according to MAME setting the interrupt vector
            // also enables interrupts, but this doesn't seem to
            // be mentioned in the spec
            p.int_control |= IntCtrl.EI;
            p.int_enabled = true;
        }
    }
}

// read control word back to CPU
fn readCtrl(pio: *PIO) u8 {
    //  I haven't found definitive documentation about what is
    //  returned when reading the control word, this
    //  is what MAME does
    return (pio.ports[PA].int_control & 0xC0) | (pio.ports[PB].int_control >> 4);
}

// new data word received from CPU
fn writeData(pio: *PIO, port_index: u1, data: u8) void {
    var p = &pio.ports[port_index];
    switch (p.mode) {
        Mode.OUTPUT => {
            p.output = data;
            p.port = data;
            pio.out_func(port_index, p.port);
        },
        Mode.INPUT => {
            p.output = data;
        },
        Mode.BIDIRECTIONAL => {
            // FIXME: not implemented
        },
        Mode.BITCONTROL => {
            p.output = data;
            p.port = p.io_select | (p.output & ~p.io_select);
            pio.out_func(port_index, p.port);
        }
    }
}

// read port data back to CPU
fn readData(pio: *PIO, port_index: u1) u8 {
    var p = &pio.ports[port_index];
    switch (p.mode) {
        Mode.OUTPUT => {
            return p.output;
        },
        Mode.INPUT => blk: {
            p.input = pio.in_func(port_index);
            p.port = p.input;
            return p.port;
        },
        Mode.BIDIRECTIONAL => {
            p.input = pio.in_func(port_index);
            p.port = (p.input & p.io_select) | (p.output & ~p.io_select);
            return p.port;
        },
        else => {
            return 0xFF;
        }
    }
}

}; //impl

//=== TEST =====================================================================
const expect = @import("std").testing.expect;

var pa_val: u8 = 0;
var pb_val: u8 = 0;

fn in_func(port: u1) u8 {
    return switch (port) {
        PA => 0,
        PB => 1,
    };
}

fn out_func(port: u1, data: u8) void {
    switch (port) {
        PA => { pa_val = data; },
        PB => { pb_val = data; },
    }
}

test "read_write_control" {
    var pio = PIO{
        .in_func = in_func,
        .out_func = out_func,
    };

    // write interrupt vector 0xEE to port A    
    try expect(pio.reset_active);
    impl.writeCtrl(&pio, PA, 0xEE);
    try expect(!pio.reset_active);
    try expect(pio.ports[PA].intr.vector == 0xEE);
    try expect(0 != (pio.ports[PA].int_control & IntCtrl.EI));
    
    // write interrupt vector 0xCC for port B
    impl.writeCtrl(&pio, PB, 0xCC);
    try expect(pio.ports[PB].intr.vector == 0xCC);
    try expect(0 != (pio.ports[PB].int_control & IntCtrl.EI));

    // set port A to output
    impl.writeCtrl(&pio, PA, (@as(u8, Mode.OUTPUT)<<6)|0x0F);
    try expect(pio.ports[PA].mode == Mode.OUTPUT);

    // set port B to input
    impl.writeCtrl(&pio, PB, (@as(u8, Mode.INPUT)<<6)|0x0F);
    try expect(pio.ports[PB].mode == Mode.INPUT);

    // set port A to bidirectional
    impl.writeCtrl(&pio, PA, (@as(u8, Mode.BIDIRECTIONAL)<<6)|0x0F);
    try expect(pio.ports[PA].mode == Mode.BIDIRECTIONAL);

    // set port A to mode control (plus followup io_select mask) 
    impl.writeCtrl(&pio, PA, (@as(u8, Mode.BITCONTROL)<<6)|0x0F);
    try expect(!pio.ports[PA].int_enabled);
    try expect(pio.ports[PA].mode == Mode.BITCONTROL);
    impl.writeCtrl(&pio, PA, 0xAA);
    try expect(pio.ports[PA].int_enabled);
    try expect(pio.ports[PA].io_select == 0xAA);

    // set port B interrupt control word (with interrupt control mask following)
    impl.writeCtrl(&pio, PB, (IntCtrl.ANDOR|IntCtrl.HILO|IntCtrl.MASK_FOLLOWS)|0x07);
    try expect(!pio.ports[PB].int_enabled);
    try expect(pio.ports[PB].int_control == (IntCtrl.ANDOR|IntCtrl.HILO|IntCtrl.MASK_FOLLOWS));
    impl.writeCtrl(&pio, PB, 0x23);
    try expect(!pio.ports[PB].int_enabled);
    try expect(pio.ports[PB].int_mask == 0x23);
    
    // enable interrupts on port B
    impl.writeCtrl(&pio, PB, IntCtrl.EI|0x03);
    try expect(pio.ports[PB].int_enabled);
    try expect(pio.ports[PB].int_control == (IntCtrl.EI|IntCtrl.ANDOR|IntCtrl.HILO|IntCtrl.MASK_FOLLOWS));

    // write interrupt control word to A and B, 
    // and read the control word back, this does not
    // seem to be documented anywhere, so we're doing
    // the same thing that MAME does.
    impl.writeCtrl(&pio, PA, IntCtrl.ANDOR|IntCtrl.HILO|0x07);
    impl.writeCtrl(&pio, PB, IntCtrl.EI|IntCtrl.ANDOR|0x07);
    const data = impl.readCtrl(&pio);
    try expect(data == 0x4C);
}
