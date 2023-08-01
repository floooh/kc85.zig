///
/// A Z80 CPU EMULATOR
/// ==================
///
/// EMULATION OVERVIEW
/// ==================
///
/// The emulation is reasonably correct for behaviour that's observable from the
/// outside, all undocumented instructions tested by ZEXALL work, including
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
/// Start reading the code at 'fn exec('.
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
const CPU = @This();

pins: u64 = 0,
ticks: u64 = 0,

regs: Regs = [_]u8{0xFF} ** NumRegs8,

IX: u16 = 0xFFFF,
IY: u16 = 0xFFFF,
WZ: u16 = 0xFFFF,
SP: u16 = 0xFFFF,
PC: u16 = 0x0000,
I: u8 = 0x00,
R: u8 = 0x00,
IM: u2 = 0x00,

ex: [NumRegs16]u16 = [_]u16{0xFFFF} ** NumRegs16, // shadow registers

ixiy: u2 = 0, // UseIX or UseIY if indexed prefix 0xDD or 0xFD active
iff1: bool = false,
iff2: bool = false,
ei: bool = false,

// address bus pins
pub const A0: u64 = 1 << 0;
pub const A1: u64 = 1 << 1;
pub const A2: u64 = 1 << 2;
pub const A3: u64 = 1 << 3;
pub const A4: u64 = 1 << 4;
pub const A5: u64 = 1 << 5;
pub const A6: u64 = 1 << 6;
pub const A7: u64 = 1 << 7;
pub const A8: u64 = 1 << 8;
pub const A9: u64 = 1 << 9;
pub const A10: u64 = 1 << 10;
pub const A11: u64 = 1 << 11;
pub const A12: u64 = 1 << 12;
pub const A13: u64 = 1 << 13;
pub const A14: u64 = 1 << 14;
pub const A15: u64 = 1 << 15;
pub const AddrPinMask: u64 = 0xFFFF;

// data bus pins
pub const D0: u64 = 1 << 16;
pub const D1: u64 = 1 << 17;
pub const D2: u64 = 1 << 18;
pub const D3: u64 = 1 << 19;
pub const D4: u64 = 1 << 20;
pub const D5: u64 = 1 << 21;
pub const D6: u64 = 1 << 22;
pub const D7: u64 = 1 << 23;
pub const DataPinShift = 16;
pub const DataPinMask: u64 = 0xFF0000;

// system control pins
pub const M1: u64 = 1 << 24; // machine cycle 1
pub const MREQ: u64 = 1 << 25; // memory request
pub const IORQ: u64 = 1 << 26; // IO request
pub const RD: u64 = 1 << 27; // read request
pub const WR: u64 = 1 << 28; // write requst
pub const RFSH: u64 = 1 << 29; // memory refresh (not implemented)
pub const CtrlPinMask = M1 | MREQ | IORQ | RD | WR | RFSH;

// CPU control pins
pub const HALT: u64 = 1 << 30; // halt and catch fire
pub const INT: u64 = 1 << 31; // maskable interrupt requested
pub const NMI: u64 = 1 << 32; // non-maskable interrupt requested

// virtual pins
pub const WAIT0: u64 = 1 << 34; // 3 virtual pins to inject up to 8 wait cycles
pub const WAIT1: u64 = 1 << 35;
pub const WAIT2: u64 = 1 << 36;
pub const IEIO: u64 = 1 << 37; // interrupt daisy chain: interrupt-enable-I/O
pub const RETI: u64 = 1 << 38; // interrupt daisy chain: RETI decoded
pub const WaitPinShift = 34;
pub const WaitPinMask = WAIT0 | WAIT1 | WAIT2;

// all pins mask
pub const PinMask: u64 = (1 << 40) - 1;

// status flag bits
pub const CF: u8 = (1 << 0);
pub const NF: u8 = (1 << 1);
pub const VF: u8 = (1 << 2);
pub const PF: u8 = VF;
pub const XF: u8 = (1 << 3);
pub const HF: u8 = (1 << 4);
pub const YF: u8 = (1 << 5);
pub const ZF: u8 = (1 << 6);
pub const SF: u8 = (1 << 7);

// system tick callback with associated userdata
pub const TickFunc = struct {
    func: *const fn (num_ticks: u64, pins: u64, userdata: usize) u64,
    userdata: usize = 0,
};

/// run the emulator for at least 'num_ticks', return number of executed ticks
pub fn exec(self: *CPU, num_ticks: u64, tick_func: TickFunc) u64 {
    self.ticks = 0;
    while (self.ticks < num_ticks) {

        // store current pin state for edge-triggered NMI detection
        const pre_pins = self.pins;

        // fetch next opcode byte
        const op = self.fetch(tick_func);

        // decode opcode (see http://www.z80.info/decoding.htm)
        // |xx|yyy|zzz|
        const x: u2 = @truncate(op >> 6);
        const y: u3 = @truncate(op >> 3);
        const z: u3 = @truncate(op & 7);
        const p: u2 = @truncate(y >> 1);
        const q: u1 = @truncate(y);

        switch (x) {
            0 => switch (z) {
                0 => switch (y) {
                    0 => {}, // NOP
                    1 => self.opEX_AF_AF(),
                    2 => self.opDJNZ_d(tick_func),
                    3 => self.opJR_d(tick_func),
                    4...7 => self.opJR_cc_d(y, tick_func),
                },
                1 => switch (q) {
                    0 => self.opLD_rp_nn(p, tick_func),
                    1 => self.opADD_HL_rp(p, tick_func),
                },
                2 => switch (y) {
                    0 => self.opLD_iBCDE_A(BC, tick_func),
                    1 => self.opLD_A_iBCDE(BC, tick_func),
                    2 => self.opLD_iBCDE_A(DE, tick_func),
                    3 => self.opLD_A_iBCDE(DE, tick_func),
                    4 => self.opLD_inn_HL(tick_func),
                    5 => self.opLD_HL_inn(tick_func),
                    6 => self.opLD_inn_A(tick_func),
                    7 => self.opLD_A_inn(tick_func),
                },
                3 => switch (q) {
                    0 => self.opINC_rp(p, tick_func),
                    1 => self.opDEC_rp(p, tick_func),
                },
                4 => self.opINC_r(y, tick_func),
                5 => self.opDEC_r(y, tick_func),
                6 => self.opLD_r_n(y, tick_func),
                7 => switch (y) {
                    0 => self.opRLCA(),
                    1 => self.opRRCA(),
                    2 => self.opRLA(),
                    3 => self.opRRA(),
                    4 => self.opDAA(),
                    5 => self.opCPL(),
                    6 => self.opSCF(),
                    7 => self.opCCF(),
                },
            },
            1 => {
                if (y == 6 and z == 6) {
                    self.opHALT();
                } else {
                    self.opLD_r_r(y, z, tick_func);
                }
            },
            2 => self.opALU_r(y, z, tick_func),
            3 => switch (z) {
                0 => self.opRET_cc(y, tick_func),
                1 => switch (q) {
                    0 => self.opPOP_rp2(p, tick_func),
                    1 => switch (p) {
                        0 => self.opRET(tick_func),
                        1 => self.opEXX(),
                        2 => self.opJP_HL(),
                        3 => self.opLD_SP_HL(tick_func),
                    },
                },
                2 => self.opJP_cc_nn(y, tick_func),
                3 => switch (y) {
                    0 => self.opJP_nn(tick_func),
                    1 => self.opCB_prefix(tick_func),
                    2 => self.opOUT_in_A(tick_func),
                    3 => self.opIN_A_in(tick_func),
                    4 => self.opEX_iSP_HL(tick_func),
                    5 => self.opEX_DE_HL(),
                    6 => self.opDI(),
                    7 => self.opEI(),
                },
                4 => self.opCALL_cc_nn(y, tick_func),
                5 => switch (q) {
                    0 => self.opPUSH_rp2(p, tick_func),
                    1 => switch (p) {
                        0 => self.opCALL_nn(tick_func),
                        1 => {
                            self.ixiy = UseIX;
                            continue;
                        }, // no interrupt handling after DD prefix
                        2 => self.opED_prefix(tick_func),
                        3 => {
                            self.ixiy = UseIY;
                            continue;
                        }, // no interrupt handling after FD prefix
                    },
                },
                6 => self.opALU_n(y, tick_func),
                7 => self.opRSTy(y, tick_func),
            },
        }

        // handle IRQ (level-triggered) and NMI (edge-triggered)
        const nmi: bool = 0 != ((self.pins & (self.pins ^ pre_pins)) & NMI);
        const int: bool = self.iff1 and (0 != (self.pins & INT));
        if (nmi or int) {
            self.handleInterrupt(nmi, int, tick_func);
        }

        // clear IX/IY prefix flag and update enable-interrupt flags if last op was EI
        self.ixiy = 0;
        if (self.ei) {
            self.ei = false;
            self.iff1 = true;
            self.iff2 = true;
        }
        self.pins &= ~INT;
    }
    return self.ticks;
}

// return true if not in the middle of an indexed op (DD / FD)
pub fn opdone(self: *CPU) bool {
    return 0 == self.ixiy;
}

// set/get 8-bit register value
pub const B = 0;
pub const C = 1;
pub const D = 2;
pub const E = 3;
pub const H = 4;
pub const L = 5;
pub const F = 6;
pub const A = 7;
pub const NumRegs8 = 8;

pub fn setR8(self: *CPU, reg: u3, val: u8) void {
    self.regs[reg] = val;
}

pub fn r8(self: *CPU, reg: u3) u8 {
    return self.regs[reg];
}

// set/get 16-bit register value (BC, DE, HL, FA)
pub const BC = 0;
pub const DE = 1;
pub const HL = 2;
pub const FA = 3;
pub const NumRegs16 = 4;

pub fn setR16(self: *CPU, reg: u2, val: u16) void {
    self.regs[@as(u3, reg) * 2 + 0] = @truncate(val >> 8);
    self.regs[@as(u3, reg) * 2 + 1] = @truncate(val);
}

pub fn r16(self: *CPU, reg: u2) u16 {
    const h = self.regs[@as(u3, reg) * 2 + 0];
    const l = self.regs[@as(u3, reg) * 2 + 1];
    return @as(u16, h) << 8 | l;
}

// set/get wait ticks on pin mask
pub fn setWait(pins: u64, wait_ticks: u3) u64 {
    return (pins & ~WaitPinMask) | (wait_ticks << WaitPinShift);
}

pub fn getWait(pins: u64) u3 {
    return @truncate(pins >> WaitPinShift);
}

// set/get address pins in pin mask
pub fn setAddr(pins: u64, a: u16) u64 {
    return (pins & ~AddrPinMask) | a;
}

pub fn getAddr(pins: u64) u16 {
    return @truncate(pins);
}

// set/get data pins in pin mask
pub fn setData(pins: u64, data: u8) u64 {
    return (pins & ~DataPinMask) | (@as(u64, data) << DataPinShift);
}

pub fn getData(pins: u64) u8 {
    return @truncate(pins >> DataPinShift);
}

// set address and data pins in pin mask
pub fn setAddrData(pins: u64, a: u16, d: u8) u64 {
    return (pins & ~(DataPinMask | AddrPinMask)) | (@as(u64, d) << DataPinShift) | a;
}

const Regs = [NumRegs8]u8;

const UseIX = (1 << 0);
const UseIY = (1 << 1);

// handle maskable and non-maskable interrupt requests
fn handleInterrupt(self: *CPU, nmi: bool, int: bool, tick_func: TickFunc) void {
    // clear IFF flags (disables interrupt)
    self.iff1 = false;
    if (int) {
        self.iff2 = false;
    }
    // interrupts deactivate HALT state
    if (0 != (self.pins & HALT)) {
        self.pins &= ~HALT;
        self.PC +%= 1;
    }
    // put PC on address bus
    self.pins = setAddr(self.pins, self.PC);
    if (nmi) {
        // non-maskable interrupt

        // perform a dummy 5-tick (not 4!) opcode fetch, don't bump PC
        self.tickWait(5, M1 | MREQ | RD, tick_func);
        self.bumpR();
        // put PC on stack
        self.push16(self.PC, tick_func);
        // jump to address 0x66
        self.PC = 0x0066;
        self.WZ = self.PC;
    } else {
        // maskable interrupt

        // interrupt acknowledge machine cycle, interrupt
        // controller is expected to put interrupt vector low byte
        // on address bus
        self.tickWait(4, M1 | IORQ, tick_func);
        const int_vec = getData(self.pins);
        self.bumpR();
        self.tick(2, 0, tick_func); // 2 filler ticks
        switch (self.IM) {
            0 => {
                // interrupt mode 0 not implemented
            },
            1 => {
                // interrupt mode 1:
                //  - put PC on stack
                //  - load address 0x0038 into PC
                self.push16(self.PC, tick_func);
                self.PC = 0x0038;
                self.WZ = self.PC;
            },
            2 => {
                // interrupt mode 2:
                //  - put PC on stack
                //  - build interrupt vector address
                //  - load interrupt service routine from interrupt vector into PC
                self.push16(self.PC, tick_func);
                var addr = (@as(u16, self.I) << 8) | (int_vec & 0xFE);
                const z: u16 = self.memRead(addr, tick_func);
                addr +%= 1;
                const w: u16 = self.memRead(addr, tick_func);
                self.PC = (w << 8) | z;
                self.WZ = self.PC;
            },
            else => unreachable,
        }
    }
}

// ED-prefix decoding
fn opED_prefix(self: *CPU, tick_func: TickFunc) void {

    // ED prefix cancels the IX/IY prefix
    self.ixiy = 0;

    const op = self.fetch(tick_func);
    const x: u2 = @truncate(op >> 6);
    const y: u3 = @truncate(op >> 3);
    const z: u3 = @truncate(op & 7);
    const p: u2 = @truncate(y >> 1);
    const q: u1 = @truncate(y);

    switch (x) {
        1 => switch (z) {
            0 => self.opIN_ry_iC(y, tick_func),
            1 => self.opOUT_iC_ry(y, tick_func),
            2 => switch (q) {
                0 => self.opSBC_HL_rp(p, tick_func),
                1 => self.opADC_HL_rp(p, tick_func),
            },
            3 => switch (q) {
                0 => self.opLD_inn_rp(p, tick_func),
                1 => self.opLD_rp_inn(p, tick_func),
            },
            4 => self.opNEG(),
            5 => self.opRETNI(tick_func),
            6 => self.opIM(y),
            7 => switch (y) {
                0 => self.opLD_I_A(tick_func),
                1 => self.opLD_R_A(tick_func),
                2 => self.opLD_A_I(tick_func),
                3 => self.opLD_A_R(tick_func),
                4 => self.opRRD(tick_func),
                5 => self.opRLD(tick_func),
                6, 7 => {}, // NONI + NOP
            },
        },
        2 => switch (z) {
            0 => switch (y) {
                4...7 => self.opLDI_LDD_LDIR_LDDR(y, tick_func),
                else => {}, // NONI + NOP
            },
            1 => switch (y) {
                4...7 => self.opCPI_CPD_CPIR_CPDR(y, tick_func),
                else => {}, // NONI + NOP
            },
            2 => switch (y) {
                4...7 => self.opINI_IND_INIR_INDR(y, tick_func),
                else => {}, // NONI + NOP
            },
            3 => switch (y) {
                4...7 => self.opOUTI_OUTD_OTIR_OTDR(y, tick_func),
                else => {}, // NONI + NOP
            },
            else => {}, // NONI + NOP
        },
        else => {}, // 0, 3 -> NONI + NOP
    }
}

// return flags for left/right-shift/rotate operations
fn lsrFlags(d8: u8, r: u8) u8 {
    return szpFlags(r) | ((d8 >> 7) & CF);
}

fn rsrFlags(d8: u8, r: u8) u8 {
    return szpFlags(r) | (d8 & CF);
}

// CB-prefix decoding (very, very special case)
fn opCB_prefix(self: *CPU, tick_func: TickFunc) void {
    // special handling for undocumented DD/FD+CB double prefix instructions,
    // these always load the value from memory (IX+d),
    // and write the value back, even for normal
    // "register" instructions
    // see: http://www.baltazarstudios.com/files/ddcb.html
    const d: u16 = if (self.ixiy != 0) self.dimm8(tick_func) else 0;

    // special opcode fetch without memory refresh and bumpR()
    const op = self.fetchCB(tick_func);
    const x: u2 = @truncate(op >> 6);
    const y: u3 = @truncate(op >> 3);
    const z: u3 = @truncate(op & 7);

    // load operand (for indexed ops always from memory)
    const d8: u8 = if ((z == 6) or (self.ixiy != 0)) blk: {
        self.tick(1, 0, tick_func); // filler tick
        self.WZ = self.loadHLIXIY();
        if (self.ixiy != 0) {
            self.tick(1, 0, tick_func); // filler tick
            self.WZ +%= d;
        }
        break :blk self.memRead(self.WZ, tick_func);
    } else self.load8(z, tick_func);

    var f: u8 = self.regs[F];
    var r: u8 = undefined;
    switch (x) {
        0 => switch (y) {
            // rot/shift
            0 => {
                r = d8 << 1 | d8 >> 7;
                f = lsrFlags(d8, r);
            }, // RLC
            1 => {
                r = d8 >> 1 | d8 << 7;
                f = rsrFlags(d8, r);
            }, // RRC
            2 => {
                r = d8 << 1 | (f & CF);
                f = lsrFlags(d8, r);
            }, // RL
            3 => {
                r = d8 >> 1 | ((f & CF) << 7);
                f = rsrFlags(d8, r);
            }, // RR
            4 => {
                r = d8 << 1;
                f = lsrFlags(d8, r);
            }, // SLA
            5 => {
                r = d8 >> 1 | (d8 & 0x80);
                f = rsrFlags(d8, r);
            }, // SRA
            6 => {
                r = d8 << 1 | 1;
                f = lsrFlags(d8, r);
            }, // SLL
            7 => {
                r = d8 >> 1;
                f = rsrFlags(d8, r);
            }, // SRL
        },
        1 => {
            // BIT (bit test)
            r = d8 & (@as(u8, 1) << y);
            f = (f & CF) | HF | if (r == 0) ZF | PF else r & SF;
            if ((z == 6) or (self.ixiy != 0)) {
                f |= @as(u8, @truncate(self.WZ >> 8)) & (YF | XF);
            } else {
                f |= d8 & (YF | XF);
            }
        },
        2 => {
            // RES (bit clear)
            r = d8 & ~(@as(u8, 1) << y);
        },
        3 => {
            // SET (bit set)
            r = d8 | (@as(u8, 1) << y);
        },
    }
    if (x != 1) {
        // write result back
        if ((z == 6) or (self.ixiy != 0)) {
            // (HL), (IX+d), (IY+d): write back to memory, for extended op,
            // even when the op is actually a register op
            self.memWrite(self.WZ, r, tick_func);
        }
        if (z != 6) {
            // write result back to register, never write back to overriden IXH/IYH/IXL/IYL
            self.store8HL(z, r, tick_func);
        }
    }
    self.regs[F] = f;
}

// helper function to increment R register
fn bumpR(self: *CPU) void {
    self.R = (self.R & 0x80) | ((self.R +% 1) & 0x7F);
}

// invoke tick callback with control pins set
fn tick(self: *CPU, num_ticks: u64, pin_mask: u64, tick_func: TickFunc) void {
    self.pins = tick_func.func(num_ticks, (self.pins & ~CtrlPinMask) | pin_mask, tick_func.userdata);
    self.ticks += num_ticks;
}

// invoke tick callback with pin mask and wait state detection
fn tickWait(self: *CPU, num_ticks: u64, pin_mask: u64, tick_func: TickFunc) void {
    self.pins = tick_func.func(num_ticks, (self.pins & ~(CtrlPinMask | WaitPinMask) | pin_mask), tick_func.userdata);
    self.ticks += num_ticks + getWait(self.pins);
}

// perform a memory-read machine cycle (3 clock cycles)
fn memRead(self: *CPU, addr: u16, tick_func: TickFunc) u8 {
    self.pins = setAddr(self.pins, addr);
    self.tickWait(3, MREQ | RD, tick_func);
    return getData(self.pins);
}

// perform a memory-write machine cycle (3 clock cycles)
fn memWrite(self: *CPU, addr: u16, data: u8, tick_func: TickFunc) void {
    self.pins = setAddrData(self.pins, addr, data);
    self.tickWait(3, MREQ | WR, tick_func);
}

// perform an IO input machine cycle (4 clock cycles)
fn ioRead(self: *CPU, addr: u16, tick_func: TickFunc) u8 {
    self.pins = setAddr(self.pins, addr);
    self.tickWait(4, IORQ | RD, tick_func);
    return getData(self.pins);
}

// perform a IO output machine cycle (4 clock cycles)
fn ioWrite(self: *CPU, addr: u16, data: u8, tick_func: TickFunc) void {
    self.pins = setAddrData(self.pins, addr, data);
    self.tickWait(4, IORQ | WR, tick_func);
}

// read unsigned 8-bit immediate
fn imm8(self: *CPU, tick_func: TickFunc) u8 {
    const val = self.memRead(self.PC, tick_func);
    self.PC +%= 1;
    return val;
}

// read the signed 8-bit address offset for IX/IX+d ops extended to unsigned 16-bit
fn dimm8(self: *CPU, tick_func: TickFunc) u16 {
    return @bitCast(@as(i16, @as(i8, @bitCast(self.imm8(tick_func)))));
}

// helper function to push 16 bit value on stack
fn push16(self: *CPU, val: u16, tick_func: TickFunc) void {
    self.SP -%= 1;
    self.memWrite(self.SP, @truncate(val >> 8), tick_func);
    self.SP -%= 1;
    self.memWrite(self.SP, @truncate(val), tick_func);
}

// helper function pop 16 bit value from stack
fn pop16(self: *CPU, tick_func: TickFunc) u16 {
    const l: u16 = self.memRead(self.SP, tick_func);
    self.SP +%= 1;
    const h: u16 = self.memRead(self.SP, tick_func);
    self.SP +%= 1;
    return (h << 8) | l;
}

// generate effective address for (HL), (IX+d), (IY+d) and put into WZ
fn addrWZ(self: *CPU, extra_ticks: u64, tick_func: TickFunc) void {
    self.WZ = self.loadHLIXIY();
    if (0 != self.ixiy) {
        const d = self.dimm8(tick_func);
        self.WZ +%= d;
        self.tick(extra_ticks, 0, tick_func);
    }
}

// perform an opcode fetch machine cycle
fn fetch(self: *CPU, tick_func: TickFunc) u8 {
    self.pins = setAddr(self.pins, self.PC);
    self.tickWait(4, M1 | MREQ | RD, tick_func);
    self.PC +%= 1;
    self.bumpR();
    return getData(self.pins);
}

// special opcode fetch without memory refresh and special R handling for IX/IY prefix case
fn fetchCB(self: *CPU, tick_func: TickFunc) u8 {
    self.pins = setAddr(self.pins, self.PC);
    self.tickWait(4, M1 | MREQ | RD, tick_func);
    self.PC +%= 1;
    if (0 == self.ixiy) {
        self.bumpR();
    }
    return getData(self.pins);
}

// read 16-bit immediate
fn imm16(self: *CPU, tick_func: TickFunc) u16 {
    const z: u16 = self.memRead(self.PC, tick_func);
    self.PC +%= 1;
    const w: u16 = self.memRead(self.PC, tick_func);
    self.PC +%= 1;
    self.WZ = (w << 8) | z;
    return self.WZ;
}

// load from 8-bit register or effective address (HL)/(IX+d)/IY+d)
fn load8(self: *CPU, z: u3, tick_func: TickFunc) u8 {
    return switch (z) {
        B, C, D, E, A => self.regs[z],
        H => switch (self.ixiy) {
            0 => self.regs[H],
            UseIX => @truncate(self.IX >> 8),
            UseIY => @truncate(self.IY >> 8),
            else => unreachable,
        },
        L => switch (self.ixiy) {
            0 => self.regs[L],
            UseIX => @truncate(self.IX),
            UseIY => @truncate(self.IY),
            else => unreachable,
        },
        F => self.memRead(self.WZ, tick_func),
    };
}

// same as load8, but also never replace H,L with IXH,IYH,IXH,IXL
fn load8HL(self: *CPU, z: u3, tick_func: TickFunc) u8 {
    if (z != 6) {
        return self.regs[z];
    } else {
        return self.memRead(self.WZ, tick_func);
    }
}

// store into 8-bit register or effective address (HL)/(IX+d)/(IY+d)
fn store8(self: *CPU, y: u3, val: u8, tick_func: TickFunc) void {
    switch (y) {
        B, C, D, E, A => {
            self.regs[y] = val;
        },
        H => switch (self.ixiy) {
            0 => {
                self.regs[H] = val;
            },
            UseIX => {
                self.IX = (self.IX & 0x00FF) | (@as(u16, val) << 8);
            },
            UseIY => {
                self.IY = (self.IY & 0x00FF) | (@as(u16, val) << 8);
            },
            else => unreachable,
        },
        L => switch (self.ixiy) {
            0 => {
                self.regs[L] = val;
            },
            UseIX => {
                self.IX = (self.IX & 0xFF00) | val;
            },
            UseIY => {
                self.IY = (self.IY & 0xFF00) | val;
            },
            else => unreachable,
        },
        F => self.memWrite(self.WZ, val, tick_func),
    }
}

// same as store8, but never replace H,L with IXH,IYH, IXL, IYL
fn store8HL(self: *CPU, y: u3, val: u8, tick_func: TickFunc) void {
    if (y != 6) {
        self.regs[y] = val;
    } else {
        self.memWrite(self.WZ, val, tick_func);
    }
}

// store into HL, IX or IY, depending on current index mode
fn storeHLIXIY(self: *CPU, val: u16) void {
    switch (self.ixiy) {
        0 => self.setR16(HL, val),
        UseIX => self.IX = val,
        UseIY => self.IY = val,
        else => unreachable,
    }
}

// store 16-bit value into register with special handling for SP
fn store16SP(self: *CPU, reg: u2, val: u16) void {
    switch (reg) {
        BC => self.setR16(BC, val),
        DE => self.setR16(DE, val),
        HL => self.storeHLIXIY(val),
        FA => self.SP = val,
    }
}

// store 16-bit value into register with special case handling for AF
fn store16AF(self: *CPU, reg: u2, val: u16) void {
    switch (reg) {
        BC => self.setR16(BC, val),
        DE => self.setR16(DE, val),
        HL => self.storeHLIXIY(val),
        FA => {
            self.regs[F] = @truncate(val);
            self.regs[A] = @truncate(val >> 8);
        },
    }
}

// load from HL, IX or IY, depending on current index mode
fn loadHLIXIY(self: *CPU) u16 {
    return switch (self.ixiy) {
        0 => self.r16(HL),
        UseIX => return self.IX,
        UseIY => return self.IY,
        else => unreachable,
    };
}

// load 16-bit value from register with special handling for SP
fn load16SP(self: *CPU, reg: u2) u16 {
    return switch (reg) {
        BC => self.r16(BC),
        DE => self.r16(DE),
        HL => self.loadHLIXIY(),
        FA => self.SP,
    };
}

// load 16-bit value from register with special case handling for AF
fn load16AF(self: *CPU, reg: u2) u16 {
    return switch (reg) {
        BC => self.r16(BC),
        DE => self.r16(DE),
        HL => self.loadHLIXIY(),
        FA => @as(u16, self.regs[A]) << 8 | self.regs[F],
    };
}

// HALT
fn opHALT(self: *CPU) void {
    self.pins |= HALT;
    self.PC -%= 1;
}

// LD r,r
fn opLD_r_r(self: *CPU, y: u3, z: u3, tick_func: TickFunc) void {
    if ((y == 6) or (z == 6)) {
        self.addrWZ(5, tick_func);
        // for (IX+d)/(IY+d), H and L are not replaced with IXH/IYH and IYH/IYL
        const val = self.load8HL(z, tick_func);
        self.store8HL(y, val, tick_func);
    } else {
        // regular LD r,r may map H and L to IXH/IYH and IXL/IYL
        const val = self.load8(z, tick_func);
        self.store8(y, val, tick_func);
    }
}

// LD r,n
fn opLD_r_n(self: *CPU, y: u3, tick_func: TickFunc) void {
    if (y == 6) {
        self.addrWZ(2, tick_func);
    }
    const val = self.imm8(tick_func);
    self.store8(y, val, tick_func);
}

// ALU r
fn opALU_r(self: *CPU, y: u3, z: u3, tick_func: TickFunc) void {
    if (z == 6) {
        self.addrWZ(5, tick_func);
    }
    const val = self.load8(z, tick_func);
    alu8(&self.regs, y, val);
}

// ALU n
fn opALU_n(self: *CPU, y: u3, tick_func: TickFunc) void {
    const val = self.imm8(tick_func);
    alu8(&self.regs, y, val);
}

// NEG
fn opNEG(self: *CPU) void {
    neg8(&self.regs);
}

// INC r
fn opINC_r(self: *CPU, y: u3, tick_func: TickFunc) void {
    if (y == 6) {
        self.addrWZ(5, tick_func);
        self.tick(1, 0, tick_func); // filler tick
    }
    const val = self.load8(y, tick_func);
    const res = inc8(&self.regs, val);
    self.store8(y, res, tick_func);
}

// DEC r
fn opDEC_r(self: *CPU, y: u3, tick_func: TickFunc) void {
    if (y == 6) {
        self.addrWZ(5, tick_func);
        self.tick(1, 0, tick_func); // filler tick
    }
    const val = self.load8(y, tick_func);
    const res = dec8(&self.regs, val);
    self.store8(y, res, tick_func);
}

// INC rp
fn opINC_rp(self: *CPU, p: u2, tick_func: TickFunc) void {
    self.tick(2, 0, tick_func); // 2 filler ticks
    self.store16SP(p, self.load16SP(p) +% 1);
}

// DEC rp
fn opDEC_rp(self: *CPU, p: u2, tick_func: TickFunc) void {
    self.tick(2, 0, tick_func); // 2 filler tick
    self.store16SP(p, self.load16SP(p) -% 1);
}

// LD rp,nn
fn opLD_rp_nn(self: *CPU, p: u2, tick_func: TickFunc) void {
    const val = self.imm16(tick_func);
    self.store16SP(p, val);
}

// LD (BC/DE),A
fn opLD_iBCDE_A(self: *CPU, r: u2, tick_func: TickFunc) void {
    self.WZ = self.r16(r);
    const val = self.regs[A];
    self.memWrite(self.WZ, val, tick_func);
    self.WZ = (@as(u16, val) << 8) | ((self.WZ +% 1) & 0xFF);
}

// LD A,(BC/DE)
fn opLD_A_iBCDE(self: *CPU, r: u2, tick_func: TickFunc) void {
    self.WZ = self.r16(r);
    self.regs[A] = self.memRead(self.WZ, tick_func);
    self.WZ +%= 1;
}

// LD (nn),HL
fn opLD_inn_HL(self: *CPU, tick_func: TickFunc) void {
    self.WZ = self.imm16(tick_func);
    const val = self.loadHLIXIY();
    self.memWrite(self.WZ, @truncate(val), tick_func);
    self.WZ +%= 1;
    self.memWrite(self.WZ, @truncate(val >> 8), tick_func);
}

// LD HL,(nn)
fn opLD_HL_inn(self: *CPU, tick_func: TickFunc) void {
    self.WZ = self.imm16(tick_func);
    const l: u16 = self.memRead(self.WZ, tick_func);
    self.WZ +%= 1;
    const h: u16 = self.memRead(self.WZ, tick_func);
    self.storeHLIXIY((h << 8) | l);
}

// LD (nn),A
fn opLD_inn_A(self: *CPU, tick_func: TickFunc) void {
    self.WZ = self.imm16(tick_func);
    const val = self.regs[A];
    self.memWrite(self.WZ, val, tick_func);
    self.WZ = (@as(u16, val) << 8) | ((self.WZ +% 1) & 0xFF);
}

// LD A,(nn)
fn opLD_A_inn(self: *CPU, tick_func: TickFunc) void {
    self.WZ = self.imm16(tick_func);
    self.regs[A] = self.memRead(self.WZ, tick_func);
    self.WZ +%= 1;
}

// LD (nn),BC/DE/HL/SP
fn opLD_inn_rp(self: *CPU, p: u2, tick_func: TickFunc) void {
    self.WZ = self.imm16(tick_func);
    const val = self.load16SP(p);
    self.memWrite(self.WZ, @truncate(val), tick_func);
    self.WZ +%= 1;
    self.memWrite(self.WZ, @truncate(val >> 8), tick_func);
}

// LD BC/DE/HL/SP,(nn)
fn opLD_rp_inn(self: *CPU, p: u2, tick_func: TickFunc) void {
    self.WZ = self.imm16(tick_func);
    const l: u16 = self.memRead(self.WZ, tick_func);
    self.WZ +%= 1;
    const h: u16 = self.memRead(self.WZ, tick_func);
    self.store16SP(p, (h << 8) | l);
}

// LD SP,HL/IX/IY
fn opLD_SP_HL(self: *CPU, tick_func: TickFunc) void {
    self.tick(2, 0, tick_func); // 2 filler ticks
    self.SP = self.loadHLIXIY();
}

// LD I,A
fn opLD_I_A(self: *CPU, tick_func: TickFunc) void {
    self.tick(1, 0, tick_func); // 1 filler tick
    self.I = self.regs[A];
}

// LD R,A
fn opLD_R_A(self: *CPU, tick_func: TickFunc) void {
    self.tick(1, 0, tick_func); // 1 filler tick
    self.R = self.regs[A];
}

// special flag computation for LD_A,I / LD A,R
fn irFlags(val: u8, f: u8, iff2: bool) u8 {
    return (f & CF) | szFlags(val) | (val & YF | XF) | if (iff2) PF else 0;
}

// LD A,I
fn opLD_A_I(self: *CPU, tick_func: TickFunc) void {
    self.tick(1, 0, tick_func); // 1 filler tick
    self.regs[A] = self.I;
    self.regs[F] = irFlags(self.regs[A], self.regs[F], self.iff2);
}

// LD A,R
fn opLD_A_R(self: *CPU, tick_func: TickFunc) void {
    self.tick(1, 0, tick_func); // 1 filler tick
    self.regs[A] = self.R;
    self.regs[F] = irFlags(self.regs[A], self.regs[F], self.iff2);
}

// PUSH BC/DE/HL/AF/IX/IY
fn opPUSH_rp2(self: *CPU, p: u2, tick_func: TickFunc) void {
    self.tick(1, 0, tick_func); // 1 filler tick
    const val = self.load16AF(p);
    self.push16(val, tick_func);
}

// POP BC/DE/HL/AF/IX/IY
fn opPOP_rp2(self: *CPU, p: u2, tick_func: TickFunc) void {
    const val = self.pop16(tick_func);
    self.store16AF(p, val);
}

// EX DE,HL
fn opEX_DE_HL(self: *CPU) void {
    const de = self.r16(DE);
    const hl = self.r16(HL);
    self.setR16(DE, hl);
    self.setR16(HL, de);
}

// EX AF,AF'
fn opEX_AF_AF(self: *CPU) void {
    const fa = self.r16(FA);
    self.setR16(FA, self.ex[FA]);
    self.ex[FA] = fa;
}

// EXX
fn opEXX(self: *CPU) void {
    const bc = self.r16(BC);
    self.setR16(BC, self.ex[BC]);
    self.ex[BC] = bc;
    const de = self.r16(DE);
    self.setR16(DE, self.ex[DE]);
    self.ex[DE] = de;
    const hl = self.r16(HL);
    self.setR16(HL, self.ex[HL]);
    self.ex[HL] = hl;
}

// EX (SP),HL
fn opEX_iSP_HL(self: *CPU, tick_func: TickFunc) void {
    self.tick(3, 0, tick_func); // 3 filler ticks
    const l: u16 = self.memRead(self.SP, tick_func);
    const h: u16 = self.memRead(self.SP +% 1, tick_func);
    const val = self.loadHLIXIY();
    self.memWrite(self.SP, @truncate(val), tick_func);
    self.memWrite(self.SP +% 1, @truncate(val >> 8), tick_func);
    self.WZ = (h << 8) | l;
    self.storeHLIXIY(self.WZ);
}

// RLCA
fn opRLCA(self: *CPU) void {
    const a = self.regs[A];
    const r = (a << 1) | (a >> 7);
    const f = self.regs[F];
    self.regs[F] = ((a >> 7) & CF) | (f & (SF | ZF | PF)) | (r & (YF | XF));
    self.regs[A] = r;
}

// RRCA
fn opRRCA(self: *CPU) void {
    const a = self.regs[A];
    const r = (a >> 1) | (a << 7);
    const f = self.regs[F];
    self.regs[F] = (a & CF) | (f & (SF | ZF | PF)) | (r & (YF | XF));
    self.regs[A] = r;
}

// RLA
fn opRLA(self: *CPU) void {
    const a = self.regs[A];
    const f = self.regs[F];
    const r = (a << 1) | (f & CF);
    self.regs[F] = ((a >> 7) & CF) | (f & (SF | ZF | PF)) | (r & (YF | XF));
    self.regs[A] = r;
}

// RRA
fn opRRA(self: *CPU) void {
    const a = self.regs[A];
    const f = self.regs[F];
    const r = (a >> 1) | ((f & CF) << 7);
    self.regs[F] = (a & CF) | (f & (SF | ZF | PF)) | (r & (YF | XF));
    self.regs[A] = r;
}

// RLD
fn opRLD(self: *CPU, tick_func: TickFunc) void {
    self.WZ = self.loadHLIXIY();
    const d_in = self.memRead(self.WZ, tick_func);
    const a_in = self.regs[A];
    const a_out = (a_in & 0xF0) | (d_in >> 4);
    const d_out = (d_in << 4) | (a_in & 0x0F);
    self.memWrite(self.WZ, d_out, tick_func);
    self.WZ +%= 1;
    self.regs[A] = a_out;
    self.regs[F] = (self.regs[F] & CF) | szpFlags(a_out);
    self.tick(4, 0, tick_func); // 4 filler ticks
}

// RRD
fn opRRD(self: *CPU, tick_func: TickFunc) void {
    self.WZ = self.loadHLIXIY();
    const d_in = self.memRead(self.WZ, tick_func);
    const a_in = self.regs[A];
    const a_out = (a_in & 0xF0) | (d_in & 0x0F);
    const d_out = (d_in >> 4) | (a_in << 4);
    self.memWrite(self.WZ, d_out, tick_func);
    self.WZ +%= 1;
    self.regs[A] = a_out;
    self.regs[F] = (self.regs[F] & CF) | szpFlags(a_out);
    self.tick(4, 0, tick_func); // 4 filler ticks
}

// DAA
fn opDAA(self: *CPU) void {
    const a = self.regs[A];
    var v = a;
    var f = self.regs[F];
    if (0 != (f & NF)) {
        if (((a & 0xF) > 0x9) or (0 != (f & HF))) {
            v -%= 0x06;
        }
        if ((a > 0x99) or (0 != (f & CF))) {
            v -%= 0x60;
        }
    } else {
        if (((a & 0xF) > 0x9) or (0 != (f & HF))) {
            v +%= 0x06;
        }
        if ((a > 0x99) or (0 != (f & CF))) {
            v +%= 0x60;
        }
    }
    f &= CF | NF;
    f |= if (a > 0x99) CF else 0;
    f |= (a ^ v) & HF;
    f |= szpFlags(v);
    self.regs[A] = v;
    self.regs[F] = f;
}

// CPL
fn opCPL(self: *CPU) void {
    const a = self.regs[A] ^ 0xFF;
    const f = self.regs[F];
    self.regs[A] = a;
    self.regs[F] = HF | NF | (f & (SF | ZF | PF | CF)) | (a & (YF | XF));
}

// SCF
fn opSCF(self: *CPU) void {
    const a = self.regs[A];
    const f = self.regs[F];
    self.regs[F] = CF | (f & (SF | ZF | PF | CF)) | (a & (YF | XF));
}

// CCF
fn opCCF(self: *CPU) void {
    const a = self.regs[A];
    const f = self.regs[F];
    self.regs[F] = (((f & CF) << 4) | (f & (SF | ZF | PF | CF)) | (a & (YF | XF))) ^ CF;
}

// LDI/LDD/LDIR/LDDR
fn opLDI_LDD_LDIR_LDDR(self: *CPU, y: u3, tick_func: TickFunc) void {
    var hl = self.r16(HL);
    var de = self.r16(DE);
    var val = self.memRead(hl, tick_func);
    self.memWrite(de, val, tick_func);
    val +%= self.regs[A];
    if (0 != (y & 1)) {
        hl -%= 1;
        de -%= 1;
    } else {
        hl +%= 1;
        de +%= 1;
    }
    self.setR16(HL, hl);
    self.setR16(DE, de);
    self.tick(2, 0, tick_func); // 2 filler ticks
    var f = (self.regs[F] & (SF | ZF | CF)) | ((val << 4) & YF) | (val & XF);
    const bc = self.r16(BC) -% 1;
    self.setR16(BC, bc);
    if (bc != 0) {
        f |= VF;
    }
    self.regs[F] = f;
    if ((y >= 6) and (0 != bc)) {
        self.PC -%= 2;
        self.WZ = self.PC +% 1;
        self.tick(5, 0, tick_func); // 5 filler ticks
    }
}

// CPI, CPD, CPIR, CPDR
fn opCPI_CPD_CPIR_CPDR(self: *CPU, y: u3, tick_func: TickFunc) void {
    var hl = self.r16(HL);
    var val = self.regs[A] -% self.memRead(hl, tick_func);
    if (0 != (y & 1)) {
        hl -%= 1;
        self.WZ -%= 1;
    } else {
        hl +%= 1;
        self.WZ +%= 1;
    }
    self.setR16(HL, hl);
    self.tick(5, 0, tick_func); // 5 filler ticks
    var f = (self.regs[F] & CF) | NF | szFlags(val);
    if ((val & 0x0F) > (self.regs[A] & 0x0F)) {
        f |= HF;
        val -%= 1;
    }
    f |= ((val << 4) & YF) | (val & XF);
    const bc = self.r16(BC) -% 1;
    self.setR16(BC, bc);
    if (bc != 0) {
        f |= VF;
    }
    self.regs[F] = f;
    if ((y >= 6) and (0 != bc) and (0 == (f & ZF))) {
        self.PC -%= 2;
        self.WZ = self.PC +% 1;
        self.tick(5, 0, tick_func); // 5 filler ticks
    }
}

// DI
fn opDI(self: *CPU) void {
    self.iff1 = false;
    self.iff2 = false;
}

// EI
fn opEI(self: *CPU) void {
    self.iff1 = false;
    self.iff2 = false;
    self.ei = true;
}

// IM
fn opIM(self: *CPU, y: u3) void {
    const im = [8]u2{ 0, 0, 1, 2, 0, 0, 1, 2 };
    self.IM = im[y];
}

// JP cc,nn
fn opJP_cc_nn(self: *CPU, y: u3, tick_func: TickFunc) void {
    const val = self.imm16(tick_func);
    if (cc(self.regs[F], y)) {
        self.PC = val;
    }
}

// JP nn
fn opJP_nn(self: *CPU, tick_func: TickFunc) void {
    self.PC = self.imm16(tick_func);
}

// JP (HL)
fn opJP_HL(self: *CPU) void {
    self.PC = self.loadHLIXIY();
}

// JR d
fn opJR_d(self: *CPU, tick_func: TickFunc) void {
    const d = self.dimm8(tick_func);
    self.PC +%= d;
    self.WZ = self.PC;
    self.tick(5, 0, tick_func); // 5 filler ticks
}

// JR cc,d
fn opJR_cc_d(self: *CPU, y: u3, tick_func: TickFunc) void {
    const d = self.dimm8(tick_func);
    if (cc(self.regs[F], y -% 4)) {
        self.PC +%= d;
        self.WZ = self.PC;
        self.tick(5, 0, tick_func); // 5 filler ticks
    }
}

// DJNZ_d
fn opDJNZ_d(self: *CPU, tick_func: TickFunc) void {
    self.tick(1, 0, tick_func); // 1 filler tick
    const d = self.dimm8(tick_func);
    self.regs[B] -%= 1;
    if (self.regs[B] > 0) {
        self.PC +%= d;
        self.WZ = self.PC;
        self.tick(5, 0, tick_func); // 5 filler ticks
    }
}

// CALL nn
fn opCALL_nn(self: *CPU, tick_func: TickFunc) void {
    const addr = self.imm16(tick_func);
    self.tick(1, 0, tick_func); // filler tick
    self.push16(self.PC, tick_func);
    self.PC = addr;
}

// CALL_cc_nn
fn opCALL_cc_nn(self: *CPU, y: u3, tick_func: TickFunc) void {
    const addr = self.imm16(tick_func);
    if (cc(self.regs[F], y)) {
        self.tick(1, 0, tick_func); // filler tick
        self.push16(self.PC, tick_func);
        self.PC = addr;
    }
}

// RET
fn opRET(self: *CPU, tick_func: TickFunc) void {
    self.PC = self.pop16(tick_func);
    self.WZ = self.PC;
}

// RETN/RETI
fn opRETNI(self: *CPU, tick_func: TickFunc) void {
    // NOTE: according to Undocumented Z80 Documented, IFF2 is also
    // copied into IFF1 in RETI, not just RETN, and RETI and RETN
    // are in fact identical
    self.pins |= RETI;
    self.PC = self.pop16(tick_func);
    self.WZ = self.PC;
    self.iff1 = self.iff2;
}

// RET_cc
fn opRET_cc(self: *CPU, y: u3, tick_func: TickFunc) void {
    self.tick(1, 0, tick_func); // filler tick
    if (cc(self.regs[F], y)) {
        self.PC = self.pop16(tick_func);
        self.WZ = self.PC;
    }
}

// ADD HL,rp
fn opADD_HL_rp(self: *CPU, p: u2, tick_func: TickFunc) void {
    const acc = self.loadHLIXIY();
    self.WZ = acc +% 1;
    const val = self.load16SP(p);
    const res: u17 = @as(u17, acc) +% val;
    self.storeHLIXIY(@truncate(res));
    var f: u17 = self.regs[F] & (SF | ZF | VF);
    f |= ((acc ^ res ^ val) >> 8) & HF;
    f |= ((res >> 16) & CF) | ((res >> 8) & (YF | XF));
    self.regs[F] = @truncate(f);
    self.tick(7, 0, tick_func); // filler ticks
}

// ADC HL,rp
fn opADC_HL_rp(self: *CPU, p: u2, tick_func: TickFunc) void {
    const acc = self.r16(HL);
    self.WZ = acc +% 1;
    const val = self.load16SP(p);
    const res: u17 = @as(u17, acc) +% val +% (self.regs[F] & CF);
    self.setR16(HL, @truncate(res));
    var f: u17 = ((val ^ acc ^ 0x8000) & (val ^ res) & 0x8000) >> 13;
    f |= ((acc ^ res ^ val) >> 8) & HF;
    f |= (res >> 16) & CF;
    f |= (res >> 8) & (SF | YF | XF);
    f |= if (0 == (res & 0xFFFF)) ZF else 0;
    self.regs[F] = @truncate(f);
    self.tick(7, 0, tick_func); // filler ticks
}

// SBC HL,rp
fn opSBC_HL_rp(self: *CPU, p: u2, tick_func: TickFunc) void {
    const acc = self.r16(HL);
    self.WZ = acc +% 1;
    const val = self.load16SP(p);
    const res: u17 = @as(u17, acc) -% val -% (self.regs[F] & CF);
    self.setR16(HL, @truncate(res));
    var f: u17 = NF | (((val ^ acc) & (acc ^ res) & 0x8000) >> 13);
    f |= ((acc ^ res ^ val) >> 8) & HF;
    f |= (res >> 16) & CF;
    f |= (res >> 8) & (SF | YF | XF);
    f |= if (0 == (res & 0xFFFF)) ZF else 0;
    self.regs[F] = @truncate(f);
    self.tick(7, 0, tick_func); // filler ticks
}

// IN A,(n)
fn opIN_A_in(self: *CPU, tick_func: TickFunc) void {
    const n = self.imm8(tick_func);
    const port = (@as(u16, self.regs[A]) << 8) | n;
    self.regs[A] = self.ioRead(port, tick_func);
    self.WZ = port +% 1;
}

// OUT (n),A
fn opOUT_in_A(self: *CPU, tick_func: TickFunc) void {
    const n = self.imm8(tick_func);
    const a = self.regs[A];
    const port = (@as(u16, a) << 8) | n;
    self.ioWrite(port, a, tick_func);
    self.WZ = (port & 0xFF00) | ((port +% 1) & 0x00FF);
}

// IN r,(C)
fn opIN_ry_iC(self: *CPU, y: u3, tick_func: TickFunc) void {
    const bc = self.r16(BC);
    const val = self.ioRead(bc, tick_func);
    self.WZ = bc +% 1;
    self.regs[F] = (self.regs[F] & CF) | szpFlags(val);
    // undocumented special case for IN (HL),(C): only store flags, throw away input byte
    if (y != 6) {
        self.store8(y, val, tick_func);
    }
}

// OUT (C),r
fn opOUT_iC_ry(self: *CPU, y: u3, tick_func: TickFunc) void {
    const bc = self.r16(BC);
    // undocumented special case for OUT (C),(HL): output 0 instead
    var val = if (y == 6) 0 else self.load8(y, tick_func);
    self.ioWrite(bc, val, tick_func);
    self.WZ = bc +% 1;
}

// INI/IND/INIR/INDR
fn opINI_IND_INIR_INDR(self: *CPU, y: u3, tick_func: TickFunc) void {
    self.tick(1, 0, tick_func); // filler tick
    var port = self.r16(BC);
    var hl = self.r16(HL);
    const val = self.ioRead(port, tick_func);
    self.memWrite(hl, val, tick_func);
    const b = self.regs[B] -% 1;
    self.regs[B] = b;
    var c = self.regs[C];
    if (0 != (y & 1)) {
        port -%= 1;
        hl -%= 1;
        c -%= 1;
    } else {
        port +%= 1;
        hl +%= 1;
        c +%= 1;
    }
    self.setR16(HL, hl);
    self.WZ = port;
    var f = (if (b == 0) ZF else (b & SF)) | (b & (XF | YF));
    if (0 != (val & SF)) {
        f |= NF;
    }
    const t = @as(u9, c) + val;
    if (0 != (t & 0x100)) {
        f |= HF | CF;
    }
    f |= szpFlags((@as(u8, @truncate(t)) & 0x07) ^ b) & PF;
    self.regs[F] = f;
    if ((y >= 6) and (b != 0)) {
        self.PC -%= 2;
        self.tick(5, 0, tick_func); // filler ticks
    }
}

// OUTI/OUTD/OTIR/OTDR
fn opOUTI_OUTD_OTIR_OTDR(self: *CPU, y: u3, tick_func: TickFunc) void {
    self.tick(1, 0, tick_func); // filler tick
    var hl = self.r16(HL);
    const val = self.memRead(hl, tick_func);
    const b = self.regs[B] -% 1;
    self.regs[B] = b;
    var port = self.r16(BC);
    self.ioWrite(port, val, tick_func);
    if (0 != (y & 1)) {
        port -%= 1;
        hl -%= 1;
    } else {
        port +%= 1;
        hl +%= 1;
    }
    self.setR16(HL, hl);
    self.WZ = port;
    var f = (if (b == 0) ZF else (b & SF)) | (b & (XF | YF));
    if (0 != (val & SF)) {
        f |= NF;
    }
    const t = @as(u9, self.regs[L]) + val;
    if (0 != (t & 0x100)) {
        f |= HF | CF;
    }
    f |= szpFlags((@as(u8, @truncate(t)) & 0x07) ^ b) & PF;
    self.regs[F] = f;
    if ((y >= 6) and (b != 0)) {
        self.PC -%= 2;
        self.tick(5, 0, tick_func); // filler ticks
    }
}

// RST y*8
fn opRSTy(self: *CPU, y: u3, tick_func: TickFunc) void {
    self.tick(1, 0, tick_func); // filler tick
    self.push16(self.PC, tick_func);
    self.PC = @as(u16, y) * 8;
    self.WZ = self.WZ;
}

// flag computation functions
fn szFlags(val: u9) u8 {
    if (@as(u8, @truncate(val)) == 0) {
        return ZF;
    } else {
        return @as(u8, @truncate(val)) & SF;
    }
}

fn szyxchFlags(acc: u9, val: u8, res: u9) u8 {
    return szFlags(res) | @as(u8, @truncate((res & (YF | XF)) | ((res >> 8) & CF) | ((acc ^ val ^ res) & HF)));
}

fn addFlags(acc: u9, val: u8, res: u9) u8 {
    return szyxchFlags(acc, val, res) | @as(u8, @truncate((((val ^ acc ^ 0x80) & (val ^ res)) >> 5) & VF));
}

fn subFlags(acc: u9, val: u8, res: u9) u8 {
    return NF | szyxchFlags(acc, val, res) | @as(u8, @truncate((((val ^ acc) & (res ^ acc)) >> 5) & VF));
}

fn cpFlags(acc: u9, val: u8, res: u9) u8 {
    return NF | szFlags(res) | @as(u8, @truncate((val & (YF | XF)) | ((res >> 8) & CF) | ((acc ^ val ^ res) & HF) | ((((val ^ acc) & (res ^ acc)) >> 5) & VF)));
}

fn szpFlags(val: u8) u8 {
    return szFlags(val) | (((@popCount(val) << 2) & PF) ^ PF) | (val & (YF | XF));
}

// test cc flag
fn cc(f: u8, y: u3) bool {
    return switch (y) {
        0 => (0 == (f & ZF)), // NZ
        1 => (0 != (f & ZF)), // Z
        2 => (0 == (f & CF)), // NC
        3 => (0 != (f & CF)), // C
        4 => (0 == (f & PF)), // PO
        5 => (0 != (f & PF)), // PE
        6 => (0 == (f & SF)), // P
        7 => (0 != (f & SF)), // M
    };
}

// ALU functions
fn add8(r: *Regs, val: u8) void {
    const acc: u9 = r[A];
    const res: u9 = acc + val;
    r[F] = addFlags(acc, val, res);
    r[A] = @truncate(res);
}

fn adc8(r: *Regs, val: u8) void {
    const acc: u9 = r[A];
    const res: u9 = acc + val + (r[F] & CF);
    r[F] = addFlags(acc, val, res);
    r[A] = @truncate(res);
}

fn sub8(r: *Regs, val: u8) void {
    const acc: u9 = r[A];
    const res: u9 = acc -% val;
    r[F] = subFlags(acc, val, res);
    r[A] = @truncate(res);
}

fn sbc8(r: *Regs, val: u8) void {
    const acc: u9 = r[A];
    const res: u9 = acc -% val -% (r[F] & CF);
    r[F] = subFlags(acc, val, res);
    r[A] = @truncate(res);
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
    const acc: u9 = r[A];
    const res: u9 = acc -% val;
    r[F] = cpFlags(acc, val, res);
}

fn alu8(r: *Regs, y: u3, val: u8) void {
    switch (y) {
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
    var f: u8 = szFlags(res) | (res & (XF | YF)) | ((res ^ val) & HF);
    f |= (((val ^ res) & res) >> 5) & VF;
    r[F] = f | (r[F] & CF);
    return res;
}

fn dec8(r: *Regs, val: u8) u8 {
    const res = val -% 1;
    var f: u8 = NF | szFlags(res) | (res & (XF | YF)) | ((res ^ val) & HF);
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
var io = if (is_test) [_]u8{0} ** 0x10000 else null;

fn clearMem() void {
    mem = [_]u8{0} ** 0x10000;
}

fn clearIO() void {
    io = [_]u8{0} ** 0x10000;
}

// a generic test tick callback
fn testTick(ticks: u64, i_pins: u64, userdata: usize) u64 {
    _ = ticks;
    _ = userdata;
    var pins = i_pins;
    const a = getAddr(pins);
    if ((pins & MREQ) != 0) {
        if ((pins & RD) != 0) {
            pins = setData(pins, mem[a]);
        } else if ((pins & WR) != 0) {
            mem[a] = getData(pins);
        }
    } else if ((pins & IORQ) != 0) {
        if ((pins & RD) != 0) {
            pins = setData(pins, io[a]);
        } else if ((pins & WR) != 0) {
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
    return (f & ~(XF | YF)) == mask;
}

fn testRF(r: *const Regs, reg: u3, val: u8, mask: u8) bool {
    return (r[reg] == val) and ((r[F] & ~(XF | YF)) == mask);
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
        fn tick_func(ticks: u64, pins: u64, userdata: usize) u64 {
            _ = userdata;
            if (ticks == 3 and getData(pins) == 0x56 and getAddr(pins) == 0x1234 and (pins & M1 | MREQ | RD) == M1 | MREQ | RD) {
                // success
                return setData(pins, 0x23);
            } else {
                return 0;
            }
        }
    };
    var cpu = CPU{ .pins = setAddrData(0, 0x1234, 0x56) };
    cpu.tick(3, M1 | MREQ | RD, .{ .func = inner.tick_func });
    try expect(getData(cpu.pins) == 0x23);
    try expect(cpu.ticks == 3);
}

test "tickWait" {
    const inner = struct {
        fn tick_func(ticks: u64, pins: u64, userdata: usize) u64 {
            _ = ticks;
            _ = userdata;
            return setWait(pins, 5);
        }
    };
    var cpu = CPU{ .pins = setWait(0, 7) };
    cpu.tickWait(3, M1 | MREQ | RD, .{ .func = inner.tick_func });
    try expect(getWait(cpu.pins) == 5);
    try expect(cpu.ticks == 8);
}

test "memRead" {
    clearMem();
    mem[0x1234] = 0x23;
    var cpu = CPU{};
    const val = cpu.memRead(0x1234, .{ .func = testTick });
    try expect((cpu.pins & CtrlPinMask) == MREQ | RD);
    try expect(getData(cpu.pins) == 0x23);
    try expect(val == 0x23);
    try expect(cpu.ticks == 3);
}

test "memWrite" {
    clearMem();
    var cpu = CPU{};
    cpu.memWrite(0x1234, 0x56, .{ .func = testTick });
    try expect((cpu.pins & CtrlPinMask) == MREQ | WR);
    try expect(getData(cpu.pins) == 0x56);
    try expect(cpu.ticks == 3);
}

test "ioRead" {
    clearIO();
    io[0x1234] = 0x23;
    var cpu = CPU{};
    const val = cpu.ioRead(0x1234, .{ .func = testTick });
    try expect((cpu.pins & CtrlPinMask) == IORQ | RD);
    try expect(getData(cpu.pins) == 0x23);
    try expect(val == 0x23);
    try expect(cpu.ticks == 4);
}

test "ioWrite" {
    clearIO();
    var cpu = CPU{};
    cpu.ioWrite(0x1234, 0x56, .{ .func = testTick });
    try expect((cpu.pins & CtrlPinMask) == IORQ | WR);
    try expect(getData(cpu.pins) == 0x56);
    try expect(cpu.ticks == 4);
}

test "bumpR" {
    // only 7 bits are incremented, and the topmost bit is sticky
    var cpu = CPU{};
    cpu.R = 0x00;
    cpu.bumpR();
    try expect(cpu.R == 1);
    cpu.R = 0x7F;
    cpu.bumpR();
    try expect(cpu.R == 0);
    cpu.R = 0x80;
    cpu.bumpR();
    try expect(cpu.R == 0x81);
    cpu.R = 0xFF;
    cpu.bumpR();
    try expect(cpu.R == 0x80);
}

test "fetch" {
    clearMem();
    mem[0x2345] = 0x42;
    var cpu = CPU{ .PC = 0x2345, .R = 0 };
    const op = cpu.fetch(.{ .func = testTick });
    try expect(op == 0x42);
    try expect((cpu.pins & CtrlPinMask) == M1 | MREQ | RD);
    try expect(getData(cpu.pins) == 0x42);
    try expect(cpu.ticks == 4);
    try expect(cpu.PC == 0x2346);
    try expect(cpu.R == 1);
}

test "add8" {
    var r = makeRegs();
    r[A] = 0xF;
    add8(&r, r[A]);
    try expect(testAF(&r, 0x1E, HF));
    add8(&r, 0xE0);
    try expect(testAF(&r, 0xFE, SF));
    r[A] = 0x81;
    add8(&r, 0x80);
    try expect(testAF(&r, 0x01, VF | CF));
    add8(&r, 0xFF);
    try expect(testAF(&r, 0x00, ZF | HF | CF));
    add8(&r, 0x40);
    try expect(testAF(&r, 0x40, 0));
    add8(&r, 0x80);
    try expect(testAF(&r, 0xC0, SF));
    add8(&r, 0x33);
    try expect(testAF(&r, 0xF3, SF));
    add8(&r, 0x44);
    try expect(testAF(&r, 0x37, CF));
}

test "adc8" {
    var r = makeRegs();
    r[A] = 0;
    adc8(&r, 0x00);
    try expect(testAF(&r, 0x00, ZF));
    adc8(&r, 0x41);
    try expect(testAF(&r, 0x41, 0));
    adc8(&r, 0x61);
    try expect(testAF(&r, 0xA2, SF | VF));
    adc8(&r, 0x81);
    try expect(testAF(&r, 0x23, VF | CF));
    adc8(&r, 0x41);
    try expect(testAF(&r, 0x65, 0));
    adc8(&r, 0x61);
    try expect(testAF(&r, 0xC6, SF | VF));
    adc8(&r, 0x81);
    try expect(testAF(&r, 0x47, VF | CF));
    adc8(&r, 0x01);
    try expect(testAF(&r, 0x49, 0));
}

test "sub8" {
    var r = makeRegs();
    r[A] = 0x04;
    sub8(&r, 0x04);
    try expect(testAF(&r, 0x00, ZF | NF));
    sub8(&r, 0x01);
    try expect(testAF(&r, 0xFF, SF | HF | NF | CF));
    sub8(&r, 0xF8);
    try expect(testAF(&r, 0x07, NF));
    sub8(&r, 0x0F);
    try expect(testAF(&r, 0xF8, SF | HF | NF | CF));
    sub8(&r, 0x79);
    try expect(testAF(&r, 0x7F, HF | VF | NF));
    sub8(&r, 0xC0);
    try expect(testAF(&r, 0xBF, SF | VF | NF | CF));
    sub8(&r, 0xBF);
    try expect(testAF(&r, 0x00, ZF | NF));
    sub8(&r, 0x01);
    try expect(testAF(&r, 0xFF, SF | HF | NF | CF));
    sub8(&r, 0xFE);
    try expect(testAF(&r, 0x01, NF));
}

test "sbc8" {
    var r = makeRegs();
    r[A] = 0x04;
    sbc8(&r, 0x04);
    try expect(testAF(&r, 0x00, ZF | NF));
    sbc8(&r, 0x01);
    try expect(testAF(&r, 0xFF, SF | HF | NF | CF));
    sbc8(&r, 0xF8);
    try expect(testAF(&r, 0x06, NF));
    sbc8(&r, 0x0F);
    try expect(testAF(&r, 0xF7, SF | HF | NF | CF));
    sbc8(&r, 0x79);
    try expect(testAF(&r, 0x7D, HF | VF | NF));
    sbc8(&r, 0xC0);
    try expect(testAF(&r, 0xBD, SF | VF | NF | CF));
    sbc8(&r, 0xBF);
    try expect(testAF(&r, 0xFD, SF | HF | NF | CF));
    sbc8(&r, 0x01);
    try expect(testAF(&r, 0xFB, SF | NF));
    sbc8(&r, 0xFE);
    try expect(testAF(&r, 0xFD, SF | HF | NF | CF));
}

test "cp8" {
    var r = makeRegs();
    r[A] = 0x04;
    cp8(&r, 0x04);
    try expect(testAF(&r, 0x04, ZF | NF));
    cp8(&r, 0x05);
    try expect(testAF(&r, 0x04, SF | HF | NF | CF));
    cp8(&r, 0x03);
    try expect(testAF(&r, 0x04, NF));
    cp8(&r, 0xFF);
    try expect(testAF(&r, 0x04, HF | NF | CF));
    cp8(&r, 0xAA);
    try expect(testAF(&r, 0x04, HF | NF | CF));
    cp8(&r, 0x80);
    try expect(testAF(&r, 0x04, SF | VF | NF | CF));
    cp8(&r, 0x7F);
    try expect(testAF(&r, 0x04, SF | HF | NF | CF));
    cp8(&r, 0x04);
    try expect(testAF(&r, 0x04, ZF | NF));
}

test "and8" {
    var r = makeRegs();
    r[A] = 0xFF;
    and8(&r, 0x01);
    try expect(testAF(&r, 0x01, HF));
    r[A] = 0xFF;
    and8(&r, 0x03);
    try expect(testAF(&r, 0x03, HF | PF));
    r[A] = 0xFF;
    and8(&r, 0x04);
    try expect(testAF(&r, 0x04, HF));
    r[A] = 0xFF;
    and8(&r, 0x08);
    try expect(testAF(&r, 0x08, HF));
    r[A] = 0xFF;
    and8(&r, 0x10);
    try expect(testAF(&r, 0x10, HF));
    r[A] = 0xFF;
    and8(&r, 0x20);
    try expect(testAF(&r, 0x20, HF));
    r[A] = 0xFF;
    and8(&r, 0x40);
    try expect(testAF(&r, 0x40, HF));
    r[A] = 0xFF;
    and8(&r, 0xAA);
    try expect(testAF(&r, 0xAA, SF | HF | PF));
}

test "xor8" {
    var r = makeRegs();
    r[A] = 0x00;
    xor8(&r, 0x00);
    try expect(testAF(&r, 0x00, ZF | PF));
    xor8(&r, 0x01);
    try expect(testAF(&r, 0x01, 0));
    xor8(&r, 0x03);
    try expect(testAF(&r, 0x02, 0));
    xor8(&r, 0x07);
    try expect(testAF(&r, 0x05, PF));
    xor8(&r, 0x0F);
    try expect(testAF(&r, 0x0A, PF));
    xor8(&r, 0x1F);
    try expect(testAF(&r, 0x15, 0));
    xor8(&r, 0x3F);
    try expect(testAF(&r, 0x2A, 0));
    xor8(&r, 0x7F);
    try expect(testAF(&r, 0x55, PF));
    xor8(&r, 0xFF);
    try expect(testAF(&r, 0xAA, SF | PF));
}

test "or8" {
    var r = makeRegs();
    r[A] = 0x00;
    or8(&r, 0x00);
    try expect(testAF(&r, 0x00, ZF | PF));
    or8(&r, 0x01);
    try expect(testAF(&r, 0x01, 0));
    or8(&r, 0x02);
    try expect(testAF(&r, 0x03, PF));
    or8(&r, 0x04);
    try expect(testAF(&r, 0x07, 0));
    or8(&r, 0x08);
    try expect(testAF(&r, 0x0F, PF));
    or8(&r, 0x10);
    try expect(testAF(&r, 0x1F, 0));
    or8(&r, 0x20);
    try expect(testAF(&r, 0x3F, PF));
    or8(&r, 0x40);
    try expect(testAF(&r, 0x7F, 0));
    or8(&r, 0x80);
    try expect(testAF(&r, 0xFF, SF | PF));
}

test "neg8" {
    var r = makeRegs();
    r[A] = 0x01;
    neg8(&r);
    try expect(testAF(&r, 0xFF, SF | HF | NF | CF));
    r[A] = 0x00;
    neg8(&r);
    try expect(testAF(&r, 0x00, ZF | NF));
    r[A] = 0x80;
    neg8(&r);
    try expect(testAF(&r, 0x80, SF | PF | NF | CF));
    r[A] = 0xC0;
    neg8(&r);
    try expect(testAF(&r, 0x40, NF | CF));
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
    r[A] = inc8(&r, r[A]);
    try expect(testRF(&r, A, 0x01, 0));
    r[A] = dec8(&r, r[A]);
    try expect(testRF(&r, A, 0x00, ZF | NF));
    r[B] = inc8(&r, r[B]);
    try expect(testRF(&r, B, 0x00, ZF | HF));
    r[B] = dec8(&r, r[B]);
    try expect(testRF(&r, B, 0xFF, SF | HF | NF));
    r[C] = inc8(&r, r[C]);
    try expect(testRF(&r, C, 0x10, HF));
    r[C] = dec8(&r, r[C]);
    try expect(testRF(&r, C, 0x0F, HF | NF));
    r[D] = inc8(&r, r[D]);
    try expect(testRF(&r, D, 0x0F, 0));
    r[D] = dec8(&r, r[D]);
    try expect(testRF(&r, D, 0x0E, NF));
    r[F] |= CF;
    r[E] = inc8(&r, r[E]);
    try expect(testRF(&r, E, 0x80, SF | HF | VF | CF));
    r[E] = dec8(&r, r[E]);
    try expect(testRF(&r, E, 0x7F, HF | VF | NF | CF));
    r[H] = inc8(&r, r[H]);
    try expect(testRF(&r, H, 0x3F, CF));
    r[H] = dec8(&r, r[H]);
    try expect(testRF(&r, H, 0x3E, NF | CF));
    r[L] = inc8(&r, r[L]);
    try expect(testRF(&r, L, 0x24, CF));
    r[L] = dec8(&r, r[L]);
    try expect(testRF(&r, L, 0x23, NF | CF));
}
