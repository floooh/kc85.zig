//
//  Audio host bindings via sokol_audio.h
//
const saudio = @import("sokol").audio;
const slog = @import("sokol").log;

pub fn setup() void {
    saudio.setup(.{ .logger = .{ .func = slog.func } });
}

pub fn shutdown() void {
    saudio.shutdown();
}

pub fn sampleRate() u32 {
    return @intCast(saudio.sampleRate());
}

pub fn push(samples: []const f32, userdata: usize) void {
    _ = userdata;
    _ = saudio.push(&samples[0], @intCast(samples.len));
}
