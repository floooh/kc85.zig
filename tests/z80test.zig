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

usingnamespace CPUReg8;
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

fn makeCPU() CPU {
    var cpu = CPU{ };
    cpu.regs[A] = 0xFF;
    cpu.regs[F] = 0x00;
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
    // FIXME: needs to loop until opdone for prefixed instructions
    return cpu.exec(0, tick);
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

fn LD_r_sn() void {
    start("LD_r_sn");
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

fn ADD_A_rn() void {
    start("ADD_A_rn");
    const prog = [_]u8{
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

fn ADC_A_rn() void {
    start("ADC_A_rn");
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

fn SUB_A_rn() void {
    start("SUB_A_rn");
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

fn SBC_A_rn() void {
    start("SBC_A_rn");
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

fn CP_A_rn() void {
    start("CP_A_rn");
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

fn AND_A_rn() void {
    start("AND_A_rn");
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

fn XOR_A_rn() void {
    start("XOR_A_rn");
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

fn OR_A_rn() void {
    start("OR_A_rn");
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

pub fn main() void {
    LD_r_sn();
    ADD_A_rn();
    ADC_A_rn();
    SUB_A_rn();
    SBC_A_rn();
    CP_A_rn();
    AND_A_rn();
    XOR_A_rn();
    OR_A_rn();
}

