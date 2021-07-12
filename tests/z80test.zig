//------------------------------------------------------------------------------
//  z80test.zig
//
//  High level instruction tester, derived from
//  https://github.com/floooh/chips-test/blob/master/tests/z80-test.c
//------------------------------------------------------------------------------

const print     = @import("std").debug.print;
const assert    = @import("std").debug.assert;
const CPU       = @import("cpu").CPU;
const CPUPins   = @import("cpu").Pins;
const CPUFlags  = @import("cpu").Flags;
const CPUReg8   = @import("cpu").Reg8;
const CPUReg16  = @import("cpu").Reg16;

usingnamespace CPUReg8;
usingnamespace CPUReg16;
usingnamespace CPUPins;
usingnamespace CPUFlags;

// 64 KB memory
var mem = [_]u8{0} ** 0x10000;

var out_port: u16 = 0;
var out_byte: u8 = 0;

fn T(cond: bool) void {
    assert(cond);
}

fn start(name: []const u8) void {
    print("=> {s} ... ", .{name});
}

fn ok() void {
    print("OK\n", .{});
}

// tick callback which handles memory and IO requests
fn tick(num_ticks: usize, p: u64) u64 {
    var pins = p;
    if ((pins & MREQ) != 0) {
        if ((pins & RD) != 0) {
            // a memory read access
            pins = setData(pins, mem[getAddr(pins)]);
        }
        else if ((pins & WR) != 0) {
            // a memory write access
            mem[getAddr(pins)] = getData(pins);
        }
    }
    else if ((pins & IORQ) != 0) {
        if ((pins & RD) != 0) {
            // an IO input access (just write the port back)
            pins = setData(pins, @truncate(u8, getAddr(pins)));
        }
        else if ((pins & WR) != 0) {
            // an IO output access
            out_port = getAddr(pins);
            out_byte = getData(pins);
        }
    }
    return pins;
}

fn mem16(addr: u16) u16 {
    const l = mem[addr];
    const h = mem[addr +% 1];
    return @as(u16,h)<<8 | l;
}

fn makeCPU() CPU {
    var cpu = CPU{ };
    cpu.regs[A] = 0xFF;
    cpu.regs[F] = 0x00;
    cpu.ex[FA] = 0x00FF;
    return cpu;
}

fn copy(start_addr: u16, bytes: []const u8) void {
    var addr: u16 = start_addr;
    for (bytes) |byte| {
        mem[addr] = byte;
        addr +%= 1;
    }
}

fn step(cpu: *CPU) usize {
    var ticks = cpu.exec(0, tick);
    while (!cpu.opdone()) {
        ticks += cpu.exec(0, tick);
    }
    return ticks;
}

fn skip(cpu: *CPU, steps: usize) void {
    var i: usize = 0;
    while (i < steps): (i += 1) {
        _ = step(cpu);
    }
}

fn flags(cpu: *CPU, expected: u8) bool {
    return (cpu.regs[F] & ~(XF|YF)) == expected;
}

fn LD_A_RI() void {
    start("LD A,R/I");
    const prog = [_]u8 {
        0xED, 0x57,         // LD A,I
        0x97,               // SUB A
        0xED, 0x5F,         // LD A,R
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();
    cpu.iff1 = true;
    cpu.iff2 = true;
    cpu.R = 0x34;
    cpu.I = 0x01;
    cpu.regs[F] = CF;

    T(9 == step(&cpu)); T(0x01 == cpu.regs[A]); T(flags(&cpu, PF|CF));
    T(4 == step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|NF));
    T(9 == step(&cpu)); T(0x39 == cpu.regs[A]); T(flags(&cpu, PF));
    ok();
}

fn LD_IR_A() void {
    start("LD I/R,A");
    const prog = [_]u8 {
        0x3E, 0x45,     // LD A,0x45
        0xED, 0x47,     // LD I,A
        0xED, 0x4F,     // LD R,A
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(7==step(&cpu)); T(0x45 == cpu.regs[A]);
    T(9==step(&cpu)); T(0x45 == cpu.I);
    T(9==step(&cpu)); T(0x45 == cpu.R);
    ok();
}
    
fn LD_r_sn() void {
    start("LD r,sn");
    const prog = [_]u8 {
        0x3E, 0x12,     // LD A,0x12
        0x47,           // LD B,A
        0x4F,           // LD C,A
        0x57,           // LD D,A
        0x5F,           // LD E,A
        0x67,           // LD H,A
        0x6F,           // LD L,A
        0x7F,           // LD A,A

        0x06, 0x13,     // LD B,0x13
        0x40,           // LD B,B
        0x48,           // LD C,B
        0x50,           // LD D,B
        0x58,           // LD E,B
        0x60,           // LD H,B
        0x68,           // LD L,B
        0x78,           // LD A,B

        0x0E, 0x14,     // LD C,0x14
        0x41,           // LD B,C
        0x49,           // LD C,C
        0x51,           // LD D,C
        0x59,           // LD E,C
        0x61,           // LD H,C
        0x69,           // LD L,C
        0x79,           // LD A,C

        0x16, 0x15,     // LD D,0x15
        0x42,           // LD B,D
        0x4A,           // LD C,D
        0x52,           // LD D,D
        0x5A,           // LD E,D
        0x62,           // LD H,D
        0x6A,           // LD L,D
        0x7A,           // LD A,D

        0x1E, 0x16,     // LD E,0x16
        0x43,           // LD B,E
        0x4B,           // LD C,E
        0x53,           // LD D,E
        0x5B,           // LD E,E
        0x63,           // LD H,E
        0x6B,           // LD L,E
        0x7B,           // LD A,E

        0x26, 0x17,     // LD H,0x17
        0x44,           // LD B,H
        0x4C,           // LD C,H
        0x54,           // LD D,H
        0x5C,           // LD E,H
        0x64,           // LD H,H
        0x6C,           // LD L,H
        0x7C,           // LD A,H

        0x2E, 0x18,     // LD L,0x18
        0x45,           // LD B,L
        0x4D,           // LD C,L
        0x55,           // LD D,L
        0x5D,           // LD E,L
        0x65,           // LD H,L
        0x6D,           // LD L,L
        0x7D,           // LD A,L        
    };
    
    copy(0x0000, &prog);
    var cpu = makeCPU();
    T(step(&cpu) == 7); T(cpu.regs[A] == 0x12);
    T(step(&cpu) == 4); T(cpu.regs[B] == 0x12);
    T(step(&cpu) == 4); T(cpu.regs[C] == 0x12);
    T(step(&cpu) == 4); T(cpu.regs[D] == 0x12);
    T(step(&cpu) == 4); T(cpu.regs[E] == 0x12);
    T(step(&cpu) == 4); T(cpu.regs[H] == 0x12);
    T(step(&cpu) == 4); T(cpu.regs[L] == 0x12);
    T(step(&cpu) == 4); T(cpu.regs[A] == 0x12);
    
    T(step(&cpu) == 7); T(cpu.regs[B] == 0x13);
    T(step(&cpu) == 4); T(cpu.regs[B] == 0x13);
    T(step(&cpu) == 4); T(cpu.regs[C] == 0x13);
    T(step(&cpu) == 4); T(cpu.regs[D] == 0x13);
    T(step(&cpu) == 4); T(cpu.regs[E] == 0x13);
    T(step(&cpu) == 4); T(cpu.regs[H] == 0x13);
    T(step(&cpu) == 4); T(cpu.regs[L] == 0x13);
    T(step(&cpu) == 4); T(cpu.regs[A] == 0x13);

    T(step(&cpu) == 7); T(cpu.regs[C] == 0x14);
    T(step(&cpu) == 4); T(cpu.regs[B] == 0x14);
    T(step(&cpu) == 4); T(cpu.regs[C] == 0x14);
    T(step(&cpu) == 4); T(cpu.regs[D] == 0x14);
    T(step(&cpu) == 4); T(cpu.regs[E] == 0x14);
    T(step(&cpu) == 4); T(cpu.regs[H] == 0x14);
    T(step(&cpu) == 4); T(cpu.regs[L] == 0x14);
    T(step(&cpu) == 4); T(cpu.regs[A] == 0x14);

    T(step(&cpu) == 7); T(cpu.regs[D] == 0x15);
    T(step(&cpu) == 4); T(cpu.regs[B] == 0x15);
    T(step(&cpu) == 4); T(cpu.regs[C] == 0x15);
    T(step(&cpu) == 4); T(cpu.regs[D] == 0x15);
    T(step(&cpu) == 4); T(cpu.regs[E] == 0x15);
    T(step(&cpu) == 4); T(cpu.regs[H] == 0x15);
    T(step(&cpu) == 4); T(cpu.regs[L] == 0x15);
    T(step(&cpu) == 4); T(cpu.regs[A] == 0x15);

    T(step(&cpu) == 7); T(cpu.regs[E] == 0x16);
    T(step(&cpu) == 4); T(cpu.regs[B] == 0x16);
    T(step(&cpu) == 4); T(cpu.regs[C] == 0x16);
    T(step(&cpu) == 4); T(cpu.regs[D] == 0x16);
    T(step(&cpu) == 4); T(cpu.regs[E] == 0x16);
    T(step(&cpu) == 4); T(cpu.regs[H] == 0x16);
    T(step(&cpu) == 4); T(cpu.regs[L] == 0x16);
    T(step(&cpu) == 4); T(cpu.regs[A] == 0x16);

    T(step(&cpu) == 7); T(cpu.regs[H] == 0x17);
    T(step(&cpu) == 4); T(cpu.regs[B] == 0x17);
    T(step(&cpu) == 4); T(cpu.regs[C] == 0x17);
    T(step(&cpu) == 4); T(cpu.regs[D] == 0x17);
    T(step(&cpu) == 4); T(cpu.regs[E] == 0x17);
    T(step(&cpu) == 4); T(cpu.regs[H] == 0x17);
    T(step(&cpu) == 4); T(cpu.regs[L] == 0x17);
    T(step(&cpu) == 4); T(cpu.regs[A] == 0x17);

    T(step(&cpu) == 7); T(cpu.regs[L] == 0x18);
    T(step(&cpu) == 4); T(cpu.regs[B] == 0x18);
    T(step(&cpu) == 4); T(cpu.regs[C] == 0x18);
    T(step(&cpu) == 4); T(cpu.regs[D] == 0x18);
    T(step(&cpu) == 4); T(cpu.regs[E] == 0x18);
    T(step(&cpu) == 4); T(cpu.regs[H] == 0x18);
    T(step(&cpu) == 4); T(cpu.regs[L] == 0x18);
    T(step(&cpu) == 4); T(cpu.regs[A] == 0x18);
    ok();
}

fn LD_r_iHLi() void {
    start("LD r,(HL)");
    const prog = [_]u8 {
        0x21, 0x00, 0x10,   // LD HL,0x1000
        0x3E, 0x33,         // LD A,0x33
        0x77,               // LD (HL),A
        0x3E, 0x22,         // LD A,0x22
        0x46,               // LD B,(HL)
        0x4E,               // LD C,(HL)
        0x56,               // LD D,(HL)
        0x5E,               // LD E,(HL)
        0x66,               // LD H,(HL)
        0x26, 0x10,         // LD H,0x10
        0x6E,               // LD L,(HL)
        0x2E, 0x00,         // LD L,0x00
        0x7E,               // LD A,(HL)
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(10==step(&cpu)); T(0x1000 == cpu.r16(HL));
    T(7==step(&cpu)); T(0x33 == cpu.regs[A]);
    T(7==step(&cpu)); T(0x33 == mem[0x1000]);
    T(7==step(&cpu)); T(0x22 == cpu.regs[A]);
    T(7==step(&cpu)); T(0x33 == cpu.regs[B]);
    T(7==step(&cpu)); T(0x33 == cpu.regs[C]);
    T(7==step(&cpu)); T(0x33 == cpu.regs[D]);
    T(7==step(&cpu)); T(0x33 == cpu.regs[E]);
    T(7==step(&cpu)); T(0x33 == cpu.regs[H]);
    T(7==step(&cpu)); T(0x10 == cpu.regs[H]);
    T(7==step(&cpu)); T(0x33 == cpu.regs[L]);
    T(7==step(&cpu)); T(0x00 == cpu.regs[L]);
    T(7==step(&cpu)); T(0x33 == cpu.regs[A]);         
    ok();
}

fn LD_iHLi_r() void {
    start("LD (HL),r");
    const prog = [_]u8 {
        0x21, 0x00, 0x10,   // LD HL,0x1000
        0x3E, 0x12,         // LD A,0x12
        0x77,               // LD (HL),A
        0x06, 0x13,         // LD B,0x13
        0x70,               // LD (HL),B
        0x0E, 0x14,         // LD C,0x14
        0x71,               // LD (HL),C
        0x16, 0x15,         // LD D,0x15
        0x72,               // LD (HL),D
        0x1E, 0x16,         // LD E,0x16
        0x73,               // LD (HL),E
        0x74,               // LD (HL),H
        0x75,               // LD (HL),L
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(10==step(&cpu)); T(0x1000 == cpu.r16(HL));
    T(7==step(&cpu)); T(0x12 == cpu.regs[A]);
    T(7==step(&cpu)); T(0x12 == mem[0x1000]);
    T(7==step(&cpu)); T(0x13 == cpu.regs[B]);
    T(7==step(&cpu)); T(0x13 == mem[0x1000]);
    T(7==step(&cpu)); T(0x14 == cpu.regs[C]);
    T(7==step(&cpu)); T(0x14 == mem[0x1000]);
    T(7==step(&cpu)); T(0x15 == cpu.regs[D]);
    T(7==step(&cpu)); T(0x15 == mem[0x1000]);
    T(7==step(&cpu)); T(0x16 == cpu.regs[E]);
    T(7==step(&cpu)); T(0x16 == mem[0x1000]);
    T(7==step(&cpu)); T(0x10 == mem[0x1000]);
    T(7==step(&cpu)); T(0x00 == mem[0x1000]);    
    ok();
}

fn LD_iHLi_n() void {
    start("LD (HL),n");
    const prog = [_]u8 {
        0x21, 0x00, 0x20,   // LD HL,0x2000
        0x36, 0x33,         // LD (HL),0x33
        0x21, 0x00, 0x10,   // LD HL,0x1000
        0x36, 0x65,         // LD (HL),0x65
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(10==step(&cpu)); T(0x2000 == cpu.r16(HL));
    T(10==step(&cpu)); T(0x33 == mem[0x2000]);
    T(10==step(&cpu)); T(0x1000 == cpu.r16(HL));
    T(10==step(&cpu)); T(0x65 == mem[0x1000]);
    ok();
}

fn LD_iIXIYi_r() void {
    start("LD (IX/IY+d),r");
    const prog = [_]u8 {
        0xDD, 0x21, 0x03, 0x10,     // LD IX,0x1003
        0x3E, 0x12,                 // LD A,0x12
        0xDD, 0x77, 0x00,           // LD (IX+0),A
        0x06, 0x13,                 // LD B,0x13
        0xDD, 0x70, 0x01,           // LD (IX+1),B
        0x0E, 0x14,                 // LD C,0x14
        0xDD, 0x71, 0x02,           // LD (IX+2),C
        0x16, 0x15,                 // LD D,0x15
        0xDD, 0x72, 0xFF,           // LD (IX-1),D
        0x1E, 0x16,                 // LD E,0x16
        0xDD, 0x73, 0xFE,           // LD (IX-2),E
        0x26, 0x17,                 // LD H,0x17
        0xDD, 0x74, 0x03,           // LD (IX+3),H
        0x2E, 0x18,                 // LD L,0x18
        0xDD, 0x75, 0xFD,           // LD (IX-3),L
        0xFD, 0x21, 0x03, 0x10,     // LD IY,0x1003
        0x3E, 0x12,                 // LD A,0x12
        0xFD, 0x77, 0x00,           // LD (IY+0),A
        0x06, 0x13,                 // LD B,0x13
        0xFD, 0x70, 0x01,           // LD (IY+1),B
        0x0E, 0x14,                 // LD C,0x14
        0xFD, 0x71, 0x02,           // LD (IY+2),C
        0x16, 0x15,                 // LD D,0x15
        0xFD, 0x72, 0xFF,           // LD (IY-1),D
        0x1E, 0x16,                 // LD E,0x16
        0xFD, 0x73, 0xFE,           // LD (IY-2),E
        0x26, 0x17,                 // LD H,0x17
        0xFD, 0x74, 0x03,           // LD (IY+3),H
        0x2E, 0x18,                 // LD L,0x18
        0xFD, 0x75, 0xFD,           // LD (IY-3),L
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(14==step(&cpu)); T(0x1003 == cpu.IX);
    T(7 ==step(&cpu)); T(0x12 == cpu.regs[A]);
    T(19==step(&cpu)); T(0x12 == mem[0x1003]); T(0x1003 == cpu.WZ);
    T(7 ==step(&cpu)); T(0x13 == cpu.regs[B]);
    T(19==step(&cpu)); T(0x13 == mem[0x1004]); T(0x1004 == cpu.WZ);
    T(7 ==step(&cpu)); T(0x14 == cpu.regs[C]);
    T(19==step(&cpu)); T(0x14 == mem[0x1005]); T(0x1005 == cpu.WZ);
    T(7 ==step(&cpu)); T(0x15 == cpu.regs[D]);
    T(19==step(&cpu)); T(0x15 == mem[0x1002]); T(0x1002 == cpu.WZ);
    T(7 ==step(&cpu)); T(0x16 == cpu.regs[E]);
    T(19==step(&cpu)); T(0x16 == mem[0x1001]);
    T(7 ==step(&cpu)); T(0x17 == cpu.regs[H]);
    T(19==step(&cpu)); T(0x17 == mem[0x1006]);
    T(7 ==step(&cpu)); T(0x18 == cpu.regs[L]);
    T(19==step(&cpu)); T(0x18 == mem[0x1000]);
    T(14==step(&cpu)); T(0x1003 == cpu.IY);
    T(7 ==step(&cpu)); T(0x12 == cpu.regs[A]);
    T(19==step(&cpu)); T(0x12 == mem[0x1003]);
    T(7 ==step(&cpu)); T(0x13 == cpu.regs[B]);
    T(19==step(&cpu)); T(0x13 == mem[0x1004]);
    T(7 ==step(&cpu)); T(0x14 == cpu.regs[C]);
    T(19==step(&cpu)); T(0x14 == mem[0x1005]);
    T(7 ==step(&cpu)); T(0x15 == cpu.regs[D]);
    T(19==step(&cpu)); T(0x15 == mem[0x1002]);
    T(7 ==step(&cpu)); T(0x16 == cpu.regs[E]);
    T(19==step(&cpu)); T(0x16 == mem[0x1001]);
    T(7 ==step(&cpu)); T(0x17 == cpu.regs[H]);
    T(19==step(&cpu)); T(0x17 == mem[0x1006]);
    T(7 ==step(&cpu)); T(0x18 == cpu.regs[L]);
    T(19==step(&cpu)); T(0x18 == mem[0x1000]);
    ok();
}

fn LD_iIXIYi_n() void {
    start("LD (IX/IY+d),n");
    const prog = [_]u8 {
        0xDD, 0x21, 0x00, 0x20,     // LD IX,0x2000
        0xDD, 0x36, 0x02, 0x33,     // LD (IX+2),0x33
        0xDD, 0x36, 0xFE, 0x11,     // LD (IX-2),0x11
        0xFD, 0x21, 0x00, 0x10,     // LD IY,0x1000
        0xFD, 0x36, 0x01, 0x22,     // LD (IY+1),0x22
        0xFD, 0x36, 0xFF, 0x44,     // LD (IY-1),0x44
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(14==step(&cpu)); T(0x2000 == cpu.IX);
    T(19==step(&cpu)); T(0x33 == mem[0x2002]);
    T(19==step(&cpu)); T(0x11 == mem[0x1FFE]);
    T(14==step(&cpu)); T(0x1000 == cpu.IY);
    T(19==step(&cpu)); T(0x22 == mem[0x1001]);
    T(19==step(&cpu)); T(0x44 == mem[0x0FFF]);
    ok();
}

fn LD_ddIXIY_nn() void {
    start("LD dd/IX/IY,nn");
    const prog = [_]u8 {
        0x01, 0x34, 0x12,       // LD BC,0x1234
        0x11, 0x78, 0x56,       // LD DE,0x5678
        0x21, 0xBC, 0x9A,       // LD HL,0x9ABC
        0x31, 0x68, 0x13,       // LD SP,0x1368
        0xDD, 0x21, 0x21, 0x43, // LD IX,0x4321
        0xFD, 0x21, 0x65, 0x87, // LD IY,0x8765
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(10==step(&cpu)); T(0x1234 == cpu.r16(BC));
    T(10==step(&cpu)); T(0x5678 == cpu.r16(DE));
    T(10==step(&cpu)); T(0x9ABC == cpu.r16(HL));
    T(10==step(&cpu)); T(0x1368 == cpu.SP);
    T(14==step(&cpu)); T(0x4321 == cpu.IX);
    T(14==step(&cpu)); T(0x8765 == cpu.IY);
    ok();
}

fn LD_A_iBCDEnni() void {
    start("LD A,(BC/DE/nn)");
    const data = [_]u8 { 0x11, 0x22, 0x33 };
    const prog = [_]u8 {
        0x01, 0x00, 0x10,   // LD BC,0x1000
        0x11, 0x01, 0x10,   // LD DE,0x1001
        0x0A,               // LD A,(BC)
        0x1A,               // LD A,(DE)
        0x3A, 0x02, 0x10,   // LD A,(0x1002)
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(10==step(&cpu)); T(0x1000 == cpu.r16(BC));
    T(10==step(&cpu)); T(0x1001 == cpu.r16(DE));
    T(7 ==step(&cpu)); T(0x11 == cpu.regs[A]); T(0x1001 == cpu.WZ);
    T(7 ==step(&cpu)); T(0x22 == cpu.regs[A]); T(0x1002 == cpu.WZ);
    T(13==step(&cpu)); T(0x33 == cpu.regs[A]); T(0x1003 == cpu.WZ);
    ok();
}

fn LD_iBCDEnni_A() void {
    start("LD (BC/DE/nn),A");
    const prog = [_]u8 {
        0x01, 0x00, 0x10,   // LD BC,0x1000
        0x11, 0x01, 0x10,   // LD DE,0x1001
        0x3E, 0x77,         // LD A,0x77
        0x02,               // LD (BC),A
        0x12,               // LD (DE),A
        0x32, 0x02, 0x10,   // LD (0x1002),A
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();
    
    T(10==step(&cpu)); T(0x1000 == cpu.r16(BC));
    T(10==step(&cpu)); T(0x1001 == cpu.r16(DE));
    T(7 ==step(&cpu)); T(0x77 == cpu.regs[A]);
    T(7 ==step(&cpu)); T(0x77 == mem[0x1000]); T(0x7701 == cpu.WZ);
    T(7 ==step(&cpu)); T(0x77 == mem[0x1001]); T(0x7702 == cpu.WZ);
    T(13==step(&cpu)); T(0x77 == mem[0x1002]); T(0x7703 == cpu.WZ);
    ok();
}

fn LD_HLddIXIY_inni() void {
    start("LD dd/IX/IY,(nn)");
    const data = [_]u8 {
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08
    };
    const prog = [_]u8 {
        0x2A, 0x00, 0x10,           // LD HL,(0x1000)
        0xED, 0x4B, 0x01, 0x10,     // LD BC,(0x1001)
        0xED, 0x5B, 0x02, 0x10,     // LD DE,(0x1002)
        0xED, 0x6B, 0x03, 0x10,     // LD HL,(0x1003) undocumented 'long' version
        0xED, 0x7B, 0x04, 0x10,     // LD SP,(0x1004)
        0xDD, 0x2A, 0x05, 0x10,     // LD IX,(0x1005)
        0xFD, 0x2A, 0x06, 0x10,     // LD IY,(0x1006)
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(16==step(&cpu)); T(0x0201 == cpu.r16(HL)); T(0x1001 == cpu.WZ);
    T(20==step(&cpu)); T(0x0302 == cpu.r16(BC)); T(0x1002 == cpu.WZ);
    T(20==step(&cpu)); T(0x0403 == cpu.r16(DE)); T(0x1003 == cpu.WZ);
    T(20==step(&cpu)); T(0x0504 == cpu.r16(HL)); T(0x1004 == cpu.WZ);
    T(20==step(&cpu)); T(0x0605 == cpu.SP); T(0x1005 == cpu.WZ);
    T(20==step(&cpu)); T(0x0706 == cpu.IX); T(0x1006 == cpu.WZ);
    T(20==step(&cpu)); T(0x0807 == cpu.IY); T(0x1007 == cpu.WZ);
    ok();
}

fn LD_inni_HLddIXIY() void {
    start("LD (nn),dd/IX/IY");
    const prog = [_]u8 {
        0x21, 0x01, 0x02,           // LD HL,0x0201
        0x22, 0x00, 0x10,           // LD (0x1000),HL
        0x01, 0x34, 0x12,           // LD BC,0x1234
        0xED, 0x43, 0x02, 0x10,     // LD (0x1002),BC
        0x11, 0x78, 0x56,           // LD DE,0x5678
        0xED, 0x53, 0x04, 0x10,     // LD (0x1004),DE
        0x21, 0xBC, 0x9A,           // LD HL,0x9ABC
        0xED, 0x63, 0x06, 0x10,     // LD (0x1006),HL undocumented 'long' version
        0x31, 0x68, 0x13,           // LD SP,0x1368
        0xED, 0x73, 0x08, 0x10,     // LD (0x1008),SP
        0xDD, 0x21, 0x21, 0x43,     // LD IX,0x4321
        0xDD, 0x22, 0x0A, 0x10,     // LD (0x100A),IX
        0xFD, 0x21, 0x65, 0x87,     // LD IY,0x8765
        0xFD, 0x22, 0x0C, 0x10,     // LD (0x100C),IY
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(10==step(&cpu)); T(0x0201 == cpu.r16(HL));
    T(16==step(&cpu)); T(0x0201 == mem16(0x1000)); T(0x1001 == cpu.WZ);
    T(10==step(&cpu)); T(0x1234 == cpu.r16(BC));
    T(20==step(&cpu)); T(0x1234 == mem16(0x1002)); T(0x1003 == cpu.WZ);
    T(10==step(&cpu)); T(0x5678 == cpu.r16(DE));
    T(20==step(&cpu)); T(0x5678 == mem16(0x1004)); T(0x1005 == cpu.WZ);
    T(10==step(&cpu)); T(0x9ABC == cpu.r16(HL));
    T(20==step(&cpu)); T(0x9ABC == mem16(0x1006)); T(0x1007 == cpu.WZ);
    T(10==step(&cpu)); T(0x1368 == cpu.SP);
    T(20==step(&cpu)); T(0x1368 == mem16(0x1008)); T(0x1009 == cpu.WZ);
    T(14==step(&cpu)); T(0x4321 == cpu.IX);
    T(20==step(&cpu)); T(0x4321 == mem16(0x100A)); T(0x100B == cpu.WZ);
    T(14==step(&cpu)); T(0x8765 == cpu.IY);
    T(20==step(&cpu)); T(0x8765 == mem16(0x100C)); T(0x100D == cpu.WZ);
    ok();
}

fn LD_SP_HLIXIY() void {
    start("LD SP,HL/IX/IY");
    const prog = [_]u8{
        0x21, 0x34, 0x12,           // LD HL,0x1234
        0xDD, 0x21, 0x78, 0x56,     // LD IX,0x5678
        0xFD, 0x21, 0xBC, 0x9A,     // LD IY,0x9ABC
        0xF9,                       // LD SP,HL
        0xDD, 0xF9,                 // LD SP,IX
        0xFD, 0xF9,                 // LD SP,IY
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(10==step(&cpu)); T(0x1234 == cpu.r16(HL));
    T(14==step(&cpu)); T(0x5678 == cpu.IX);
    T(14==step(&cpu)); T(0x9ABC == cpu.IY);
    T(6 ==step(&cpu)); T(0x1234 == cpu.SP);
    T(10==step(&cpu)); T(0x5678 == cpu.SP);
    T(10==step(&cpu)); T(0x9ABC == cpu.SP);
    ok();
}

fn PUSH_POP_qqIXIY() void {
    start("PUSH/POP qqIXIY");
    const prog = [_]u8 {
        0x01, 0x34, 0x12,       // LD BC,0x1234
        0x11, 0x78, 0x56,       // LD DE,0x5678
        0x21, 0xBC, 0x9A,       // LD HL,0x9ABC
        0x3E, 0xEF,             // LD A,0xEF
        0xDD, 0x21, 0x45, 0x23, // LD IX,0x2345
        0xFD, 0x21, 0x89, 0x67, // LD IY,0x6789
        0x31, 0x00, 0x01,       // LD SP,0x0100
        0xF5,                   // PUSH AF
        0xC5,                   // PUSH BC
        0xD5,                   // PUSH DE
        0xE5,                   // PUSH HL
        0xDD, 0xE5,             // PUSH IX
        0xFD, 0xE5,             // PUSH IY
        0xF1,                   // POP AF
        0xC1,                   // POP BC
        0xD1,                   // POP DE
        0xE1,                   // POP HL
        0xDD, 0xE1,             // POP IX
        0xFD, 0xE1,             // POP IY
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();
    
    T(10==step(&cpu)); T(0x1234 == cpu.r16(BC));
    T(10==step(&cpu)); T(0x5678 == cpu.r16(DE));
    T(10==step(&cpu)); T(0x9ABC == cpu.r16(HL));
    T(7 ==step(&cpu)); T(0x00EF == cpu.r16(FA));
    T(14==step(&cpu)); T(0x2345 == cpu.IX);
    T(14==step(&cpu)); T(0x6789 == cpu.IY);
    T(10==step(&cpu)); T(0x0100 == cpu.SP);
    T(11==step(&cpu)); T(0xEF00 == mem16(0x00FE)); T(0x00FE == cpu.SP);
    T(11==step(&cpu)); T(0x1234 == mem16(0x00FC)); T(0x00FC == cpu.SP);
    T(11==step(&cpu)); T(0x5678 == mem16(0x00FA)); T(0x00FA == cpu.SP);
    T(11==step(&cpu)); T(0x9ABC == mem16(0x00F8)); T(0x00F8 == cpu.SP);
    T(15==step(&cpu)); T(0x2345 == mem16(0x00F6)); T(0x00F6 == cpu.SP);
    T(15==step(&cpu)); T(0x6789 == mem16(0x00F4)); T(0x00F4 == cpu.SP);
    T(10==step(&cpu)); T(0x8967 == cpu.r16(FA)); T(0x00F6 == cpu.SP);
    T(10==step(&cpu)); T(0x2345 == cpu.r16(BC)); T(0x00F8 == cpu.SP);
    T(10==step(&cpu)); T(0x9ABC == cpu.r16(DE)); T(0x00FA == cpu.SP);
    T(10==step(&cpu)); T(0x5678 == cpu.r16(HL)); T(0x00FC == cpu.SP);
    T(14==step(&cpu)); T(0x1234 == cpu.IX); T(0x00FE == cpu.SP);
    T(14==step(&cpu)); T(0xEF00 == cpu.IY); T(0x0100 == cpu.SP);
    ok();
}

fn EX() void {
    start("EX");
    const prog = [_]u8 {
        0x21, 0x34, 0x12,       // LD HL,0x1234
        0x11, 0x78, 0x56,       // LD DE,0x5678
        0xEB,                   // EX DE,HL
        0x3E, 0x11,             // LD A,0x11
        0x08,                   // EX AF,AF'
        0x3E, 0x22,             // LD A,0x22
        0x08,                   // EX AF,AF'
        0x01, 0xBC, 0x9A,       // LD BC,0x9ABC
        0xD9,                   // EXX
        0x21, 0x11, 0x11,       // LD HL,0x1111
        0x11, 0x22, 0x22,       // LD DE,0x2222
        0x01, 0x33, 0x33,       // LD BC,0x3333
        0xD9,                   // EXX
        0x31, 0x00, 0x01,       // LD SP,0x0100
        0xD5,                   // PUSH DE
        0xE3,                   // EX (SP),HL
        0xDD, 0x21, 0x99, 0x88, // LD IX,0x8899
        0xDD, 0xE3,             // EX (SP),IX
        0xFD, 0x21, 0x77, 0x66, // LD IY,0x6677
        0xFD, 0xE3,             // EX (SP),IY
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(10==step(&cpu)); T(0x1234 == cpu.r16(HL));
    T(10==step(&cpu)); T(0x5678 == cpu.r16(DE));
    T(4 ==step(&cpu)); T(0x1234 == cpu.r16(DE)); T(0x5678 == cpu.r16(HL));
    T(7 ==step(&cpu)); T(0x0011 == cpu.r16(FA)); T(0x00FF == cpu.ex[FA]);
    T(4 ==step(&cpu)); T(0x00FF == cpu.r16(FA)); T(0x0011 == cpu.ex[FA]);
    T(7 ==step(&cpu)); T(0x0022 == cpu.r16(FA)); T(0x0011 == cpu.ex[FA]);
    T(4 ==step(&cpu)); T(0x0011 == cpu.r16(FA)); T(0x0022 == cpu.ex[FA]);
    T(10==step(&cpu)); T(0x9ABC == cpu.r16(BC));
    T(4 ==step(&cpu));
    T(0xFFFF == cpu.r16(HL)); T(0x5678 == cpu.ex[HL]);
    T(0xFFFF == cpu.r16(DE)); T(0x1234 == cpu.ex[DE]);
    T(0xFFFF == cpu.r16(BC)); T(0x9ABC == cpu.ex[BC]);
    T(10==step(&cpu)); T(0x1111 == cpu.r16(HL));
    T(10==step(&cpu)); T(0x2222 == cpu.r16(DE));
    T(10==step(&cpu)); T(0x3333 == cpu.r16(BC));
    T(4 ==step(&cpu));
    T(0x5678 == cpu.r16(HL)); T(0x1111 == cpu.ex[HL]);
    T(0x1234 == cpu.r16(DE)); T(0x2222 == cpu.ex[DE]);
    T(0x9ABC == cpu.r16(BC)); T(0x3333 == cpu.ex[BC]);
    T(10==step(&cpu)); T(0x0100 == cpu.SP);
    T(11==step(&cpu)); T(0x1234 == mem16(0x00FE));
    T(19==step(&cpu)); T(0x1234 == cpu.r16(HL)); T(cpu.WZ == cpu.r16(HL)); T(0x5678 == mem16(0x00FE));
    T(14==step(&cpu)); T(0x8899 == cpu.IX);
    T(23==step(&cpu)); T(0x5678 == cpu.IX); T(cpu.WZ == cpu.IX); T(0x8899 == mem16(0x00FE));
    T(14==step(&cpu)); T(0x6677 == cpu.IY);
    T(23==step(&cpu)); T(0x8899 == cpu.IY); T(cpu.WZ == cpu.IY); T(0x6677 == mem16(0x00FE));
    ok();
}

fn ADD_rn() void {
    start("ADD rn");
    const prog = [_]u8 {
        0x3E, 0x0F,     // LD A,0x0F
        0x87,           // ADD A,A
        0x06, 0xE0,     // LD B,0xE0
        0x80,           // ADD A,B
        0x3E, 0x81,     // LD A,0x81
        0x0E, 0x80,     // LD C,0x80
        0x81,           // ADD A,C
        0x16, 0xFF,     // LD D,0xFF
        0x82,           // ADD A,D
        0x1E, 0x40,     // LD E,0x40
        0x83,           // ADD A,E
        0x26, 0x80,     // LD H,0x80
        0x84,           // ADD A,H
        0x2E, 0x33,     // LD L,0x33
        0x85,           // ADD A,L
        0xC6, 0x44,     // ADD A,0x44
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();
    
    T(7==step(&cpu)); T(0x0F == cpu.regs[A]); T(flags(&cpu, 0));
    T(4==step(&cpu)); T(0x1E == cpu.regs[A]); T(flags(&cpu, HF));
    T(7==step(&cpu)); T(0xE0 == cpu.regs[B]);
    T(4==step(&cpu)); T(0xFE == cpu.regs[A]); T(flags(&cpu, SF));
    T(7==step(&cpu)); T(0x81 == cpu.regs[A]);
    T(7==step(&cpu)); T(0x80 == cpu.regs[C]);
    T(4==step(&cpu)); T(0x01 == cpu.regs[A]); T(flags(&cpu, VF|CF));
    T(7==step(&cpu)); T(0xFF == cpu.regs[D]);
    T(4==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|HF|CF));
    T(7==step(&cpu)); T(0x40 == cpu.regs[E]);
    T(4==step(&cpu)); T(0x40 == cpu.regs[A]); T(flags(&cpu, 0));
    T(7==step(&cpu)); T(0x80 == cpu.regs[H]);
    T(4==step(&cpu)); T(0xC0 == cpu.regs[A]); T(flags(&cpu, SF));
    T(7==step(&cpu)); T(0x33 == cpu.regs[L]);
    T(4==step(&cpu)); T(0xF3 == cpu.regs[A]); T(flags(&cpu, SF));
    T(7==step(&cpu)); T(0x37 == cpu.regs[A]); T(flags(&cpu, CF));
    ok();
}

fn ADD_iHLIXIYi() void {
    start("ADD (HL/IX+d/IY+d)");
    const data = [_]u8 { 0x41, 0x61, 0x81 };
    const prog = [_]u8 {
        0x21, 0x00, 0x10,       // LD HL,0x1000
        0xDD, 0x21, 0x00, 0x10, // LD IX,0x1000
        0xFD, 0x21, 0x03, 0x10, // LD IY,0x1003
        0x3E, 0x00,             // LD A,0x00
        0x86,                   // ADD A,(HL)
        0xDD, 0x86, 0x01,       // ADD A,(IX+1)
        0xFD, 0x86, 0xFF,       // ADD A,(IY-1)
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(10==step(&cpu)); T(0x1000 == cpu.r16(HL));
    T(14==step(&cpu)); T(0x1000 == cpu.IX);
    T(14==step(&cpu)); T(0x1003 == cpu.IY);
    T(7 ==step(&cpu)); T(0x00 == cpu.regs[A]);
    T(7 ==step(&cpu)); T(0x41 == cpu.regs[A]); T(flags(&cpu,0));
    T(19==step(&cpu)); T(0xA2 == cpu.regs[A]); T(flags(&cpu,SF|VF));
    T(19==step(&cpu)); T(0x23 == cpu.regs[A]); T(flags(&cpu,VF|CF));
    ok();
}

fn ADC_rn() void {
    start("ADC rn");
    const prog = [_]u8 {
        0x3E, 0x00,         // LD A,0x00
        0x06, 0x41,         // LD B,0x41
        0x0E, 0x61,         // LD C,0x61
        0x16, 0x81,         // LD D,0x81
        0x1E, 0x41,         // LD E,0x41
        0x26, 0x61,         // LD H,0x61
        0x2E, 0x81,         // LD L,0x81
        0x8F,               // ADC A,A
        0x88,               // ADC A,B
        0x89,               // ADC A,C
        0x8A,               // ADC A,D
        0x8B,               // ADC A,E
        0x8C,               // ADC A,H
        0x8D,               // ADC A,L
        0xCE, 0x01,         // ADC A,0x01
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(7==step(&cpu)); T(0x00 == cpu.regs[A]);
    T(7==step(&cpu)); T(0x41 == cpu.regs[B]);
    T(7==step(&cpu)); T(0x61 == cpu.regs[C]);
    T(7==step(&cpu)); T(0x81 == cpu.regs[D]);
    T(7==step(&cpu)); T(0x41 == cpu.regs[E]);
    T(7==step(&cpu)); T(0x61 == cpu.regs[H]);
    T(7==step(&cpu)); T(0x81 == cpu.regs[L]);
    T(4==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF));
    T(4==step(&cpu)); T(0x41 == cpu.regs[A]); T(flags(&cpu, 0));
    T(4==step(&cpu)); T(0xA2 == cpu.regs[A]); T(flags(&cpu, SF|VF));
    T(4==step(&cpu)); T(0x23 == cpu.regs[A]); T(flags(&cpu, VF|CF));
    T(4==step(&cpu)); T(0x65 == cpu.regs[A]); T(flags(&cpu, 0));
    T(4==step(&cpu)); T(0xC6 == cpu.regs[A]); T(flags(&cpu, SF|VF));
    T(4==step(&cpu)); T(0x47 == cpu.regs[A]); T(flags(&cpu, VF|CF));
    T(7==step(&cpu)); T(0x49 == cpu.regs[A]); T(flags(&cpu, 0));
    ok();
}

fn ADC_iHLIXIYi() void {
    start("ADC (HL/IX+d/IY+d)");
    const data = [_]u8 { 0x41, 0x61, 0x81, 0x2 };
    const prog = [_]u8 {
        0x21, 0x00, 0x10,       // LD HL,0x1000
        0xDD, 0x21, 0x00, 0x10, // LD IX,0x1000
        0xFD, 0x21, 0x03, 0x10, // LD IY,0x1003
        0x3E, 0x00,             // LD A,0x00
        0x86,                   // ADD A,(HL)
        0xDD, 0x8E, 0x01,       // ADC A,(IX+1)
        0xFD, 0x8E, 0xFF,       // ADC A,(IY-1)
        0xDD, 0x8E, 0x03,       // ADC A,(IX+3)
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(10==step(&cpu)); T(0x1000 == cpu.r16(HL));
    T(14==step(&cpu)); T(0x1000 == cpu.IX);
    T(14==step(&cpu)); T(0x1003 == cpu.IY);
    T(7 ==step(&cpu)); T(0x00 == cpu.regs[A]);
    T(7 ==step(&cpu)); T(0x41 == cpu.regs[A]); T(flags(&cpu, 0));
    T(19==step(&cpu)); T(0xA2 == cpu.regs[A]); T(flags(&cpu, SF|VF));
    T(19==step(&cpu)); T(0x23 == cpu.regs[A]); T(flags(&cpu, VF|CF));
    T(19==step(&cpu)); T(0x26 == cpu.regs[A]); T(flags(&cpu, 0));
    ok();
}

fn SUB_rn() void {
    start("SUB rn");
    const prog = [_]u8 {
        0x3E, 0x04,     // LD A,0x04
        0x06, 0x01,     // LD B,0x01
        0x0E, 0xF8,     // LD C,0xF8
        0x16, 0x0F,     // LD D,0x0F
        0x1E, 0x79,     // LD E,0x79
        0x26, 0xC0,     // LD H,0xC0
        0x2E, 0xBF,     // LD L,0xBF
        0x97,           // SUB A,A
        0x90,           // SUB A,B
        0x91,           // SUB A,C
        0x92,           // SUB A,D
        0x93,           // SUB A,E
        0x94,           // SUB A,H
        0x95,           // SUB A,L
        0xD6, 0x01,     // SUB A,0x01
        0xD6, 0xFE,     // SUB A,0xFE
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(7==step(&cpu)); T(0x04 == cpu.regs[A]);
    T(7==step(&cpu)); T(0x01 == cpu.regs[B]);
    T(7==step(&cpu)); T(0xF8 == cpu.regs[C]);
    T(7==step(&cpu)); T(0x0F == cpu.regs[D]);
    T(7==step(&cpu)); T(0x79 == cpu.regs[E]);
    T(7==step(&cpu)); T(0xC0 == cpu.regs[H]);
    T(7==step(&cpu)); T(0xBF == cpu.regs[L]);
    T(4==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|NF));
    T(4==step(&cpu)); T(0xFF == cpu.regs[A]); T(flags(&cpu, SF|HF|NF|CF));
    T(4==step(&cpu)); T(0x07 == cpu.regs[A]); T(flags(&cpu, NF));
    T(4==step(&cpu)); T(0xF8 == cpu.regs[A]); T(flags(&cpu, SF|HF|NF|CF));
    T(4==step(&cpu)); T(0x7F == cpu.regs[A]); T(flags(&cpu, HF|VF|NF));
    T(4==step(&cpu)); T(0xBF == cpu.regs[A]); T(flags(&cpu, SF|VF|NF|CF));
    T(4==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|NF));
    T(7==step(&cpu)); T(0xFF == cpu.regs[A]); T(flags(&cpu, SF|HF|NF|CF));
    T(7==step(&cpu)); T(0x01 == cpu.regs[A]); T(flags(&cpu, NF));
    ok();
}

fn SUB_iHLIXIYi() void {
    start("SUB (HL/IX+d/IY+d)");
    const data = [_]u8 { 0x41, 0x61, 0x81 };
    const prog = [_]u8 {
        0x21, 0x00, 0x10,       // LD HL,0x1000
        0xDD, 0x21, 0x00, 0x10, // LD IX,0x1000
        0xFD, 0x21, 0x03, 0x10, // LD IY,0x1003
        0x3E, 0x00,             // LD A,0x00
        0x96,                   // SUB A,(HL)
        0xDD, 0x96, 0x01,       // SUB A,(IX+1)
        0xFD, 0x96, 0xFE,       // SUB A,(IY-2)
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(10==step(&cpu)); T(0x1000 == cpu.r16(HL));
    T(14==step(&cpu)); T(0x1000 == cpu.IX);
    T(14==step(&cpu)); T(0x1003 == cpu.IY);
    T(7 ==step(&cpu)); T(0x00 == cpu.regs[A]);
    T(7 ==step(&cpu)); T(0xBF == cpu.regs[A]); T(flags(&cpu, SF|HF|NF|CF));
    T(19==step(&cpu)); T(0x5E == cpu.regs[A]); T(flags(&cpu, VF|NF));
    T(19==step(&cpu)); T(0xFD == cpu.regs[A]); T(flags(&cpu, SF|NF|CF));
    ok();
}

fn SBC_rn() void {
    start("SBC rn");
    const prog = [_]u8 {
        0x3E, 0x04,     // LD A,0x04
        0x06, 0x01,     // LD B,0x01
        0x0E, 0xF8,     // LD C,0xF8
        0x16, 0x0F,     // LD D,0x0F
        0x1E, 0x79,     // LD E,0x79
        0x26, 0xC0,     // LD H,0xC0
        0x2E, 0xBF,     // LD L,0xBF
        0x97,           // SUB A,A
        0x98,           // SBC A,B
        0x99,           // SBC A,C
        0x9A,           // SBC A,D
        0x9B,           // SBC A,E
        0x9C,           // SBC A,H
        0x9D,           // SBC A,L
        0xDE, 0x01,     // SBC A,0x01
        0xDE, 0xFE,     // SBC A,0xFE
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 7); 
    T(4==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|NF));
    T(4==step(&cpu)); T(0xFF == cpu.regs[A]); T(flags(&cpu, SF|HF|NF|CF));
    T(4==step(&cpu)); T(0x06 == cpu.regs[A]); T(flags(&cpu, NF));
    T(4==step(&cpu)); T(0xF7 == cpu.regs[A]); T(flags(&cpu, SF|HF|NF|CF));
    T(4==step(&cpu)); T(0x7D == cpu.regs[A]); T(flags(&cpu, HF|VF|NF));
    T(4==step(&cpu)); T(0xBD == cpu.regs[A]); T(flags(&cpu, SF|VF|NF|CF));
    T(4==step(&cpu)); T(0xFD == cpu.regs[A]); T(flags(&cpu, SF|HF|NF|CF));
    T(7==step(&cpu)); T(0xFB == cpu.regs[A]); T(flags(&cpu, SF|NF));
    T(7==step(&cpu)); T(0xFD == cpu.regs[A]); T(flags(&cpu, SF|HF|NF|CF));
    ok();
}

fn SBC_iHLIXIYi() void {
    start("SBC (HL/IX+d/IY+d)");
    const data = [_]u8 { 0x41, 0x61, 0x81 };
    const prog = [_]u8 {
        0x21, 0x00, 0x10,       // LD HL,0x1000
        0xDD, 0x21, 0x00, 0x10, // LD IX,0x1000
        0xFD, 0x21, 0x03, 0x10, // LD IY,0x1003
        0x3E, 0x00,             // LD A,0x00
        0x9E,                   // SBC A,(HL)
        0xDD, 0x9E, 0x01,       // SBC A,(IX+1)
        0xFD, 0x9E, 0xFE,       // SBC A,(IY-2)
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(10==step(&cpu)); T(0x1000 == cpu.r16(HL));
    T(14==step(&cpu)); T(0x1000 == cpu.IX);
    T(14==step(&cpu)); T(0x1003 == cpu.IY);
    T(7 ==step(&cpu)); T(0x00 == cpu.regs[A]);
    T(7 ==step(&cpu)); T(0xBF == cpu.regs[A]); T(flags(&cpu, SF|HF|NF|CF));
    T(19==step(&cpu)); T(0x5D == cpu.regs[A]); T(flags(&cpu, VF|NF));
    T(19==step(&cpu)); T(0xFC == cpu.regs[A]); T(flags(&cpu, SF|NF|CF));
    ok();
}

fn CP_rn() void {
    start("CP rn");
    const prog = [_]u8 {
        0x3E, 0x04,     // LD A,0x04
        0x06, 0x05,     // LD B,0x05
        0x0E, 0x03,     // LD C,0x03
        0x16, 0xff,     // LD D,0xff
        0x1E, 0xaa,     // LD E,0xaa
        0x26, 0x80,     // LD H,0x80
        0x2E, 0x7f,     // LD L,0x7f
        0xBF,           // CP A
        0xB8,           // CP B
        0xB9,           // CP C
        0xBA,           // CP D
        0xBB,           // CP E
        0xBC,           // CP H
        0xBD,           // CP L
        0xFE, 0x04,     // CP 0x04
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(7==step(&cpu)); T(0x04 == cpu.regs[A]);
    T(7==step(&cpu)); T(0x05 == cpu.regs[B]);
    T(7==step(&cpu)); T(0x03 == cpu.regs[C]);
    T(7==step(&cpu)); T(0xff == cpu.regs[D]);
    T(7==step(&cpu)); T(0xaa == cpu.regs[E]);
    T(7==step(&cpu)); T(0x80 == cpu.regs[H]);
    T(7==step(&cpu)); T(0x7f == cpu.regs[L]);
    T(4==step(&cpu)); T(0x04 == cpu.regs[A]); T(flags(&cpu, ZF|NF));
    T(4==step(&cpu)); T(0x04 == cpu.regs[A]); T(flags(&cpu, SF|HF|NF|CF));
    T(4==step(&cpu)); T(0x04 == cpu.regs[A]); T(flags(&cpu, NF));
    T(4==step(&cpu)); T(0x04 == cpu.regs[A]); T(flags(&cpu, HF|NF|CF));
    T(4==step(&cpu)); T(0x04 == cpu.regs[A]); T(flags(&cpu, HF|NF|CF));
    T(4==step(&cpu)); T(0x04 == cpu.regs[A]); T(flags(&cpu, SF|VF|NF|CF));
    T(4==step(&cpu)); T(0x04 == cpu.regs[A]); T(flags(&cpu, SF|HF|NF|CF));
    T(7==step(&cpu)); T(0x04 == cpu.regs[A]); T(flags(&cpu, ZF|NF)) ;
    ok();
}

fn CP_iHLIXIYi() void {
    start("CP (HL/IX+d/IY+d)");
    const data = [_]u8 { 0x41, 0x61, 0x22 };
    const prog = [_]u8 {
        0x21, 0x00, 0x10,       // LD HL,0x1000
        0xDD, 0x21, 0x00, 0x10, // LD IX,0x1000
        0xFD, 0x21, 0x03, 0x10, // LD IY,0x1003
        0x3E, 0x41,             // LD A,0x41
        0xBE,                   // CP (HL)
        0xDD, 0xBE, 0x01,       // CP (IX+1)
        0xFD, 0xBE, 0xFF,       // CP (IY-1)
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(10==step(&cpu)); T(0x1000 == cpu.r16(HL));
    T(14==step(&cpu)); T(0x1000 == cpu.IX);
    T(14==step(&cpu)); T(0x1003 == cpu.IY);
    T(7 ==step(&cpu)); T(0x41 == cpu.regs[A]);
    T(7 ==step(&cpu)); T(0x41 == cpu.regs[A]); T(flags(&cpu, ZF|NF));
    T(19==step(&cpu)); T(0x41 == cpu.regs[A]); T(flags(&cpu, SF|NF|CF));
    T(19==step(&cpu)); T(0x41 == cpu.regs[A]); T(flags(&cpu, HF|NF));
    ok();
}

fn AND_rn() void {
    start("AND rn");
    const prog = [_]u8 {
        0x3E, 0xFF,             // LD A,0xFF
        0x06, 0x01,             // LD B,0x01
        0x0E, 0x03,             // LD C,0x02
        0x16, 0x04,             // LD D,0x04
        0x1E, 0x08,             // LD E,0x08
        0x26, 0x10,             // LD H,0x10
        0x2E, 0x20,             // LD L,0x20
        0xA0,                   // AND B
        0xF6, 0xFF,             // OR 0xFF
        0xA1,                   // AND C
        0xF6, 0xFF,             // OR 0xFF
        0xA2,                   // AND D
        0xF6, 0xFF,             // OR 0xFF
        0xA3,                   // AND E
        0xF6, 0xFF,             // OR 0xFF
        0xA4,                   // AND H
        0xF6, 0xFF,             // OR 0xFF
        0xA5,                   // AND L
        0xF6, 0xFF,             // OR 0xFF
        0xE6, 0x40,             // AND 0x40
        0xF6, 0xFF,             // OR 0xFF
        0xE6, 0xAA,             // AND 0xAA
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 7);
    T(4==step(&cpu)); T(0x01 == cpu.regs[A]); T(flags(&cpu, HF));
    T(7==step(&cpu)); T(0xFF == cpu.regs[A]); T(flags(&cpu, SF|PF));
    T(4==step(&cpu)); T(0x03 == cpu.regs[A]); T(flags(&cpu, HF|PF));
    T(7==step(&cpu)); T(0xFF == cpu.regs[A]); T(flags(&cpu, SF|PF));
    T(4==step(&cpu)); T(0x04 == cpu.regs[A]); T(flags(&cpu, HF));
    T(7==step(&cpu)); T(0xFF == cpu.regs[A]); T(flags(&cpu, SF|PF));
    T(4==step(&cpu)); T(0x08 == cpu.regs[A]); T(flags(&cpu, HF));
    T(7==step(&cpu)); T(0xFF == cpu.regs[A]); T(flags(&cpu, SF|PF));
    T(4==step(&cpu)); T(0x10 == cpu.regs[A]); T(flags(&cpu, HF));
    T(7==step(&cpu)); T(0xFF == cpu.regs[A]); T(flags(&cpu, SF|PF));
    T(4==step(&cpu)); T(0x20 == cpu.regs[A]); T(flags(&cpu, HF));
    T(7==step(&cpu)); T(0xFF == cpu.regs[A]); T(flags(&cpu, SF|PF));
    T(7==step(&cpu)); T(0x40 == cpu.regs[A]); T(flags(&cpu, HF));
    T(7==step(&cpu)); T(0xFF == cpu.regs[A]); T(flags(&cpu, SF|PF));
    T(7==step(&cpu)); T(0xAA == cpu.regs[A]); T(flags(&cpu, SF|HF|PF));    
    ok();
}

fn AND_iHLIXIYi() void {
    start("AND (HL/IX+d/IY+d)");
    const data = [_]u8 { 0xFE, 0xAA, 0x99 };
    const prog = [_]u8 {
        0x21, 0x00, 0x10,           // LD HL,0x1000
        0xDD, 0x21, 0x00, 0x10,     // LD IX,0x1000
        0xFD, 0x21, 0x03, 0x10,     // LD IY,0x1003
        0x3E, 0xFF,                 // LD A,0xFF
        0xA6,                       // AND (HL)
        0xDD, 0xA6, 0x01,           // AND (IX+1)
        0xFD, 0xA6, 0xFF,           // AND (IX-1)
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 4);
    T(7 ==step(&cpu)); T(0xFE == cpu.regs[A]); T(flags(&cpu, SF|HF));
    T(19==step(&cpu)); T(0xAA == cpu.regs[A]); T(flags(&cpu, SF|HF|PF));
    T(19==step(&cpu)); T(0x88 == cpu.regs[A]); T(flags(&cpu, SF|HF|PF));
    ok();
}

fn XOR_rn() void {
    start("XOR_rn");
    const prog = [_]u8 {
        0x97,           // SUB A
        0x06, 0x01,     // LD B,0x01
        0x0E, 0x03,     // LD C,0x03
        0x16, 0x07,     // LD D,0x07
        0x1E, 0x0F,     // LD E,0x0F
        0x26, 0x1F,     // LD H,0x1F
        0x2E, 0x3F,     // LD L,0x3F
        0xAF,           // XOR A
        0xA8,           // XOR B
        0xA9,           // XOR C
        0xAA,           // XOR D
        0xAB,           // XOR E
        0xAC,           // XOR H
        0xAD,           // XOR L
        0xEE, 0x7F,     // XOR 0x7F
        0xEE, 0xFF,     // XOR 0xFF       
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 7);
    T(4==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|PF));
    T(4==step(&cpu)); T(0x01 == cpu.regs[A]); T(flags(&cpu, 0));
    T(4==step(&cpu)); T(0x02 == cpu.regs[A]); T(flags(&cpu, 0));
    T(4==step(&cpu)); T(0x05 == cpu.regs[A]); T(flags(&cpu, PF));
    T(4==step(&cpu)); T(0x0A == cpu.regs[A]); T(flags(&cpu, PF));
    T(4==step(&cpu)); T(0x15 == cpu.regs[A]); T(flags(&cpu, 0));
    T(4==step(&cpu)); T(0x2A == cpu.regs[A]); T(flags(&cpu, 0));
    T(7==step(&cpu)); T(0x55 == cpu.regs[A]); T(flags(&cpu, PF));
    T(7==step(&cpu)); T(0xAA == cpu.regs[A]); T(flags(&cpu, SF|PF));     
    ok();
}

fn OR_rn() void {
    start("OR_rn");
    const prog = [_]u8 {
        0x97,           // SUB A
        0x06, 0x01,     // LD B,0x01
        0x0E, 0x02,     // LD C,0x02
        0x16, 0x04,     // LD D,0x04
        0x1E, 0x08,     // LD E,0x08
        0x26, 0x10,     // LD H,0x10
        0x2E, 0x20,     // LD L,0x20
        0xB7,           // OR A
        0xB0,           // OR B
        0xB1,           // OR C
        0xB2,           // OR D
        0xB3,           // OR E
        0xB4,           // OR H
        0xB5,           // OR L
        0xF6, 0x40,     // OR 0x40
        0xF6, 0x80,     // OR 0x80
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 7);
    T(4==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|PF));
    T(4==step(&cpu)); T(0x01 == cpu.regs[A]); T(flags(&cpu, 0));
    T(4==step(&cpu)); T(0x03 == cpu.regs[A]); T(flags(&cpu, PF));
    T(4==step(&cpu)); T(0x07 == cpu.regs[A]); T(flags(&cpu, 0));
    T(4==step(&cpu)); T(0x0F == cpu.regs[A]); T(flags(&cpu, PF));
    T(4==step(&cpu)); T(0x1F == cpu.regs[A]); T(flags(&cpu, 0));
    T(4==step(&cpu)); T(0x3F == cpu.regs[A]); T(flags(&cpu, PF));
    T(7==step(&cpu)); T(0x7F == cpu.regs[A]); T(flags(&cpu, 0));
    T(7==step(&cpu)); T(0xFF == cpu.regs[A]); T(flags(&cpu, SF|PF));
    ok();
}

fn OR_XOR_iHLIXIYi() void {
    start("OR/XOR (HL/IX+d/IY+d)");
    const data = [_]u8 { 0x41, 0x62, 0x84 };
    const prog = [_]u8 {
        0x3E, 0x00,                 // LD A,0x00
        0x21, 0x00, 0x10,           // LD HL,0x1000
        0xDD, 0x21, 0x00, 0x10,     // LD IX,0x1000
        0xFD, 0x21, 0x03, 0x10,     // LD IY,0x1003
        0xB6,                       // OR (HL)
        0xDD, 0xB6, 0x01,           // OR (IX+1)
        0xFD, 0xB6, 0xFF,           // OR (IY-1)
        0xAE,                       // XOR (HL)
        0xDD, 0xAE, 0x01,           // XOR (IX+1)
        0xFD, 0xAE, 0xFF,           // XOR (IY-1)
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();
    
    skip(&cpu, 4);
    T(7 ==step(&cpu)); T(0x41 == cpu.regs[A]); T(flags(&cpu, PF));
    T(19==step(&cpu)); T(0x63 == cpu.regs[A]); T(flags(&cpu, PF));
    T(19==step(&cpu)); T(0xE7 == cpu.regs[A]); T(flags(&cpu, SF|PF));
    T(7 ==step(&cpu)); T(0xA6 == cpu.regs[A]); T(flags(&cpu, SF|PF));
    T(19==step(&cpu)); T(0xC4 == cpu.regs[A]); T(flags(&cpu, SF));
    T(19==step(&cpu)); T(0x40 == cpu.regs[A]); T(flags(&cpu, 0));
    ok();
}

fn INC_DEC_r() void {
    start("INC/DEC r");
    const prog = [_]u8 {
        0x3e, 0x00,         // LD A,0x00
        0x06, 0xFF,         // LD B,0xFF
        0x0e, 0x0F,         // LD C,0x0F
        0x16, 0x0E,         // LD D,0x0E
        0x1E, 0x7F,         // LD E,0x7F
        0x26, 0x3E,         // LD H,0x3E
        0x2E, 0x23,         // LD L,0x23
        0x3C,               // INC A
        0x3D,               // DEC A
        0x04,               // INC B
        0x05,               // DEC B
        0x0C,               // INC C
        0x0D,               // DEC C
        0x14,               // INC D
        0x15,               // DEC D
        0xFE, 0x01,         // CP 0x01  // set carry flag (should be preserved)
        0x1C,               // INC E
        0x1D,               // DEC E
        0x24,               // INC H
        0x25,               // DEC H
        0x2C,               // INC L
        0x2D,               // DEC L
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 7);
    T(0x00 == cpu.regs[A]);
    T(0xFF == cpu.regs[B]);
    T(0x0F == cpu.regs[C]);
    T(0x0E == cpu.regs[D]);
    T(0x7F == cpu.regs[E]);
    T(0x3E == cpu.regs[H]);
    T(0x23 == cpu.regs[L]);
    T(4==step(&cpu)); T(0x01 == cpu.regs[A]); T(flags(&cpu, 0));
    T(4==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|NF));
    T(4==step(&cpu)); T(0x00 == cpu.regs[B]); T(flags(&cpu, ZF|HF));
    T(4==step(&cpu)); T(0xFF == cpu.regs[B]); T(flags(&cpu, SF|HF|NF));
    T(4==step(&cpu)); T(0x10 == cpu.regs[C]); T(flags(&cpu, HF));
    T(4==step(&cpu)); T(0x0F == cpu.regs[C]); T(flags(&cpu, HF|NF));
    T(4==step(&cpu)); T(0x0F == cpu.regs[D]); T(flags(&cpu, 0));
    T(4==step(&cpu)); T(0x0E == cpu.regs[D]); T(flags(&cpu, NF));
    T(7==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, SF|HF|NF|CF));
    T(4==step(&cpu)); T(0x80 == cpu.regs[E]); T(flags(&cpu, SF|HF|VF|CF));
    T(4==step(&cpu)); T(0x7F == cpu.regs[E]); T(flags(&cpu, HF|VF|NF|CF));
    T(4==step(&cpu)); T(0x3F == cpu.regs[H]); T(flags(&cpu, CF));
    T(4==step(&cpu)); T(0x3E == cpu.regs[H]); T(flags(&cpu, NF|CF));
    T(4==step(&cpu)); T(0x24 == cpu.regs[L]); T(flags(&cpu, CF));
    T(4==step(&cpu)); T(0x23 == cpu.regs[L]); T(flags(&cpu, NF|CF));
    ok();
}

fn INC_DEC_iHLIXIYi() void {
    start("INC/DEC (HL/IX+d/IY+d)");
    const data = [_]u8 { 0x00, 0x3F, 0x7F };
    const prog = [_]u8 {
        0x21, 0x00, 0x10,           // LD HL,0x1000
        0xDD, 0x21, 0x00, 0x10,     // LD IX,0x1000
        0xFD, 0x21, 0x03, 0x10,     // LD IY,0x1003
        0x35,                       // DEC (HL)
        0x34,                       // INC (HL)
        0xDD, 0x34, 0x01,           // INC (IX+1)
        0xDD, 0x35, 0x01,           // DEC (IX+1)
        0xFD, 0x34, 0xFF,           // INC (IY-1)
        0xFD, 0x35, 0xFF,           // DEC (IY-1)
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 3);
    T(11==step(&cpu)); T(0xFF == mem[0x1000]); T(flags(&cpu, SF|HF|NF));
    T(11==step(&cpu)); T(0x00 == mem[0x1000]); T(flags(&cpu, ZF|HF));
    T(23==step(&cpu)); T(0x40 == mem[0x1001]); T(flags(&cpu, HF));
    T(23==step(&cpu)); T(0x3F == mem[0x1001]); T(flags(&cpu, HF|NF));
    T(23==step(&cpu)); T(0x80 == mem[0x1002]); T(flags(&cpu, SF|HF|VF));
    T(23==step(&cpu)); T(0x7F == mem[0x1002]); T(flags(&cpu, HF|PF|NF));
    ok();
}

fn INC_DEC_ssIXIY() void {
    start("INC/DEC ss/IX/IY");
    const prog = [_]u8 {
        0x01, 0x00, 0x00,       // LD BC,0x0000
        0x11, 0xFF, 0xFF,       // LD DE,0xffff
        0x21, 0xFF, 0x00,       // LD HL,0x00ff
        0x31, 0x11, 0x11,       // LD SP,0x1111
        0xDD, 0x21, 0xFF, 0x0F, // LD IX,0x0fff
        0xFD, 0x21, 0x34, 0x12, // LD IY,0x1234
        0x0B,                   // DEC BC
        0x03,                   // INC BC
        0x13,                   // INC DE
        0x1B,                   // DEC DE
        0x23,                   // INC HL
        0x2B,                   // DEC HL
        0x33,                   // INC SP
        0x3B,                   // DEC SP
        0xDD, 0x23,             // INC IX
        0xDD, 0x2B,             // DEC IX
        0xFD, 0x23,             // INC IX
        0xFD, 0x2B,             // DEC IX
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 6);
    T(6 ==step(&cpu)); T(0xFFFF == cpu.r16(BC));
    T(6 ==step(&cpu)); T(0x0000 == cpu.r16(BC));
    T(6 ==step(&cpu)); T(0x0000 == cpu.r16(DE));
    T(6 ==step(&cpu)); T(0xFFFF == cpu.r16(DE));
    T(6 ==step(&cpu)); T(0x0100 == cpu.r16(HL));
    T(6 ==step(&cpu)); T(0x00FF == cpu.r16(HL));
    T(6 ==step(&cpu)); T(0x1112 == cpu.SP);
    T(6 ==step(&cpu)); T(0x1111 == cpu.SP);
    T(10==step(&cpu)); T(0x1000 == cpu.IX);
    T(10==step(&cpu)); T(0x0FFF == cpu.IX);
    T(10==step(&cpu)); T(0x1235 == cpu.IY);
    T(10==step(&cpu)); T(0x1234 == cpu.IY);
    ok();
}

fn RLCA_RLA_RRCA_RRA() void {
    start("RLCA/RLA/RRCA/RRA");
    const prog = [_]u8 {
        0x3E, 0xA0,     // LD A,0xA0
        0x07,           // RLCA
        0x07,           // RLCA
        0x0F,           // RRCA
        0x0F,           // RRCA
        0x17,           // RLA
        0x17,           // RLA
        0x1F,           // RRA
        0x1F,           // RRA
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();
    cpu.regs[F] = 0xFF;

    T(7==step(&cpu)); T(0xA0 == cpu.regs[A]);
    T(4==step(&cpu)); T(0x41 == cpu.regs[A]); T(flags(&cpu, SF|ZF|VF|CF));
    T(4==step(&cpu)); T(0x82 == cpu.regs[A]); T(flags(&cpu, SF|ZF|VF));
    T(4==step(&cpu)); T(0x41 == cpu.regs[A]); T(flags(&cpu, SF|ZF|VF));
    T(4==step(&cpu)); T(0xA0 == cpu.regs[A]); T(flags(&cpu, SF|ZF|VF|CF));
    T(4==step(&cpu)); T(0x41 == cpu.regs[A]); T(flags(&cpu, SF|ZF|VF|CF));
    T(4==step(&cpu)); T(0x83 == cpu.regs[A]); T(flags(&cpu, SF|ZF|VF));
    T(4==step(&cpu)); T(0x41 == cpu.regs[A]); T(flags(&cpu, SF|ZF|VF|CF));
    T(4==step(&cpu)); T(0xA0 == cpu.regs[A]); T(flags(&cpu, SF|ZF|VF|CF));
    ok();
}

fn RLC_RL_RRC_RR_r() void {
    start("RLC/RL/RRC/RR r");
    const prog = [_]u8 {
        0x3E, 0x01,     // LD A,0x01
        0x06, 0xFF,     // LD B,0xFF
        0x0E, 0x03,     // LD C,0x03
        0x16, 0xFE,     // LD D,0xFE
        0x1E, 0x11,     // LD E,0x11
        0x26, 0x3F,     // LD H,0x3F
        0x2E, 0x70,     // LD L,0x70

        0xCB, 0x0F,     // RRC A
        0xCB, 0x07,     // RLC A
        0xCB, 0x08,     // RRC B
        0xCB, 0x00,     // RLC B
        0xCB, 0x01,     // RLC C
        0xCB, 0x09,     // RRC C
        0xCB, 0x02,     // RLC D
        0xCB, 0x0A,     // RRC D
        0xCB, 0x0B,     // RRC E
        0xCB, 0x03,     // RLC E
        0xCB, 0x04,     // RLC H
        0xCB, 0x0C,     // RCC H
        0xCB, 0x05,     // RLC L
        0xCB, 0x0D,     // RRC L

        0xCB, 0x1F,     // RR A
        0xCB, 0x17,     // RL A
        0xCB, 0x18,     // RR B
        0xCB, 0x10,     // RL B
        0xCB, 0x11,     // RL C
        0xCB, 0x19,     // RR C
        0xCB, 0x12,     // RL D
        0xCB, 0x1A,     // RR D
        0xCB, 0x1B,     // RR E
        0xCB, 0x13,     // RL E
        0xCB, 0x14,     // RL H
        0xCB, 0x1C,     // RR H
        0xCB, 0x15,     // RL L
        0xCB, 0x1D,     // RR L
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 7);
    T(8==step(&cpu)); T(0x80 == cpu.regs[A]); T(flags(&cpu, SF|CF));
    T(8==step(&cpu)); T(0x01 == cpu.regs[A]); T(flags(&cpu, CF));
    T(8==step(&cpu)); T(0xFF == cpu.regs[B]); T(flags(&cpu, SF|PF|CF));
    T(8==step(&cpu)); T(0xFF == cpu.regs[B]); T(flags(&cpu, SF|PF|CF));
    T(8==step(&cpu)); T(0x06 == cpu.regs[C]); T(flags(&cpu, PF));
    T(8==step(&cpu)); T(0x03 == cpu.regs[C]); T(flags(&cpu, PF));
    T(8==step(&cpu)); T(0xFD == cpu.regs[D]); T(flags(&cpu, SF|CF));
    T(8==step(&cpu)); T(0xFE == cpu.regs[D]); T(flags(&cpu, SF|CF));
    T(8==step(&cpu)); T(0x88 == cpu.regs[E]); T(flags(&cpu, SF|PF|CF));
    T(8==step(&cpu)); T(0x11 == cpu.regs[E]); T(flags(&cpu, PF|CF));
    T(8==step(&cpu)); T(0x7E == cpu.regs[H]); T(flags(&cpu, PF));
    T(8==step(&cpu)); T(0x3F == cpu.regs[H]); T(flags(&cpu, PF));
    T(8==step(&cpu)); T(0xE0 == cpu.regs[L]); T(flags(&cpu, SF));
    T(8==step(&cpu)); T(0x70 == cpu.regs[L]); T(flags(&cpu, 0));
    T(8==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|PF|CF));
    T(8==step(&cpu)); T(0x01 == cpu.regs[A]); T(flags(&cpu, 0));
    T(8==step(&cpu)); T(0x7F == cpu.regs[B]); T(flags(&cpu, CF));
    T(8==step(&cpu)); T(0xFF == cpu.regs[B]); T(flags(&cpu, SF|PF));
    T(8==step(&cpu)); T(0x06 == cpu.regs[C]); T(flags(&cpu, PF));
    T(8==step(&cpu)); T(0x03 == cpu.regs[C]); T(flags(&cpu, PF));
    T(8==step(&cpu)); T(0xFC == cpu.regs[D]); T(flags(&cpu, SF|PF|CF));
    T(8==step(&cpu)); T(0xFE == cpu.regs[D]); T(flags(&cpu, SF));
    T(8==step(&cpu)); T(0x08 == cpu.regs[E]); T(flags(&cpu, CF));
    T(8==step(&cpu)); T(0x11 == cpu.regs[E]); T(flags(&cpu, PF));
    T(8==step(&cpu)); T(0x7E == cpu.regs[H]); T(flags(&cpu, PF));
    T(8==step(&cpu)); T(0x3F == cpu.regs[H]); T(flags(&cpu, PF));
    T(8==step(&cpu)); T(0xE0 == cpu.regs[L]); T(flags(&cpu, SF));
    T(8==step(&cpu)); T(0x70 == cpu.regs[L]); T(flags(&cpu, 0));
    ok();
}

fn RRC_RLC_RR_RL_iHLIXIYi() void {
    start("RRC/RLC/RR/RL (HL/IX+d/IY+d)");
    const data = [_]u8{ 0x01, 0xFF, 0x11 };
    const prog = [_]u8 {
        0x21, 0x00, 0x10,           // LD HL,0x1000
        0xDD, 0x21, 0x00, 0x10,     // LD IX,0x1001
        0xFD, 0x21, 0x03, 0x10,     // LD IY,0x1003
        0xCB, 0x0E,                 // RRC (HL)
        0x7E,                       // LD A,(HL)
        0xCB, 0x06,                 // RLC (HL)
        0x7E,                       // LD A,(HL)
        0xDD, 0xCB, 0x01, 0x0E,     // RRC (IX+1)
        0xDD, 0x7E, 0x01,           // LD A,(IX+1)
        0xDD, 0xCB, 0x01, 0x06,     // RLC (IX+1)
        0xDD, 0x7E, 0x01,           // LD A,(IX+1)
        0xFD, 0xCB, 0xFF, 0x0E,     // RRC (IY-1)
        0xFD, 0x7E, 0xFF,           // LD A,(IY-1)
        0xFD, 0xCB, 0xFF, 0x06,     // RLC (IY-1)
        0xFD, 0x7E, 0xFF,           // LD A,(IY-1)
        0xCB, 0x1E,                 // RR (HL)
        0x7E,                       // LD A,(HL)
        0xCB, 0x16,                 // RL (HL)
        0x7E,                       // LD A,(HL)
        0xDD, 0xCB, 0x01, 0x1E,     // RR (IX+1)
        0xDD, 0x7E, 0x01,           // LD A,(IX+1)
        0xDD, 0xCB, 0x01, 0x16,     // RL (IX+1)
        0xDD, 0x7E, 0x01,           // LD A,(IX+1)
        0xFD, 0xCB, 0xFF, 0x16,     // RL (IY-1)
        0xFD, 0x7E, 0xFF,           // LD A,(IY-1)
        0xFD, 0xCB, 0xFF, 0x1E,     // RR (IY-1)
        0xFD, 0x7E, 0xFF,           // LD A,(IY-1)
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();
    
    skip(&cpu, 3);
    T(15==step(&cpu)); T(0x80 == mem[0x1000]); T(flags(&cpu, SF|CF));
    T(7 ==step(&cpu)); T(0x80 == cpu.regs[A]);
    T(15==step(&cpu)); T(0x01 == mem[0x1000]); T(flags(&cpu, CF));
    T(7 ==step(&cpu)); T(0x01 == cpu.regs[A]);
    T(23==step(&cpu)); T(0xFF == mem[0x1001]); T(flags(&cpu, SF|PF|CF));
    T(19==step(&cpu)); T(0xFF == cpu.regs[A]);
    T(23==step(&cpu)); T(0xFF == mem[0x1001]); T(flags(&cpu, SF|PF|CF));
    T(19==step(&cpu)); T(0xFF == cpu.regs[A]);
    T(23==step(&cpu)); T(0x88 == mem[0x1002]); T(flags(&cpu, SF|PF|CF));
    T(19==step(&cpu)); T(0x88 == cpu.regs[A]);
    T(23==step(&cpu)); T(0x11 == mem[0x1002]); T(flags(&cpu, PF|CF));
    T(19==step(&cpu)); T(0x11 == cpu.regs[A]);
    T(15==step(&cpu)); T(0x80 == mem[0x1000]); T(flags(&cpu, SF|CF));
    T(7 ==step(&cpu)); T(0x80 == cpu.regs[A]);
    T(15==step(&cpu)); T(0x01 == mem[0x1000]); T(flags(&cpu, CF));
    T(7 ==step(&cpu)); T(0x01 == cpu.regs[A]);
    T(23==step(&cpu)); T(0xFF == mem[0x1001]); T(flags(&cpu, SF|PF|CF));
    T(19==step(&cpu)); T(0xFF == cpu.regs[A]);
    T(23==step(&cpu)); T(0xFF == mem[0x1001]); T(flags(&cpu, SF|PF|CF));
    T(19==step(&cpu)); T(0xFF == cpu.regs[A]);
    T(23==step(&cpu)); T(0x23 == mem[0x1002]); T(flags(&cpu, 0));
    T(19==step(&cpu)); T(0x23 == cpu.regs[A]);
    T(23==step(&cpu)); T(0x11 == mem[0x1002]); T(flags(&cpu, PF|CF));
    T(19==step(&cpu)); T(0x11 == cpu.regs[A]);
    ok();
}

fn SLA_r() void {
    start("SLA_r");
    const prog = [_]u8 {
        0x3E, 0x01,         // LD A,0x01
        0x06, 0x80,         // LD B,0x80
        0x0E, 0xAA,         // LD C,0xAA
        0x16, 0xFE,         // LD D,0xFE
        0x1E, 0x7F,         // LD E,0x7F
        0x26, 0x11,         // LD H,0x11
        0x2E, 0x00,         // LD L,0x00
        0xCB, 0x27,         // SLA A
        0xCB, 0x20,         // SLA B
        0xCB, 0x21,         // SLA C
        0xCB, 0x22,         // SLA D
        0xCB, 0x23,         // SLA E
        0xCB, 0x24,         // SLA H
        0xCB, 0x25,         // SLA L
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 7);
    T(8==step(&cpu)); T(0x02 == cpu.regs[A]); T(flags(&cpu, 0));
    T(8==step(&cpu)); T(0x00 == cpu.regs[B]); T(flags(&cpu, ZF|PF|CF));
    T(8==step(&cpu)); T(0x54 == cpu.regs[C]); T(flags(&cpu, CF));
    T(8==step(&cpu)); T(0xFC == cpu.regs[D]); T(flags(&cpu, SF|PF|CF));
    T(8==step(&cpu)); T(0xFE == cpu.regs[E]); T(flags(&cpu, SF));
    T(8==step(&cpu)); T(0x22 == cpu.regs[H]); T(flags(&cpu, PF));
    T(8==step(&cpu)); T(0x00 == cpu.regs[L]); T(flags(&cpu, ZF|PF));
    ok();
}

fn SLA_iHLIXIYi() void {
    start("SLA (HL/IX+d/IY+d)");
    const data = [_]u8 { 0x01, 0x80, 0xAA };
    const prog = [_]u8 {
        0x21, 0x00, 0x10,           // LD HL,0x1000
        0xDD, 0x21, 0x00, 0x10,     // LD IX,0x1001
        0xFD, 0x21, 0x03, 0x10,     // LD IY,0x1003
        0xCB, 0x26,                 // SLA (HL)
        0x7E,                       // LD A,(HL)
        0xDD, 0xCB, 0x01, 0x26,     // SLA (IX+1)
        0xDD, 0x7E, 0x01,           // LD A,(IX+1)
        0xFD, 0xCB, 0xFF, 0x26,     // SLA (IY-1)
        0xFD, 0x7E, 0xFF,           // LD A,(IY-1)
    };
    copy(0x1000, &data);
    copy(0x000, &prog);
    var cpu = makeCPU();
    
    skip(&cpu, 3);
    T(15==step(&cpu)); T(0x02 == mem[0x1000]); T(flags(&cpu, 0));
    T(7 ==step(&cpu)); T(0x02 == cpu.regs[A]);
    T(23==step(&cpu)); T(0x00 == mem[0x1001]); T(flags(&cpu, ZF|PF|CF));
    T(19==step(&cpu)); T(0x00 == cpu.regs[A]);
    T(23==step(&cpu)); T(0x54 == mem[0x1002]); T(flags(&cpu, CF));
    T(19==step(&cpu)); T(0x54 == cpu.regs[A]);
    ok();
}

fn SRA_r() void {
    start("SRA r");
    const prog = [_]u8 {
        0x3E, 0x01,         // LD A,0x01
        0x06, 0x80,         // LD B,0x80
        0x0E, 0xAA,         // LD C,0xAA
        0x16, 0xFE,         // LD D,0xFE
        0x1E, 0x7F,         // LD E,0x7F
        0x26, 0x11,         // LD H,0x11
        0x2E, 0x00,         // LD L,0x00
        0xCB, 0x2F,         // SRA A
        0xCB, 0x28,         // SRA B
        0xCB, 0x29,         // SRA C
        0xCB, 0x2A,         // SRA D
        0xCB, 0x2B,         // SRA E
        0xCB, 0x2C,         // SRA H
        0xCB, 0x2D,         // SRA L
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();
    
    skip(&cpu, 7);
    T(8==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|PF|CF));
    T(8==step(&cpu)); T(0xC0 == cpu.regs[B]); T(flags(&cpu, SF|PF));
    T(8==step(&cpu)); T(0xD5 == cpu.regs[C]); T(flags(&cpu, SF));
    T(8==step(&cpu)); T(0xFF == cpu.regs[D]); T(flags(&cpu, SF|PF));
    T(8==step(&cpu)); T(0x3F == cpu.regs[E]); T(flags(&cpu, PF|CF));
    T(8==step(&cpu)); T(0x08 == cpu.regs[H]); T(flags(&cpu, CF));
    T(8==step(&cpu)); T(0x00 == cpu.regs[L]); T(flags(&cpu, ZF|PF));
    ok();
}

fn SRA_iHLIXIYi() void {
    start("SRA (HL/IX+d/IY+d)");
    const data = [_]u8 { 0x01, 0x80, 0xAA };
    const prog = [_]u8 {
        0x21, 0x00, 0x10,           // LD HL,0x1000
        0xDD, 0x21, 0x00, 0x10,     // LD IX,0x1001
        0xFD, 0x21, 0x03, 0x10,     // LD IY,0x1003
        0xCB, 0x2E,                 // SRA (HL)
        0x7E,                       // LD A,(HL)
        0xDD, 0xCB, 0x01, 0x2E,     // SRA (IX+1)
        0xDD, 0x7E, 0x01,           // LD A,(IX+1)
        0xFD, 0xCB, 0xFF, 0x2E,     // SRA (IY-1)
        0xFD, 0x7E, 0xFF,           // LD A,(IY-1)
    };
    copy(0x1000, &data);
    copy(0x000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 3);
    T(15==step(&cpu)); T(0x00 == mem[0x1000]); T(flags(&cpu, ZF|PF|CF));
    T(7 ==step(&cpu)); T(0x00 == cpu.regs[A]);
    T(23==step(&cpu)); T(0xC0 == mem[0x1001]); T(flags(&cpu, SF|PF));
    T(19==step(&cpu)); T(0xC0 == cpu.regs[A]);
    T(23==step(&cpu)); T(0xD5 == mem[0x1002]); T(flags(&cpu, SF));
    T(19==step(&cpu)); T(0xD5 == cpu.regs[A]);
    ok();
}

fn SRL_r() void {
    start("SRL r");
    const prog = [_]u8 {
        0x3E, 0x01,         // LD A,0x01
        0x06, 0x80,         // LD B,0x80
        0x0E, 0xAA,         // LD C,0xAA
        0x16, 0xFE,         // LD D,0xFE
        0x1E, 0x7F,         // LD E,0x7F
        0x26, 0x11,         // LD H,0x11
        0x2E, 0x00,         // LD L,0x00
        0xCB, 0x3F,         // SRL A
        0xCB, 0x38,         // SRL B
        0xCB, 0x39,         // SRL C
        0xCB, 0x3A,         // SRL D
        0xCB, 0x3B,         // SRL E
        0xCB, 0x3C,         // SRL H
        0xCB, 0x3D,         // SRL L
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 7);
    T(8==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|PF|CF));
    T(8==step(&cpu)); T(0x40 == cpu.regs[B]); T(flags(&cpu, 0));
    T(8==step(&cpu)); T(0x55 == cpu.regs[C]); T(flags(&cpu, PF));
    T(8==step(&cpu)); T(0x7F == cpu.regs[D]); T(flags(&cpu, 0));
    T(8==step(&cpu)); T(0x3F == cpu.regs[E]); T(flags(&cpu, PF|CF));
    T(8==step(&cpu)); T(0x08 == cpu.regs[H]); T(flags(&cpu, CF));
    T(8==step(&cpu)); T(0x00 == cpu.regs[L]); T(flags(&cpu, ZF|PF));
    ok();
}

fn SRL_iHLIXIYi() void {
    start("SRL (HL/IX+d/IY+d)");
    const data = [_]u8 { 0x01, 0x80, 0xAA };
    const prog = [_]u8 {
        0x21, 0x00, 0x10,           // LD HL,0x1000
        0xDD, 0x21, 0x00, 0x10,     // LD IX,0x1001
        0xFD, 0x21, 0x03, 0x10,     // LD IY,0x1003
        0xCB, 0x3E,                 // SRL (HL)
        0x7E,                       // LD A,(HL)
        0xDD, 0xCB, 0x01, 0x3E,     // SRL (IX+1)
        0xDD, 0x7E, 0x01,           // LD A,(IX+1)
        0xFD, 0xCB, 0xFF, 0x3E,     // SRL (IY-1)
        0xFD, 0x7E, 0xFF,           // LD A,(IY-1)
    };
    copy(0x1000, &data);
    copy(0x000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 3);
    T(15==step(&cpu)); T(0x00 == mem[0x1000]); T(flags(&cpu, ZF|PF|CF));
    T(7 ==step(&cpu)); T(0x00 == cpu.regs[A]);
    T(23==step(&cpu)); T(0x40 == mem[0x1001]); T(flags(&cpu, 0));
    T(19==step(&cpu)); T(0x40 == cpu.regs[A]);
    T(23==step(&cpu)); T(0x55 == mem[0x1002]); T(flags(&cpu, PF));
    T(19==step(&cpu)); T(0x55 == cpu.regs[A]);
    ok();
}

fn RLD_RRD() void {
    start("RLD/RRD");
    const prog = [_]u8 {
        0x3E, 0x12,         // LD A,0x12
        0x21, 0x00, 0x10,   // LD HL,0x1000
        0x36, 0x34,         // LD (HL),0x34
        0xED, 0x67,         // RRD
        0xED, 0x6F,         // RLD
        0x7E,               // LD A,(HL)
        0x3E, 0xFE,         // LD A,0xFE
        0x36, 0x00,         // LD (HL),0x00
        0xED, 0x6F,         // RLD
        0xED, 0x67,         // RRD
        0x7E,               // LD A,(HL)
        0x3E, 0x01,         // LD A,0x01
        0x36, 0x00,         // LD (HL),0x00
        0xED, 0x6F,         // RLD
        0xED, 0x67,         // RRD
        0x7E
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();
    
    T(7 ==step(&cpu)); T(0x12 == cpu.regs[A]);
    T(10==step(&cpu)); T(0x1000 == cpu.r16(HL));
    T(10==step(&cpu)); T(0x34 == mem[0x1000]);
    T(18==step(&cpu)); T(0x14 == cpu.regs[A]); T(0x23 == mem[0x1000]); T(0x1001 == cpu.WZ);
    T(18==step(&cpu)); T(0x12 == cpu.regs[A]); T(0x34 == mem[0x1000]); T(0x1001 == cpu.WZ);
    T(7 ==step(&cpu)); T(0x34 == cpu.regs[A]);
    T(7 ==step(&cpu)); T(0xFE == cpu.regs[A]);
    T(10==step(&cpu)); T(0x00 == mem[0x1000]);
    T(18==step(&cpu)); T(0xF0 == cpu.regs[A]); T(0x0E == mem[0x1000]); T(flags(&cpu, SF|PF)); T(0x1001 == cpu.WZ);
    T(18==step(&cpu)); T(0xFE == cpu.regs[A]); T(0x00 == mem[0x1000]); T(flags(&cpu, SF)); T(0x1001 == cpu.WZ);
    T(7 ==step(&cpu)); T(0x00 == cpu.regs[A]);
    T(7 ==step(&cpu)); T(0x01 == cpu.regs[A]);
    T(10==step(&cpu)); T(0x00 == mem[0x1000]);
    cpu.regs[F] |= CF;
    T(18==step(&cpu)); T(0x00 == cpu.regs[A]); T(0x01 == mem[0x1000]); T(flags(&cpu, ZF|PF|CF)); T(0x1001 == cpu.WZ);
    T(18==step(&cpu)); T(0x01 == cpu.regs[A]); T(0x00 == mem[0x1000]); T(flags(&cpu, CF)); T(0x1001 == cpu.WZ);
    T(7 ==step(&cpu)); T(0x00 == cpu.regs[A]);
    ok();
}

fn HALTx() void {
    start("HALT");
    const prog = [_]u8 {
        0x76,       // HALT
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();
    T(4==step(&cpu)); T(0x0000 == cpu.PC); T(0 != (cpu.pins & HALT));
    T(4==step(&cpu)); T(0x0000 == cpu.PC); T(0 != (cpu.pins & HALT));
    T(4==step(&cpu)); T(0x0000 == cpu.PC); T(0 != (cpu.pins & HALT));
    ok();
}

fn BIT() void {
    start("BIT");
    // FIXME only test cycle count for now
    const prog = [_]u8 {
        0xCB, 0x47,             // BIT 0,A
        0xCB, 0x46,             // BIT 0,(HL)
        0xDD, 0xCB, 0x01, 0x46, // BIT 0,(IX+1)
        0xFD, 0xCB, 0xFF, 0x46, // BIT 0,(IY-1)
        0xDD, 0xCB, 0x02, 0x47, // undocumented: BIT 0,(IX+2),A
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(8 ==step(&cpu));
    T(12==step(&cpu));
    T(20==step(&cpu));
    T(20==step(&cpu));
    T(20==step(&cpu));
    ok();
}

fn SET() void {
    start("SET");
    // FIXME only test cycle count for now 
    const prog = [_]u8 {
        0xCB, 0xC7,             // SET 0,A
        0xCB, 0xC6,             // SET 0,(HL)
        0xDD, 0xCB, 0x01, 0xC6, // SET 0,(IX+1)
        0xFD, 0xCB, 0xFF, 0xC6, // SET 0,(IY-1)
        0xDD, 0xCB, 0x02, 0xC7, // undocumented: SET 0,(IX+2),A
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();
    
    T(8 ==step(&cpu));
    T(15==step(&cpu));
    T(23==step(&cpu));
    T(23==step(&cpu));
    T(23==step(&cpu));
    ok();
}

fn RES() void {
    start("RES");
    // FIXME only test cycle count for now
    const prog = [_]u8 {
        0xCB, 0x87,             // RES 0,A
        0xCB, 0x86,             // RES 0,(HL)
        0xDD, 0xCB, 0x01, 0x86, // RES 0,(IX+1)
        0xFD, 0xCB, 0xFF, 0x86, // RES 0,(IY-1)
        0xDD, 0xCB, 0x02, 0x87, // undocumented: RES 0,(IX+2),A
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(8 ==step(&cpu));
    T(15==step(&cpu));
    T(23==step(&cpu));
    T(23==step(&cpu));
    T(23==step(&cpu));
    ok();
}

fn DAA() void {
    start("DAA");
    const prog = [_]u8 {
        0x3e, 0x15,         // ld a,0x15
        0x06, 0x27,         // ld b,0x27
        0x80,               // add a,b
        0x27,               // daa
        0x90,               // sub b
        0x27,               // daa
        0x3e, 0x90,         // ld a,0x90
        0x06, 0x15,         // ld b,0x15
        0x80,               // add a,b
        0x27,               // daa
        0x90,               // sub b
        0x27                // daa
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(7==step(&cpu)); T(0x15 == cpu.regs[A]);
    T(7==step(&cpu)); T(0x27 == cpu.regs[B]);
    T(4==step(&cpu)); T(0x3C == cpu.regs[A]); T(flags(&cpu, 0));
    T(4==step(&cpu)); T(0x42 == cpu.regs[A]); T(flags(&cpu, HF|PF));
    T(4==step(&cpu)); T(0x1B == cpu.regs[A]); T(flags(&cpu, HF|NF));
    T(4==step(&cpu)); T(0x15 == cpu.regs[A]); T(flags(&cpu, NF));
    T(7==step(&cpu)); T(0x90 == cpu.regs[A]); T(flags(&cpu, NF));
    T(7==step(&cpu)); T(0x15 == cpu.regs[B]); T(flags(&cpu, NF));
    T(4==step(&cpu)); T(0xA5 == cpu.regs[A]); T(flags(&cpu, SF));
    T(4==step(&cpu)); T(0x05 == cpu.regs[A]); T(flags(&cpu, PF|CF));
    T(4==step(&cpu)); T(0xF0 == cpu.regs[A]); T(flags(&cpu, SF|NF|CF));
    T(4==step(&cpu)); T(0x90 == cpu.regs[A]); T(flags(&cpu, SF|PF|NF|CF));
    ok();
}

fn CPL() void {
    start("CPL");
    const prog = [_]u8 {
        0x97,               // SUB A
        0x2F,               // CPL
        0x2F,               // CPL
        0xC6, 0xAA,         // ADD A,0xAA
        0x2F,               // CPL
        0x2F,               // CPL
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(4==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|NF));
    T(4==step(&cpu)); T(0xFF == cpu.regs[A]); T(flags(&cpu, ZF|HF|NF));
    T(4==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|HF|NF));
    T(7==step(&cpu)); T(0xAA == cpu.regs[A]); T(flags(&cpu, SF));
    T(4==step(&cpu)); T(0x55 == cpu.regs[A]); T(flags(&cpu, SF|HF|NF));
    T(4==step(&cpu)); T(0xAA == cpu.regs[A]); T(flags(&cpu, SF|HF|NF));
    ok();
}

fn CCF_SCF() void {
    start("CCF/SCF");
    const prog = [_]u8{
        0x97,           // SUB A
        0x37,           // SCF
        0x3F,           // CCF
        0xD6, 0xCC,     // SUB 0xCC
        0x3F,           // CCF
        0x37,           // SCF
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();
    
    T(4==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|NF));
    T(4==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|CF));
    T(4==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|HF));
    T(7==step(&cpu)); T(0x34 == cpu.regs[A]); T(flags(&cpu, HF|NF|CF));
    T(4==step(&cpu)); T(0x34 == cpu.regs[A]); T(flags(&cpu, HF));
    T(4==step(&cpu)); T(0x34 == cpu.regs[A]); T(flags(&cpu, CF));
    ok();
}

fn NEG() void {
    start("NEG");
    const prog = [_]u8 {
        0x3E, 0x01,         // LD A,0x01
        0xED, 0x44,         // NEG
        0xC6, 0x01,         // ADD A,0x01
        0xED, 0x44,         // NEG
        0xD6, 0x80,         // SUB A,0x80
        0xED, 0x44,         // NEG
        0xC6, 0x40,         // ADD A,0x40
        0xED, 0x44,         // NEG
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();

    T(7==step(&cpu)); T(0x01 == cpu.regs[A]);
    T(8==step(&cpu)); T(0xFF == cpu.regs[A]); T(flags(&cpu, SF|HF|NF|CF));
    T(7==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|HF|CF));
    T(8==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|NF));
    T(7==step(&cpu)); T(0x80 == cpu.regs[A]); T(flags(&cpu, SF|PF|NF|CF));
    T(8==step(&cpu)); T(0x80 == cpu.regs[A]); T(flags(&cpu, SF|PF|NF|CF));
    T(7==step(&cpu)); T(0xC0 == cpu.regs[A]); T(flags(&cpu, SF));
    T(8==step(&cpu)); T(0x40 == cpu.regs[A]); T(flags(&cpu, NF|CF));    
    ok();
}

fn LDI() void {
    start("LDI");
    const data = [_]u8 { 0x01, 0x02, 0x03 };
    const prog = [_]u8 {
        0x21, 0x00, 0x10,       // LD HL,0x1000
        0x11, 0x00, 0x20,       // LD DE,0x2000
        0x01, 0x03, 0x00,       // LD BC,0x0003
        0xED, 0xA0,             // LDI
        0xED, 0xA0,             // LDI
        0xED, 0xA0,             // LDI
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 3);
    T(16==step(&cpu));
    T(0x1001 == cpu.r16(HL));
    T(0x2001 == cpu.r16(DE));
    T(0x0002 == cpu.r16(BC));
    T(0x01 == mem[0x2000]);
    T(flags(&cpu, PF));
    T(16==step(&cpu));
    T(0x1002 == cpu.r16(HL));
    T(0x2002 == cpu.r16(DE));
    T(0x0001 == cpu.r16(BC));
    T(0x02 == mem[0x2001]);
    T(flags(&cpu, PF));
    T(16==step(&cpu));
    T(0x1003 == cpu.r16(HL));
    T(0x2003 == cpu.r16(DE));
    T(0x0000 == cpu.r16(BC));
    T(0x03 == mem[0x2002]);
    T(flags(&cpu, 0));
    ok();
}

fn LDIR() void {
    start("LDIR");
    const data = [_]u8 { 0x01, 0x02, 0x03, };
    const prog = [_]u8 {
        0x21, 0x00, 0x10,       // LD HL,0x1000
        0x11, 0x00, 0x20,       // LD DE,0x2000
        0x01, 0x03, 0x00,       // LD BC,0x0003
        0xED, 0xB0,             // LDIR
        0x3E, 0x33,             // LD A,0x33
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 3);
    T(21==step(&cpu));
    T(0x1001 == cpu.r16(HL));
    T(0x2001 == cpu.r16(DE));
    T(0x0002 == cpu.r16(BC));
    T(0x000A == cpu.WZ);
    T(0x01 == mem[0x2000]);
    T(flags(&cpu, PF));
    T(21==step(&cpu));
    T(0x1002 == cpu.r16(HL));
    T(0x2002 == cpu.r16(DE));
    T(0x0001 == cpu.r16(BC));
    T(0x000A == cpu.WZ);
    T(0x02 == mem[0x2001]);
    T(flags(&cpu, PF));
    T(16==step(&cpu));
    T(0x1003 == cpu.r16(HL));
    T(0x2003 == cpu.r16(DE));
    T(0x0000 == cpu.r16(BC));
    T(0x02 == mem[0x2001]);
    T(0x03 == mem[0x2002]);
    T(flags(&cpu, 0));
    T(7==step(&cpu)); T(0x33 == cpu.regs[A]);
    ok();
}

fn LDD() void {
    start("LDD");
    const data = [_]u8 { 0x01, 0x02, 0x03 };
    const prog = [_]u8 {
        0x21, 0x02, 0x10,       // LD HL,0x1002
        0x11, 0x02, 0x20,       // LD DE,0x2002
        0x01, 0x03, 0x00,       // LD BC,0x0003
        0xED, 0xA8,             // LDD
        0xED, 0xA8,             // LDD
        0xED, 0xA8,             // LDD
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 3);
    T(16==step(&cpu));
    T(0x1001 == cpu.r16(HL));
    T(0x2001 == cpu.r16(DE));
    T(0x0002 == cpu.r16(BC));
    T(0x03 == mem[0x2002]);
    T(flags(&cpu, PF));
    T(16==step(&cpu));
    T(0x1000 == cpu.r16(HL));
    T(0x2000 == cpu.r16(DE));
    T(0x0001 == cpu.r16(BC));
    T(0x02 == mem[0x2001]);
    T(flags(&cpu, PF));
    T(16 == step(&cpu));
    T(0x0FFF == cpu.r16(HL));
    T(0x1FFF == cpu.r16(DE));
    T(0x0000 == cpu.r16(BC));
    T(0x01 == mem[0x2000]);
    T(flags(&cpu, 0));
    ok();
}

fn LDDR() void {
    start("LDDR");
    const data = [_]u8 { 0x01, 0x02, 0x03 };
    const prog = [_]u8 {
        0x21, 0x02, 0x10,       // LD HL,0x1002
        0x11, 0x02, 0x20,       // LD DE,0x2002
        0x01, 0x03, 0x00,       // LD BC,0x0003
        0xED, 0xB8,             // LDDR
        0x3E, 0x33,             // LD A,0x33
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 3);
    T(21==step(&cpu));
    T(0x1001 == cpu.r16(HL));
    T(0x2001 == cpu.r16(DE));
    T(0x0002 == cpu.r16(BC));
    T(0x000A == cpu.WZ);
    T(0x03 == mem[0x2002]);
    T(flags(&cpu, PF));
    T(21==step(&cpu));
    T(0x1000 == cpu.r16(HL));
    T(0x2000 == cpu.r16(DE));
    T(0x0001 == cpu.r16(BC));
    T(0x000A == cpu.WZ);
    T(0x02 == mem[0x2001]);
    T(flags(&cpu, PF));
    T(16==step(&cpu));
    T(0x0FFF == cpu.r16(HL));
    T(0x1FFF == cpu.r16(DE));
    T(0x0000 == cpu.r16(BC));
    T(0x000A == cpu.WZ);
    T(0x01 == mem[0x2000]);
    T(flags(&cpu, 0));
    T(7 == step(&cpu)); T(0x33 == cpu.regs[A]);
    ok();
}

fn CPI() void {
    start("CPI");
    const data = [_]u8 { 0x01, 0x02, 0x03, 0x04 };
    const prog = [_]u8 {
        0x21, 0x00, 0x10,       // ld hl,0x1000
        0x01, 0x04, 0x00,       // ld bc,0x0004
        0x3e, 0x03,             // ld a,0x03
        0xed, 0xa1,             // cpi
        0xed, 0xa1,             // cpi
        0xed, 0xa1,             // cpi
        0xed, 0xa1,             // cpi
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 3);
    T(16 == step(&cpu));
    T(0x1001 == cpu.r16(HL));
    T(0x0003 == cpu.r16(BC));
    T(flags(&cpu, PF|NF));
    cpu.regs[F] |= CF;
    T(16 == step(&cpu));
    T(0x1002 == cpu.r16(HL));
    T(0x0002 == cpu.r16(BC));
    T(flags(&cpu, PF|NF|CF));
    T(16 == step(&cpu));
    T(0x1003 == cpu.r16(HL));
    T(0x0001 == cpu.r16(BC));
    T(flags(&cpu, ZF|PF|NF|CF));
    T(16 == step(&cpu));
    T(0x1004 == cpu.r16(HL));
    T(0x0000 == cpu.r16(BC));
    T(flags(&cpu, SF|HF|NF|CF));
    ok();
}

fn CPIR() void {
    start("CPIR");
    const data = [_]u8 { 0x01, 0x02, 0x03, 0x04 };
    const prog = [_]u8 {
        0x21, 0x00, 0x10,       // ld hl,0x1000
        0x01, 0x04, 0x00,       // ld bc,0x0004
        0x3e, 0x03,             // ld a,0x03
        0xed, 0xb1,             // cpir
        0xed, 0xb1,             // cpir
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 3);
    T(21 == step(&cpu));
    T(0x1001 == cpu.r16(HL));
    T(0x0003 == cpu.r16(BC));
    T(flags(&cpu, PF|NF));
    cpu.regs[F] |= CF;
    T(21 == step(&cpu));
    T(0x1002 == cpu.r16(HL));
    T(0x0002 == cpu.r16(BC));
    T(flags(&cpu, PF|NF|CF));
    T(16 == step(&cpu));
    T(0x1003 == cpu.r16(HL));
    T(0x0001 == cpu.r16(BC));
    T(flags(&cpu, ZF|PF|NF|CF));
    T(16 == step(&cpu));
    T(0x1004 == cpu.r16(HL));
    T(0x0000 == cpu.r16(BC));
    T(flags(&cpu, SF|HF|NF|CF));
    ok();
}

fn CPD() void {
    start("CPD");
    const data = [_]u8 { 0x01, 0x02, 0x03, 0x04 };
    const prog = [_]u8 {
        0x21, 0x03, 0x10,       // ld hl,0x1004
        0x01, 0x04, 0x00,       // ld bc,0x0004
        0x3e, 0x02,             // ld a,0x03
        0xed, 0xa9,             // cpi
        0xed, 0xa9,             // cpi
        0xed, 0xa9,             // cpi
        0xed, 0xa9,             // cpi
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 3);
    T(16 == step(&cpu));
    T(0x1002 == cpu.r16(HL));
    T(0x0003 == cpu.r16(BC));
    T(flags(&cpu, SF|HF|PF|NF));
    cpu.regs[F] |= CF;
    T(16 == step(&cpu));
    T(0x1001 == cpu.r16(HL));
    T(0x0002 == cpu.r16(BC));
    T(flags(&cpu, SF|HF|PF|NF|CF));
    T(16 == step(&cpu));
    T(0x1000 == cpu.r16(HL));
    T(0x0001 == cpu.r16(BC));
    T(flags(&cpu, ZF|PF|NF|CF));
    T(16 == step(&cpu));
    T(0x0FFF == cpu.r16(HL));
    T(0x0000 == cpu.r16(BC));
    T(flags(&cpu, NF|CF));
    ok();
}

fn CPDR() void{
    start("CPDR");
    const data = [_]u8 { 0x01, 0x02, 0x03, 0x04 };
    const prog = [_]u8 {
        0x21, 0x03, 0x10,       // ld hl,0x1004
        0x01, 0x04, 0x00,       // ld bc,0x0004
        0x3e, 0x02,             // ld a,0x03
        0xed, 0xb9,             // cpdr
        0xed, 0xb9,             // cpdr
    };
    copy(0x1000, &data);
    copy(0x0000, &prog);
    var cpu = makeCPU();

    skip(&cpu, 3);
    T(21 == step(&cpu));
    T(0x1002 == cpu.r16(HL));
    T(0x0003 == cpu.r16(BC));
    T(flags(&cpu, SF|HF|PF|NF));
    cpu.regs[F] |= CF;
    T(21 == step(&cpu));
    T(0x1001 == cpu.r16(HL));
    T(0x0002 == cpu.r16(BC));
    T(flags(&cpu, SF|HF|PF|NF|CF));
    T(16 == step(&cpu));
    T(0x1000 == cpu.r16(HL));
    T(0x0001 == cpu.r16(BC));
    T(flags(&cpu, ZF|PF|NF|CF));
    T(16 == step(&cpu));
    T(0x0FFF == cpu.r16(HL));
    T(0x0000 == cpu.r16(BC));
    T(flags(&cpu, NF|CF));
    ok();
}

fn DI_EI_IM() void {
    start("DI/EI/IM");
    const prog = [_]u8 {
        0xF3,           // DI
        0xFB,           // EI
        0x00,           // NOP
        0xF3,           // DI
        0xFB,           // EI
        0x00,           // NOP
        0xED, 0x46,     // IM 0
        0xED, 0x56,     // IM 1
        0xED, 0x5E,     // IM 2
        0xED, 0x46,     // IM 0
    };
    copy(0x0000, &prog);
    var cpu = makeCPU();
    
    T(4==step(&cpu)); T(!cpu.iff1); T(!cpu.iff2);
    T(4==step(&cpu)); T(cpu.iff1);  T(cpu.iff2);
    T(4==step(&cpu)); T(cpu.iff1);  T(cpu.iff2);
    T(4==step(&cpu)); T(!cpu.iff1); T(!cpu.iff2);
    T(4==step(&cpu)); T(cpu.iff1);  T(cpu.iff2);
    T(4==step(&cpu)); T(cpu.iff1);  T(cpu.iff2);
    T(8==step(&cpu)); T(0 == cpu.IM);
    T(8==step(&cpu)); T(1 == cpu.IM);
    T(8==step(&cpu)); T(2 == cpu.IM);
    T(8==step(&cpu)); T(0 == cpu.IM);
    ok();
}

fn JP_cc_nn() void{
    start("JP cc,nn");
    const prog = [_]u8 {
        0x97,               //          SUB A
        0xC2, 0x0C, 0x02,   //          JP NZ,label0
        0xCA, 0x0C, 0x02,   //          JP Z,label0
        0x00,               //          NOP
        0xC6, 0x01,         // label0:  ADD A,0x01
        0xCA, 0x15, 0x02,   //          JP Z,label1
        0xC2, 0x15, 0x02,   //          JP NZ,label1
        0x00,               //          NOP
        0x07,               // label1:  RLCA
        0xEA, 0x1D, 0x02,   //          JP PE,label2
        0xE2, 0x1D, 0x02,   //          JP PO,label2
        0x00,               //          NOP
        0xC6, 0xFD,         // label2:  ADD A,0xFD
        0xF2, 0x26, 0x02,   //          JP P,label3
        0xFA, 0x26, 0x02,   //          JP M,label3
        0x00,               //          NOP
        0xD2, 0x2D, 0x02,   // label3:  JP NC,label4
        0xDA, 0x2D, 0x02,   //          JP C,label4
        0x00,               //          NOP
        0x00,               //          NOP
    };
    copy(0x0204, &prog);
    var cpu = makeCPU();
    cpu.PC = 0x0204;
    
    T(4 ==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|NF));
    T(10==step(&cpu)); T(0x0208 == cpu.PC); T(0x020C == cpu.WZ);
    T(10==step(&cpu)); T(0x020C == cpu.PC); T(0x020C == cpu.WZ);
    T(7 ==step(&cpu)); T(0x01 == cpu.regs[A]); T(flags(&cpu, 0));
    T(10==step(&cpu)); T(0x0211 == cpu.PC);
    T(10==step(&cpu)); T(0x0215 == cpu.PC);
    T(4 ==step(&cpu)); T(0x02 == cpu.regs[A]); T(flags(&cpu, 0));
    T(10==step(&cpu)); T(0x0219 == cpu.PC);
    T(10==step(&cpu)); T(0x021D == cpu.PC);
    T(7 ==step(&cpu)); T(0xFF == cpu.regs[A]); T(flags(&cpu, SF));
    T(10==step(&cpu)); T(0x0222 == cpu.PC);
    T(10==step(&cpu)); T(0x0226 == cpu.PC);
    T(10==step(&cpu)); T(0x022D == cpu.PC);
    ok();
}

fn JP_JR() void {
    start("JP/JR");
    const prog = [_]u8 {
        0x21, 0x16, 0x02,           //      LD HL,l3
        0xDD, 0x21, 0x19, 0x02,     //      LD IX,l4
        0xFD, 0x21, 0x21, 0x02,     //      LD IY,l5
        0xC3, 0x14, 0x02,           //      JP l0
        0x18, 0x04,                 // l1:  JR l2
        0x18, 0xFC,                 // l0:  JR l1
        0xDD, 0xE9,                 // l3:  JP (IX)
        0xE9,                       // l2:  JP (HL)
        0xFD, 0xE9,                 // l4:  JP (IY)
        0x18, 0x06,                 // l6:  JR l7
        0x00, 0x00, 0x00, 0x00,     //      4x NOP
        0x18, 0xF8,                 // l5:  JR l6
        0x00                        // l7:  NOP
    };
    copy(0x0204, &prog);
    var cpu = makeCPU();
    cpu.PC = 0x0204;

    T(10==step(&cpu)); T(0x0216 == cpu.r16(HL));
    T(14==step(&cpu)); T(0x0219 == cpu.IX);
    T(14==step(&cpu)); T(0x0221 == cpu.IY);
    T(10==step(&cpu)); T(0x0214 == cpu.PC); T(0x0214 == cpu.WZ);
    T(12==step(&cpu)); T(0x0212 == cpu.PC); T(0x0212 == cpu.WZ);
    T(12==step(&cpu)); T(0x0218 == cpu.PC); T(0x0218 == cpu.WZ);
    T(4 ==step(&cpu)); T(0x0216 == cpu.PC); T(0x0218 == cpu.WZ);
    T(8 ==step(&cpu)); T(0x0219 == cpu.PC); T(0x0218 == cpu.WZ);
    T(8 ==step(&cpu)); T(0x0221 == cpu.PC); T(0x0218 == cpu.WZ);
    T(12==step(&cpu)); T(0x021B == cpu.PC); T(0x021B == cpu.WZ);
    T(12==step(&cpu)); T(0x0223 == cpu.PC); T(0x0223 == cpu.WZ);
    ok();
}

fn JR_cc_d() void {
    start("JR cc,e");
    const prog = [_]u8 {
        0x97,           //      SUB A
        0x20, 0x03,     //      JR NZ,l0
        0x28, 0x01,     //      JR Z,l0
        0x00,           //      NOP
        0xC6, 0x01,     // l0:  ADD A,0x01
        0x28, 0x03,     //      JR Z,l1
        0x20, 0x01,     //      JR NZ,l1
        0x00,           //      NOP
        0xD6, 0x03,     // l1:  SUB 0x03
        0x30, 0x03,     //      JR NC,l2
        0x38, 0x01,     //      JR C,l2
        0x00,           //      NOP
        0x00,           // l2:  NOP
    };
    copy(0x0204, &prog);
    var cpu = makeCPU();
    cpu.PC = 0x0204;

    T(4 ==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|NF));
    T(7 ==step(&cpu)); T(0x0207 == cpu.PC);
    T(12==step(&cpu)); T(0x020A == cpu.PC); T(0x020A == cpu.WZ);
    T(7 ==step(&cpu)); T(0x01 == cpu.regs[A]); T(flags(&cpu, 0));
    T(7 ==step(&cpu)); T(0x020E == cpu.PC);
    T(12==step(&cpu)); T(0x0211 == cpu.PC); T(0x0211 == cpu.WZ);
    T(7 ==step(&cpu)); T(0xFE == cpu.regs[A]); T(flags(&cpu, SF|HF|NF|CF));
    T(7 ==step(&cpu)); T(0x0215 == cpu.PC);
    T(12==step(&cpu)); T(0x0218 == cpu.PC); T(0x0218 == cpu.WZ);
    ok();
}

fn DJNZ() void {
    start("DJNZ");
    const prog = [_]u8 {
        0x06, 0x03,         //      LD B,0x03
        0x97,               //      SUB A
        0x3C,               // l0:  INC A
        0x10, 0xFD,         //      DJNZ l0
        0x00,               //      NOP
    };
    copy(0x0204, &prog);
    var cpu = makeCPU();
    cpu.PC = 0x0204;
    
    T(7 ==step(&cpu)); T(0x03 == cpu.regs[B]);
    T(4 ==step(&cpu)); T(0x00 == cpu.regs[A]);
    T(4 ==step(&cpu)); T(0x01 == cpu.regs[A]);
    T(13==step(&cpu)); T(0x02 == cpu.regs[B]); T(0x0207 == cpu.PC); T(0x0207 == cpu.WZ);
    T(4 ==step(&cpu)); T(0x02 == cpu.regs[A]);
    T(13==step(&cpu)); T(0x01 == cpu.regs[B]); T(0x0207 == cpu.PC); T(0x0207 == cpu.WZ);
    T(4 ==step(&cpu)); T(0x03 == cpu.regs[A]);
    T(8 ==step(&cpu)); T(0x00 == cpu.regs[B]); T(0x020A == cpu.PC); T(0x0207 == cpu.WZ);
    ok();
}

fn CALL_RET() void {
    start("CALL/RET");
    const prog = [_]u8 {
        0xCD, 0x0A, 0x02,       //      CALL l0
        0xCD, 0x0A, 0x02,       //      CALL l0
        0xC9,                   // l0:  RET
    };
    copy(0x0204, &prog);
    var cpu = makeCPU();
    cpu.SP = 0x0100;
    cpu.PC = 0x0204;

    T(17 == step(&cpu));
    T(0x020A == cpu.PC); T(0x020A == cpu.WZ); T(0x00FE == cpu.SP);
    T(0x07 == mem[0x00FE]); T(0x02 == mem[0x00FF]);
    T(10 == step(&cpu));
    T(0x0207 == cpu.PC); T(0x0207 == cpu.WZ); T(0x0100 == cpu.SP);
    T(17 == step(&cpu));
    T(0x020A == cpu.PC); T(0x020A == cpu.WZ); T(0x00FE == cpu.SP);
    T(0x0A == mem[0x00FE]); T(0x02 == mem[0x00FF]);
    T(10 == step(&cpu));
    T(0x020A == cpu.PC); T(0x020A == cpu.WZ); T(0x0100 == cpu.SP);
    ok();
}

pub fn main() void {
    LD_A_RI();
    LD_IR_A();
    LD_r_sn();
    LD_r_iHLi();
    LD_iHLi_r();
    LD_iHLi_n();
    LD_iIXIYi_r();
    LD_iIXIYi_n();
    LD_ddIXIY_nn();
    LD_A_iBCDEnni();
    LD_iBCDEnni_A();
    LD_HLddIXIY_inni();
    LD_inni_HLddIXIY();
    LD_SP_HLIXIY();
    PUSH_POP_qqIXIY();
    EX();
    ADD_rn();
    ADD_iHLIXIYi();
    ADC_rn();
    ADC_iHLIXIYi();
    SUB_rn();
    SUB_iHLIXIYi();
    SBC_rn();
    SBC_iHLIXIYi();
    CP_rn();
    CP_iHLIXIYi();
    AND_rn();
    AND_iHLIXIYi();
    XOR_rn();
    OR_rn();
    OR_XOR_iHLIXIYi();
    INC_DEC_r();
    INC_DEC_iHLIXIYi();
    INC_DEC_ssIXIY();
    RLCA_RLA_RRCA_RRA();
    RLC_RL_RRC_RR_r();
    RRC_RLC_RR_RL_iHLIXIYi();
    SLA_r();
    SLA_iHLIXIYi();
    SRA_r();
    SRA_iHLIXIYi();
    SRL_r();
    SRL_iHLIXIYi();
    RLD_RRD();
    HALTx();
    BIT();
    SET();
    RES();
    DAA();
    CPL();
    CCF_SCF();
    NEG();
    LDI();
    LDIR();
    LDD();
    LDDR();
    CPI();
    CPIR();
    CPD();
    CPDR();
    DI_EI_IM();
    JP_cc_nn();
    JP_JR();
    JR_cc_d();
    DJNZ();
    CALL_RET();
}

