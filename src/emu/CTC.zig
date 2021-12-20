//
//  Z80 CTC emulator
//
const DaisyChain = @import("DaisyChain.zig");

const CTC = @This();
channels: [NumChannels]Channel = [_]Channel{.{}} ** NumChannels,
    
// reset the CTC chip
pub fn reset(self: *CTC) void {
    for (self.channels) |*chn| {
        chn.control = Ctrl.RESET;
        chn.constant = 0;
        chn.down_counter = 0;
        chn.waiting_for_trigger = false;
        chn.trigger_edge = false;
        chn.prescaler_mask = 0x0F;
        chn.intr.reset();
    }
}

// perform an IO request
pub fn iorq(self: *CTC, in_pins: u64) u64 {
    var pins = in_pins;
    // check for chip-enabled and IO requested
    if ((pins & (CE|IORQ|M1)) == (CE|IORQ)) {
        const chn_index: u2 = @truncate(u2, pins >> CS0PinShift);
        if (0 != (pins & RD)) {
            // an IO read request
            pins = self.ioRead(chn_index, pins);
        }
        else {
            // an IO write request
            pins = self.ioWrite(chn_index, pins);
        }
    }
    return pins;
}

// execute one clock tick
pub fn tick(self: *CTC, in_pins: u64) u64 {
    var pins = in_pins & ~(ZCTO0|ZCTO1|ZCTO2);
    for (self.channels) |*chn, i| {
        const chn_index = @truncate(u2, i);
        // check if externally triggered
        if (chn.waiting_for_trigger or ((chn.control & Ctrl.MODE) == Ctrl.MODE_COUNTER)) {
            const trg: bool = (0 != (pins & (CLKTRG0 << chn_index)));
            if (trg != chn.ext_trigger) {
                chn.ext_trigger = trg;
                // rising/falling edge trigger
                if (chn.trigger_edge == trg) {
                    pins = self.activeEdge(chn_index, pins);
                }
            }
        }
        else if ((chn.control & (Ctrl.MODE|Ctrl.RESET|Ctrl.CONST_FOLLOWS)) == Ctrl.MODE_TIMER) {
            // handle timer mode downcounting
            chn.prescaler -%= 1;
            if (0 == (chn.prescaler & chn.prescaler_mask)) {
                // prescaler has reached zero, tick the down counter
                chn.down_counter -%= 1;
                if (0 == chn.down_counter) {
                    pins = self.counterZero(chn_index, pins);
                }
            }
        }
    }
    return pins;
}


// call once per CPU machine cycle to handle interrupts
pub fn int(self: *CTC, in_pins: u64) u64 {
    var pins = in_pins;
    for (self.channels) |*chn| {
        pins = chn.intr.tick(pins);
    }
    return pins;
}

// set data pins in pin mask
pub fn setData(pins: u64, data: u8) u64 {
    return (pins & ~DataPinMask) | (@as(u64, data) << DataPinShift);
}

// get data pins in pin mask
pub fn getData(pins: u64) u8 {
    return @truncate(u8, pins >> DataPinShift);
}

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

// CTC specific pins, starting at pin 40
pub const CE:       u64 = 1<<40;    // chip enable
pub const CS0:      u64 = 1<<41;    // channel select 0
pub const CS1:      u64 = 1<<42;    // channel select 1
pub const CLKTRG0:  u64 = 1<<43;    // clock/timer trigger 0
pub const CLKTRG1:  u64 = 1<<44;    // clock/timer trigger 1
pub const CLKTRG2:  u64 = 1<<45;    // clock/timer trigger 2
pub const CLKTRG3:  u64 = 1<<46;    // click/timer trigger 3
pub const ZCTO0:    u64 = 1<<47;    // zero count / timeout 0
pub const ZCTO1:    u64 = 1<<48;    // zero count / timeout 1
pub const ZCTO2:    u64 = 1<<49;    // zero count / timeout 2

const CS0PinShift = 41;

// control register bits
pub const Ctrl = struct {
    pub const EI:               u8 = 1<<7;      // 1: interrupt enabled, 0: interrupt disabled

    pub const MODE:             u8 = 1<<6;      // 1: counter mode, 0: timer mode
    pub const MODE_COUNTER:     u8 = 1<<6;
    pub const MODE_TIMER:       u8 = 0;

    pub const PRESCALER:        u8 = 1<<5;      // 1: prescale value 256, 0: prescale value 16
    pub const PRESCALER_256:    u8 = 1<<5;
    pub const PRESCALER_16:     u8 = 0;

    pub const EDGE:             u8 = 1<<4;      // 1: rising edge, 0: falling edge
    pub const EDGE_RISING:      u8 = 1<<4;
    pub const EDGE_FALLING:     u8 = 0;

    pub const TRIGGER:          u8 = 1<<3;      // 1: CLK/TRG pulse starts timer, 0: trigger when time constant loaded
    pub const TRIGGER_WAIT:     u8 = 1<<3;
    pub const TRIGGER_AUTO:     u8 = 0;

    pub const CONST_FOLLOWS:    u8 = 1<<2;      // 1: time constant follows, 0: no time constant follows
    pub const RESET:            u8 = 1<<1;      // 1: software reset, 0: continue operation
    pub const CONTROL:          u8 = 1<<0;      // 1: control, 0: vector
    pub const VECTOR:           u8 = 0;
};

// CTC channel state
pub const NumChannels = 4;
pub const Channel = struct {
    control: u8 = Ctrl.RESET,
    constant: u8 = 0,
    down_counter: u8 = 0,
    prescaler: u8 = 0,
    trigger_edge: bool = false,
    waiting_for_trigger: bool = false,
    ext_trigger: bool = false,
    prescaler_mask: u8 = 0x0F,
    intr: DaisyChain = .{},
};


// read from CTC channel
fn ioRead(self: *CTC, chn_index: u2, pins: u64) u64 {
    return setData(pins, self.channels[chn_index].down_counter);
}

// write to CTC channel
fn ioWrite(self: *CTC, chn_index: u2, in_pins: u64) u64 {
    var pins = in_pins;
    const data = getData(pins);
    const chn = &self.channels[chn_index];
    if (0 != (chn.control & Ctrl.CONST_FOLLOWS)) {
        // timer constant following control word
        chn.control &= ~(Ctrl.CONST_FOLLOWS|Ctrl.RESET);
        chn.constant = data;
        if ((chn.control & Ctrl.MODE) == Ctrl.MODE_TIMER) {
            if ((chn.control & Ctrl.TRIGGER) == Ctrl.TRIGGER_WAIT) {
                chn.waiting_for_trigger = true;
            }
            else {
                chn.down_counter = chn.constant;
            }
        }
        else {
            chn.down_counter = chn.constant;
        }
    }
    else if (0 != (data & Ctrl.CONTROL)) {
        // a new control word
        const old_ctrl = chn.control;
        chn.control = data;
        chn.trigger_edge = ((data & Ctrl.EDGE) == Ctrl.EDGE_RISING);
        if ((chn.control & Ctrl.PRESCALER) == Ctrl.PRESCALER_16) {
            chn.prescaler_mask = 0x0F;
        }
        else {
            chn.prescaler_mask = 0xFF;
        }

        // changing the Trigger Slope triggers an 'active edge' */
        if ((old_ctrl & Ctrl.EDGE) != (chn.control & Ctrl.EDGE)) {
            pins = self.activeEdge(chn_index, pins);
        }
    }
    else {
        // the interrupt vector for the entire CTC must be written
        // to channel 0, the vectors for the following channels 
        // are then computed from the base vector plus 2 bytes per channel
        //
        if (0 == chn_index) {
            for (self.channels) |*c, i| {
                c.intr.vector = (data & 0xF8) +% 2*@truncate(u8,i);
            }
        }
    }
    return pins;
}

// Issue an 'active edge' on a channel, this happens when a CLKTRG pin
// is triggered, or when reprogramming the Z80CTC_CTRL_EDGE control bit.
// 
// This results in:
// - if the channel is in timer mode and waiting for trigger,
//   the waiting flag is cleared and timing starts
// - if the channel is in counter mode, the counter decrements
//
fn activeEdge(self: *CTC, chn_index: u3, in_pins: u64) u64 {
    var pins = in_pins;
    const chn = &self.channels[chn_index];
    if ((chn.control & Ctrl.MODE) == Ctrl.MODE_COUNTER) {
        // counter mode
        chn.down_counter -%= 1;
        if (0 == chn.down_counter) {
            pins = self.counterZero(chn_index, pins);
        }
    }
    else if (chn.waiting_for_trigger) {
        // timer mode and waiting for trigger
        chn.waiting_for_trigger = false;
        chn.down_counter = chn.constant;
    }
    return pins;
}

// called when the downcounter reaches zero, request interrupt,
// trigger ZCTO pin and reload downcounter
//
fn counterZero(self: *CTC, chn_index: u3, in_pins: u64) u64 {
    var pins = in_pins;
    const chn = &self.channels[chn_index];
    // if down counter has reached zero, trigger interrupt and ZCTO pin
    if (0 != (chn.control & Ctrl.EI)) {
        // interrupt enabled, request an interrupt
        chn.intr.irq();
    }
    // last channel doesn't have a ZCTO pin
    if (chn_index < 3) {
        // set ZCTO pin
        pins |= ZCTO0 << chn_index;
    }
    // reload down counter
    chn.down_counter = chn.constant;
    return pins;
}

//== TESTS =====================================================================
const expect = @import("std").testing.expect;

test "ctc intvector" {
    var ctc = CTC{ };
    var pins = setData(0, 0xE0);
    pins = ctc.ioWrite(0, pins);
    try expect(0xE0 == ctc.channels[0].intr.vector);
    try expect(0xE2 == ctc.channels[1].intr.vector);
    try expect(0xE4 == ctc.channels[2].intr.vector);
    try expect(0xE6 == ctc.channels[3].intr.vector);
}

test "ctc timer" {
    var ctc = CTC{};
    var pins: u64 = 0;
    const chn = &ctc.channels[1];
    
    // write control word
    const ctrl = Ctrl.EI|Ctrl.MODE_TIMER|Ctrl.PRESCALER_16|Ctrl.TRIGGER_AUTO|Ctrl.CONST_FOLLOWS|Ctrl.CONTROL;
    pins = setData(pins, ctrl);
    pins = ctc.ioWrite(1, pins);
    try expect(ctrl == ctc.channels[1].control);

    // write timer constant
    pins = setData(pins, 10);
    pins = ctc.ioWrite(1, pins);
    try expect(0 == (chn.control & Ctrl.CONST_FOLLOWS));
    try expect(10 == chn.constant);
    try expect(10 == chn.down_counter);
    var r: usize = 0;
    while (r < 3): (r += 1) {
        var i: usize = 0;
        while (i < 160): (i += 1) {
            pins = ctc.tick(pins);
            if (i != 159) {
                try expect(0 == (pins & ZCTO1));
            }
        }
        try expect(0 != (pins & ZCTO1));
        try expect(10 == chn.down_counter);
    }
}

test "ctc timer wait trigger" {
    var ctc = CTC{};
    var pins: u64 = 0;
    const chn = &ctc.channels[1];

    // enable interrupt, mode timer, prescaler 16, trigger-wait, trigger-rising-edge, const follows
    const ctrl = Ctrl.EI|Ctrl.MODE_TIMER|Ctrl.PRESCALER_16|Ctrl.TRIGGER_WAIT|Ctrl.EDGE_RISING|Ctrl.CONST_FOLLOWS|Ctrl.CONTROL;
    pins = setData(pins, ctrl);
    pins = ctc.ioWrite(1, pins);
    try expect(chn.control == ctrl);
    // write timer constant 
    pins = setData(pins, 10);
    pins = ctc.ioWrite(1, pins);
    try expect(0 == (chn.control & Ctrl.CONST_FOLLOWS));
    try expect(10 == chn.constant);

    // tick the CTC without starting the timer 
    {
        var i: usize = 0;
        while (i < 300): (i += 1) {
            pins = ctc.tick(pins);
            try expect(0 == (pins & ZCTO1));
        }
    }
    // now start the timer on next tick
    pins |= CLKTRG1;
    pins = ctc.tick(pins);
    var r: usize = 0;
    while (r < 3): (r += 1) {
        var i: usize = 0;
        while (i < 160): (i += 1) {
            pins = ctc.tick(pins);
            if (i != 159) {
                try expect(0 == (pins & ZCTO1));
            }
            else {
                try expect(0 != (pins & ZCTO1));
                try expect(10 == chn.down_counter);
            }
        }
    }
}

test "ctc counter" {
    var ctc = CTC{};
    var pins: u64 = 0;
    const chn = &ctc.channels[1];

    // enable interrupt, mode counter, trigger-rising-edge, const follows
    const ctrl = Ctrl.EI|Ctrl.MODE_COUNTER|Ctrl.EDGE_RISING|Ctrl.CONST_FOLLOWS|Ctrl.CONTROL;
    pins = setData(pins, ctrl);
    pins = ctc.ioWrite(1, pins);
    try expect(ctc.channels[1].control == ctrl);
    // write counter constant
    pins = setData(pins, 10);
    pins = ctc.ioWrite(1, pins);
    try expect(0 == (chn.control & Ctrl.CONST_FOLLOWS));
    try expect(10 == chn.constant);

    // trigger the CLKTRG1 pin
    var r: usize = 0;
    while (r < 3): (r += 1) {
        var i: usize = 0;
        while (i < 10): (i += 1) {
            pins |= CLKTRG1;
            pins = ctc.tick(pins);
            if (i != 9) {
                try expect(0 == (pins & ZCTO1));
            }
            else {
                try expect(0 != (pins & ZCTO1));
                try expect(10 == chn.down_counter);
            }
            pins &= ~CLKTRG1;
            pins = ctc.tick(pins);
        }
    }
}
