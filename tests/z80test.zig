//------------------------------------------------------------------------------
//  z80test.zig
//
//  High level instruction tester, derived from
//  https://github.com/floooh/chips-test/blob/master/tests/z80-test.c
//------------------------------------------------------------------------------

const print = @import("std").debug.print;
const assert = @import("std").debug.assert;
const z80 = @import("cpu");

usingnamespace z80;

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
            pins = setData(pins, mem[z80.getAddr(pins)]);
        }
        else if ((pins & z80.WR) != 0) {
            // a memory write access
            mem[getAddr(pins)] = z80.getData(pins);
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

fn makeCPU() z80.State {
    var cpu = z80.State{ };
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

fn step(cpu: *z80.State) usize {
    // FIXME: needs to loop until opdone for prefixed instructions
    return z80.exec(cpu, 0, tick);
}

fn flags(cpu: *z80.State, expected: u8) bool {
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

pub fn main() void {
    LD_r_sn();
    ADD_A_rn();
}

