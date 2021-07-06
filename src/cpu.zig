const pins = @import("pins.zig").Pins;

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
const NumRegs = 8;

pub const CPU = struct {

    regs: [8]u8 = [_]u8{0xFF} ** 8,

    wz: u16 = 0xFFFF,
    ix: u16 = 0xFFFF,
    iy: u16 = 0xFFFF,
    sp: u16 = 0xFFFF,
    pc: u16 = 0x0000,
    ir: u16 = 0x0000,

    im: u8 = 0,

    iff1: bool = false,
    iff2: bool = false,

    pub const TickFunc = fn(num_ticks: usize, pins: u64) u64;

    /// set CPU into reset state
    pub fn reset(self: *CPU) void {
        self = .{};
    }
    
    /// execute instructions for at least 'num_ticks', return number of executed ticks
    pub fn exec(self: *CPU, num_ticks: usize, tick_func: TickFunc) usize {

    }

};

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
fn add8(r: *[NumRegs]u8, val: u8) void {
    const acc: usize = r[A];
    const res: usize = acc + val;
    r[F] = addFlags(acc, val, res);
    r[A] = @truncate(u8, res);
}

fn adc8(r: *[NumRegs]u8, val: u8) void {
    const acc: usize = r[A];
    const res: usize = acc + val + (r[F] & CF);
    r[F] = addFlags(acc, val, res);
    r[A] = @truncate(u8, res);
}

fn sub8(r: *[NumRegs]u8, val: u8) void {
    const acc: usize = r[A];
    const res: usize = acc -% val; 
    r[F] = subFlags(acc, val, res);
    r[A] = @truncate(u8, res);
}
    
fn sbc8(r: *[NumRegs]u8, val: u8) void {
    const acc: usize = r[A];
    const res: usize = acc -% val -% (r[F] & CF);
    r[F] = subFlags(acc, val, res);
    r[A] = @truncate(u8, res);
}
    
fn and8(r: *[NumRegs]u8, val: u8) void {
    r[A] &= val;
    r[F] = szpFlags(r[A]) | HF;
}
    
fn xor8(r: *[NumRegs]u8, val: u8) void {
    r[A] ^= val;
    r[F] = szpFlags(r[A]);
}

fn or8(r: *[NumRegs]u8, val: u8) void {
    r[A] |= val;
    r[F] = szpFlags(r[A]);
}

fn cp8(r: *[NumRegs]u8, val: u8) void {
    const acc: usize = r[A];
    const res: usize = acc -% val;
    r[F] = cpFlags(acc, val, res);
}
    
fn alu8(r: *[NumRegs]u8, y: u3, val: u8) void {
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

fn neg8(r: *[NumRegs]u8) void {
    const val = r[A];
    r[A] = 0;
    sub8(r, val);
}

fn inc8(r: *[NumRegs]u8, reg: u3) void {
    const val: u8 = r[reg];
    const res: u8 = val +% 1;
    var f: u8 = szFlags(res) | (res & (XF|YF)) | ((res ^ val) & HF);
    if (res == 0x80) { f |= VF; }
    r[F] = f | (r[F] & CF);
    r[reg] = res;
}

fn dec8(r: *[NumRegs]u8, reg: u3) void {
    const val: u8 = r[reg];
    const res: u8 = val -% 1;
    var f: u8 = NF | szFlags(res) | (res & (XF|YF)) | ((res ^ val) & HF);
    if (res == 0x7F) { f |= VF; }
    r[F] = f | (r[F] & CF);
    r[reg] = res;
}

//=== TESTS ====================================================================
const expect = @import("std").testing.expect;

fn makeRegs() [NumRegs]u8 {
    var res: [NumRegs]u8 = [_]u8{0xFF} ** NumRegs;
    res[F] = 0;
    return res;
}

fn flags(f: u8, mask: u8) bool {
    return (f & ~(XF|YF)) == mask;
}

fn testRF(r: *const [NumRegs]u8, reg: u3, val: u8, mask: u8) bool {
    return (r[reg] == val) and ((r[F] & ~(XF|YF)) == mask);
}

fn testAF(r: *const [NumRegs]u8, val: u8, mask: u8) bool {
    return testRF(r, A, val, mask);
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
