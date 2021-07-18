//
//  host bindings timing helper functions
//
const stm = @import("sokol").time;

const state = struct {
    var cur_frame_time: f64 = 0;
    var last_time_stamp: u64 = 0;
};

pub fn setup() void {
    // setup sokol-time
    stm.setup();
    state.cur_frame_time = 0;
    state.last_time_stamp = stm.now();
}

// return frame time in microseconds
pub fn frameTime() u32 {
    state.cur_frame_time = stm.us(stm.roundToCommonRefreshRate(stm.laptime(&state.last_time_stamp)));
    // prevent death spiral on host systems that are too slow to
    // run the emulator in realtime, or during long frame (e.g. debugging)
    if (state.cur_frame_time < 1000) {
        state.cur_frame_time = 1000;
    }
    if (state.cur_frame_time > 24000) {
        state.cur_frame_time = 24000;
    }
    return @floatToInt(u32, state.cur_frame_time);
}
