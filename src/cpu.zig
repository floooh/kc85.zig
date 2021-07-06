const pins = @import("pins.zig").Pins;

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

// a packed 16-bit register pair
const R16 = struct {
    h: u8,          // B, D, H, F
    l: u8,          // C, E, L, A
};

pub const CPU = struct {

    bc: R16 = .{ .h = 0xFF, .l = 0xFF },
    de: R16 = .{ .h = 0xFF, .l = 0xFF },
    hl: R16 = .{ .h = 0xFF, .l = 0xFF },
    fa: R16 = .{ .h = 0xFF, .l = 0xFF },

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
fn add8(fa: R16, val: u8) R16 {
    const acc: usize = fa.l;
    const res: usize = acc + val;
    return R16{ .h = addFlags(acc, val, res), .l = @truncate(u8, res) };
}

fn adc8(fa: R16, val: u8) R16 {
    const acc: usize = fa.l;
    const res: usize = acc + val + (fa.h & CF);
    return R16{ .h = addFlags(acc, val, res), .l = @truncate(u8, res) };
}

fn sub8(fa: R16, val: u8) R16 {
    const acc: usize = fa.l;
    const res: usize = acc -% val; 
    return R16{ .h = subFlags(acc, val, res), .l = @truncate(u8, res) };
}
    
fn sbc8(fa: R16, val: u8) R16 {
    const acc: usize = fa.l;
    const res: usize = acc -% val -% (fa.h & CF);
    return R16{ .h = subFlags(acc, val, res), .l = @truncate(u8, res) };
}
    
fn and8(fa: R16, val: u8) R16 {
    const a = fa.l & val;
    return R16{ .h = szpFlags(a) | HF, .l = a };
}
    
fn xor8(fa: R16, val: u8) R16 {
    const a = fa.l ^ val;
    return R16{ .h = szpFlags(a), .l = a };
}

fn or8(fa: R16, val: u8) R16 {
    const a = fa.l | val;
    return R16{ .h = szpFlags(a), .l = a };
}

fn cp8(fa: R16, val: u8) R16 {
    const acc: usize = fa.l;
    const res: usize = acc -% val;
    return R16{ .h = cpFlags(acc, val, res), .l = fa.l };
}
    
fn alu8(fa: R16, y: u3, val: u8) R16 {
    return switch(y) {
        0 => add8(fa, val),
        1 => adc8(fa, val),
        2 => sub8(fa, val),
        3 => sbc8(fa, val),
        4 => and8(fa, val),
        5 => xor8(fa, val),
        6 => or8(fa, val),
        7 => cp8(fa, val)
    };
}

//=== TESTS ====================================================================
const expect = @import("std").testing.expect;

fn flags(f: u8, mask: u8) bool {
    return (f & ~(XF|YF)) == mask;
}

fn testAF(fa: R16, val: u8, mask: u8) bool {
    return (fa.l == val) and ((fa.h & ~(XF|YF)) == mask);
}

test "initial state" {
    var cpu = CPU{};
    try expect(cpu.fa.h == 0xFF);
    try expect(cpu.fa.l == 0xFF);
    try expect(cpu.bc.h == 0xFF);
    try expect(cpu.bc.l == 0xFF);
    try expect(cpu.de.h == 0xFF);
    try expect(cpu.de.l == 0xFF);
    try expect(cpu.hl.h == 0xFF);
    try expect(cpu.hl.l == 0xFF);

    try expect(cpu.wz == 0xFFFF);
    try expect(cpu.ix == 0xFFFF);
    try expect(cpu.iy == 0xFFFF);
    try expect(cpu.sp == 0xFFFF);
    try expect(cpu.pc == 0);
    try expect(cpu.ir == 0);
    try expect(cpu.im == 0);
    try expect(cpu.iff1 == false);
    try expect(cpu.iff2 == false);
}

test "add8" {
    var fa = R16{ .h=0, .l=0xF };
    fa = add8(fa, fa.l);    try expect(testAF(fa, 0x1E, HF));
    fa = add8(fa, 0xE0);    try expect(testAF(fa, 0xFE, SF));
    fa.l = 0x81; 
    fa = add8(fa, 0x80);    try expect(testAF(fa, 0x01, VF|CF));
    fa = add8(fa, 0xFF);    try expect(testAF(fa, 0x00, ZF|HF|CF));
    fa = add8(fa, 0x40);    try expect(testAF(fa, 0x40, 0));
    fa = add8(fa, 0x80);    try expect(testAF(fa, 0xC0, SF));
    fa = add8(fa, 0x33);    try expect(testAF(fa, 0xF3, SF));
    fa = add8(fa, 0x44);    try expect(testAF(fa, 0x37, CF));
}

test "adc8" {
    var fa = R16{ .h=0, .l=0 };
    fa = adc8(fa, 0x00);    try expect(testAF(fa, 0x00, ZF));
    fa = adc8(fa, 0x41);    try expect(testAF(fa, 0x41, 0));
    fa = adc8(fa, 0x61);    try expect(testAF(fa, 0xA2, SF|VF));
    fa = adc8(fa, 0x81);    try expect(testAF(fa, 0x23, VF|CF));
    fa = adc8(fa, 0x41);    try expect(testAF(fa, 0x65, 0));
    fa = adc8(fa, 0x61);    try expect(testAF(fa, 0xC6, SF|VF));
    fa = adc8(fa, 0x81);    try expect(testAF(fa, 0x47, VF|CF));
    fa = adc8(fa, 0x01);    try expect(testAF(fa, 0x49, 0));
}

test "sub8" {
    var fa = R16{ .h=0, .l=0x04 };
    fa = sub8(fa, 0x04);    try expect(testAF(fa, 0x00, ZF|NF));
    fa = sub8(fa, 0x01);    try expect(testAF(fa, 0xFF, SF|HF|NF|CF));
    fa = sub8(fa, 0xF8);    try expect(testAF(fa, 0x07, NF));
    fa = sub8(fa, 0x0F);    try expect(testAF(fa, 0xF8, SF|HF|NF|CF));
    fa = sub8(fa, 0x79);    try expect(testAF(fa, 0x7F, HF|VF|NF));
    fa = sub8(fa, 0xC0);    try expect(testAF(fa, 0xBF, SF|VF|NF|CF));
    fa = sub8(fa, 0xBF);    try expect(testAF(fa, 0x00, ZF|NF));
    fa = sub8(fa, 0x01);    try expect(testAF(fa, 0xFF, SF|HF|NF|CF));
    fa = sub8(fa, 0xFE);    try expect(testAF(fa, 0x01, NF));
}

test "sbc8" {
    var fa = R16{ .h=0, .l=0x04 };
    fa = sbc8(fa, 0x04);    try expect(testAF(fa, 0x00, ZF|NF));
    fa = sbc8(fa, 0x01);    try expect(testAF(fa, 0xFF, SF|HF|NF|CF));
    fa = sbc8(fa, 0xF8);    try expect(testAF(fa, 0x06, NF));
    fa = sbc8(fa, 0x0F);    try expect(testAF(fa, 0xF7, SF|HF|NF|CF));
    fa = sbc8(fa, 0x79);    try expect(testAF(fa, 0x7D, HF|VF|NF));
    fa = sbc8(fa, 0xC0);    try expect(testAF(fa, 0xBD, SF|VF|NF|CF));
    fa = sbc8(fa, 0xBF);    try expect(testAF(fa, 0xFD, SF|HF|NF|CF));
    fa = sbc8(fa, 0x01);    try expect(testAF(fa, 0xFB, SF|NF));
    fa = sbc8(fa, 0xFE);    try expect(testAF(fa, 0xFD, SF|HF|NF|CF));
}

test "cp8" {
    var fa = R16{ .h=0, .l=0x04 };
    fa = cp8(fa, 0x04);     try expect(testAF(fa, 0x04, ZF|NF));
    fa = cp8(fa, 0x05);     try expect(testAF(fa, 0x04, SF|HF|NF|CF));
    fa = cp8(fa, 0x03);     try expect(testAF(fa, 0x04, NF));
    fa = cp8(fa, 0xFF);     try expect(testAF(fa, 0x04, HF|NF|CF));
    fa = cp8(fa, 0xAA);     try expect(testAF(fa, 0x04, HF|NF|CF));
    fa = cp8(fa, 0x80);     try expect(testAF(fa, 0x04, SF|VF|NF|CF));
    fa = cp8(fa, 0x7F);     try expect(testAF(fa, 0x04, SF|HF|NF|CF));
    fa = cp8(fa, 0x04);     try expect(testAF(fa, 0x04, ZF|NF));
}

test "and8" {
    var fa = R16{ .h=0, .l=0xFF };
    fa = and8(fa, 0x01);    try expect(testAF(fa, 0x01, HF));       fa.l = 0xFF;
    fa = and8(fa, 0x03);    try expect(testAF(fa, 0x03, HF|PF));    fa.l = 0xFF;
    fa = and8(fa, 0x04);    try expect(testAF(fa, 0x04, HF));       fa.l = 0xFF;
    fa = and8(fa, 0x08);    try expect(testAF(fa, 0x08, HF));       fa.l = 0xFF;
    fa = and8(fa, 0x10);    try expect(testAF(fa, 0x10, HF));       fa.l = 0xFF;
    fa = and8(fa, 0x20);    try expect(testAF(fa, 0x20, HF));       fa.l = 0xFF;
    fa = and8(fa, 0x40);    try expect(testAF(fa, 0x40, HF));       fa.l = 0xFF;
    fa = and8(fa, 0xAA);    try expect(testAF(fa, 0xAA, SF|HF|PF));
}

test "xor8" {
    var fa = R16{ .h=0, .l=0 };
    fa = xor8(fa, 0x00);    try expect(testAF(fa, 0x00, ZF|PF));
    fa = xor8(fa, 0x01);    try expect(testAF(fa, 0x01, 0));
    fa = xor8(fa, 0x03);    try expect(testAF(fa, 0x02, 0));
    fa = xor8(fa, 0x07);    try expect(testAF(fa, 0x05, PF));
    fa = xor8(fa, 0x0F);    try expect(testAF(fa, 0x0A, PF));
    fa = xor8(fa, 0x1F);    try expect(testAF(fa, 0x15, 0));
    fa = xor8(fa, 0x3F);    try expect(testAF(fa, 0x2A, 0));
    fa = xor8(fa, 0x7F);    try expect(testAF(fa, 0x55, PF));
    fa = xor8(fa, 0xFF);    try expect(testAF(fa, 0xAA, SF|PF));
}

test "or8" {
    var fa = R16{ .h=0, .l=0 };
    fa = or8(fa, 0x00);     try expect(testAF(fa, 0x00, ZF|PF));
    fa = or8(fa, 0x01);     try expect(testAF(fa, 0x01, 0));
    fa = or8(fa, 0x02);     try expect(testAF(fa, 0x03, PF));
    fa = or8(fa, 0x04);     try expect(testAF(fa, 0x07, 0));
    fa = or8(fa, 0x08);     try expect(testAF(fa, 0x0F, PF));
    fa = or8(fa, 0x10);     try expect(testAF(fa, 0x1F, 0));
    fa = or8(fa, 0x20);     try expect(testAF(fa, 0x3F, PF));
    fa = or8(fa, 0x40);     try expect(testAF(fa, 0x7F, 0));
    fa = or8(fa, 0x80);     try expect(testAF(fa, 0xFF, SF|PF));
}
