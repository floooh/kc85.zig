//
//  host bindings timing helper functions
//
const stm = @import("sokol").time;

const state = struct {
    var cur_time: f64 = 0;
    var last_time_stamp: u64 = 0;
};

pub fn setup() void {
    // setup sokol-time
    stm.setup();
    state.cur_time = 0;
    state.last_time_stamp = stm.now();
}

// return frame time in microseconds
pub fn frameTime() u64 {
    state.cur_time = stm.us(stm.roundToCommonRefreshRate(stm.laptime(&state.last_time_stamp)));
    // prevent death spiral on host systems that are too slow to
    // run the emulator in realtime, or during long frame (e.g. debugging)
    if (state.cur_time > 24000) {
        state.cur_time = 24000;
    }
    return @floatToInt(u64, state.cur_time);
}
