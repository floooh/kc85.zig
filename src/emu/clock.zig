//
//  Helper functions to convert microsecond to system clock ticks,
//  and keep track of executed ticks.
//
const assert = @import("std").debug.assert;

// clock state
pub const Clock = struct {
    freq_hz:        i64,
    ticks_to_run:   i64 = 0,
    overrun_ticks:  i64 = 0,
    
    // return the number of ticks to run for micro_seconds, taking overrun
    // ticks from last invocation into account
    pub fn ticksToRun(clk: *Clock, micro_seconds: u32) u64 {
        return impl.ticksToRun(clk, micro_seconds);
    }

    // feed back number of actually executed ticks to compute 'overrun ticks'
    // for the next invocation
    pub fn ticksExecuted(clk: *Clock, ticks_executed: u64) void {
        impl.ticksExecuted(clk, ticks_executed);
    }
};

//=== IMPLEMENTATION ===========================================================
const impl = struct {

fn ticksToRun(clk: *Clock, micro_seconds: u32) u64 {
    assert(micro_seconds > 0);
    const ticks: i64 = @divTrunc(clk.freq_hz * micro_seconds, 1_000_000);
    clk.ticks_to_run = ticks - clk.overrun_ticks;
    if (clk.ticks_to_run < 1) {
        clk.ticks_to_run = 1;
    }
    return @intCast(u64, clk.ticks_to_run);
}

pub fn ticksExecuted(clk: *Clock, ticks_executed: u64) void {
    const ticks: i64 = @intCast(i64, ticks_executed);
    if (ticks > clk.ticks_to_run) {
        clk.overrun_ticks = ticks - clk.ticks_to_run;
    }
    else {
        clk.overrun_ticks = 0;
    }
}

}; // impl;



