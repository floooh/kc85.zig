///
/// A Z80 CPU EMULATOR
/// ==================
///
/// NOTE: this emulator is slow but (hopefully) somewhat educational, the reason
/// is that the instruction decoding is done "algorithmically" using this
/// recipe:
///
///     http://www.z80.info/decoding.htm
///
/// A CPU emulator written for performance would instead use a big "unfolded"
/// jump table with specialized code for each instruction, which would
/// look more like this (not very readable as you can see):
///
///     https://github.com/floooh/chips/blob/0b59f6bc48ace805a2040a2d5ae5414027c7bdd0/chips/z80.h#L866-L880
///
///
/// EMULATION OVERVIEW
/// ==================
///
/// The emulation is reasonably correct for behaviour that's observable from the
/// outside, all undocumented instructions tested by ZEXALL work (WIP!), including
/// the flag bits YF and XF which are visible side effects of the internal
/// WZ / MEMPTR register.
///
/// The CPU emulation should enable cycle-perfect system emulations, but it 
/// is not "cycle steppable", instead the "exec function" will only return
/// after a full instruction has been completed (which may cause the tick
/// callback to be called multiple times though - this is how cycle-perfect
/// system emulation is enabled).
///
/// The 'system tick callback' function is called once for every machine cycle with
/// the number of clock cycles as argument. The separation between clock cycles
/// (T cycles) and machine cycles (M cycles) is a bit confusing when coming
/// from other CPUs: The clock cycle is ticked with the regular hardware 
/// CPU frequency (up to 4 MHz on legacy Z80s, while a machine cycle is a 
/// "logical group" of clock cycles (for instance a memory read or write 
/// (3 clock cycles), a IO read or write (4 clock cycles) or instruction fetch 
/// machine cycles (4 clock cycles)). 
///
/// There are no fixed rules for machine cycle length. While the above listed 
/// clock cycle counts are most common, some instructions have stretched machine 
/// cycles (which are called 'filler ticks' in this CPU emulation). In addition,
/// memory and IO machine cycles can be stretched by feeding WAIT cycles back
/// into the CPU (on real hardware usually used to deal with slow memory or IO
/// devices, or (more commonly in home computers) to synchronize shared access
/// between CPU and the display hardware to video memory.
///
/// Communication between the CPU emulation and the system tick callback
/// happens through a single 64-bit pin bit-mask with (most of) the 40 CPU pins
/// mapped to a bit in the 64-bit pin mask.
///
/// How THE INSTRUCTION LOOP WORKS:
/// ===============================
///
///     1. The next opcode byte is loaded from memory ("fetch" machine cycle)
///     2. The opcode byte is split into 3 bit groups (x, y, z), see below
///        "HOW INSTRUCTION DECODING WORKS"
///     3. A nested cascade of switch-statements on x, y and z is used to find
///        the right instruction handler function
///     4. The instruction is 'handled', this may involve memory read/write 
///        and IO read/write machine cycles.
///     5. Interrupt requests are handled.
///     6. Loop back to (1) until the requested number of clock cycles is reached.
/// 
/// In a code-generated emulator, all those special cases which are handled
/// dynamically in this emulator would be "baked" into specialized code.
///
///
/// HOW INSTRUCTION DECODING WORKS:
/// ==============================
///
/// Start reading the code at 'fn _exec('.
///
/// Z80 opcodes are one byte split into 3 bit groups:
///
///      76 543 210   bit pos
///     |xx|yyy|zzz|  bit group
///
/// The topmost 2 bits (xx) split the 'instruction space' into 4 quadrants:
///
///     * Q1: all the LD instructions with 8-bit registers as source or 
///       destination, the bit group zzz encodes the source, and the 
///       bit group yyy encodes the destination (all 7 8-bit registers, and (HL))
///     * Q2: all the 8-bit ALU ops with registers or (HL) as source, the
///       bit group yyy defines one of 8 ALU operations (ADD, ADC, SUB, SBC, AND, XOR
///       OR and CP), and the bit zzz defines the source (registers B,C,D,E,H,L,A or (HL)),
///       the destination of ALU ops is always register A
///     * Q0 and Q3 are the "grab bag quadrants" where all the odd instructions
///       and prefixes are stuffed.
///
/// The prefixes DD and FD behave like regular instructions, except that
/// interrupt handling is disabled between the prefix instruction and the 
/// following instruction that's prefixed. The action of the prefix instructions
/// DD and FD is to map the index registers IX or IY to HL. This means that
/// in the following instruction, all uses of HL are replaced with IX or IY, and
/// a memory access (HL) is replaced with (IX+d) or (IY+d). There are only few
/// exceptions:

///     * in the register loading instructions "LD r,(IX/IY+d)"" and
///       "LD (IX/IY+d),r" the source and target registers H and L are never replaced
///       with IXH/IYH and IYH/IYL
///     * in the "EX DE,HL" and "EXX" instructions, HL is never replaced with IX 
///       or IY (however there *are* prefixed versions of "EX (SP),HL" which 
///       replace HL with IX or IY
///     * all ED prefixed instructions disable any active HL <=> IX/IY mapping
///
/// This behaviour of the DD and FD prefixes is why the CPU will happily execute
/// sequences of DD and FD prefix bytes, with the only side effect that no
/// interrupt requests are processed during the sequence.
///
///
/// WHY IS THE EMULATION SLOW
/// =========================
///
/// Some of the reasons why the emulation is slow:
///
///     1. the nested switch statements: it may take up to 4 hops to find
///        the right instruction handler
///     2. the dynamic mapping of HL to IX/IY that needs to be checked on every access
///        to the H and L registers
///     3. various other special cases when accessing the register bank through
///        'register indices', mainly handling the special case for register
///        index 6 which maps to (HL) and (IX/IY+d)
///
/// It's easily fast enough to run in the emulation in realtime of course, 
/// and the CPU usually isn't the most performance-critical part in a
/// home computer emulator anyway (instead the video system is).
///
/// 
pub const Pins = struct {
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

    // set wait ticks on pin mask
    pub fn setWait(pins: u64, wait_ticks: u3) u64 {
        return (pins & ~WaitPinMask) | @as(u64, wait_ticks) << WaitPinShift;
    }

    // extract wait ticks from pin mask
    pub fn getWait(pins: u64) u3 {
        return @truncate(u3, pins >> WaitPinShift);
    }

    // set address pins in pin mask
    pub fn setAddr(pins: u64, a: u16) u64 {
        return (pins & ~AddrPinMask) | a;
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
    pub fn setAddrData(pins: u64, a: u16, d: u8) u64 {
        return (pins & ~(DataPinMask|AddrPinMask)) | (@as(u64, d) << DataPinShift) | a;
    }
};

// status flag bits
pub const Flags = struct {
    pub const CF: u8 = (1<<0);
    pub const NF: u8 = (1<<1);
    pub const VF: u8 = (1<<2);
    pub const PF: u8 = VF;
    pub const XF: u8 = (1<<3);
    pub const HF: u8 = (1<<4);
    pub const YF: u8 = (1<<5);
    pub const ZF: u8 = (1<<6);
    pub const SF: u8 = (1<<7);
};

// 8-bit register indices
pub const Reg8 = struct {
    pub const B = 0;
    pub const C = 1;
    pub const D = 2;
    pub const E = 3;
    pub const H = 4;
    pub const L = 5;
    pub const F = 6;
    pub const A = 7;
    pub const NumRegs8 = 8;
};

// 16-bit register indices
pub const Reg16 = struct {
    pub const BC = 0;
    pub const DE = 1;
    pub const HL = 2;
    pub const FA = 3;
    pub const NumRegs16 = 4;
};

pub const TickFunc = fn(usize, u64) u64;

const Regs = [NumRegs8]u8;

// flag bits for CPU.ixiy
const UseIX = (1<<0);
const UseIY = (1<<1);

pub const CPU = struct {

    pins: u64 = 0,
    ticks: usize = 0,

    regs: Regs = [_]u8{0xFF} ** NumRegs8,

    IX: u16 = 0xFFFF,
    IY: u16 = 0xFFFF,
    WZ: u16 = 0xFFFF,
    SP: u16 = 0xFFFF,
    PC: u16 = 0x0000,
    I:  u8 = 0x00,
    R:  u8 = 0x00,
    IM: u8 = 0x00,

    ex: [NumRegs16]u16 = [_]u16{0xFFFF} ** NumRegs16,    // shadow registers
    
    addr: u16 = 0,  // effective address for (HL), (IX+d), (IY+d)

    ixiy: u2 = 0,   // UseIX or UseIY if indexed prefix 0xDD or 0xFD active
    iff1: bool = false,
    iff2: bool = false,
    ei:   bool = false,
    
    /// run the emulator for at least 'num_ticks', return number of executed ticks
    pub fn exec(cpu: *CPU, num_ticks: usize, tick_func: TickFunc) usize {
        return _exec(cpu, num_ticks, tick_func);
    }
    
    // return true if not in the middle of an indexed op (DD / FD)
    pub fn opdone(cpu: *CPU) bool {
        return 0 == cpu.ixiy;
    }
    
    /// get 16-bit register value (BC, DE, HL, FA)
    pub fn r16(cpu: *CPU, reg: u2) u16 {
        return getR16(&cpu.regs, reg);
    }
};

usingnamespace Pins;
usingnamespace Flags;
usingnamespace Reg8;
usingnamespace Reg16;

fn _exec(cpu: *CPU, num_ticks: usize, tick_func: TickFunc) usize {
    cpu.ticks = 0;
    var running = true;
    while (running): (running = cpu.ticks < num_ticks) {

        // fetch next opcode byte
        const op = fetch(cpu, tick_func);

        // decode opcode (see http://www.z80.info/decoding.htm)
        // |xx|yyy|zzz|
        const x = @truncate(u2, (op >> 6) & 3);
        const y = @truncate(u3, (op >> 3) & 7);
        const z = @truncate(u3, op & 7);
        const p = @truncate(u2, (y >> 1));
        const q = @truncate(u1, y);

        switch (x) {
            0 => switch (z) {
                0 => switch (y) {
                    0 => { }, // NOP
                    1 => opEX_AF_AF(cpu),
                    2 => opDJNZ_d(cpu, tick_func),
                    3 => opJR_d(cpu, tick_func),
                    4...7 => opJR_cc_d(cpu, y, tick_func),
                },
                1 => switch (q) {
                    0 => opLD_rp_nn(cpu, p, tick_func),
                    1 => opADD_HL_rp(cpu, p, tick_func),
                },
                2 => switch (y) {
                    0 => opLD_iBCDE_A(cpu, BC, tick_func),
                    1 => opLD_A_iBCDE(cpu, BC, tick_func),
                    2 => opLD_iBCDE_A(cpu, DE, tick_func),
                    3 => opLD_A_iBCDE(cpu, DE, tick_func),
                    4 => opLD_inn_HL(cpu, tick_func),
                    5 => opLD_HL_inn(cpu, tick_func),
                    6 => opLD_inn_A(cpu, tick_func),
                    7 => opLD_A_inn(cpu, tick_func)
                },
                3 => switch (q) {
                    0 => opINC_rp(cpu, p, tick_func),
                    1 => opDEC_rp(cpu, p, tick_func),
                },
                4 => opINC_r(cpu, y, tick_func),
                5 => opDEC_r(cpu, y, tick_func),
                6 => opLD_r_n(cpu, y, tick_func),
                7 => switch (y) {
                    0 => opRLCA(cpu),
                    1 => opRRCA(cpu),
                    2 => opRLA(cpu),
                    3 => opRRA(cpu),
                    4 => opDAA(cpu),
                    5 => opCPL(cpu),
                    6 => opSCF(cpu),
                    7 => opCCF(cpu),
                }
            },
            1 => {
                if (y == 6 and z == 6) { opHALT(cpu); }
                else { opLD_r_r(cpu, y, z, tick_func); }
            },
            2 => opALU_r(cpu, y, z, tick_func),
            3 => switch (z) {
                0 => opRET_cc(cpu, y, tick_func),
                1 => switch (q) {
                    0 => opPOP_rp2(cpu, p, tick_func),
                    1 => switch (p) {
                        0 => opRET(cpu, tick_func),
                        1 => opEXX(cpu),
                        2 => opJP_HL(cpu),
                        3 => opLD_SP_HL(cpu, tick_func),
                    }
                },
                2 => opJP_cc_nn(cpu, y, tick_func),
                3 => switch (y) {
                    0 => opJP_nn(cpu, tick_func),
                    1 => opCB_prefix(cpu, tick_func),
                    2 => opOUT_in_A(cpu, tick_func),
                    3 => opIN_A_in(cpu, tick_func),
                    4 => opEX_iSP_HL(cpu, tick_func),
                    5 => opEX_DE_HL(cpu),
                    6 => opDI(cpu),
                    7 => opEI(cpu),
                },
                4 => opCALL_cc_nn(cpu, y, tick_func),
                5 => switch (q) {
                    0 => opPUSH_rp2(cpu, p, tick_func),
                    1 => switch (p) {
                        0 => opCALL_nn(cpu, tick_func),
                        1 => { cpu.ixiy = UseIX; continue; }, // no interrupt handling after DD prefix
                        2 => opED_prefix(cpu, tick_func),
                        3 => { cpu.ixiy = UseIY; continue; }, // no interrupt handling after FD prefix
                    }
                },
                6 => opALU_n(cpu, y, tick_func),
                7 => unreachable,
            }
        }
        cpu.ixiy = 0;
        if (cpu.ei) {
            cpu.ei = false;
            cpu.iff1 = true;
            cpu.iff2 = true;
        }
    }
    return cpu.ticks;
}

// ED-prefix decoding
fn opED_prefix(cpu: *CPU, tick_func: TickFunc) void {

    // ED prefix cancels the IX/IY prefix
    cpu.ixiy = 0;

    const op = fetch(cpu, tick_func);
    const x = @truncate(u2, (op >> 6) & 3);
    const y = @truncate(u3, (op >> 3) & 7);
    const z = @truncate(u3, op & 7);
    const p = @truncate(u2, (y >> 1));
    const q = @truncate(u1, y);

    switch (x) {
        1 => switch (z) {
            0 => opIN_ry_iC(cpu, y, tick_func),
            1 => opOUT_iC_ry(cpu, y, tick_func),
            2 => switch (q) {
                0 => opSBC_HL_rp(cpu, p, tick_func),
                1 => opADC_HL_rp(cpu, p, tick_func),
            },
            3 => switch (q) {
                0 => opLD_inn_rp(cpu, p, tick_func),
                1 => opLD_rp_inn(cpu, p, tick_func),
            },
            4 => opNEG(cpu),
            5 => unreachable,
            6 => opIM(cpu, y),
            7 => switch(y) {
                0 => opLD_I_A(cpu, tick_func),
                1 => opLD_R_A(cpu, tick_func),
                2 => opLD_A_I(cpu, tick_func),
                3 => opLD_A_R(cpu, tick_func),
                4 => opRRD(cpu, tick_func),
                5 => opRLD(cpu, tick_func),
                6, 7 => { }, // NONI + NOP
            }
        },
        2 => switch (z) {
            0 => switch (y) {
                4...7 => opLDI_LDD_LDIR_LDDR(cpu, y, tick_func),
                else => { } // NONI + NOP
            },
            1 => switch (y) { 
                4...7 => opCPI_CPD_CPIR_CPDR(cpu, y, tick_func),
                else => { } // NONI + NOP
            },
            2 => switch (y) {
                4...7 => opINI_IND_INIR_INDR(cpu, y, tick_func),
                else => { }, // NONI + NOP
            },
            3 => switch (y) {
                4...7 => opOUTI_OUTD_OTIR_OTDR(cpu, y, tick_func),
                else => { }, // NONI + NOP
            },
            else => { },   // NONI + NOP
        },
        else => { },        // 0, 3 -> NONI + NOP
    }
}

// return flags for left/right-shift/rotate operations
fn lsrFlags(d8: usize, r: usize) u8 {
    return szpFlags(@truncate(u8, r)) | @truncate(u8, d8 >> 7 & CF);
}

fn rsrFlags(d8: usize, r: usize) u8 {
    return szpFlags(@truncate(u8, r)) | @truncate(u8, d8 & CF);
}

// CB-prefix decoding
fn opCB_prefix(cpu: *CPU, tick_func: TickFunc) void {
    // special handling for undocumented DD/FD+CB double prefix instructions,
    // these always load the value from memory (IX+d),
    // and write the value back, even for normal
    // "register" instructions
    // see: http://www.baltazarstudios.com/files/ddcb.html
    const d: u16 = if (cpu.ixiy != 0) dimm8(cpu, tick_func) else 0;
    
    // special opcode fetch without memory refresh and bumpR()
    const op = fetchCB(cpu, tick_func);
    const x = @truncate(u2, (op >> 6) & 3);
    const y = @truncate(u3, (op >> 3) & 7);
    const z = @truncate(u3, op & 7);
    
    // load operand (for indexed ops always from memory)
    const d8: usize = if ((z == 6) or (cpu.ixiy != 0)) blk: {
        tick(cpu, 1, 0, tick_func); // filler tick
        cpu.addr = loadHLIXIY(cpu);
        if (cpu.ixiy != 0) {
            tick(cpu, 1, 0, tick_func); // filler tick
            cpu.addr +%= d;
            cpu.WZ = cpu.addr;
        }
        cpu.pins = setAddr(cpu.pins, cpu.addr);
        memRead(cpu, tick_func);
        break: blk getData(cpu.pins);
    }
    else load8(cpu, z, tick_func);
    
    var f: usize = cpu.regs[F];
    var r: usize = undefined;
    switch (x) {
        0 => switch (y) {
            // rot/shift
            0 => { r = d8<<1 | d8>>7;       f = lsrFlags(d8, r); },     // RLC
            1 => { r = d8>>1 | d8<<7;       f = rsrFlags(d8, r); },     // RRC
            2 => { r = d8<<1 | (f&CF);      f = lsrFlags(d8, r); },     // RL
            3 => { r = d8>>1 | ((f&CF)<<7); f = rsrFlags(d8, r); },     // RR
            4 => { r = d8<<1;               f = lsrFlags(d8, r); },     // SLA
            5 => { r = d8>>1 | (d8&0x80);   f = rsrFlags(d8, r); },     // SRA
            6 => { r = d8<<1 | 1;           f = lsrFlags(d8, r); },     // SLL
            7 => { r = d8>>1;               f = rsrFlags(d8, r); },     // SRL
        },
        1 => {
            // BIT (bit test)
            r = d8 & (@as(usize,1) << y);
            f = (f & CF) | HF | if (r==0) ZF|PF else r&SF;
            if ((z == 6) or (cpu.ixiy != 0)) {
                f |= (cpu.WZ >> 8) & (YF|XF);
            }
            else {
                f |= d8 & (YF|XF);
            }
        },
        2 => {
            // RES (bit clear)
            r = d8 & ~(@as(usize,1) << y);
        },
        3 => {
            // SET (bit set)
            r = d8 | (@as(usize, 1) << y);
        }
    }
    if (x != 1) {
        // write result back
        if ((z == 6) or (cpu.ixiy != 0)) {
            // (HL), (IX+d), (IY+d): write back to memory, for extended op,
            // even when the op is actually a register op
            cpu.pins = setAddrData(cpu.pins, cpu.addr, @truncate(u8, r));
            memWrite(cpu, tick_func);
        }
        if (z != 6) {
            // write result back to register, never write back to overriden IXH/IYH/IXL/IYL
            store8HL(cpu, z, @truncate(u8, r), tick_func);
        }
    }
    cpu.regs[F] = @truncate(u8, f);
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


// helper function to increment R register
fn bumpR(cpu: *CPU) void {
    cpu.R = (cpu.R & 0x80) | ((cpu.R +% 1) & 0x7F);
}

// helper function to bump PC register with wraparound
fn bumpPC(cpu: *CPU) void {
    cpu.PC +%= 1;
}

// invoke tick callback with control pins set
fn tick(cpu: *CPU, num_ticks: usize, pin_mask: u64, tick_func: TickFunc) void {
    cpu.pins = tick_func(num_ticks, (cpu.pins & ~CtrlPinMask) | pin_mask);
    cpu.ticks += num_ticks;
}

// invoke tick callback with pin mask and wait state detection
fn tickWait(cpu: *CPU, num_ticks: usize, pin_mask: u64, tick_func: TickFunc) void {
    cpu.pins = tick_func(num_ticks, (cpu.pins & ~(CtrlPinMask|WaitPinMask) | pin_mask));
    cpu.ticks += num_ticks + getWait(cpu.pins);
}

// perform a memory-read machine cycle (3 clock cycles)
fn memRead(cpu: *CPU, tick_func: TickFunc) void {
    tickWait(cpu, 3, MREQ|RD, tick_func);
}

// perform a memory-write machine cycle (3 clock cycles)
fn memWrite(cpu: *CPU, tick_func: TickFunc) void {
    tickWait(cpu, 3, MREQ|WR, tick_func);
}

// perform an IO input machine cycle (4 clock cycles)
fn ioRead(cpu: *CPU, tick_func: TickFunc) void {
    tickWait(cpu, 4, IORQ|RD, tick_func);
}

// perform a IO output machine cycle (4 clock cycles)
fn ioWrite(cpu: *CPU, tick_func: TickFunc) void {
    tickWait(cpu, 4, IORQ|WR, tick_func);
}

// generate effective address for (HL), (IX+d), (IY+d) and put into cpu.addr
fn addr(cpu: *CPU, extra_ticks: usize, tick_func: TickFunc) void {
    cpu.addr = loadHLIXIY(cpu);
    if (0 != cpu.ixiy) {
        const d = dimm8(cpu, tick_func);
        cpu.addr +%= d;
        cpu.WZ = cpu.addr;
        tick(cpu, extra_ticks, 0, tick_func);
    }
}

// perform an instruction fetch machine cycle 
fn fetch(cpu: *CPU, tick_func: TickFunc) u8 {
    cpu.pins = setAddr(cpu.pins, cpu.PC);
    tickWait(cpu, 4, M1|MREQ|RD, tick_func);
    bumpPC(cpu);
    bumpR(cpu);
    return getData(cpu.pins);
}

// special opcode fetch without memory refresh and special R handling
fn fetchCB(cpu: *CPU, tick_func: TickFunc) u8 {
    cpu.pins = setAddr(cpu.pins, cpu.PC);
    tickWait(cpu, 4, M1|MREQ|RD, tick_func);
    bumpPC(cpu);
    if (0 == cpu.ixiy) {
        bumpR(cpu);
    }
    return getData(cpu.pins);
}

// read 8-bit immediate
fn imm8(cpu: *CPU, tick_func: TickFunc) u8 {
    cpu.pins = setAddr(cpu.pins, cpu.PC);
    bumpPC(cpu);
    memRead(cpu, tick_func);
    return getData(cpu.pins);
}

// read the 8-bit signed address offset for IX/IX+d ops
fn dimm8(cpu: *CPU, tick_func: TickFunc) u16 {
    return @bitCast(u16, @as(i16, @bitCast(i8, imm8(cpu, tick_func))));
}

// read 16-bit immediate
fn imm16(cpu: *CPU, tick_func: TickFunc) u16 {
    cpu.pins = setAddr(cpu.pins, cpu.PC);
    bumpPC(cpu);
    memRead(cpu, tick_func);
    const z: u16 = getData(cpu.pins);
    cpu.pins = setAddr(cpu.pins, cpu.PC);
    bumpPC(cpu);
    memRead(cpu, tick_func);
    const w: u16 = getData(cpu.pins);
    const wz = (w<<8) | z;
    cpu.WZ = wz;
    return wz;
}

// load from 8-bit register or effective address (HL)/(IX+d)/IY+d)
fn load8(cpu: *CPU, z: u3, tick_func: TickFunc) u8 {
    return switch (z) {
        B,C,D,E,A=> cpu.regs[z],
        H => switch (cpu.ixiy) {
            0 => cpu.regs[H],
            UseIX => @truncate(u8, cpu.IX >> 8),
            UseIY => @truncate(u8, cpu.IY >> 8),
            else => unreachable,
        },
        L => switch (cpu.ixiy) {
            0 => cpu.regs[L],
            UseIX => @truncate(u8, cpu.IX),
            UseIY => @truncate(u8, cpu.IY),
            else => unreachable,
        },
        F => blk: {
            cpu.pins = setAddr(cpu.pins, cpu.addr);
            memRead(cpu, tick_func);
            break: blk getData(cpu.pins);

        }
    };
}

// same as load8, but also never replace H,L with IXH,IYH,IXH,IXL
fn load8HL(cpu: *CPU, z: u3, tick_func: TickFunc) u8 {
    if (z != 6) {
        return cpu.regs[z];
    }
    else {
        cpu.pins = setAddr(cpu.pins, cpu.addr);
        memRead(cpu, tick_func);
        return getData(cpu.pins);
    }
}

// store into 8-bit register or effective address (HL)/(IX+d)/(IY+d)
fn store8(cpu: *CPU, y: u3, val: u8, tick_func: TickFunc) void {
    switch (y) {
        B,C,D,E,A => { cpu.regs[y] = val; },
        H => switch (cpu.ixiy) {
            0 => { cpu.regs[H] = val; },
            UseIX => { cpu.IX = (cpu.IX & 0x00FF) | (@as(u16,val)<<8); },
            UseIY => { cpu.IY = (cpu.IY & 0x00FF) | (@as(u16,val)<<8); },
            else => unreachable,
        },
        L => switch (cpu.ixiy) {
            0 => { cpu.regs[L] = val; },
            UseIX => { cpu.IX = (cpu.IX & 0xFF00) | val; },
            UseIY => { cpu.IY = (cpu.IY & 0xFF00) | val; },
            else => unreachable,
        },
        F => {
            cpu.pins = setAddrData(cpu.pins, cpu.addr, val);
            memWrite(cpu, tick_func);
        }
    }
}

// same as store8, but never replace H,L with IXH,IYH, IXL, IYL
fn store8HL(cpu: *CPU, y: u3, val: u8, tick_func: TickFunc) void {
    if (y != 6) {
        cpu.regs[y] = val;
    }
    else {
        cpu.pins = setAddrData(cpu.pins, cpu.addr, val);
        memWrite(cpu, tick_func);
    }
}

// store into HL, IX or IY, depending on current index mode
fn storeHLIXIY(cpu: *CPU, val: u16) void {
    switch (cpu.ixiy) {
        0     => setR16(&cpu.regs, HL, val),
        UseIX => cpu.IX = val,
        UseIY => cpu.IY = val,
        else  => unreachable 
    }
}

// store 16-bit value into register with special handling for SP
fn store16SP(cpu: *CPU, reg: u2, val: u16) void {
    switch (reg) {
        BC   => setR16(&cpu.regs, BC, val),
        DE   => setR16(&cpu.regs, DE, val),
        HL   => storeHLIXIY(cpu, val),
        FA   => cpu.SP = val,
    }
}

// store 16-bit value into register with special case handling for AF
fn store16AF(cpu: *CPU, reg: u2, val: u16) void {
    switch (reg) {
        BC   => setR16(&cpu.regs, BC, val),
        DE   => setR16(&cpu.regs, DE, val),
        HL   => storeHLIXIY(cpu, val),
        FA   => { cpu.regs[F] = @truncate(u8, val); cpu.regs[A] = @truncate(u8, val>>8); },
    }
}

// load from HL, IX or IY, depending on current index mode
fn loadHLIXIY(cpu: *CPU) u16 {
    return switch (cpu.ixiy) {
        0     => getR16(&cpu.regs, HL),
        UseIX => return cpu.IX,
        UseIY => return cpu.IY,
        else  => unreachable
    };
}

// load 16-bit value from register with special handling for SP
fn load16SP(cpu: *CPU, reg: u2) u16 {
    return switch(reg) {
        BC   => getR16(&cpu.regs, BC),
        DE   => getR16(&cpu.regs, DE),
        HL   => loadHLIXIY(cpu),
        FA   => cpu.SP,
    };
}

// load 16-bit value from register with special case handling for AF
fn load16AF(cpu: *CPU, reg: u2) u16 {
    return switch(reg) {
        BC   => getR16(&cpu.regs, BC),
        DE   => getR16(&cpu.regs, DE),
        HL   => loadHLIXIY(cpu),
        FA   => @as(u16, cpu.regs[A])<<8 | cpu.regs[F],
    };
}

// HALT
fn opHALT(cpu: *CPU) void {
    cpu.pins |= HALT;
    cpu.PC -%= 1;
}

// LD r,r
fn opLD_r_r(cpu: *CPU, y: u3, z: u3, tick_func: TickFunc) void {
    if ((y == 6) or (z == 6)) {
        addr(cpu, 5, tick_func);
        // for (IX+d)/(IY+d), H and L are not replace with IXH/IYH and IYH/IYL
        const val = load8HL(cpu, z, tick_func);
        store8HL(cpu, y, val, tick_func);
    }
    else {
        // regular LD r,r may map H and L to IXH/IYH and IXL/IYL
        const val = load8(cpu, z, tick_func);
        store8(cpu, y, val, tick_func);
    }
}

// LD r,n
fn opLD_r_n(cpu: *CPU, y: u3, tick_func: TickFunc) void {
    if (y == 6) {
        addr(cpu, 2, tick_func);
    }
    const val = imm8(cpu, tick_func);
    store8(cpu, y, val, tick_func);
}

// ALU r
fn opALU_r(cpu: *CPU, y: u3, z: u3, tick_func: TickFunc) void {
    if (z == 6) {
        addr(cpu, 5, tick_func);
    }
    const val = load8(cpu, z, tick_func);
    alu8(&cpu.regs, y, val);
}

// ALU n
fn opALU_n(cpu: *CPU, y: u3, tick_func: TickFunc) void {
    const val = imm8(cpu, tick_func);
    alu8(&cpu.regs, y, val);
}

// NEG
fn opNEG(cpu: *CPU) void {
    neg8(&cpu.regs);
}

// INC r
fn opINC_r(cpu: *CPU, y: u3, tick_func: TickFunc) void {
    if (y == 6) {
        addr(cpu, 5, tick_func);
        tick(cpu, 1, 0, tick_func); // filler tick
    }
    const val = load8(cpu, y, tick_func);
    const res = inc8(&cpu.regs, val);
    store8(cpu, y, res, tick_func);
}

// DEC r
fn opDEC_r(cpu: *CPU, y: u3, tick_func: TickFunc) void {
    if (y == 6) {
        addr(cpu, 5, tick_func);
        tick(cpu, 1, 0, tick_func); // filler tick
    }
    const val = load8(cpu, y, tick_func);
    const res = dec8(&cpu.regs, val);
    store8(cpu, y, res, tick_func);
}

// INC rp
fn opINC_rp(cpu: *CPU, p: u2, tick_func: TickFunc) void {
    tick(cpu, 2, 0, tick_func); // 2 filler ticks
    store16SP(cpu, p, load16SP(cpu, p) +% 1);
}

// DEC rp
fn opDEC_rp(cpu: *CPU, p: u2, tick_func: TickFunc) void {
    tick(cpu, 2, 0, tick_func); // 2 filler tick
    store16SP(cpu, p, load16SP(cpu, p) -% 1);
}

// LD rp,nn
fn opLD_rp_nn(cpu: *CPU, p: u2, tick_func: TickFunc) void {
    const val = imm16(cpu, tick_func);
    store16SP(cpu, p, val);
}

// LD (BC/DE),A
fn opLD_iBCDE_A(cpu: *CPU, r: u2, tick_func: TickFunc) void {
    cpu.WZ = getR16(&cpu.regs, r);
    const val = cpu.regs[A];
    cpu.pins = setAddrData(cpu.pins, cpu.WZ, val);
    memWrite(cpu, tick_func);
    cpu.WZ = (@as(u16, val)<<8) | ((cpu.WZ +% 1) & 0xFF);
}

// LD A,(BC/DE)
fn opLD_A_iBCDE(cpu: *CPU, r: u2, tick_func: TickFunc) void {
    cpu.WZ = getR16(&cpu.regs, r);
    cpu.pins = setAddr(cpu.pins, cpu.WZ);
    memRead(cpu, tick_func);
    cpu.regs[A] = getData(cpu.pins);
    cpu.WZ +%= 1;
}

// LD (nn),HL
fn opLD_inn_HL(cpu: *CPU, tick_func: TickFunc) void {
    cpu.WZ = imm16(cpu, tick_func);
    const val = loadHLIXIY(cpu);
    cpu.pins = setAddrData(cpu.pins, cpu.WZ, @truncate(u8, val));
    memWrite(cpu, tick_func);
    cpu.WZ +%= 1;
    cpu.pins = setAddrData(cpu.pins, cpu.WZ, @truncate(u8, val>>8));
    memWrite(cpu, tick_func);
}

// LD HL,(nn)
fn opLD_HL_inn(cpu: *CPU, tick_func: TickFunc) void {
    cpu.WZ = imm16(cpu, tick_func);
    cpu.pins = setAddr(cpu.pins, cpu.WZ);
    memRead(cpu, tick_func);
    const l = getData(cpu.pins);
    cpu.WZ +%= 1;
    cpu.pins = setAddr(cpu.pins, cpu.WZ);
    memRead(cpu, tick_func);
    const h = getData(cpu.pins);
    storeHLIXIY(cpu, @as(u16, h)<<8 | l);
}

// LD (nn),A
fn opLD_inn_A(cpu: *CPU, tick_func: TickFunc) void {
    cpu.WZ = imm16(cpu, tick_func);
    const val = cpu.regs[A];
    cpu.pins = setAddrData(cpu.pins, cpu.WZ, val);
    memWrite(cpu, tick_func);
    cpu.WZ = (@as(u16, val)<<8) | ((cpu.WZ +% 1) & 0xFF);
}

// LD A,(nn)
fn opLD_A_inn(cpu: *CPU, tick_func: TickFunc) void {
    cpu.WZ = imm16(cpu, tick_func);
    cpu.pins = setAddr(cpu.pins, cpu.WZ);
    memRead(cpu, tick_func);
    cpu.WZ +%= 1;
    cpu.regs[A] = getData(cpu.pins);
}

// LD (nn),BC/DE/HL/SP
fn opLD_inn_rp(cpu: *CPU, p: u2, tick_func: TickFunc) void {
    cpu.WZ = imm16(cpu, tick_func);
    const val = load16SP(cpu, p);
    cpu.pins = setAddrData(cpu.pins, cpu.WZ, @truncate(u8, val));
    memWrite(cpu, tick_func);
    cpu.WZ +%= 1;
    cpu.pins = setAddrData(cpu.pins, cpu.WZ, @truncate(u8, val>>8));
    memWrite(cpu, tick_func);
}

// LD BC/DE/HL/SP,(nn)
fn opLD_rp_inn(cpu: *CPU, p: u2, tick_func: TickFunc) void {
    cpu.WZ = imm16(cpu, tick_func);
    cpu.pins = setAddr(cpu.pins, cpu.WZ);
    memRead(cpu, tick_func);
    const l = getData(cpu.pins);
    cpu.WZ +%= 1;
    cpu.pins = setAddr(cpu.pins, cpu.WZ);
    memRead(cpu, tick_func);
    const h = getData(cpu.pins);
    store16SP(cpu, p, (@as(u16,h)<<8) | l);
}

// LD SP,HL/IX/IY
fn opLD_SP_HL(cpu: *CPU, tick_func: TickFunc) void {
    tick(cpu, 2, 0, tick_func);     // 2 filler ticks
    cpu.SP = loadHLIXIY(cpu);
}

// LD I,A
fn opLD_I_A(cpu: *CPU, tick_func: TickFunc) void {
    tick(cpu, 1, 0, tick_func);     // 1 filler tick
    cpu.I = cpu.regs[A];
}

// LD R,A
fn opLD_R_A(cpu: *CPU, tick_func: TickFunc) void {
    tick(cpu, 1, 0, tick_func);     // 1 filler tick
    cpu.R = cpu.regs[A];
}

// special flag computation for LD_A,I / LD A,R
fn irFlags(val: u8, f: u8, iff2: bool) u8{
    return (f & CF) | szFlags(val) | (val & YF|XF) | if (iff2) PF else 0;
}

// LD A,I
fn opLD_A_I(cpu: *CPU, tick_func: TickFunc) void {
    tick(cpu, 1, 0, tick_func);     // 1 filler tick
    cpu.regs[A] = cpu.I;
    cpu.regs[F] = irFlags(cpu.regs[A], cpu.regs[F], cpu.iff2);
}

// LD A,R
fn opLD_A_R(cpu: *CPU, tick_func: TickFunc) void {
    tick(cpu, 1, 0, tick_func);     // 1 filler tick
    cpu.regs[A] = cpu.R;
    cpu.regs[F] = irFlags(cpu.regs[A], cpu.regs[F], cpu.iff2);
}

// PUSH BC/DE/HL/AF/IX/IY
fn opPUSH_rp2(cpu: *CPU, p: u2, tick_func: TickFunc) void {
    tick(cpu, 1, 0, tick_func);     // 1 filler tick
    const val = load16AF(cpu, p);
    cpu.SP -%= 1;
    cpu.pins = setAddrData(cpu.pins, cpu.SP, @truncate(u8, val>>8));
    memWrite(cpu, tick_func);
    cpu.SP -%= 1;
    cpu.pins = setAddrData(cpu.pins, cpu.SP, @truncate(u8, val));
    memWrite(cpu, tick_func);
}

// POP BC/DE/HL/AF/IX/IY
fn opPOP_rp2(cpu: *CPU, p: u2, tick_func: TickFunc) void {
    cpu.pins = setAddr(cpu.pins, cpu.SP);
    cpu.SP +%= 1;
    memRead(cpu, tick_func);
    const l = getData(cpu.pins);
    cpu.pins = setAddr(cpu.pins, cpu.SP);
    cpu.SP +%= 1;
    memRead(cpu, tick_func);
    const h = getData(cpu.pins);
    store16AF(cpu, p, @as(u16,h)<<8 | l);
}

// EX DE,HL
fn opEX_DE_HL(cpu: *CPU) void {
    const de = getR16(&cpu.regs, DE);
    const hl = getR16(&cpu.regs, HL);
    setR16(&cpu.regs, DE, hl);
    setR16(&cpu.regs, HL, de);
}

// EX AF,AF'
fn opEX_AF_AF(cpu: *CPU) void {
    const fa = getR16(&cpu.regs, FA);
    setR16(&cpu.regs, FA, cpu.ex[FA]);
    cpu.ex[FA] = fa;
}

// EXX
fn opEXX(cpu: *CPU) void {
    const bc = getR16(&cpu.regs, BC); setR16(&cpu.regs, BC, cpu.ex[BC]); cpu.ex[BC] = bc;
    const de = getR16(&cpu.regs, DE); setR16(&cpu.regs, DE, cpu.ex[DE]); cpu.ex[DE] = de;
    const hl = getR16(&cpu.regs, HL); setR16(&cpu.regs, HL, cpu.ex[HL]); cpu.ex[HL] = hl;
}

// EX (SP),HL
fn opEX_iSP_HL(cpu: *CPU, tick_func: TickFunc) void {
    tick(cpu, 3, 0, tick_func);     // 3 filler ticks
    cpu.pins = setAddr(cpu.pins, cpu.SP);
    memRead(cpu, tick_func);
    const l = getData(cpu.pins);
    cpu.pins = setAddr(cpu.pins, cpu.SP +% 1);
    memRead(cpu, tick_func);
    const h = getData(cpu.pins);
    const val = loadHLIXIY(cpu);
    cpu.pins = setAddrData(cpu.pins, cpu.SP, @truncate(u8, val));
    memWrite(cpu, tick_func);
    cpu.pins = setAddrData(cpu.pins, cpu.SP +% 1, @truncate(u8, val>>8));
    memWrite(cpu, tick_func);
    cpu.WZ = @as(u16, h)<<8 | l;
    storeHLIXIY(cpu, cpu.WZ);
}

// RLCA
fn opRLCA(cpu: *CPU) void {
    const a: usize = cpu.regs[A];
    const r = (a<<1) | (a>>7);
    const f = cpu.regs[F];
    cpu.regs[F] = @truncate(u8, ((a>>7) & CF) | (f & (SF|ZF|PF)) | (r & (YF|XF)));
    cpu.regs[A] = @truncate(u8, r);
}

// RRCA
fn opRRCA(cpu: *CPU) void {
    const a: usize = cpu.regs[A];
    const r = (a>>1) | (a<<7);
    const f = cpu.regs[F];
    cpu.regs[F] = @truncate(u8, (a & CF) | (f & (SF|ZF|PF)) | (r & (YF|XF)));
    cpu.regs[A] = @truncate(u8, r);
}

// RLA
fn opRLA(cpu: *CPU) void {
    const a: usize = cpu.regs[A];
    const f = cpu.regs[F];
    const r = (a<<1) | (f & CF);
    cpu.regs[F] = @truncate(u8, ((a>>7) & CF) | (f & (SF|ZF|PF)) | (r & (YF|XF)));
    cpu.regs[A] = @truncate(u8, r);
}

// RRA
fn opRRA(cpu: *CPU) void {
    const a: usize = cpu.regs[A];
    const f = cpu.regs[F];
    const r = (a >> 1) | ((f & CF) << 7);
    cpu.regs[F] = @truncate(u8, (a & CF) | (f & (SF|ZF|PF)) | (r & (YF|XF)));
    cpu.regs[A] = @truncate(u8, r);
}

// RLD
fn opRLD(cpu: *CPU, tick_func: TickFunc) void {
    cpu.WZ = loadHLIXIY(cpu);
    cpu.pins = setAddr(cpu.pins, cpu.WZ);
    memRead(cpu, tick_func);
    const d_in = getData(cpu.pins);
    const a_in = cpu.regs[A];
    const a_out = (a_in & 0xF0) | (d_in >> 4);
    const d_out = (d_in << 4) | (a_in & 0x0F);
    cpu.pins = setAddrData(cpu.pins, cpu.WZ, d_out);
    memWrite(cpu, tick_func);
    cpu.WZ +%= 1;
    cpu.regs[A] = a_out;
    cpu.regs[F] = (cpu.regs[F] & CF) | szpFlags(a_out);
    tick(cpu, 4, 0, tick_func); // 4 filler ticks
}

// RRD
fn opRRD(cpu: *CPU, tick_func: TickFunc) void {
    cpu.WZ = loadHLIXIY(cpu);
    cpu.pins = setAddr(cpu.pins, cpu.WZ);
    memRead(cpu, tick_func);
    const d_in = getData(cpu.pins);
    const a_in = cpu.regs[A];
    const a_out = (a_in & 0xF0) | (d_in & 0x0F);
    const d_out = (d_in >> 4) | (a_in << 4);
    cpu.pins = setAddrData(cpu.pins, cpu.WZ, d_out);
    memWrite(cpu, tick_func);
    cpu.WZ +%= 1;
    cpu.regs[A] = a_out;
    cpu.regs[F] = (cpu.regs[F] & CF) | szpFlags(a_out);
    tick(cpu, 4, 0, tick_func); // 4 filler ticks
}

// DAA
fn opDAA(cpu: *CPU) void {
    const a = cpu.regs[A];
    var v = a;
    var f = cpu.regs[F];
    if (0 != (f & NF)) {
        if (((a & 0xF) > 0x9) or (0 != (f & HF))) {
            v -%= 0x06;
        }
        if ((a > 0x99) or (0 != (f & CF))) {
            v -%= 0x60;
        }
    }
    else {
        if (((a & 0xF) > 0x9) or (0 != (f & HF))) {
            v +%= 0x06;
        }
        if ((a > 0x99) or (0 != (f & CF))) {
            v +%= 0x60;
        }
    }
    f &= CF|NF;
    f |= if (a > 0x99) CF else 0;
    f |= (a ^ v) & HF;
    f |= szpFlags(v);
    cpu.regs[A] = v;
    cpu.regs[F] = f;
}

// CPL
fn opCPL(cpu: *CPU) void {
    const a = cpu.regs[A] ^ 0xFF;
    const f = cpu.regs[F];
    cpu.regs[A] = a;
    cpu.regs[F] = HF | NF | (f & (SF|ZF|PF|CF)) | (a & (YF|XF));
}

// SCF
fn opSCF(cpu: *CPU) void {
    const a = cpu.regs[A];
    const f = cpu.regs[F];
    cpu.regs[F] = CF | (f & (SF|ZF|PF|CF)) | (a & (YF|XF));
}

// CCF
fn opCCF(cpu: *CPU) void {
    const a = cpu.regs[A];
    const f = cpu.regs[F];
    cpu.regs[F] = (((f & CF)<<4) | (f & (SF|ZF|PF|CF)) | (a & (YF|XF))) ^ CF;
}

// LDI/LDD/LDIR/LDDR
fn opLDI_LDD_LDIR_LDDR(cpu: *CPU, y: u3, tick_func: TickFunc) void {
    var hl = getR16(&cpu.regs, HL);
    var de = getR16(&cpu.regs, DE);
    cpu.pins = setAddr(cpu.pins, hl);
    memRead(cpu, tick_func);
    const val = getData(cpu.pins) +% cpu.regs[A];
    cpu.pins = setAddr(cpu.pins, de);
    memWrite(cpu, tick_func);
    if (0 != (y & 1)) {
        hl -%= 1;
        de -%= 1;
    }
    else {
        hl +%= 1;
        de +%= 1;
    }
    setR16(&cpu.regs, HL, hl);
    setR16(&cpu.regs, DE, de);
    tick(cpu, 2, 0, tick_func);    // 2 filler ticks
    var f = (cpu.regs[F] & (SF|ZF|CF)) | ((val << 4) & YF) | (val & XF);
    const bc = getR16(&cpu.regs, BC) -% 1;
    setR16(&cpu.regs, BC, bc);
    if (bc != 0) {
        f |= VF;
    }
    cpu.regs[F] = f;
    if ((y >= 6) and (0 != bc)) {
        cpu.PC -%= 2;
        cpu.WZ = cpu.PC +% 1;
        tick(cpu, 5, 0, tick_func); // 5 filler ticks
    }
}

// CPI, CPD, CPIR, CPDR
fn opCPI_CPD_CPIR_CPDR(cpu: *CPU, y: u3, tick_func: TickFunc) void {
    var hl = getR16(&cpu.regs, HL);
    cpu.pins = setAddr(cpu.pins, hl);
    memRead(cpu, tick_func);
    if (0 != (y & 1)) {
        hl -%= 1;
        cpu.WZ -%= 1;
    }
    else {
        hl +%= 1;
        cpu.WZ +%= 1;
    }
    setR16(&cpu.regs, HL, hl);
    tick(cpu, 5, 0, tick_func); // 5 filler ticks
    var val = cpu.regs[A] -% getData(cpu.pins);
    var f = (cpu.regs[F] & CF) | NF | szFlags(val);
    if ((val & 0x0F) > (cpu.regs[A] & 0x0F)) {
        f |= HF;
        val -%= 1;
    }
    f |= ((val << 4) & YF) | (val & XF);
    const bc = getR16(&cpu.regs, BC) -% 1;
    setR16(&cpu.regs, BC, bc);
    if (bc != 0) {
        f |= VF;
    }
    cpu.regs[F] = f;
    if ((y >= 6) and (0 != bc) and (0 == (f & ZF))) {
        cpu.PC -%= 2;
        cpu.WZ = cpu.PC +% 1;
        tick(cpu, 5, 0, tick_func); // 5 filler ticks
    }
}

// DI
fn opDI(cpu: *CPU) void {
    cpu.iff1 = false;
    cpu.iff2 = false;
}

// EI
fn opEI(cpu: *CPU) void {
    cpu.iff1 = false;
    cpu.iff2 = false;
    cpu.ei = true;
}

// IM
fn opIM(cpu: *CPU, y: u3) void {
    const im = [8]u8 { 0, 0, 1, 2, 0, 0, 1, 2 };
    cpu.IM = im[y];
}

// JP cc,nn
fn opJP_cc_nn(cpu: *CPU, y: u3, tick_func: TickFunc) void {
    const val = imm16(cpu, tick_func);
    const f = cpu.regs[F];
    if (cc(cpu.regs[F], y)) {
        cpu.PC = val;
    }
}

// JP nn
fn opJP_nn(cpu: *CPU, tick_func: TickFunc) void {
    cpu.PC = imm16(cpu, tick_func);
}

// JP (HL)
fn opJP_HL(cpu: *CPU) void {
    cpu.PC = loadHLIXIY(cpu);
}

// JR d
fn opJR_d(cpu: *CPU, tick_func: TickFunc) void {
    const d = dimm8(cpu, tick_func);
    cpu.PC +%= d;
    cpu.WZ = cpu.PC;
    tick(cpu, 5, 0, tick_func); // 5 filler ticks
}

// JR cc,d
fn opJR_cc_d(cpu: *CPU, y: u3, tick_func: TickFunc) void {
    const d = dimm8(cpu, tick_func);
    if (cc(cpu.regs[F], y -% 4)) {
        cpu.PC +%= d;
        cpu.WZ = cpu.PC;
        tick(cpu, 5, 0, tick_func); // 5 filler ticks
    }
}

// DJNZ_d
fn opDJNZ_d(cpu: *CPU, tick_func: TickFunc) void {
    tick(cpu, 1, 0, tick_func); // 1 filler tick
    const d = dimm8(cpu, tick_func);
    cpu.regs[B] -%= 1;
    if (cpu.regs[B] > 0) {
        cpu.PC +%= d;
        cpu.WZ = cpu.PC;
        tick(cpu, 5, 0, tick_func); // 5 filler ticks
    }
}

// CALL nn
fn opCALL_nn(cpu: *CPU, tick_func: TickFunc) void {
    const a16 = imm16(cpu, tick_func);
    tick(cpu, 1, 0, tick_func); // filler tick
    var sp = cpu.SP -% 1;
    cpu.pins = setAddrData(cpu.pins, sp, @truncate(u8, cpu.PC>>8));
    memWrite(cpu, tick_func);
    sp -%= 1;
    cpu.pins = setAddrData(cpu.pins, sp, @truncate(u8, cpu.PC));
    memWrite(cpu, tick_func);
    cpu.SP = sp;
    cpu.PC = a16;
}

// CALL_cc_nn
fn opCALL_cc_nn(cpu: *CPU, y: u3, tick_func: TickFunc) void {
    const a16 = imm16(cpu, tick_func);
    if (cc(cpu.regs[F], y)) {
        tick(cpu, 1, 0, tick_func); // filler tick
        var sp = cpu.SP -% 1;
        cpu.pins = setAddrData(cpu.pins, sp, @truncate(u8, cpu.PC>>8));
        memWrite(cpu, tick_func);
        sp -%= 1;
        cpu.pins = setAddrData(cpu.pins, sp, @truncate(u8, cpu.PC));
        memWrite(cpu, tick_func);
        cpu.SP = sp;
        cpu.PC = a16;
    }
}

// RET
fn opRET(cpu: *CPU, tick_func: TickFunc) void {
    var sp = cpu.SP;
    cpu.pins = setAddr(cpu.pins, sp);
    memRead(cpu, tick_func);
    const l = getData(cpu.pins);
    sp +%= 1;
    cpu.pins = setAddr(cpu.pins, sp);
    memRead(cpu, tick_func);
    const h = getData(cpu.pins);
    sp +%= 1;
    cpu.SP = sp;
    cpu.PC = @as(u16, h)<<8 | l;
    cpu.WZ = cpu.PC;
}

// RET_cc
fn opRET_cc(cpu: *CPU, y: u3, tick_func: TickFunc) void {
    tick(cpu, 1, 0, tick_func); // filler tick
    if (cc(cpu.regs[F], y)) {
        var sp = cpu.SP;
        cpu.pins = setAddr(cpu.pins, sp);
        memRead(cpu, tick_func);
        sp +%= 1;
        const l = getData(cpu.pins);
        cpu.pins = setAddr(cpu.pins, sp);
        memRead(cpu, tick_func);
        sp +%= 1;
        const h = getData(cpu.pins);
        cpu.SP = sp;
        cpu.PC = @as(u16, h)<<8 | l;
        cpu.WZ = cpu.PC;
    }
}

// ADD HL,rp
fn opADD_HL_rp(cpu: *CPU, p: u2, tick_func: TickFunc) void {
    const acc = loadHLIXIY(cpu);
    cpu.WZ = acc +% 1;
    const val = load16SP(cpu, p);
    const res: u17 = @as(u17,acc) +% val;
    storeHLIXIY(cpu, @truncate(u16, res));
    var f: u17 = cpu.regs[F] & (SF|ZF|VF);
    f |= ((acc^res^val)>>8) & HF;
    f |= ((res >> 16) & CF) | ((res >> 8) & (YF|XF));
    cpu.regs[F] = @truncate(u8, f);
    tick(cpu, 7, 0, tick_func); // filler ticks
}

// ADC HL,rp
fn opADC_HL_rp(cpu: *CPU, p: u2, tick_func: TickFunc) void {
    const acc = loadHLIXIY(cpu);
    cpu.WZ = acc +% 1;
    const val = load16SP(cpu, p);
    const res: u17 = @as(u17,acc) +% val +% (cpu.regs[F] & CF);
    storeHLIXIY(cpu, @truncate(u16, res));
    var f: u17 = ((val ^ acc ^ 0x8000) & (val ^ res) & 0x8000) >> 13;
    f |= ((acc ^ res ^ val) >> 8) & HF;
    f |= (res >> 16) & CF;
    f |= (res >> 8) & (SF|YF|XF);
    f |= if (0 == (res & 0xFFFF)) ZF else 0;
    cpu.regs[F] = @truncate(u8, f);
    tick(cpu, 7, 0, tick_func); // filler ticks
}

// SBC HL,rp
fn opSBC_HL_rp(cpu: *CPU, p: u2, tick_func: TickFunc) void {
    const acc = loadHLIXIY(cpu);
    cpu.WZ = acc +% 1;
    const val = load16SP(cpu, p);
    const res: u17 = acc -% val -% (cpu.regs[F] & CF);
    storeHLIXIY(cpu, @truncate(u16, res));
    var f: u17 = NF | (((val ^ acc) & (acc ^ res) & 0x8000) >> 13);
    f |= ((acc ^ res ^ val) >> 8) & HF;
    f |= (res >> 16) & CF;
    f |= (res >> 8) & (SF|YF|XF);
    f |= if (0 == (res & 0xFFFF)) ZF else 0;
    cpu.regs[F] = @truncate(u8, f);
    tick(cpu, 7, 0, tick_func); // filler ticks
}

// IN A,(n)
fn opIN_A_in(cpu: *CPU, tick_func: TickFunc) void {
    const n = imm8(cpu, tick_func);
    const port = (@as(u16, cpu.regs[A])<<8) | n;
    cpu.pins = setAddr(cpu.pins, port);
    ioRead(cpu, tick_func);
    cpu.regs[A] = getData(cpu.pins);
    cpu.WZ = port +% 1;
}

// OUT (n),A
fn opOUT_in_A(cpu: *CPU, tick_func: TickFunc) void {
    const n = imm8(cpu, tick_func);
    const a = cpu.regs[A];
    const port = (@as(u16, a)<<8) | n;
    cpu.pins = setAddrData(cpu.pins, port, a);
    ioWrite(cpu, tick_func);
    cpu.WZ = (port & 0xFF00) | ((port +% 1) & 0x00FF);
}

// IN r,(C)
fn opIN_ry_iC(cpu: *CPU, y: u3, tick_func: TickFunc) void {
    const bc = getR16(&cpu.regs, BC);
    cpu.pins = setAddr(cpu.pins, bc);
    ioRead(cpu, tick_func);
    cpu.WZ = bc +% 1;
    const val = getData(cpu.pins);
    cpu.regs[F] = (cpu.regs[F] & CF) | szpFlags(val);
    // undocumented special case for IN (HL),(C): only store flags, throw away input byte
    if (y != 6) {
        store8(cpu, y, val, tick_func);
    }
}

// OUT (C),r
fn opOUT_iC_ry(cpu: *CPU, y: u3, tick_func: TickFunc) void {
    const bc = getR16(&cpu.regs, BC);
    // undocumented special case for OUT (C),(HL): output 0 instead
    var val = if (y == 6) 0 else load8(cpu, y, tick_func);
    cpu.pins = setAddrData(cpu.pins, bc, val);
    ioWrite(cpu, tick_func);
    cpu.WZ = bc +% 1;
}

// INI/IND/INIR/INDR
fn opINI_IND_INIR_INDR(cpu: *CPU, y: u3, tick_func: TickFunc) void {
    tick(cpu, 1, 0, tick_func); // filler tick
    var port = getR16(&cpu.regs, BC);
    var hl = getR16(&cpu.regs, HL);
    cpu.pins = setAddr(cpu.pins, port);
    ioRead(cpu, tick_func);
    const val = getData(cpu.pins);
    cpu.pins = setAddr(cpu.pins, hl);
    memWrite(cpu, tick_func);
    const b = cpu.regs[B] -% 1;
    cpu.regs[B] = b;
    var c = cpu.regs[C];
    if (0 != (y & 1)) {
        port -%= 1; hl -%= 1; c -%= 1;
    }
    else {
        port +%= 1; hl +%= 1; c +%= 1;
    }
    setR16(&cpu.regs, HL, hl);
    cpu.WZ = port;
    var f = (if (b == 0) ZF else (b & SF)) | (b & (XF|YF));
    if (0 != (val & SF)) {
        f |= NF;
    }
    const t: u17 = @as(u17,c) + val;
    if (0 != (t & 0x100)) {
        f |= HF|CF;
    }
    f |= szpFlags((@truncate(u8,t) & 0x07) ^ b) & PF;
    cpu.regs[F] = f;
    if ((y >= 6) and (b != 0)) {
        cpu.PC -%= 2;
        tick(cpu, 5, 0, tick_func); // filler ticks
    }
}

// OUTI/OUTD/OTIR/OTDR
fn opOUTI_OUTD_OTIR_OTDR(cpu: *CPU, y: u3, tick_func: TickFunc) void {
    tick(cpu, 1, 0, tick_func); // filler tick
    var hl = getR16(&cpu.regs, HL);
    cpu.pins = setAddr(cpu.pins, hl);
    memRead(cpu, tick_func);
    const val = getData(cpu.pins);
    const b = cpu.regs[B] -% 1;
    cpu.regs[B] = b;
    var port = getR16(&cpu.regs, BC);
    cpu.pins = setAddr(cpu.pins, port);
    ioWrite(cpu, tick_func);
    if (0 != (y & 1)) {
        port -%= 1; hl -%= 1;
    }
    else {
        port +%= 1; hl +%= 1;
    }
    setR16(&cpu.regs, HL, hl);
    cpu.WZ = port;
    var f = (if (b == 0) ZF else (b & SF)) | (b & (XF|YF));
    if (0 != (val & SF)) {
        f |= NF;
    }
    const t: u17 = @as(u17, cpu.regs[L]) + val;
    if (0 != (t & 0x100)) {
        f |= HF|CF;
    }
    f |= szpFlags((@truncate(u8,t) & 0x07) ^ b) & PF;
    cpu.regs[F] = f;
    if ((y >= 6) and (b != 0)) {
        cpu.PC -%= 2;
        tick(cpu, 5, 0, tick_func); // filler ticks
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

// test cc flag
fn cc(f: u8, y: u3) bool {
    return switch (y) {
        0 => (0 == (f & ZF)),   // NZ
        1 => (0 != (f & ZF)),   // Z
        2 => (0 == (f & CF)),   // NC
        3 => (0 != (f & CF)),   // C
        4 => (0 == (f & PF)),   // PO
        5 => (0 != (f & PF)),   // PE
        6 => (0 == (f & SF)),   // P
        7 => (0 != (f & SF)),   // M
    };
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

fn inc8(r: *Regs, val: u8) u8 {
    const res = val +% 1;
    var f: u8 = szFlags(res) | (res & (XF|YF)) | ((res ^ val) & HF);
    f |= (((val ^ res) & res) >> 5) & VF;
    r[F] = f | (r[F] & CF);
    return res;
}

fn dec8(r: *Regs, val: u8) u8 {
    const res = val -% 1;
    var f: u8 = NF | szFlags(res) | (res & (XF|YF)) | ((res ^ val) & HF);
    f |= (((val ^ res) & val) >> 5) & VF;
    r[F] = f | (r[F] & CF);
    return res;
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
    const a = getAddr(pins);
    if ((pins & MREQ) != 0) {
        if ((pins & RD) != 0) {
            pins = setData(pins, mem[a]);
        }
        else if ((pins & WR) != 0) {
            mem[a] = getData(pins);
        }
    }
    else if ((pins & IORQ) != 0) {
        if ((pins & RD) != 0) {
            pins = setData(pins, io[a]);
        }
        else if ((pins & WR) != 0) {
            io[a] = getData(pins);
        }
    }
    return pins;
}

fn makeRegs() Regs {
    var res: Regs = [_]u8{0xFF} ** NumRegs8;
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
    var cpu = CPU{ .pins = setAddrData(0, 0x1234, 0x56) };
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
    var cpu = CPU{ .pins = setWait(0, 7) };
    tickWait(&cpu, 3, M1|MREQ|RD, inner.tick_func);
    try expect(getWait(cpu.pins) == 5);
    try expect(cpu.ticks == 8);
}

test "memRead" {
    clearMem();
    mem[0x1234] = 0x23;
    var cpu = CPU{ .pins = setAddr(0, 0x1234) };
    memRead(&cpu, testTick);
    try expect((cpu.pins & CtrlPinMask) == MREQ|RD);
    try expect(getData(cpu.pins) == 0x23);
    try expect(cpu.ticks == 3);
}

test "memWrite" {
    clearMem();
    var cpu = CPU{ .pins = setAddrData(0, 0x1234, 0x56) };
    memWrite(&cpu, testTick);
    try expect((cpu.pins & CtrlPinMask) == MREQ|WR);
    try expect(getData(cpu.pins) == 0x56);
    try expect(cpu.ticks == 3);
}

test "ioRead" {
    clearIO();
    io[0x1234] = 0x23;
    var cpu = CPU{ .pins = setAddr(0, 0x1234) };
    ioRead(&cpu, testTick);
    try expect((cpu.pins & CtrlPinMask) == IORQ|RD);
    try expect(getData(cpu.pins) == 0x23);
    try expect(cpu.ticks == 4);
}

test "ioWrite" {
    clearIO();
    var cpu = CPU{ .pins = setAddrData(0, 0x1234, 0x56) };
    ioWrite(&cpu, testTick);
    try expect((cpu.pins & CtrlPinMask) == IORQ|WR);
    try expect(getData(cpu.pins) == 0x56);
    try expect(cpu.ticks == 4);
}

test "bumpR" {
    // only 7 bits are incremented, and the topmost bit is sticky
    var cpu = CPU{ };
    cpu.R = 0x00; bumpR(&cpu); try expect(cpu.R == 1);
    cpu.R = 0x7F; bumpR(&cpu); try expect(cpu.R == 0);
    cpu.R = 0x80; bumpR(&cpu); try expect(cpu.R == 0x81);
    cpu.R = 0xFF; bumpR(&cpu); try expect(cpu.R == 0x80);
}

test "fetch" {
    clearMem();
    mem[0x2345] = 0x42;
    var cpu = CPU{ .PC = 0x2345, .R = 0 };
    const op = fetch(&cpu, testTick);
    try expect(op == 0x42);
    try expect((cpu.pins & CtrlPinMask) == M1|MREQ|RD);
    try expect(getData(cpu.pins) == 0x42);
    try expect(cpu.ticks == 4);
    try expect(cpu.PC == 0x2346);
    try expect(cpu.R == 1);
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
    r[A] = inc8(&r, r[A]); try expect(testRF(&r, A, 0x01, 0));
    r[A] = dec8(&r, r[A]); try expect(testRF(&r, A, 0x00, ZF|NF));
    r[B] = inc8(&r, r[B]); try expect(testRF(&r, B, 0x00, ZF|HF));
    r[B] = dec8(&r, r[B]); try expect(testRF(&r, B, 0xFF, SF|HF|NF));
    r[C] = inc8(&r, r[C]); try expect(testRF(&r, C, 0x10, HF));
    r[C] = dec8(&r, r[C]); try expect(testRF(&r, C, 0x0F, HF|NF));
    r[D] = inc8(&r, r[D]); try expect(testRF(&r, D, 0x0F, 0));
    r[D] = dec8(&r, r[D]); try expect(testRF(&r, D, 0x0E, NF));
    r[F] |= CF;
    r[E] = inc8(&r, r[E]); try expect(testRF(&r, E, 0x80, SF|HF|VF|CF)); 
    r[E] = dec8(&r, r[E]); try expect(testRF(&r, E, 0x7F, HF|VF|NF|CF));
    r[H] = inc8(&r, r[H]); try expect(testRF(&r, H, 0x3F, CF));
    r[H] = dec8(&r, r[H]); try expect(testRF(&r, H, 0x3E, NF|CF));
    r[L] = inc8(&r, r[L]); try expect(testRF(&r, L, 0x24, CF));
    r[L] = dec8(&r, r[L]); try expect(testRF(&r, L, 0x23, NF|CF));
}
