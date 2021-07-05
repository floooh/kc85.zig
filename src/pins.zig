// shared pin definitions for the KC85 system bus

pub const Pins = struct {

    // address bus pins
    pub const A0  = 1<<0;
    pub const A1  = 1<<1;
    pub const A2  = 1<<2;
    pub const A3  = 1<<3;
    pub const A4  = 1<<4;
    pub const A5  = 1<<5;
    pub const A6  = 1<<6;
    pub const A7  = 1<<7;
    pub const A8  = 1<<8;
    pub const A9  = 1<<9;
    pub const A10 = 1<<10;
    pub const A11 = 1<<11;
    pub const A12 = 1<<12;
    pub const A13 = 1<<13;
    pub const A14 = 1<<14;
    pub const A15 = 1<<15;
    pub const AddrMask = 0xFFFF;

    // data bus pins
    pub const D0 = 1<<16;
    pub const D1 = 1<<17;
    pub const D2 = 1<<18;
    pub const D3 = 1<<19;
    pub const D4 = 1<<20;
    pub const D5 = 1<<21;
    pub const D6 = 1<<22;
    pub const D7 = 1<<23;
    pub const DataMask = 0xFF0000;

    // Z80 CPU pins
    pub const CPU = struct {

        // system control pins
        pub const M1   = 1<<24;     // machine cycle 1
        pub const MREQ = 1<<25;     // memory request
        pub const IORQ = 1<<26;     // IO request
        pub const RD   = 1<<27;     // read request
        pub const WR   = 1<<28;     // write requst
        pub const RFSH = 1<<29;     // memory refresh (not implemented)

        // CPU control pins
        pub const HALT  = 1<<30;    // halt and catch fire
        pub const INT   = 1<<31;    // maskable interrupt requested
        pub const NMI   = 1<<32;    // non-maskable interrupt requested
        pub const RESET = 1<<33;    // reset requested

        // virtual pins
        pub const WAIT0 = 1<<34;    // 3 virtual pins to inject up to 8 wait cycles
        pub const WAIT1 = 1<<35;
        pub const WAIT2 = 1<<36;
        pub const IEIO  = 1<<37;    // interrupt daisy chain: interrupt-enable-I/O
        pub const RETI  = 1<<38;    // interrupt daisy chain: RETI decoded
    };

    // Z80 CTC pins
    pub const CTC = struct {
        // shared pins
        pub const M1    = CPU.M1;
        pub const IORQ  = CPU.IORQ;
        pub const RD    = CPU.RD;
        pub const INT   = CPU.INT;
        pub const RESET = CPU.RESET;
        pub const IEIO  = CPU.IEIO;
        pub const RETI  = CPU.RETI;

        // chip-specific pins starting at bit 40
        pub const CE      = (1<<40);    // chip enable
        pub const CS0     = (1<<41);    // channel select 0
        pub const CS1     = (1<<42);    // channel select 1
        pub const CLKTRG0 = (1<<43);    // clock timer trigger 0..3
        pub const CLKTRG1 = (1<<44);
        pub const CLKTRG2 = (1<<45);
        pub const CLKTRG3 = (1<<46);
        pub const ZCTO0   = (1<<47);    // zero-count/timeout 0..2
        pub const ZCTO1   = (1<<48);
        pub const ZCTO2   = (1<<49);
    };

    // Z80 PIO pins
    pub const PIO = struct {
        // shared pins
        pub const M1    = CPU.M1;
        pub const IORQ  = CPU.IORQ;
        pub const RD    = CPU.RD;
        pub const INT   = CPU.INT;
        pub const IEIO  = CPU.IEIO;
        pub const RETI  = CPU.RETI;

        // chip-specific pins start at bit 40
        pub const CE    = 1<<40;    // chip enable
        pub const BASEL = 1<<41;    // port A/B select
        pub const CDSEL = 1<<42;    // control/data select
        pub const ARDY  = 1<<43;    // port A ready
        pub const BRDY  = 1<<44;    // port B ready
        pub const ASTB  = 1<<45;    // port A strobe
        pub const BSTB  = 1<<46;    // port B strobe

        // A/B port pins
        pub const PA0 = 1<<48;
        pub const PA1 = 1<<49;
        pub const PA2 = 1<<50;
        pub const PA3 = 1<<51;
        pub const PA4 = 1<<52;
        pub const PA5 = 1<<53;
        pub const PA6 = 1<<54;
        pub const PA7 = 1<<55;

        pub const PB0 = 1<<56;
        pub const PB1 = 1<<57;
        pub const PB2 = 1<<58;
        pub const PB3 = 1<<59;
        pub const PB4 = 1<<60;
        pub const PB5 = 1<<61;
        pub const PB6 = 1<<62;
        pub const PB7 = 1<<63;
    };
};