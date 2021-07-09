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
pub const CF: u8 = (1<<0);
pub const NF: u8 = (1<<1);
pub const VF: u8 = (1<<2);
pub const PF: u8 = VF;
pub const XF: u8 = (1<<3);
pub const HF: u8 = (1<<4);
pub const YF: u8 = (1<<5);
pub const ZF: u8 = (1<<6);
pub const SF: u8 = (1<<7);

// 8-bit register indices
pub const B = 0;
pub const C = 1;
pub const D = 2;
pub const E = 3;
pub const H = 4;
pub const L = 5;
pub const F = 6;
pub const A = 7;
pub const NumRegs = 8;

// 16-bit register indices
pub const BC = 0;
pub const DE = 1;
pub const HL = 2;
pub const FA = 3;

const Regs = [NumRegs]u8;

pub const TickFunc = fn(usize, u64) u64;

pub const State = struct {

    pins: u64 = 0,
    ticks: usize = 0,

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

// run the emulation for at least 'num_ticks', return number of executed ticks
pub fn exec(cpu: *State, num_ticks: usize, tick_func: TickFunc) usize {
    cpu.ticks = 0;
    var running = true;
    while (running): (running = cpu.ticks < num_ticks) {

        // fetch next opcode byte
        fetch(cpu, tick_func);
        const op = getData(cpu.pins);

        // FIXME: special case ED
        // FIXME: HL <=> IX/IY mapping

        // decode opcode (see http://www.z80.info/decoding.htm)
        // |xx|yyy|zzz|
        const x = @truncate(u2, (op >> 6) & 3);
        const y = @truncate(u3, (op >> 3) & 7);
        const z = @truncate(u3, op & 7);

        switch (x) {
            0 => switch (z) {
                6 => ld_r_n(cpu, y, tick_func),
                else => unreachable // FIXME!
            },
            // LD quadrant
            1 => {
                if (y == 6 and z == 6) { halt(cpu); }
                else { ld_r_r(cpu, y, z, tick_func); }
            },
            // ALU quadrant
            2 => {
                alu_r(cpu, y, z, tick_func);
            },
            3 => switch (z) {
                6 => alu_n(cpu, y, tick_func),
                else => unreachable // FIXME!
            }
        }
    }
    return cpu.ticks;
}

// set 16 bit register
fn setR16(r: *Regs, reg: u2, val: u16) void {
    r[@as(u3,reg)*2 + 0] = @truncate(u8, val >> 8);
    r[@as(u3,reg)*2 + 1] = @truncate(u8, val);
}

// get 16 bit register
fn getR16(r: *Regs, reg: u2) u16 {
    const h = r[@as(u3,reg)*2 + 0];
    const l = r[@as(u3,reg)*2 + 1];
    return @as(u16,h)<<8 | l;
}

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

// helper function to increment R register
fn bumpR(r: u8) u8 {
    return (r & 0x80) | ((r +% 1) & 0x7F);
}

// invoke tick callback with control pins set
fn tick(cpu: *State, num_ticks: usize, pin_mask: u64, tick_func: TickFunc) void {
    cpu.pins = tick_func(num_ticks, (cpu.pins & ~CtrlPinMask) | pin_mask);
    cpu.ticks += num_ticks;
}

// invoke tick callback with pin mask and wait state detection
fn tickWait(cpu: *State, num_ticks: usize, pin_mask: u64, tick_func: TickFunc) void {
    cpu.pins = tick_func(num_ticks, (cpu.pins & ~(CtrlPinMask|WaitPinMask) | pin_mask));
    cpu.ticks += num_ticks + getWait(cpu.pins);
}

// perform a memory-read machine cycle (3 clock cycles)
fn memRead(cpu: *State, tick_func: TickFunc) void {
    tickWait(cpu, 3, MREQ|RD, tick_func);
}

// perform a memory-write machine cycle (3 clock cycles)
fn memWrite(cpu: *State, tick_func: TickFunc) void {
    tickWait(cpu, 3, MREQ|WR, tick_func);
}

// perform an IO input machine cycle (4 clock cycles)
fn ioIn(cpu: *State, tick_func: TickFunc) void {
    tickWait(cpu, 4, IORQ|RD, tick_func);
}

// perform a IO output machine cycle (4 clock cycles)
fn ioOut(cpu: *State, tick_func: TickFunc) void {
    tickWait(cpu, 4, IORQ|WR, tick_func);
}

// generate effective address for (HL), (IX+d), (IY+d), result in address bus pins
fn addrM(cpu: *State, extra_ticks: usize, tick_func: TickFunc) void {
    var addr = getR16(&cpu.regs, HL);
    // FIXME handle IX+d, IY+d
    cpu.pins = setAddr(cpu.pins, addr);
}

// perform a read machine cycle at (HL/IX+d/IY+d), result in data bus pins
fn readM(cpu: *State, tick_func: TickFunc) void {
    addrM(cpu, 5, tick_func);
    memRead(cpu, tick_func);
}

// perform a write machine cycle at (HL/IX+d/IY+d)
fn writeM(cpu: *State, tick_func: TickFunc) void {
    addrM(cpu, 5, tick_func);
    memWrite(cpu, tick_func);
}

// perform an instruction fetch machine cycle 
fn fetch(cpu: *State, tick_func: TickFunc) void {
    cpu.pins = setAddr(cpu.pins, cpu.PC);
    tickWait(cpu, 4, M1|MREQ|RD, tick_func);
    cpu.PC +%= 1;
    cpu.R = bumpR(cpu.R);
}

// read 8-bit immediate
fn imm8(cpu: *State, tick_func: TickFunc) void {
    cpu.pins = setAddr(cpu.pins, cpu.PC);
    memRead(cpu, tick_func);
    cpu.PC +%= 1;
}

// get 8-bit register or (HL/IX+d/IY+d) value
fn src8(cpu: *State, z: u3, tick_func: TickFunc) u8 {
    return if (z != 6) cpu.regs[z] else blk:{
        readM(cpu, tick_func); 
        break :blk getData(cpu.pins);
    };
}

// HALT impl
fn halt(cpu: *State) void {
    cpu.pins |= HALT;
    cpu.PC -%= 1;
}

// LD r,r impl
fn ld_r_r(cpu: *State, y: u3, z: u3, tick_func: TickFunc) void {
    const src = src8(cpu, z, tick_func);
    if (y == 6) {
        cpu.pins = setData(cpu.pins, src);
        writeM(cpu, tick_func);
    }
    else {
        cpu.regs[y] = src;
    }
}

// LD r,n impl
fn ld_r_n(cpu: *State, y: u3, tick_func: TickFunc) void {
    imm8(cpu, tick_func);
    if (y == 6) {
        writeM(cpu, tick_func);
    }
    else {
        cpu.regs[y] = getData(cpu.pins);
    }
}

// ALU r impl
fn alu_r(cpu: *State, y: u3, z: u3, tick_func: TickFunc) void {
    const src = src8(cpu, z, tick_func);
    switch(y) {
        0 => add8(&cpu.regs, src),
        1 => adc8(&cpu.regs, src),
        2 => sub8(&cpu.regs, src),
        3 => sbc8(&cpu.regs, src),
        4 => and8(&cpu.regs, src),
        5 => xor8(&cpu.regs, src),
        6 => or8(&cpu.regs, src),
        7 => cp8(&cpu.regs, src),
    }
}

// ALU n impl
fn alu_n(cpu: *State, y: u3, tick_func: TickFunc) void {
    imm8(cpu, tick_func);
    const src = getData(cpu.pins);
    switch(y) {
        0 => add8(&cpu.regs, src),
        1 => adc8(&cpu.regs, src),
        2 => sub8(&cpu.regs, src),
        3 => sbc8(&cpu.regs, src),
        4 => and8(&cpu.regs, src),
        5 => xor8(&cpu.regs, src),
        6 => or8(&cpu.regs, src),
        7 => cp8(&cpu.regs, src),
    }
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

// FIXME: is this check needed to make sure that a regular exe won't have 
// a 64 KByte blob in the data section?
const is_test = @import("builtin").is_test;
var mem = if (is_test) [_]u8{0} ** 0x10000 else null;
var io  = if (is_test) [_]u8{0} ** 0x10000 else null;

fn clearMem() void {
    mem = [_]u8{0} ** 0x10000;
}

fn clearIO() void {
    io = [_]u8{0} ** 0x10000;
}

// a generic test tick callback
fn testTick(ticks: usize, i_pins: u64) u64 {
    var pins = i_pins;
    const addr = getAddr(pins);
    if ((pins & MREQ) != 0) {
        if ((pins & RD) != 0) {
            pins = setData(pins, mem[addr]);
        }
        else if ((pins & WR) != 0) {
            mem[addr] = getData(pins);
        }
    }
    else if ((pins & IORQ) != 0) {
        if ((pins & RD) != 0) {
            pins = setData(pins, io[addr]);
        }
        else if ((pins & WR) != 0) {
            mem[addr] = getData(pins);
        }
    }
    return pins;
}

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
            if (ticks == 3 and getData(pins) == 0x56 and getAddr(pins) == 0x1234 and (pins & M1|MREQ|RD) == M1|MREQ|RD) {
                // success
                return setData(pins, 0x23);
            }
            else {
                return 0;
            }
        }
    };
    var cpu = State{ .pins = setAddrData(0, 0x1234, 0x56) };
    tick(&cpu, 3, M1|MREQ|RD, inner.tick_func);
    try expect(getData(cpu.pins) == 0x23);
    try expect(cpu.ticks == 3);
}

test "tickWait" {
    const inner = struct {
        fn tick_func(ticks: usize, pins: u64) u64 {
            return setWait(pins, 5);
        }
    };
    var cpu = State{ .pins = setWait(0, 7) };
    tickWait(&cpu, 3, M1|MREQ|RD, inner.tick_func);
    try expect(getWait(cpu.pins) == 5);
    try expect(cpu.ticks == 8);
}

test "memRead" {
    clearMem();
    mem[0x1234] = 0x23;
    var cpu = State{ .pins = setAddr(0, 0x1234) };
    memRead(&cpu, testTick);
    try expect((cpu.pins & CtrlPinMask) == MREQ|RD);
    try expect(getData(cpu.pins) == 0x23);
    try expect(cpu.ticks == 3);
}

test "memWrite" {
    clearMem();
    var cpu = State{ .pins = setAddrData(0, 0x1234, 0x56) };
    memWrite(&cpu, testTick);
    try expect((cpu.pins & CtrlPinMask) == MREQ|WR);
    try expect(getData(cpu.pins) == 0x56);
    try expect(cpu.ticks == 3);
}

test "ioIn" {
    clearIO();
    io[0x1234] = 0x23;
    var cpu = State{ .pins = setAddr(0, 0x1234) };
    ioIn(&cpu, testTick);
    try expect((cpu.pins & CtrlPinMask) == IORQ|RD);
    try expect(getData(cpu.pins) == 0x23);
    try expect(cpu.ticks == 4);
}

test "ioOut" {
    clearIO();
    var cpu = State{ .pins = setAddrData(0, 0x1234, 0x56) };
    ioOut(&cpu, testTick);
    try expect((cpu.pins & CtrlPinMask) == IORQ|WR);
    try expect(getData(cpu.pins) == 0x56);
    try expect(cpu.ticks == 4);
}

test "bumpR" {
    // only 7 bits are incremented, and the topmost bit is sticky
    try expect(bumpR(0x00) == 1);
    try expect(bumpR(0x7F) == 0);
    try expect(bumpR(0x80) == 0x81);
    try expect(bumpR(0xFF) == 0x80);
}

test "fetch" {
    clearMem();
    mem[0x2345] = 0x42;
    var cpu = State{ .PC = 0x2345, .R = 0 };
    fetch(&cpu, testTick);
    try expect((cpu.pins & CtrlPinMask) == M1|MREQ|RD);
    try expect(getData(cpu.pins) == 0x42);
    try expect(cpu.ticks == 4);
    try expect(cpu.PC == 0x2346);
    try expect(cpu.R == 1);
}

test "readM (HL)" {
    clearMem();
    mem[0x1234] = 0x23;
    var cpu = State{};
    setR16(&cpu.regs, HL, 0x1234);
    try expect(cpu.regs[H] == 0x12);
    try expect(cpu.regs[L] == 0x34);
    readM(&cpu, testTick);
    try expect((cpu.pins & CtrlPinMask) == MREQ|RD);
    try expect(getData(cpu.pins) == 0x23);
    try expect(cpu.ticks == 3);
}

test "writeM (HL)" {
    clearMem();
    var cpu = State{ .pins = setData(0, 0x23) };
    setR16(&cpu.regs, HL, 0x1234);
    writeM(&cpu, testTick);
    try expect((cpu.pins & CtrlPinMask) == MREQ|WR);
    try expect(mem[0x1234] == 0x23);
    try expect(cpu.ticks == 3);
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
