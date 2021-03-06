//
//  Audio host bindings via sokol_audio.h
//
const saudio = @import("sokol").audio;

pub fn setup() void {
    saudio.setup(.{});
}

pub fn shutdown() void {
    saudio.shutdown();
}

pub fn sampleRate() u32 {
    return @intCast(u32, saudio.sampleRate());
}

pub fn push(samples: []const f32, userdata: usize) void {
    _ = userdata;
    _ = saudio.push(&samples[0], @intCast(i32, samples.len));
}