//
//  Shared Z80 interrupt daisychain implementation for CTC and PIO.
//

// shared pins relevant for interrupt handling
pub const M1:   u64 = 1<<24;    // machine cycle 1
pub const IORQ: u64 = 1<<26;    // IO request
pub const INT:  u64 = 1<<31;    // maskable interrupt requested
pub const IEIO: u64 = 1<<37;    // interrupt daisy chain: interrupt-enable-I/O
pub const RETI: u64 = 1<<38;    // interrupt daisy chain: RETI decoded

pub const INT_NEEDED:       u3 = 1<<0;  // interrupt request needed
pub const INT_REQUESTED:    u3 = 1<<1;  // interrupt request issued, waiting for ACK from CPU
pub const INT_SERVICING:    u3 = 1<<2;  // interrupt was acknoledged, now serving 

pub const DaisyChain = struct {
    state:  u8 = 0,         // combo of Flags
    vector: u8 = 0,         // Z80 interrupt vector
    
    /// reset the daisychain state
    pub fn reset(self: *DaisyChain) void {
        impl.reset(self);
    }
    
    // request an interrupt
    pub fn irq(self: *DaisyChain) void {
        impl.irq(self);
    }

    /// invoke each tick to handle interrupts
    pub fn tick(self: *DaisyChain, pins: u64) u64 {
        return impl.tick(self, pins); 
    }
};

//== IMPLEMENTATION ============================================================

const impl = struct {

const DataPinShift = 16;
const DataPinMask: u64 = 0xFF0000;

fn setData(pins: u64, data: u8) u64 {
    return (pins & ~DataPinMask) | (@as(u64, data) << DataPinShift);
}

fn reset(self: *DaisyChain) void {
    self.state = 0;
}

fn irq(self: *DaisyChain) void {
    self.state |= INT_NEEDED;
}

fn tick(self: *DaisyChain, in_pins: u64) u64 {
    var pins = in_pins;

    // - set status of IEO pin depending on IEI pin and current
    //   channel's interrupt request/acknowledge status, this
    //   'ripples' to the next channel and downstream interrupt
    //   controllers
    //
    // - the IEO pin will be set to inactive (interrupt disabled)
    //   when: (1) the IEI pin is inactive, or (2) the IEI pin is
    //   active and and an interrupt has been requested
    //
    // - if an interrupt has been requested but not ackowledged by
    //   the CPU because interrupts are disabled, the RETI state
    //   must be passed to downstream devices. If a RETI is 
    //   received in the interrupt-requested state, the IEIO
    //   pin will be set to active, so that downstream devices
    //   get a chance to decode the RETI
    //
    
    // if any higher priority device in the daisy chain has cleared
    // the IEIO pin, skip interrupt handling
    //
    if ((0 != (pins & IEIO)) and (0 != self.state)) {
        // check if if the CPU has decoded a RETI
        if (0 != (pins & RETI)) {
            // if we're the device that's currently under service by
            // the CPU, keep interrupts enabled for downstream devices and
            // clear our interrupt state (this is basically the
            // 'HELP' logic described in the PIO and CTC manuals
            //
            if (0 != (self.state & INT_SERVICING)) {
                self.state = 0;
            }
            // if we are *NOT* the device currently under service, this
            // means we have an interrupt request pending but the CPU
            // denied the request (because interruprs were disabled)
            //
            
            // need to request interrupt?
            if (0 != (self.state & INT_NEEDED)) {
                self.state &= ~INT_NEEDED;
                self.state |= INT_REQUESTED;
            }
            // need to place interrupt vector on data bus?
            if ((pins & (IORQ|M1)) == (IORQ|M1)) {
                // CPU has acknowledged the interrupt, place interrupt vector on data bus
                pins = setData(pins, self.vector);
                self.state &= ~INT_REQUESTED;
                self.state |= INT_SERVICING;
            }
            // disable interrupts for downstream devices?
            if (0 != self.int_state) {
                pins &= ~IEIO;
            }
            // set INT pin state during INT_REQUESTED
            if (0 != (self.state & INT_REQUESTED)) {
                pins |= INT;
            }
        }
    }
    return pins;
}

}; // impl