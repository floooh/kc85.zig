# IMPLEMENTATION NOTES

Some implementation notes from top to bottom.

## Project structure and build script

The different KC85 versions (KC85/2, /3 and /4) are each compiled into its
own executable using conditional compilation.

[Here](https://github.com/floooh/kc85.zig/blob/8c510ad15391358239ea5e095d043c7b7b6acd6b/build.zig#L18)
the generic function ```addKC85()``` is called once for each build target using a comptime
argument to define the KC85 version:
```zig
    addKC85(b, sokol, target, mode, .KC85_2);
    addKC85(b, sokol, target, mode, .KC85_3);
    addKC85(b, sokol, target, mode, .KC85_4);
```

[Here](https://github.com/floooh/kc85.zig/blob/8c510ad15391358239ea5e095d043c7b7b6acd6b/build.zig#L28-L34)
in the addKC85() build function, a unique executable build target is generated, and a build option is added to the target:

```zig
    const name = switch (kc85_model) {
        .KC85_2 => "kc852",
        .KC85_3 => "kc853",
        .KC85_4 => "kc854"
    };
    const exe = b.addExecutable(name, "src/main.zig");
    exe.addBuildOption(KC85Model, "kc85_model", kc85_model);
```

The Zig build system code-generates a module file with all build options, which is 
implicitely imported into the build target's root package. The generated source
code is located in the *zig-out* directory and looks like this (for the **kc854**
build target):

```zig
pub const KC85Model = enum {
    KC85_2,
    KC85_3,
    KC85_4,
};
pub const kc85_model: KC85Model = KC85Model.KC85_4;
```

The kc85 build targets are split into 3 separate packages:

- **[emu](https://github.com/floooh/kc85.zig/tree/impl-notes/src/emu)**: the actual emulator source code, completely platform-agnostic
- **[host](https://github.com/floooh/kc85.zig/tree/impl-notes/src/host)**: the "host bindings", this is the source code which connects the emulator source code to the host platform for rendering the emulator display output into a window, make the emulator's sound output audible and receiving keyboard input from the host's window system.
- **[sokol](https://github.com/floooh/kc85.zig/tree/impl-notes/src/sokol)**: this the mixed C/Zig language bindings package to the sokol headers

And finally there's the top-level **[main.zig](https://github.com/floooh/kc85.zig/blob/impl-notes/src/main.zig)** source file which ties everything together.

Module packages need a single top level module which gathers and 're-exports' all package modules which need to be visible from the outside, looking like [this](https://github.com/floooh/kc85.zig/blob/impl-notes/src/host/host.zig):

```zig
pub const gfx   = @import("gfx.zig");
pub const audio = @import("audio.zig");
pub const time  = @import("time.zig");
pub const args  = @import("args.zig");
```

Packages and their dependencies need to be registered in the [build.zig file](https://github.com/floooh/kc85.zig/blob/a347744ef7071915d2eb6c67a27d389ec6b2fb09/build.zig#L46-L62)

```zig
    const pkg_sokol = Pkg{
        .name = "sokol",
        .path = "src/sokol/sokol.zig"
    };
    const pkg_emu = Pkg{
        .name = "emu",
        .path = "src/emu/emu.zig", 
        .dependencies = &[_]Pkg{ pkg_buildoptions }
    };
    const pkg_host = Pkg{
        .name = "host",
        .path = "src/host/host.zig",
        .dependencies = &[_]Pkg{ pkg_sokol }
    };
    exe.addPackage(pkg_sokol);
    exe.addPackage(pkg_emu);
    exe.addPackage(pkg_host);
```

Note the ['buildoptions package hack'](https://github.com/floooh/kc85.zig/blob/a347744ef7071915d2eb6c67a27d389ec6b2fb09/build.zig#L36-L45), which is a temporary workaround for [this bug](https://github.com/ziglang/zig/issues/5375):

```zig
    // FIXME: HACK to make buildoptions available to other packages than root
    // see: https://github.com/ziglang/zig/issues/5375
    const pkg_buildoptions = Pkg{
        .name = "build_options", 
        .path = switch (kc85_model) {
            .KC85_2 => "zig-cache/kc852_build_options.zig",
            .KC85_3 => "zig-cache/kc853_build_options.zig",
            .KC85_4 => "zig-cache/kc854_build_options.zig"
        },
    };
```

Some examples of how the imported buildoptions module is used:

[To select a specific window title:](https://github.com/floooh/kc85.zig/blob/8c510ad15391358239ea5e095d043c7b7b6acd6b/src/main.zig#L52-L68)

```zig
    sapp.run(.{
        // ...
        .window_title = switch (kc85_model) {
            .KC85_2 => "KC85/2",
            .KC85_3 => "KC85/3",
            .KC85_4 => "KC85/4"
        }
    });
```

[To select the ROM images needed for a specific KC85 version:](https://github.com/floooh/kc85.zig/blob/8c510ad15391358239ea5e095d043c7b7b6acd6b/src/main.zig#L76-L87)

```zig
    state.kc = KC85.create(&state.arena.allocator, .{
        // ...
        .rom_caos22  = if (kc85_model == .KC85_2) @embedFile("roms/caos22.852") else null,
        .rom_caos31  = if (kc85_model == .KC85_3) @embedFile("roms/caos31.853") else null,
        .rom_caos42c = if (kc85_model == .KC85_4) @embedFile("roms/caos42c.854") else null,
        .rom_caos42e = if (kc85_model == .KC85_4) @embedFile("roms/caos42e.854") else null,
        .rom_kcbasic = if (kc85_model != .KC85_2) @embedFile("roms/basic_c0.853") else null,
    }) catch unreachable;
```

Down in the emulator code, [to select KC85-model-specific code paths:](https://github.com/floooh/kc85.zig/blob/8c510ad15391358239ea5e095d043c7b7b6acd6b/src/emu/kc85.zig#L947-L952):

```zig
fn tickVideo(sys: *KC85, num_ticks: u64, pins: u64) u64 {
    return switch (model) {
        .KC85_2, .KC85_3 => tickVideoKC8523(sys, num_ticks, pins),
        .KC85_4 => tickVideoKC854(sys, num_ticks, pins),
    };
}
```

All those decisions happen at compile time, so that the inactive code and data won't be included
in the executable. This is how Zig handles #ifdef-style conditional compilation.

## The main.zig file

Execution starts at the Zig [main function](https://github.com/floooh/kc85.zig/blob/02be0a4d1981c135b0c352048352c8759784eb5b/src/main.zig#L39-L69) which first creates an ArenaAllocator sitting
on top of the C runtime allocator. This will be used for all dynamic memory allocation in 
Zig code:

```zig
    state.arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer state.arena.deinit();
```

Next, command line arguments are parsed through a hardwired argument parser 
in the **host** package. If arg parsing fails, the program will terminate
with exit code 5, if the program was started with -h or -help, the program
will regularly exit (the help text had already been printed in the
argument parser module):

```zig
    state.args = Args.parse(&state.arena.allocator) catch |err| {
        warn("Failed to parse arguments\n", .{});
        return;
    };
    if (state.args.help) {
        return;
    }
```

Finally, the sokol_app.h application loop will take over, this will return
when the user asks the application to exit (for instance by pressing the
window close button):

```zig
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = input,
        .width = gfx.WindowWidth,
        .height = gfx.WindowHeight,
        .icon = .{
            // FIXME: KC85 logo
            .sokol_default = true,
        },
        .window_title = switch (kc85_model) {
            .KC85_2 => "KC85/2",
            .KC85_3 => "KC85/3",
            .KC85_4 => "KC85/4"
        }
    });
```

After sokol_app.h has created the application window, the [**init()** callback
function](https://github.com/floooh/kc85.zig/blob/02be0a4d1981c135b0c352048352c8759784eb5b/src/main.zig#L71-L121) will be called, this first initializes the graphics, audio and time measuring host binding modules, and
then creates a KC85 emulator instance on the heap using the ArenaAllocator which was
created at the start of the application. The KC85.create() function takes two
arguments: a pointer to a Zig allocator, and a 'desc struct' with initialization
parameters:

```zig
    state.kc = KC85.create(&state.arena.allocator, .{
        .pixel_buffer = gfx.pixel_buffer[0..],
        .audio_func  = .{ .func = audio.push },
        .audio_sample_rate = audio.sampleRate(),
        .patch_func = .{ .func = patchFunc },
        .rom_caos22  = if (kc85_model == .KC85_2) @embedFile("roms/caos22.852") else null,
        .rom_caos31  = if (kc85_model == .KC85_3) @embedFile("roms/caos31.853") else null,
        .rom_caos42c = if (kc85_model == .KC85_4) @embedFile("roms/caos42c.854") else null,
        .rom_caos42e = if (kc85_model == .KC85_4) @embedFile("roms/caos42e.854") else null,
        .rom_kcbasic = if (kc85_model != .KC85_2) @embedFile("roms/basic_c0.853") else null,
    }) catch |err| {
        warn("Failed to allocate KC85 instance with: {}\n", .{ err });
        std.process.exit(10);
    };
```

Apart from the operating system ROM images (which are directly embedded from the file system
at compile time using Zig's ```@embedFile``` builtin), a KC85 instance requires a 'pixel 
buffer', which is a chunk of memory to render the emulator's display output too, a similar
buffer for the generated audio sample stream, and the sample rate of the audio backend.

Additionally, an optional 'patch callback' is provided which will be called after a tape
image file has been loaded, to allow outside code to apply patches to known problems
in the loaded games.

For the unlikely case that allocation fails, a warning will be shown and the program
terminates with exit code 10.

After the KC85 instance has been successfully created, the command line arguments
(which have been parsed at startup) will be checked if any expansion modules need
be initialized into one of the two expansion slots in the KC85 computers:

```zig
    for (state.args.slots) |slot| {
        if (slot.mod_name) |mod_name| {
            var mod_type = moduleNameToType(mod_name);
            var rom_image: ?[]const u8 = null;
            if (slot.mod_path) |path| {
                rom_image = fs.cwd().readFileAlloc(&state.arena.allocator, path, max_file_size) catch |err| blk:{
                    warn("Failed to load ROM file '{s}' with: {}\n", .{ path, err });
                    mod_type = .NONE;
                    break :blk null;
                };
            }
            state.kc.insertModule(slot.addr, mod_type, rom_image) catch |err| {
                warn("Failed to insert module '{s}' with: {}\n", .{ mod_name, err });
            };
        }
    }
```

An expansion module can either be a simple RAM module or a ROM module. In case of a 
ROM module, a ROM dump must be provided, which will be loaded from the file system.

This loading happens through Zig's standard library, which provides a very handy
function to load an entire file into an adhoc-allocated memory buffer. If
loading the ROM dump fails, a warning will be shown, the module and no module
will be inserted. Note the somewhat awkward way error handling block:

```zig
rom_image = ... catch |err| blk:{
    ...
    break :blk null;
};
```

This replaces the result of the erroneous ```readFileAlloc()``` call with ```null```.

IMHO it would be nice if in such a simple situation one could omit the block name
and write this instead:

```zig
rom_image = ... catch |err| {
    ...
    break null;
};
```

Finally, the command line args are checked whether a tape file should be pre-loaded.
This is pretty much the same as the ROM image file loading:

```zig
    if (state.args.file) |path| {
        state.file_data = fs.cwd().readFileAlloc(&state.arena.allocator, path, max_file_size) catch |err| blk:{
            warn("Failed to load snapshot file '{s}' with: {}\n", .{ path, err });
            break :blk null;
        };
    }
    else {
        state.file_data = null;
    }
```

That's all for the initialization. On to the [per-frame callback function](https://github.com/floooh/kc85.zig/blob/d1d5f5eed96bdc211d41da44c446d5ce4ec91429/src/main.zig#L124-L137), which is 
called by sokol_app.h at display refresh rate:

The first three lines are the actually important stuff: first, the time measuremnt
host binding module is asked for the current frame duration in microseconds, 
than the emulator will be asked to "run" for the equivalent number of 
emulator clock cycles, and finally the current video output of the emulator
will be rendered to the host window (we don't care about the screen tearing
effect which will happen because the emulator's video system runs at
PAL frequency - 50 Hz - while the host system's display refresh rate will
most like be 60 Hz, or higher).

The last part of the frame callback function checks if a pre-loaded tape file
must be loaded into the emulator. This needs to happen after the emulated
system has finished booting (which is checked with the time.elapsed() helper
function in our time measurement host binding module):

```zig
    if ((state.file_data != null) and time.elapsed(load_delay_us)) {
        state.kc.load(state.file_data.?) catch |err| {
            warn("Failed to load snapshot file '{s}' with: {}\n", .{ state.args.file.?, err });
        };
        // arena allocator takes care of deallocation
        state.file_data = null;
    }
```

The only interesting part here is the **.?** which is used to convert the optional
(meaning it can be 'null') file_data byte-slice into a non-optional byte-slice
expected by the KC85.load() function. A Zig **slice** is simply a builtin pointer/size
pair type. Zig slices replace all use cases in C where a pointer to more than one
item is used - while Zig 'pointers' only point to a single item, and also
don't allow pointer arithmetic (so Zig pointers are similar to a slice with 1 item).

The ```cleanup()``` [callback function](https://github.com/floooh/kc85.zig/blob/d1d5f5eed96bdc211d41da44c446d5ce4ec91429/src/main.zig#L139-L143) in **main.zig** is called once when the
user quits the application regularly:

```zig
export fn cleanup() void {
    state.kc.destroy(&state.arena.allocator);
    audio.shutdown();
    gfx.shutdown();
}
```

First, the KC85 instance which was allocated on the heap is freed. This isn't
strictly necessary, because all allocated memory will be freed anyway when the
ArenaAllocator is teared down before the main function exits. Next the
shutdown functions of the audio and graphics host binding modules will be called.
Nothing to see here really.

Finally, the sokol_app.h [event callback](https://github.com/floooh/kc85.zig/blob/d1d5f5eed96bdc211d41da44c446d5ce4ec91429/src/main.zig#L145-L200), which converts keyboard input events
to emulator key presses:

```zig
export fn input(event: ?*const sapp.Event) void {
    const ev = event.?;
    // ...
}
```

The optional pointer (indicated by the ```?*```) and the conversion to a non-optional
pointer looks a bit awkward, this is because the event callback function is directly
called from C code, and C pointers can be null (while Zig pointers cannot be null,
unless they're optional pointers). This is a little wart in the sokol-header host bindings
though, not a Zig problem.

As in many other places, the keyboard input code uses Zig's switch() as expression:

```zig
    const key: u8 = switch (ev.key_code) {
        .SPACE      => 0x20,
        .ENTER      => 0x0D,
        .RIGHT      => 0x09,
        .LEFT       => 0x08,
        //...
    };
```

Using **switch** and **if** as expressions is probably the one "better C" feature
of Zig which I'm using the most. Incredibly handy, especially when initializing
data structures (like in the call to **sapp.run()** where I'm selecting a different window
title based on the KC85 model using an expression-switch):

```zig
    sapp.run(.{
        // ...
        .window_title = switch (kc85_model) {
            .KC85_2 => "KC85/2",
            .KC85_3 => "KC85/3",
            .KC85_4 => "KC85/4"
        }
    });
```

That's pretty much all the interesting stuff in **main.zig**, on to the
host bindings package:

## Host Bindings

[TODO]
