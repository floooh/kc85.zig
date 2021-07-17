//
//  Graphics host bindings (via sokol-gfx)
//
const sokol = @import("sokol");
const sg    = sokol.gfx;
const sapp  = sokol.app;
const sgapp = sokol.app_gfx_glue;

const BorderWidth = 10;
const BorderHeight = 10;

pub const WindowWidth = 2 * 320 + 2 * BorderWidth;
pub const WindowHeight = 2 * 256 + 2 * BorderHeight;

const state = struct {
    var pass_action: sg.PassAction = .{ };
};

pub fn setup() void {
    sg.setup(.{ .context = sgapp.context() });
    state.pass_action.colors[0] = .{ .action = .CLEAR, .value = .{ .r=0, .g=0, .b=0, .a=0 } };
}

pub fn draw() void {
    sg.beginDefaultPass(state.pass_action, sapp.width(), sapp.height());
    sg.endPass();
    sg.commit();
}

pub fn shutdown() void {
    sg.shutdown();
}