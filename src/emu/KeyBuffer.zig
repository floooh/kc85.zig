//
//  A simple keyboard buffer which keeps keys pressed for a minimal
//  amount of time so that the emulated computer system has enough
//  time to for scanning the keyboard state.
//
const assert = @import("std").debug.assert;

const buf_size = 8;

const KeyState = struct {
    pressed_time: u64 = 0,
    key_code: u8 = 0,
    released: bool = false,
};

const KeyBuffer = @This();
// time in microseconds that pressed keys will at least remain pressed
sticky_duration: u64,
// current time in microsecs, bumped by update()
cur_time: u64 = 0,
// currently pressed keys
keys: [buf_size]KeyState = [_]KeyState{.{}} ** buf_size,

// call once per frame with frame duration (any time unit)
pub fn update(self: *KeyBuffer, frame_duration: u32) void {
    // check for sticky keys that should be released
    for (self.keys) |*key| {
        if (key.released) {
            // properly handle time wraparound
            if ((self.cur_time < key.pressed_time) or (self.cur_time > (key.pressed_time + self.sticky_duration))) {
                // reset "expired" keys
                key.* = .{};
            }
        }
    }
    self.cur_time +%= frame_duration;
}

// notify keyboard matrix about a pressed key
pub fn keyDown(self: *KeyBuffer, key_code: u8) void {
    assert(0 != key_code);
    // first check if key is already in key buffer, if yes, just update the pressed-time
    for (self.keys) |*key| {
        if (key.key_code == key_code) {
            key.pressed_time = self.cur_time;
            key.released = false;
            return;
        }
    }
    // otherwise find the first free slot in the buffer
    for (self.keys) |*key| {
        if (0 == key.key_code) {
            key.key_code = key_code;
            key.pressed_time = self.cur_time;
            key.released = false;
            return;
        }
    }
}

// notify keyboard matrix about a released key
pub fn keyUp(self: *KeyBuffer, key_code: u8) void {
    assert(0 != key_code);
    for (self.keys) |*key| {
        if (key.key_code == key_code) {
            key.released = true;
            return;
        }
    }
}

// get the most recently pressed key in the key buffer, zero means none
pub fn mostRecentKey(self: *KeyBuffer) u8 {
    var t: u64 = 0;
    var key_code: u8 = 0;
    for (self.keys) |*key| {
        if ((0 != key.key_code) and (key.pressed_time > t)) {
            t = key.pressed_time;
            key_code = key.key_code;
        }
    }
    return key_code;
}
