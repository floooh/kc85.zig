const pins = @import("pins.zig").Pins;

pub const CPU = struct {

    pub const CF: u8 = (1<<0);
    pub const NF: u8 = (1<<1);
    pub const VF: u8 = (1<<2);
    pub const PF: u8 = VF;
    pub const XF: u8 = (1<<3);
    pub const HF: u8 = (1<<4);
    pub const YF: u8 = (1<<5);
    pub const ZF: u8 = (1<<6);
    pub const SF: u8 = (1<<7);

    B: u8 = 0xFF,
    C: u8 = 0xFF,
    D: u8 = 0xFF,
    E: u8 = 0xFF,
    H: u8 = 0xFF,
    L: u8 = 0xFF,
    F: u8 = 0xFF,
    A: u8 = 0xFF,
    
    WZ: u16 = 0xFFFF,
    IX: u16 = 0xFFFF,
    IY: u16 = 0xFFFF,
    SP: u16 = 0xFFFF,
    PC: u16 = 0x0000,
    IR: u16 = 0x0000,

    IM: u8 = 0,

    IFF1: bool = false,
    IFF2: bool = false,

    pub const TickFunc = fn(num_ticks: usize, pins: u64) u64;

    /// set CPU into reset state
    pub fn reset(self: *CPU) void {
        self = .{};
    }
    
    /// execute instructions for at least 'num_ticks', return number of executed ticks
    pub fn exec(self: *CPU, num_ticks: usize, tick_func: TickFunc) usize {

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
    fn add8(self: *CPU, val: u8) void {
        const acc: usize = self.A;
        const res: usize = acc + val;
        self.A = @truncate(u8, res);
        self.F = addFlags(acc, val, res);
    }
    
    fn adc8(self: *CPU, val: u8) void {
        const acc: usize = self.A;
        const res: usize = acc + val + (self.F & CF);
        self.A = @truncate(u8, res);
        self.F = addFlags(acc, val, res);
    }

    fn sub8(self: *CPU, val: u8) void {
        const acc: usize = self.A;
        const res: usize = acc -% val; 
        self.A = @truncate(u8, res);
        self.F = subFlags(acc, val, res);
    }
    
    fn sbc8(self: *CPU, val: u8) void {
        const acc: usize = self.A;
        const res: usize = acc -% val -% (self.F & CF);
        self.A = @truncate(u8, res);
        self.F = subFlags(acc, val, res);
    }
    
    fn and8(self: *CPU, val: u8) void {
        self.A &= val;
        self.F = szpFlags(self.A) | HF;
    }
    
    fn xor8(self: *CPU, val: u8) void {
        self.A ^= val;
        self.F = szpFlags(self.A);
    }

    fn or8(self: *CPU, val: u8) void {
        self.A |= val;
        self.F = szpFlags(self.A);
    }

    fn cp8(self: *CPU, val: u8) void {
        const acc: usize = self.A;
        const res: usize = acc -% val;
        self.F = cpFlags(acc, val, res);
    }
    
    fn alu8(self: *CPU, y: u3, val: u8) void {
        return switch(y) {
            0 => self.add8(val),
            1 => self.adc8(val),
            2 => self.sub8(val),
            3 => self.sbc8(val),
            4 => self.and8(val),
            5 => self.xor8(val),
            6 => self.or8(val),
            7 => self.cp8(val)
        };
    }
};

//=== TESTS ====================================================================
const expect = @import("std").testing.expect;

fn flags(f: u8, mask: u8) bool {
    return (f & ~(CPU.XF|CPU.YF)) == mask;
}

fn af(cpu: *const CPU, val: u8, mask: u8) bool {
    return (cpu.A == val) and ((cpu.F & ~(CPU.XF|CPU.YF)) == mask);
}

test "initial state" {
    var cpu = CPU{};
    try expect(cpu.A == 0xFF);
    try expect(cpu.F == 0xFF);
    try expect(cpu.B == 0xFF);
    try expect(cpu.C == 0xFF);
    try expect(cpu.D == 0xFF);
    try expect(cpu.E == 0xFF);
    try expect(cpu.H == 0xFF);
    try expect(cpu.L == 0xFF);

    try expect(cpu.WZ == 0xFFFF);
    try expect(cpu.IX == 0xFFFF);
    try expect(cpu.IY == 0xFFFF);
    try expect(cpu.SP == 0xFFFF);
    try expect(cpu.PC == 0);
    try expect(cpu.IR == 0);
    try expect(cpu.IM == 0);
    try expect(cpu.IFF1 == false);
    try expect(cpu.IFF2 == false);
}

test "add8" {
    var cpu = CPU{ .A=0, .F = 0 };
    cpu.A = 0xF;
    cpu.add8(cpu.A);    try expect(af(&cpu, 0x1E, CPU.HF));
    cpu.add8(0xE0);     try expect(af(&cpu, 0xFE, CPU.SF));
    cpu.A = 0x81; 
    cpu.add8(0x80);     try expect(af(&cpu, 0x01, CPU.VF|CPU.CF));
    cpu.add8(0xFF);     try expect(af(&cpu, 0x00, CPU.ZF|CPU.HF|CPU.CF));
    cpu.add8(0x40);     try expect(af(&cpu, 0x40, 0));
    cpu.add8(0x80);     try expect(af(&cpu, 0xC0, CPU.SF));
    cpu.add8(0x33);     try expect(af(&cpu, 0xF3, CPU.SF));
    cpu.add8(0x44);     try expect(af(&cpu, 0x37, CPU.CF));
}

test "adc8" {
    var cpu = CPU{ .A=0, .F=0, .B=0x41, .C=0x61, .D=0x81, .E=0x41, .H=0x61, .L=0x81 };
    cpu.adc8(cpu.A);    try expect(af(&cpu, 0x00, CPU.ZF));
    cpu.adc8(cpu.B);    try expect(af(&cpu, 0x41, 0));
    cpu.adc8(cpu.C);    try expect(af(&cpu, 0xA2, CPU.SF|CPU.VF));
    cpu.adc8(cpu.D);    try expect(af(&cpu, 0x23, CPU.VF|CPU.CF));
    cpu.adc8(cpu.E);    try expect(af(&cpu, 0x65, 0));
    cpu.adc8(cpu.H);    try expect(af(&cpu, 0xC6, CPU.SF|CPU.VF));
    cpu.adc8(cpu.L);    try expect(af(&cpu, 0x47, CPU.VF|CPU.CF));
    cpu.adc8(0x01);     try expect(af(&cpu, 0x49, 0));
}

test "sub8" {
    var cpu = CPU{ .A=0x04, .F=0, .B=0x01, .C=0xF8, .D=0x0F, .E=0x79, .H=0xC0, .L=0xBF };
    cpu.sub8(cpu.A);    try expect(af(&cpu, 0x00, CPU.ZF|CPU.NF));
    cpu.sub8(cpu.B);    try expect(af(&cpu, 0xFF, CPU.SF|CPU.HF|CPU.NF|CPU.CF));
    cpu.sub8(cpu.C);    try expect(af(&cpu, 0x07, CPU.NF));
    cpu.sub8(cpu.D);    try expect(af(&cpu, 0xF8, CPU.SF|CPU.HF|CPU.NF|CPU.CF));
    cpu.sub8(cpu.E);    try expect(af(&cpu, 0x7F, CPU.HF|CPU.VF|CPU.NF));
    cpu.sub8(cpu.H);    try expect(af(&cpu, 0xBF, CPU.SF|CPU.VF|CPU.NF|CPU.CF));
    cpu.sub8(cpu.L);    try expect(af(&cpu, 0x00, CPU.ZF|CPU.NF));
    cpu.sub8(0x01);     try expect(af(&cpu, 0xFF, CPU.SF|CPU.HF|CPU.NF|CPU.CF));
    cpu.sub8(0xFE);     try expect(af(&cpu, 0x01, CPU.NF));
}

test "sbc8" {
    var cpu = CPU{ .A=0x04, .F=0, .B=0x01, .C=0xF8, .D=0x0F, .E=0x79, .H=0xC0, .L=0xBF };
    cpu.sbc8(cpu.A);    try expect(af(&cpu, 0x00, CPU.ZF|CPU.NF));
    cpu.sbc8(cpu.B);    try expect(af(&cpu, 0xFF, CPU.SF|CPU.HF|CPU.NF|CPU.CF));
    cpu.sbc8(cpu.C);    try expect(af(&cpu, 0x06, CPU.NF));
    cpu.sbc8(cpu.D);    try expect(af(&cpu, 0xF7, CPU.SF|CPU.HF|CPU.NF|CPU.CF));
    cpu.sbc8(cpu.E);    try expect(af(&cpu, 0x7D, CPU.HF|CPU.VF|CPU.NF));
    cpu.sbc8(cpu.H);    try expect(af(&cpu, 0xBD, CPU.SF|CPU.VF|CPU.NF|CPU.CF));
    cpu.sbc8(cpu.L);    try expect(af(&cpu, 0xFD, CPU.SF|CPU.HF|CPU.NF|CPU.CF));
    cpu.sbc8(0x01);     try expect(af(&cpu, 0xFB, CPU.SF|CPU.NF));
    cpu.sbc8(0xFE);     try expect(af(&cpu, 0xFD, CPU.SF|CPU.HF|CPU.NF|CPU.CF));
}

test "cp8" {
    var cpu = CPU{ .A=0x04, .F=0, .B=0x05, .C=0x03, .D=0xFF, .E=0xAA, .H=0x80, .L=0x7F };
    cpu.cp8(cpu.A);     try expect(af(&cpu, 0x04, CPU.ZF|CPU.NF));
    cpu.cp8(cpu.B);     try expect(af(&cpu, 0x04, CPU.SF|CPU.HF|CPU.NF|CPU.CF));
    cpu.cp8(cpu.C);     try expect(af(&cpu, 0x04, CPU.NF));
    cpu.cp8(cpu.D);     try expect(af(&cpu, 0x04, CPU.HF|CPU.NF|CPU.CF));
    cpu.cp8(cpu.E);     try expect(af(&cpu, 0x04, CPU.HF|CPU.NF|CPU.CF));
    cpu.cp8(cpu.H);     try expect(af(&cpu, 0x04, CPU.SF|CPU.VF|CPU.NF|CPU.CF));
    cpu.cp8(cpu.L);     try expect(af(&cpu, 0x04, CPU.SF|CPU.HF|CPU.NF|CPU.CF));
    cpu.cp8(0x04);      try expect(af(&cpu, 0x04, CPU.ZF|CPU.NF));
}

test "and8" {
    var cpu = CPU{ .A=0xFF, .F=0, .B=0x01, .C=0x03, .D=0x04, .E=0x08, .H=0x10, .L=0x20 };
    cpu.and8(cpu.B);    try expect(af(&cpu, 0x01, CPU.HF));         cpu.or8(0xFF);
    cpu.and8(cpu.C);    try expect(af(&cpu, 0x03, CPU.HF|CPU.PF));  cpu.or8(0xFF);
    cpu.and8(cpu.D);    try expect(af(&cpu, 0x04, CPU.HF));         cpu.or8(0xFF);
    cpu.and8(cpu.E);    try expect(af(&cpu, 0x08, CPU.HF));         cpu.or8(0xFF);
    cpu.and8(cpu.H);    try expect(af(&cpu, 0x10, CPU.HF));         cpu.or8(0xFF);
    cpu.and8(cpu.L);    try expect(af(&cpu, 0x20, CPU.HF));         cpu.or8(0xFF);
    cpu.and8(0x40);     try expect(af(&cpu, 0x40, CPU.HF));         cpu.or8(0xFF);
    cpu.and8(0xAA);     try expect(af(&cpu, 0xAA, CPU.SF|CPU.HF|CPU.PF));
}

test "xor8" {
    var cpu = CPU{ .A=0x00, .F=0, .B=0x01, .C=0x03, .D=0x07, .E=0x0F, .H=0x1F, .L=0x3F };
    cpu.xor8(cpu.A);    try expect(af(&cpu, 0x00, CPU.ZF|CPU.PF));
    cpu.xor8(cpu.B);    try expect(af(&cpu, 0x01, 0));
    cpu.xor8(cpu.C);    try expect(af(&cpu, 0x02, 0));
    cpu.xor8(cpu.D);    try expect(af(&cpu, 0x05, CPU.PF));
    cpu.xor8(cpu.E);    try expect(af(&cpu, 0x0A, CPU.PF));
    cpu.xor8(cpu.H);    try expect(af(&cpu, 0x15, 0));
    cpu.xor8(cpu.L);    try expect(af(&cpu, 0x2A, 0));
    cpu.xor8(0x7F);     try expect(af(&cpu, 0x55, CPU.PF));
    cpu.xor8(0xFF);     try expect(af(&cpu, 0xAA, CPU.SF|CPU.PF));
}

test "or8" {
    var cpu = CPU{ .A=0x00, .F=0, .B=0x01, .C=0x02, .D=0x04, .E=0x08, .H=0x10, .L=0x20 };
    cpu.or8(cpu.A);     try expect(af(&cpu, 0x00, CPU.ZF|CPU.PF));
    cpu.or8(cpu.B);     try expect(af(&cpu, 0x01, 0));
    cpu.or8(cpu.C);     try expect(af(&cpu, 0x03, CPU.PF));
    cpu.or8(cpu.D);     try expect(af(&cpu, 0x07, 0));
    cpu.or8(cpu.E);     try expect(af(&cpu, 0x0F, CPU.PF));
    cpu.or8(cpu.H);     try expect(af(&cpu, 0x1F, 0));
    cpu.or8(cpu.L);     try expect(af(&cpu, 0x3F, CPU.PF));
    cpu.or8(0x40);      try expect(af(&cpu, 0x7F, 0));
    cpu.or8(0x80);      try expect(af(&cpu, 0xFF, CPU.SF|CPU.PF));
}

// FIXME: tests for CP