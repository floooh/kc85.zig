//
//  A simple square-wave beeper.
//

const fixedpoint_scale = 16;
const dcadjust_buflen = 512;

const Beeper = @This();
sample: f32,
state: u1,
period: i32,
counter: i32,
magnitude: f32,
dcadjust_sum: f32,
dcadjust_pos: u9,
dcadjust_buf: [dcadjust_buflen]f32,

pub const Desc = struct {
    tick_hz: u32,
    sound_hz: u32,
    volume: f32,
};

// return an initialized Beeper instance
pub fn init(desc: Beeper.Desc) Beeper {
    const p = @as(i32, @intCast((desc.tick_hz * fixedpoint_scale) / desc.sound_hz));
    return .{
        .state = 0,
        .period = p,
        .counter = p,
        .magnitude = desc.volume,
        .sample = 0.0,
        .dcadjust_sum = 0.0,
        .dcadjust_pos = 0,
        .dcadjust_buf = [_]f32{0.0} ** dcadjust_buflen,
    };
}

// reset a Beeper instance
pub fn reset(self: *Beeper) void {
    self.state = 0;
    self.counter = self.period;
    self.sample = 0.0;
}

// toggle beeper oscillator
pub fn toggle(self: *Beeper) void {
    self.state = ~self.state;
}

// call each tick, returns true if Beeper.sample is ready
pub fn tick(self: *Beeper) bool {
    self.counter -= fixedpoint_scale;
    if (self.counter <= 0) {
        self.counter += self.period;
        self.sample = self.dcadjust(@as(f32, @floatFromInt(self.state))) * self.magnitude;
        return true;
    } else {
        return false;
    }
}

// DC adjustment filter from StSound, this moves an "offcenter"
// signal back to the zero-line (e.g. the volume-level output
// from the chip simulation which is >0.0 gets converted to
// a +/- sample value)
fn dcadjust(self: *Beeper, sample: f32) f32 {
    self.dcadjust_sum -= self.dcadjust_buf[self.dcadjust_pos];
    self.dcadjust_sum += sample;
    self.dcadjust_buf[self.dcadjust_pos] = sample;
    self.dcadjust_pos +%= 1;
    return sample - (self.dcadjust_sum / @as(f32, @floatFromInt(dcadjust_buflen)));
}
