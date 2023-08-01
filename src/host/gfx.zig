//
//  Graphics host bindings (via sokol-gfx)
//
const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const slog = sokol.log;
const sgapp = sokol.app_gfx_glue;
const shd = @import("shaders/shaders.glsl.zig");

const KC85DisplayWidth = 320;
const KC85DisplayHeight = 256;
const KC85NumPixels = KC85DisplayWidth * KC85DisplayHeight;

const BorderWidth = 10;
const BorderHeight = 10;

pub const WindowWidth = 2 * KC85DisplayWidth + 2 * BorderWidth;
pub const WindowHeight = 2 * KC85DisplayHeight + 2 * BorderHeight;

pub var pixel_buffer: [KC85NumPixels]u32 = undefined;

const state = struct {
    const upscale = struct {
        var pip: sg.Pipeline = .{};
        var bind: sg.Bindings = .{};
        var pass: sg.Pass = .{};
        var pass_action: sg.PassAction = .{};
    };

    const display = struct {
        var pip: sg.Pipeline = .{};
        var bind: sg.Bindings = .{};
        var pass_action: sg.PassAction = .{};
    };
};

pub fn setup() void {
    sg.setup(.{
        .buffer_pool_size = 8,
        .image_pool_size = 8,
        .shader_pool_size = 8,
        .pipeline_pool_size = 8,
        .context_pool_size = 1,
        .context = sgapp.context(),
        .logger = .{ .func = slog.func },
    });

    state.upscale.pass_action.colors[0] = .{ .load_action = .DONTCARE };
    state.display.pass_action.colors[0] = .{ .load_action = .CLEAR, .clear_value = .{ .r = 0.05, .g = 0.05, .b = 0.05, .a = 1.0 } };

    // fullscreen triangle vertices
    const verts = [_]f32{
        0.0, 0.0,
        2.0, 0.0,
        0.0, 2.0,
    };
    state.upscale.bind.vertex_buffers[0] = sg.makeBuffer(.{ .data = sg.asRange(&verts) });
    state.display.bind.vertex_buffers[0] = sg.makeBuffer(.{ .data = sg.asRange(&verts) });

    // 2 pipeline state objects for rendering to display and upscaling
    var pip_desc = sg.PipelineDesc{
        .shader = sg.makeShader(shd.displayShaderDesc(sg.queryBackend())),
    };
    pip_desc.layout.attrs[0].format = .FLOAT2;
    state.display.pip = sg.makePipeline(pip_desc);

    pip_desc.shader = sg.makeShader(shd.upscaleShaderDesc(sg.queryBackend()));
    pip_desc.depth.pixel_format = .NONE;
    state.upscale.pip = sg.makePipeline(pip_desc);

    // a texture with the emulator's raw pixel data
    state.upscale.bind.fs.images[0] = sg.makeImage(.{
        .width = KC85DisplayWidth,
        .height = KC85DisplayHeight,
        .pixel_format = .RGBA8,
        .usage = .STREAM,
    });

    // and a sampler to sample the raw pixel data
    state.upscale.bind.fs.samplers[0] = sg.makeSampler(.{
        .min_filter = .NEAREST,
        .mag_filter = .NEAREST,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE,
    });

    // a 2x upscaled render target texture
    state.display.bind.fs.images[0] = sg.makeImage(.{
        .render_target = true,
        .width = 2 * KC85DisplayWidth,
        .height = 2 * KC85DisplayHeight,
    });

    // and a sampler to sample the render target texture
    state.display.bind.fs.samplers[0] = sg.makeSampler(.{
        .min_filter = .LINEAR,
        .mag_filter = .LINEAR,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE,
    });

    // a render pass for 2x upscaling
    var pass_desc = sg.PassDesc{};
    pass_desc.color_attachments[0].image = state.display.bind.fs.images[0];
    state.upscale.pass = sg.makePass(pass_desc);
}

pub fn shutdown() void {
    sg.shutdown();
}

pub fn draw() void {
    // copy emulator pixel data into upscaling source texture
    var image_data = sg.ImageData{};
    image_data.subimage[0][0] = sg.asRange(&pixel_buffer);
    sg.updateImage(state.upscale.bind.fs.images[0], image_data);

    // upscale the source texture 2x with nearest filtering
    sg.beginPass(state.upscale.pass, state.upscale.pass_action);
    sg.applyPipeline(state.upscale.pip);
    sg.applyBindings(state.upscale.bind);
    sg.draw(0, 3, 1);
    sg.endPass();

    // draw the display pass with linear filtering
    const w = sapp.widthf();
    const h = sapp.heightf();
    sg.beginDefaultPassf(state.display.pass_action, w, h);
    applyViewport(w, h);
    sg.applyPipeline(state.display.pip);
    sg.applyBindings(state.display.bind);
    sg.draw(0, 3, 1);
    sg.applyViewportf(0, 0, w, h, true);
    sg.endPass();
    sg.commit();
}

fn applyViewport(canvas_width: f32, canvas_height: f32) void {
    const canvas_aspect = canvas_width / canvas_height;
    const fb_aspect = @as(f32, KC85DisplayWidth) / @as(f32, KC85DisplayHeight);
    const frame_x = @as(f32, BorderWidth);
    const frame_y = @as(f32, BorderHeight);
    var vp_x: f32 = 0.0;
    var vp_y: f32 = 0.0;
    var vp_w: f32 = 0.0;
    var vp_h: f32 = 0.0;
    if (fb_aspect < canvas_aspect) {
        vp_y = frame_y;
        vp_h = canvas_height - (2.0 * frame_y);
        vp_w = (canvas_height * fb_aspect) - (2.0 * frame_x);
        vp_x = (canvas_width - vp_w) / 2.0;
    } else {
        vp_x = frame_x;
        vp_w = canvas_width - (2.0 * frame_x);
        vp_h = (canvas_width / fb_aspect) - (2.0 * frame_y);
        vp_y = frame_y;
    }
    sg.applyViewportf(vp_x, vp_y, vp_w, vp_h, true);
}
