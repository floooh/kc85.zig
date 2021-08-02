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
in the **host** package. If parsing arguments fails, the program

This is the entry point of the KC85 execut
