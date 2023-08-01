//
//  Helper functions to convert microsecond to system clock ticks,
//  and keep track of executed ticks.
//
const assert = @import("std").debug.assert;

const Clock = @This();
freq_hz: i64,
ticks_to_run: i64 = 0,
overrun_ticks: i64 = 0,

// return the number of ticks to run for micro_seconds, taking overrun
// ticks from last invocation into account
pub fn ticksToRun(self: *Clock, micro_seconds: u32) u64 {
    assert(micro_seconds > 0);
    const ticks: i64 = @divTrunc(self.freq_hz * micro_seconds, 1_000_000);
    self.ticks_to_run = ticks - self.overrun_ticks;
    if (self.ticks_to_run < 1) {
        self.ticks_to_run = 1;
    }
    return @intCast(self.ticks_to_run);
}

pub fn ticksExecuted(self: *Clock, ticks_executed: u64) void {
    const ticks: i64 = @intCast(ticks_executed);
    if (ticks > self.ticks_to_run) {
        self.overrun_ticks = ticks - self.ticks_to_run;
    } else {
        self.overrun_ticks = 0;
    }
}
