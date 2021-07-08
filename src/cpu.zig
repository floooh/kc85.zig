// address bus pins
pub const A0:  u64 = 1<<0;
pub const A1:  u64 = 1<<1;
pub const A2:  u64 = 1<<2;
pub const A3:  u64 = 1<<3;
pub const A4:  u64 = 1<<4;
pub const A5:  u64 = 1<<5;
pub const A6:  u64 = 1<<6;
pub const A7:  u64 = 1<<7;
pub const A8:  u64 = 1<<8;
pub const A9:  u64 = 1<<9;
pub const A10: u64 = 1<<10;
pub const A11: u64 = 1<<11;
pub const A12: u64 = 1<<12;
pub const A13: u64 = 1<<13;
pub const A14: u64 = 1<<14;
pub const A15: u64 = 1<<15;
pub const AddrPinMask: u64 = 0xFFFF;

// data bus pins
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

// system control pins
pub const M1:   u64 = 1<<24;     // machine cycle 1
pub const MREQ: u64 = 1<<25;     // memory request
pub const IORQ: u64 = 1<<26;     // IO request
pub const RD:   u64 = 1<<27;     // read request
pub const WR:   u64 = 1<<28;     // write requst
pub const RFSH: u64 = 1<<29;     // memory refresh (not implemented)
pub const CtrlPinMask = M1|MREQ|IORQ|RD|WR|RFSH;

// CPU control pins
pub const HALT:  u64 = 1<<30;    // halt and catch fire
pub const INT:   u64 = 1<<31;    // maskable interrupt requested
pub const NMI:   u64 = 1<<32;    // non-maskable interrupt requested
pub const RESET: u64 = 1<<33;    // reset requested

// virtual pins
pub const WAIT0: u64 = 1<<34;    // 3 virtual pins to inject up to 8 wait cycles
pub const WAIT1: u64 = 1<<35;
pub const WAIT2: u64 = 1<<36;
pub const IEIO:  u64 = 1<<37;    // interrupt daisy chain: interrupt-enable-I/O
pub const RETI:  u64 = 1<<38;    // interrupt daisy chain: RETI decoded
pub const WaitPinShift = 34;
pub const WaitPinMask = WAIT0|WAIT1|WAIT2;

// status flag bits
const CF: u8 = (1<<0);
const NF: u8 = (1<<1);
const VF: u8 = (1<<2);
const PF: u8 = VF;
const XF: u8 = (1<<3);
const HF: u8 = (1<<4);
const YF: u8 = (1<<5);
const ZF: u8 = (1<<6);
const SF: u8 = (1<<7);

// register bank indices
const B = 0;
const C = 1;
const D = 2;
const E = 3;
const H = 4;
const L = 5;
const F = 6;
const A = 7;
const IXH = 8;
const IXL = 9;
const IYH = 10;
const IYL = 11;
const NumRegs = 12;

const Regs = [NumRegs]u8;

pub const TickFunc = fn(usize, u64) u64;

pub const State = struct {

    regs: Regs = [_]u8{0xFF} ** NumRegs,

    WZ: u16 = 0xFFFF,
    SP: u16 = 0xFFFF,
    PC: u16 = 0x0000,
    I:  u8 = 0x00,
    R:  u8 = 0x00,
    IM: u8 = 0x00,

    iff1: bool = false,
    iff2: bool = false,
};

const PinsAndTicks = struct {
    pins: u64,
    ticks: u64,
};

// set wait ticks on pin mask
pub fn setWait(pins: u64, wait_ticks: u3) u64 {
    return (pins & ~WaitPinMask) | @as(u64, wait_ticks) << WaitPinShift;
}

// extract wait ticks from pin mask
pub fn getWait(pins: u64) u3 {
    return @truncate(u3, pins >> WaitPinShift);
}

// set address pins in pin mask
pub fn setAddr(pins: u64, addr: u16) u64 {
    return (pins & ~AddrPinMask) | addr;
}

// get address from pin mask
pub fn getAddr(pins: u64) u16 {
    return @truncate(u16, pins);
}

// set data pins in pin mask
pub fn setData(pins: u64, data: u8) u64 {
    return (pins & ~DataPinMask) | (@as(u64, data) << DataPinShift);
}

// get data pins in pin mask
pub fn getData(pins: u64) u8 {
    return @truncate(u8, pins >> DataPinShift);
}

// set address and data pins in pin mask
pub fn setAddrData(pins: u64, addr: u16, data: u8) u64 {
    return (pins & ~(DataPinMask|AddrPinMask)) | (@as(u64, data) << DataPinShift) | addr;
}

// invoke tick callback with control pins set
fn tick(pt: PinsAndTicks, num_ticks: usize, pin_mask: u64, tick_func: TickFunc) PinsAndTicks {
    return .{
        .pins = tick_func(num_ticks, (pt.pins & ~CtrlPinMask) | pin_mask),
        .ticks = pt.ticks + num_ticks
    };
}

// invoke tick callback with pin mask and wait state detection
fn tickWait(pt: PinsAndTicks, num_ticks: usize, pin_mask: u64, tick_func: TickFunc) PinsAndTicks {
    return .{
        .pins = tick_func(num_ticks, (pt.pins & ~(CtrlPinMask|WaitPinMask) | pin_mask)),
        .ticks = pt.ticks + num_ticks + getWait(pt.pins)
    };
}

// perform a memory-read machine cycle (3 clock cycles)
fn memRead(pt: PinsAndTicks, addr: u16, tick_func: TickFunc) PinsAndTicks {
    return tickWait(.{ .pins = setAddr(pt.pins, addr), .ticks = pt.ticks }, 3, MREQ|RD, tick_func);
}

// perform a memory-write machine cycle (3 clock cycles)
fn memWrite(pt: PinsAndTicks, addr: u16, data: u8, tick_func: TickFunc) PinsAndTicks {
    return tickWait(.{ .pins = setAddrData(pt.pins, addr, data), .ticks = pt.ticks }, 3, MREQ|WR, tick_func);
}

// perform an IO input machine cycle (4 clock cycles)
fn ioIn(pt: PinsAndTicks, addr: u16, tick_func: TickFunc) PinsAndTicks {
    return tickWait(.{ .pins = setAddr(pt.pins, addr), .ticks = pt.ticks }, 4, IORQ|RD, tick_func);
}

// perform a IO output machine cycle (4 clock cycles)
fn ioOut(pt: PinsAndTicks, addr: u16, data: u8, tick_func: TickFunc) PinsAndTicks {
    return tickWait(.{ .pins = setAddrData(pt.pins, addr, data), .ticks = pt.ticks }, 4, IORQ|WR, tick_func);
}

// helper function to increment R register
fn bumpR(r: u8) u8 {
    return (r & 0x80) | ((r +% 1) & 0x7F);
}

// perform an instruction fetch machine cycle (without bumping PC and R, and without refresh cycle)
fn fetch(pt: PinsAndTicks, pc: u16, tick_func: TickFunc) PinsAndTicks {
    return tickWait(.{ .pins = setAddr(pt.pins, pc), .ticks = pt.ticks }, 4, M1|MREQ|RD, tick_func);
}

// flag computation functions
fn szFlags(val: usize) u8 {
    if ((val & 0xFF) == 0) {
        return ZF;
    }
    else {
        return @truncate(u8, val & SF);
    }
}

fn szyxchFlags(acc: usize, val: u8, res: usize) u8 {
    return szFlags(res) | @truncate(u8, (res & (YF|XF)) | ((res >> 8) & CF) | ((acc^val^res) & HF));
}

fn addFlags(acc: usize, val: u8, res: usize) u8 {
    return szyxchFlags(acc, val, res) | @truncate(u8, (((val^acc^0x80) & (val^res))>>5) & VF);
}

fn subFlags(acc: usize, val: u8, res: usize) u8 {
    return NF | szyxchFlags(acc, val, res) | @truncate(u8, (((val^acc) & (res^acc))>>5) & VF);
}

fn cpFlags(acc: usize, val: u8, res: usize) u8 {
    return NF | szFlags(res) | @truncate(u8, (val & (YF|XF)) | ((res >> 8) & CF) | ((acc^val^res) & HF) | ((((val^acc) & (res^acc))>>5) & VF));
}

fn szpFlags(val: u8) u8 {
    return szFlags(val) | (((@popCount(u8, val)<<2) & PF) ^ PF);
}

// ALU functions
fn add8(r: *Regs, val: u8) void {
    const acc: usize = r[A];
    const res: usize = acc + val;
    r[F] = addFlags(acc, val, res);
    r[A] = @truncate(u8, res);
}

fn adc8(r: *Regs, val: u8) void {
    const acc: usize = r[A];
    const res: usize = acc + val + (r[F] & CF);
    r[F] = addFlags(acc, val, res);
    r[A] = @truncate(u8, res);
}

fn sub8(r: *Regs, val: u8) void {
    const acc: usize = r[A];
    const res: usize = acc -% val; 
    r[F] = subFlags(acc, val, res);
    r[A] = @truncate(u8, res);
}
    
fn sbc8(r: *Regs, val: u8) void {
    const acc: usize = r[A];
    const res: usize = acc -% val -% (r[F] & CF);
    r[F] = subFlags(acc, val, res);
    r[A] = @truncate(u8, res);
}
    
fn and8(r: *Regs, val: u8) void {
    r[A] &= val;
    r[F] = szpFlags(r[A]) | HF;
}
    
fn xor8(r: *Regs, val: u8) void {
    r[A] ^= val;
    r[F] = szpFlags(r[A]);
}

fn or8(r: *Regs, val: u8) void {
    r[A] |= val;
    r[F] = szpFlags(r[A]);
}

fn cp8(r: *Regs, val: u8) void {
    const acc: usize = r[A];
    const res: usize = acc -% val;
    r[F] = cpFlags(acc, val, res);
}
    
fn alu8(r: *Regs, y: u3, val: u8) void {
    switch(y) {
        0 => add8(r, val),
        1 => adc8(r, val),
        2 => sub8(r, val),
        3 => sbc8(r, val),
        4 => and8(r, val),
        5 => xor8(r, val),
        6 => or8(r, val),
        7 => cp8(r, val),
    }
}

fn neg8(r: *Regs) void {
    const val = r[A];
    r[A] = 0;
    sub8(r, val);
}

fn inc8(r: *Regs, reg: u3) void {
    const val: u8 = r[reg];
    const res: u8 = val +% 1;
    var f: u8 = szFlags(res) | (res & (XF|YF)) | ((res ^ val) & HF);
    // set VF if bit 7 flipped from 0 to 1
    f |= ((val ^ res) & (res & 0x80) >> 5) & VF;
    r[F] = f | (r[F] & CF);
    r[reg] = res;
}

fn dec8(r: *Regs, reg: u3) void {
    const val: u8 = r[reg];
    const res: u8 = val -% 1;
    var f: u8 = NF | szFlags(res) | (res & (XF|YF)) | ((res ^ val) & HF);
    // set VF if but 7 flipped from 1 to 0
    f |= ((val ^ res) & (val & 0x80) >> 5) & VF;
    r[F] = f | (r[F] & CF);
    r[reg] = res;
}

//=== TESTS ====================================================================
const expect = @import("std").testing.expect;

fn makeRegs() Regs {
    var res: Regs = [_]u8{0xFF} ** NumRegs;
    res[F] = 0;
    return res;
}

fn flags(f: u8, mask: u8) bool {
    return (f & ~(XF|YF)) == mask;
}

fn testRF(r: *const Regs, reg: u3, val: u8, mask: u8) bool {
    return (r[reg] == val) and ((r[F] & ~(XF|YF)) == mask);
}

fn testAF(r: *const Regs, val: u8, mask: u8) bool {
    return testRF(r, A, val, mask);
}

test "set/get data" {
    var pins: u64 = 0;
    pins = setData(pins, 0xFF);
    try expect(getData(pins) == 0xFF);
    pins = setData(pins, 1);
    try expect(getData(pins) == 1);
}

test "set/get address" {
    var pins: u64 = 0;
    pins = setAddr(pins, 0x1234);
    try expect(getAddr(pins) == 0x1234);
    pins = setAddr(pins, 0x4321);
    try expect(getAddr(pins) == 0x4321);
}

test "setAddrData" {
    var pins: u64 = 0;
    pins = setAddrData(pins, 0x1234, 0x54);
    try expect(pins == 0x541234);
    try expect(getAddr(pins) == 0x1234);
    try expect(getData(pins) == 0x54);
}

test "set/get wait ticks" {
    var pins: u64 = 0x221111;
    pins = setWait(pins, 7);
    try expect(getWait(pins) == 7);
    pins = setWait(pins, 1);
    try expect(getWait(pins) == 1);
    try expect(getAddr(pins) == 0x1111);
    try expect(getData(pins) == 0x22);
}

test "tick" {
    const inner = struct {
        fn tick_func(ticks: usize, pins: u64) u64 {
            if (ticks == 3 and getData(pins) == 0x54 and getAddr(pins) == 0x1234 and (pins & M1|MREQ|RD) == M1|MREQ|RD) {
                // success
                return setData(pins, 0x23);
            }
            else {
                return 0;
            }
        }
    };
    var pt = PinsAndTicks{ .pins = setAddrData(0, 0x1234, 0x54), .ticks = 0 };
    pt = tick(pt, 3, M1|MREQ|RD, inner.tick_func);
    try expect(getData(pt.pins) == 0x23);
    try expect(pt.ticks == 3);
}

test "tickWait" {
    const inner = struct {
        fn tick_func(ticks: usize, pins: u64) u64 {
            return setWait(pins, 5);
        }
    };
    // make sure that any stuck wait ticks are deleted
    var pt = PinsAndTicks{ .pins = setWait(0, 7), .ticks = 0 };
    pt = tickWait(pt, 3, M1|MREQ|RD, inner.tick_func);
    try expect(getWait(pt.pins) == 5);
    try expect(pt.ticks == 8);
}

test "memRead" {
    const inner = struct {
        fn tick_func(ticks: usize, pins: u64) u64 {
            if ((pins & MREQ|RD) == MREQ|RD and getAddr(pins) == 0x1234) {
                // success
                return setData(pins, 0x23);
            }
            else {
                return pins;
            }
        }
    };
    var pt = PinsAndTicks{ .pins = 0, .ticks = 0 };
    pt = memRead(pt, 0x1234, inner.tick_func);
    try expect(getData(pt.pins) == 0x23);
    try expect(pt.ticks == 3);
}

test "memWrite" {
    const inner = struct {
        fn tick_func(ticks: usize, pins: u64) u64 {
            if ((pins & MREQ|WR) == MREQ|WR and getAddr(pins) == 0x1234 and getData(pins) == 0x56) {
                // success
                return setData(pins, 0x23);
            }
            else {
                return pins;
            }
        }
    };
    var pt = PinsAndTicks{ .pins = 0, .ticks = 0 };
    pt = memWrite(pt, 0x1234, 0x56, inner.tick_func);
    try expect(getData(pt.pins) == 0x23);
    try expect(pt.ticks == 3);
}

test "ioIn" {
    const inner = struct {
        fn tick_func(ticks: usize, pins: u64) u64 {
            if ((pins & IORQ|RD) == IORQ|RD and getAddr(pins) == 0x1234) {
                // success
                return setData(pins, 0x23);       
            }
            else {
                return pins;
            }
        }
    };
    var pt = PinsAndTicks{ .pins = 0, .ticks = 0 };
    pt = ioIn(pt, 0x1234, inner.tick_func);
    try expect(getData(pt.pins) == 0x23);
    try expect(pt.ticks == 4);
}

test "ioOut" {
    const inner = struct {
        fn tick_func(ticks: usize, pins: u64) u64 {
            if ((pins & IORQ|WR) == IORQ|WR and getAddr(pins) == 0x1234 and getData(pins) == 0x56) {
                // success
                return setData(pins, 0x23);
            }
            else {
                return pins;
            }
        }
    };
    var pt = PinsAndTicks{ .pins = 0, .ticks = 0 };
    pt = ioOut(pt, 0x1234, 0x56, inner.tick_func);
    try expect(getData(pt.pins) == 0x23);
    try expect(pt.ticks == 4);
}

test "bumpR" {
    // only 7 bits are incremented, and the topmost bit is sticky
    try expect(bumpR(0x00) == 1);
    try expect(bumpR(0x7F) == 0);
    try expect(bumpR(0x80) == 0x81);
    try expect(bumpR(0xFF) == 0x80);
}

test "fetch" {
    const inner = struct {
        fn tick_func(ticks:usize, pins: u64) u64 {
            if ((pins & M1|MREQ|RD) == M1|MREQ|RD and getAddr(pins) == 0x1234) {
                // success
                return setData(pins, 0x23);
            }
            else {
                return pins;
            }
        }
    };
    var pt = PinsAndTicks{ .pins = 0, .ticks = 0 };
    pt = fetch(pt, 0x1234, inner.tick_func);
    try expect(getData(pt.pins) == 0x23);
    try expect(pt.ticks == 4);
}

test "add8" {
    var r = makeRegs();
    r[A] = 0xF;
    add8(&r, r[A]); try expect(testAF(&r, 0x1E, HF));
    add8(&r, 0xE0); try expect(testAF(&r, 0xFE, SF));
    r[A] = 0x81; 
    add8(&r, 0x80); try expect(testAF(&r, 0x01, VF|CF));
    add8(&r, 0xFF); try expect(testAF(&r, 0x00, ZF|HF|CF));
    add8(&r, 0x40); try expect(testAF(&r, 0x40, 0));
    add8(&r, 0x80); try expect(testAF(&r, 0xC0, SF));
    add8(&r, 0x33); try expect(testAF(&r, 0xF3, SF));
    add8(&r, 0x44); try expect(testAF(&r, 0x37, CF));
}

test "adc8" {
    var r = makeRegs();
    r[A] = 0;
    adc8(&r, 0x00); try expect(testAF(&r, 0x00, ZF));
    adc8(&r, 0x41); try expect(testAF(&r, 0x41, 0));
    adc8(&r, 0x61); try expect(testAF(&r, 0xA2, SF|VF));
    adc8(&r, 0x81); try expect(testAF(&r, 0x23, VF|CF));
    adc8(&r, 0x41); try expect(testAF(&r, 0x65, 0));
    adc8(&r, 0x61); try expect(testAF(&r, 0xC6, SF|VF));
    adc8(&r, 0x81); try expect(testAF(&r, 0x47, VF|CF));
    adc8(&r, 0x01); try expect(testAF(&r, 0x49, 0));
}

test "sub8" {
    var r = makeRegs();
    r[A] = 0x04;
    sub8(&r, 0x04); try expect(testAF(&r, 0x00, ZF|NF));
    sub8(&r, 0x01); try expect(testAF(&r, 0xFF, SF|HF|NF|CF));
    sub8(&r, 0xF8); try expect(testAF(&r, 0x07, NF));
    sub8(&r, 0x0F); try expect(testAF(&r, 0xF8, SF|HF|NF|CF));
    sub8(&r, 0x79); try expect(testAF(&r, 0x7F, HF|VF|NF));
    sub8(&r, 0xC0); try expect(testAF(&r, 0xBF, SF|VF|NF|CF));
    sub8(&r, 0xBF); try expect(testAF(&r, 0x00, ZF|NF));
    sub8(&r, 0x01); try expect(testAF(&r, 0xFF, SF|HF|NF|CF));
    sub8(&r, 0xFE); try expect(testAF(&r, 0x01, NF));
}

test "sbc8" {
    var r = makeRegs();
    r[A] = 0x04;
    sbc8(&r, 0x04); try expect(testAF(&r, 0x00, ZF|NF));
    sbc8(&r, 0x01); try expect(testAF(&r, 0xFF, SF|HF|NF|CF));
    sbc8(&r, 0xF8); try expect(testAF(&r, 0x06, NF));
    sbc8(&r, 0x0F); try expect(testAF(&r, 0xF7, SF|HF|NF|CF));
    sbc8(&r, 0x79); try expect(testAF(&r, 0x7D, HF|VF|NF));
    sbc8(&r, 0xC0); try expect(testAF(&r, 0xBD, SF|VF|NF|CF));
    sbc8(&r, 0xBF); try expect(testAF(&r, 0xFD, SF|HF|NF|CF));
    sbc8(&r, 0x01); try expect(testAF(&r, 0xFB, SF|NF));
    sbc8(&r, 0xFE); try expect(testAF(&r, 0xFD, SF|HF|NF|CF));
}

test "cp8" {
    var r = makeRegs();
    r[A] = 0x04;
    cp8(&r, 0x04); try expect(testAF(&r, 0x04, ZF|NF));
    cp8(&r, 0x05); try expect(testAF(&r, 0x04, SF|HF|NF|CF));
    cp8(&r, 0x03); try expect(testAF(&r, 0x04, NF));
    cp8(&r, 0xFF); try expect(testAF(&r, 0x04, HF|NF|CF));
    cp8(&r, 0xAA); try expect(testAF(&r, 0x04, HF|NF|CF));
    cp8(&r, 0x80); try expect(testAF(&r, 0x04, SF|VF|NF|CF));
    cp8(&r, 0x7F); try expect(testAF(&r, 0x04, SF|HF|NF|CF));
    cp8(&r, 0x04); try expect(testAF(&r, 0x04, ZF|NF));
}

test "and8" {
    var r = makeRegs();
    r[A] = 0xFF;
    and8(&r, 0x01); try expect(testAF(&r, 0x01, HF));       r[A] = 0xFF;
    and8(&r, 0x03); try expect(testAF(&r, 0x03, HF|PF));    r[A] = 0xFF;
    and8(&r, 0x04); try expect(testAF(&r, 0x04, HF));       r[A] = 0xFF;
    and8(&r, 0x08); try expect(testAF(&r, 0x08, HF));       r[A] = 0xFF;
    and8(&r, 0x10); try expect(testAF(&r, 0x10, HF));       r[A] = 0xFF;
    and8(&r, 0x20); try expect(testAF(&r, 0x20, HF));       r[A] = 0xFF;
    and8(&r, 0x40); try expect(testAF(&r, 0x40, HF));       r[A] = 0xFF;
    and8(&r, 0xAA); try expect(testAF(&r, 0xAA, SF|HF|PF));
}

test "xor8" {
    var r = makeRegs();
    r[A] = 0x00;
    xor8(&r, 0x00); try expect(testAF(&r, 0x00, ZF|PF));
    xor8(&r, 0x01); try expect(testAF(&r, 0x01, 0));
    xor8(&r, 0x03); try expect(testAF(&r, 0x02, 0));
    xor8(&r, 0x07); try expect(testAF(&r, 0x05, PF));
    xor8(&r, 0x0F); try expect(testAF(&r, 0x0A, PF));
    xor8(&r, 0x1F); try expect(testAF(&r, 0x15, 0));
    xor8(&r, 0x3F); try expect(testAF(&r, 0x2A, 0));
    xor8(&r, 0x7F); try expect(testAF(&r, 0x55, PF));
    xor8(&r, 0xFF); try expect(testAF(&r, 0xAA, SF|PF));
}

test "or8" {
    var r = makeRegs();
    r[A] = 0x00;
    or8(&r, 0x00); try expect(testAF(&r, 0x00, ZF|PF));
    or8(&r, 0x01); try expect(testAF(&r, 0x01, 0));
    or8(&r, 0x02); try expect(testAF(&r, 0x03, PF));
    or8(&r, 0x04); try expect(testAF(&r, 0x07, 0));
    or8(&r, 0x08); try expect(testAF(&r, 0x0F, PF));
    or8(&r, 0x10); try expect(testAF(&r, 0x1F, 0));
    or8(&r, 0x20); try expect(testAF(&r, 0x3F, PF));
    or8(&r, 0x40); try expect(testAF(&r, 0x7F, 0));
    or8(&r, 0x80); try expect(testAF(&r, 0xFF, SF|PF));
}

test "neg8" {
    var r = makeRegs();
    r[A]=0x01; neg8(&r); try expect(testAF(&r, 0xFF, SF|HF|NF|CF));
    r[A]=0x00; neg8(&r); try expect(testAF(&r, 0x00, ZF|NF));
    r[A]=0x80; neg8(&r); try expect(testAF(&r, 0x80, SF|PF|NF|CF));
    r[A]=0xC0; neg8(&r); try expect(testAF(&r, 0x40, NF|CF));
}

test "inc8 dec8" {
    var r = makeRegs();
    r[A] = 0x00;
    r[B] = 0xFF;
    r[C] = 0x0F;
    r[D] = 0x0E;
    r[E] = 0x7F;
    r[H] = 0x3E;
    r[L] = 0x23;
    inc8(&r, A); try expect(testRF(&r, A, 0x01, 0));
    dec8(&r, A); try expect(testRF(&r, A, 0x00, ZF|NF));
    inc8(&r, B); try expect(testRF(&r, B, 0x00, ZF|HF));
    dec8(&r, B); try expect(testRF(&r, B, 0xFF, SF|HF|NF));
    inc8(&r, C); try expect(testRF(&r, C, 0x10, HF));
    dec8(&r, C); try expect(testRF(&r, C, 0x0F, HF|NF));
    inc8(&r, D); try expect(testRF(&r, D, 0x0F, 0));
    dec8(&r, D); try expect(testRF(&r, D, 0x0E, NF));
    r[F] |= CF;
    inc8(&r, E); try expect(testRF(&r, E, 0x80, SF|HF|VF|CF)); 
    dec8(&r, E); try expect(testRF(&r, E, 0x7F, HF|VF|NF|CF));
    inc8(&r, H); try expect(testRF(&r, H, 0x3F, CF));
    dec8(&r, H); try expect(testRF(&r, H, 0x3E, NF|CF));
    inc8(&r, L); try expect(testRF(&r, L, 0x24, CF));
    dec8(&r, L); try expect(testRF(&r, L, 0x23, NF|CF));
}
