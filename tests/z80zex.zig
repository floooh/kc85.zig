///
/// Runs the ZEXDOC and ZEXALL tests in a minimal CP/M environment.
///
const build_options = @import("build_options");
const print  = @import("std").debug.print;
usingnamespace @import("emu").z80;

var mem: [0x10000]u8 = undefined;

// tick callback
fn tick(num_ticks: usize, pins: usize, userdata: usize) u64 {
    if (0 != (pins & MREQ)) {
        // a memory request
        if (0 != (pins & RD)) {
            // a memory read access
            return setData(pins, mem[getAddr(pins)]);
        }
        else if (0 != (pins & WR)) {
            // a memory write access
            mem[getAddr(pins)] = getData(pins);
        }
    }
    // NOTE: we don't need to handle IO requests for the ZEX tests
    return pins;
}

fn putChar(c: u8) void {
    print("{c}", .{c});
}

fn copy(start_addr: u16, bytes: []const u8) void {
    var addr = start_addr;
    for (bytes) |byte| {
        mem[addr] = byte;
        addr +%= 1;
    }
}

// emulate required CP/M system calls
fn cpmBDOS(cpu: *CPU) bool {
    var retval: bool = true;
    switch (cpu.regs[C]) {
        2 => {
            // output character in register E
            putChar(cpu.regs[E]);
        },
        9 => {
            // output $-terminated string pointed to by register DE
            var addr = cpu.r16(DE);
            while (mem[addr] != '$'): (addr +%= 1) {
                putChar(mem[addr]);
            }
        },
        else => {
            print("Unhandled CP/M system call: {X}\n", .{ cpu.regs[C] });
            retval = false;
        }
    }
    
    // emulate a RET
    const z: u16 = mem[cpu.SP]; cpu.SP +%= 1;
    const w: u16 = mem[cpu.SP]; cpu.SP +%= 1;
    cpu.WZ = (w<<8) | z;
    cpu.PC = cpu.WZ;
    return retval;
}

// run the currently configured test
fn runTest(cpu: *CPU, name: []const u8) void {
    print("Running {s}:\n\n", .{ name });
    var ticks: usize = 0;
    while (true) {
        ticks += cpu.exec(0, .{ .func=tick, .userdata=0 });
        switch (cpu.PC) {
            0 => break, // done
            5 => { if (!cpmBDOS(cpu)) break; },
            else => { }
        }
    }
    print("\n\n", .{});
}

// run the ZEXDOC test
fn zexdoc() void {
    copy(0x0100, @embedFile("roms/zexdoc.com"));
    var cpu = CPU{ .SP = 0xF000, .PC = 0x0100 };
    runTest(&cpu, "ZEXDOC");
}

// run the ZEXALL test
fn zexall() void {
    copy(0x0100, @embedFile("roms/zexall.com"));
    var cpu = CPU{ .SP = 0xF000, .PC = 0x0100 };
    runTest(&cpu, "ZEXALL");
}

pub fn main() void {
    if (build_options.zexdoc) {
        zexdoc();
    }
    if (build_options.zexall) {
        zexall();
    }
}
