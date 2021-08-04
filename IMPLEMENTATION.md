# IMPLEMENTATION NOTES

Some implementation notes from top (build.zig) to bottom (the actual emulator code).

## Project structure and build script

The different KC85 versions (KC85/2, /3 and /4) are compiled into separate
executables using conditional compilation.

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

The kc85 build targets are split into 3 separate packages:

- **[emu](https://github.com/floooh/kc85.zig/tree/main/src/emu)**: the actual emulator source code, completely platform-agnostic
- **[host](https://github.com/floooh/kc85.zig/tree/main/src/host)**: the "host bindings", this is the source code which connects the emulator source code to the host platform for rendering the emulator display output into a window, make the emulator's sound output audible and receiving keyboard input from the host's window system.
- **[sokol](https://github.com/floooh/kc85.zig/tree/main/src/sokol)**: this the mixed C/Zig language bindings package to the sokol headers

And finally there's the top-level **[main.zig](https://github.com/floooh/kc85.zig/blob/main/src/main.zig)** source file which ties everything together.

Module packages need a single top level module which gathers and 're-exports' all package modules which need to be visible from the outside, looking like [this](https://github.com/floooh/kc85.zig/blob/main/src/host/host.zig):

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
        std.os.exit(5);
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

Apart from the operating system ROM images (which are directly embedded from
the file system at compile time using Zig's ```@embedFile``` builtin), a KC85
instance requires a 'pixel buffer', which is a chunk of memory to render the
emulator's display output too, a callback to push generated audio samples to
the host platform's audio backend, and the sample rate of the audio backend.

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

The [host bindings](https://github.com/floooh/kc85.zig/tree/main/src/host) package
takes care of:

- render the emulator's display output to a window via sokol_gfx.h
- routing the emulator's audio output to the host platforms audio API via sokol_audio.h
- time measuring for running the emulator in real time via sokol_time.h
- command line parsing via the Zig standard library

The [args.zig module](https://github.com/floooh/kc85.zig/blob/main/src/host/args.zig)
contains a simple hardwired argument parser on top of Zig's ```std.process.args```.

The code isn't all that remarkable but is a good example for working with Zig's
optional values and error unions (because the return value of the argument
iterator's next() function is both). In such 'non-trivial' situations I found it
helpful to use expressive variable names to keep track of the 'type wrappers'.

For instance an error union variable might be called ```error_or_value```, and
once the error and value has been separated, the resulting variables would
be called ```err``` and ```value```. Same for optional variables, sometimes
it makes sense to call them ```optional_value```, and once the 'optional' has
been stripped away, just call the remaining non-optional variable ```value```.

The ArgIterator's ```next()``` function returns a value of type ```?NextError![]u8```,
which is a bit of a mouthful, but the type declaration can be read from left to right:

The ```?``` means it's an optional value, so the function either returns
```null```, or the error union type ```NextError![]u8```, which is either an
error from the NextError error set, or a ```[]u8``` byte slice containing the
string of the next command line argument.

This complex return value can easily be unwrapped with Zig's syntax sugar for
optionals and error unions. First we'll iterate over the arguments using 
Zig's "while with optionals" (the ```a``` parameter is an allocator that has been
passed into the arg parsing function from the outside), if the next function
return 'null', the iteration is complete:

```zig
    while (arg_iter.next(a)) |error_or_arg| {
        // ...
    }
```

The ```error_or_arg``` variable is now guaranteed to be non-null, but it
can still contain an error. Next the value payload is separated from the error 
using ```catch```, and if the error union contained an error, a warning
will be shown and the error will be passed up to the caller.

```zig
    const arg = error_or_arg catch |err| {
        warn("Error parsing arguments: {s}", .{ err });
        return err;
    }; 
```

The remaining ```arg``` variable is now finally the actual argument
string we're interested in as a byte slice ```[]u8```.

A similar unwrapping happens further down when a followup argument (such as a
module name) is expected, but this time a bit more compact:

```zig
    mod_name = try arg_iter.next(a) orelse {
        warn("Expected module name after '-slot8'\n", .{});
        return error.InvalidArgs;
    };
```

First the ```orelse``` removes the optional part from the return value, if the
return value is ```null```, the ```orelse``` block will be executed, which
results in the function returning an adhoc error 'InvalidArgs' (lookup for
"Inferred Error Sets" in the Zig documentation to find out more about this very
convenient feature:
https://ziglang.org/documentation/master/#Inferred-Error-Sets).

Otherwise the resulting error union type will be checked by the ```try```.
If the error union contains an error, the function stops executing and the
resulting error will be returned to the caller. Otherwise the unwrapped
argument string is assigned to mod_name.

The code in [gfx.zig](https://github.com/floooh/kc85.zig/blob/main/src/host/gfx.zig),
[audio.zig](https://github.com/floooh/kc85.zig/blob/main/src/host/audio.zig)
and [time.zig](https://github.com/floooh/kc85.zig/blob/main/src/host/time.zig)
is all bog-standard Sokol Header code (using the automatically generated
[Zig bindings](https://github.com/floooh/sokol-zig). If you're interesting
in this stuff it's better to look at the [sokol-zig examples](https://github.com/floooh/sokol-zig/tree/master/src/examples)
directly.

## The Emulator Code

All the emulator code is in the [emu package](https://github.com/floooh/kc85.zig/tree/main/src/emu).

The package structure has the module [kc85.zig](https://github.com/floooh/kc85.zig/blob/main/src/emu/kc85.zig)
at the top, with all other modules being dependencies:

- the 3 Z80 family chips in the KC85: [CPU](https://github.com/floooh/kc85.zig/blob/main/src/emu/z80.zig), [CTC](https://github.com/floooh/kc85.zig/blob/main/src/emu/z80ctc.zig) and [PIO](https://github.com/floooh/kc85.zig/blob/main/src/emu/z80pio.zig)
- a [interrupt daisy chain](https://github.com/floooh/kc85.zig/blob/main/src/emu/z80daisy.zig) helper module which is shared between the PIO and CTC module.
- a [virtual memory system](https://github.com/floooh/kc85.zig/blob/main/src/emu/memory.zig) to map host memory to a 16-bit address space
- a [clock helper module](https://github.com/floooh/kc85.zig/blob/main/src/emu/clock.zig) which converts micro-seconds to emulator clock ticks, and keeps track of executed clock ticks
- a simple [square wave beeper](https://github.com/floooh/kc85.zig/blob/main/src/emu/beeper.zig) to generate audio samples
- and a [keyboard buffer helper](https://github.com/floooh/kc85.zig/blob/main/src/emu/keybuf.zig) which stores short host system key presses long enough for the emulator's operating system to scan the currently pressed keys

This is a good time to talk about the somewhat unusual code structure of the emulator modules. Each modules exposes
a class-like struct with namespaced functions (which in Zig allow method-call-syntax). But (and that's the
unusual part) the implementation code of the namespaced functions isn't in the struct declaration, but
in a separate, private implementation namespace. Example:

```zig
pub const Clock = struct {
    freq_hz:        i64,
    ticks_to_run:   i64 = 0,
    overrun_ticks:  i64 = 0,
    
    pub fn ticksToRun(clk: *Clock, micro_seconds: u32) u64 {
        return impl.ticksToRun(clk, micro_seconds);
    }

    pub fn ticksExecuted(clk: *Clock, ticks_executed: u64) void {
        impl.ticksExecuted(clk, ticks_executed);
    }
};

const impl = struct {

fn ticksToRun(clk: *Clock, micro_seconds: u32) u64 {
    // implementation code here
}

} // impl
```

The only reason for this code structure is that I probably have too much C in the blood ;)

Just like in C headers, I like to look at the top of a file to explore its
public API. Moving the lengthy (and frankly, unimportant) implementation code out of 
the public API 'declarations' towards the bottom of the source keeps the 
important part of the module (the public API) compact at the top of the
file instead of mixing API declarations and implementation code. This preference
is clearly a C-ism, and Zig shares this "problem" with pretty much all other
languages with a module system. At the moment this looks like a good solution
to me, but of course it's entirely subjective, and maybe I'll change my mind
as I write more Zig code.

Another interesting topic is that I suffered from much of the same "decision paralysis"
that I experienced in C++ code, and which is less of a problem in C.

Some examples:

### Class-style APIs or function-style APIs?

TBH I would have preferred C-style function APIs, which functions living 
outside the structs they work on. Moving functions into structs allows
method-call-syntax, which sometimes has advantages (mainly being able
to chain method calls, instead of nesting them), but it also comes with a
couple of downsides, which are pretty well known from C++ (mainly that 
types can't be extended with new 'methods' - Zig doesn't have [UFCS](https://en.wikipedia.org/wiki/Uniform_Function_Call_Syntax)).

But in Zig, using namespaced functions has another advantage: you can
import a single struct from a module, and get all the functions that
work on this struct too with this single import. IMHO that's a very important
feature, and maybe explains why Zig doesn't have UFCS (even though I still
find this a bit disappointing).

For instance, I would have preferred to use method-call-syntax for a lot
of helper functions in testing code, [like here](https://github.com/floooh/kc85.zig/blob/138035b72bd713b5c67b323d65761f235d8e8f2b/tests/z80test.zig#L84-L101):

```zig
fn step(cpu: *CPU) usize {
    var ticks = cpu.exec(0, .{ .func=tick, .userdata=0 });
    while (!cpu.opdone()) {
        ticks += cpu.exec(0, .{ .func=tick, .userdata=0 });
    }
    return ticks;
}

fn skip(cpu: *CPU, steps: usize) void {
    var i: usize = 0;
    while (i < steps): (i += 1) {
        _ = step(cpu);
    }
}

fn flags(cpu: *CPU, expected: u8) bool {
    return (cpu.regs[F] & ~(XF|YF)) == expected;
}
```

With UFCS I could write the following piece of testing code:

```zig
    skip(&cpu, 7); 
    T(4==step(&cpu)); T(0x00 == cpu.regs[A]); T(flags(&cpu, ZF|NF));
    T(4==step(&cpu)); T(0xFF == cpu.regs[A]); T(flags(&cpu, SF|HF|NF|CF));
    T(4==step(&cpu)); T(0x06 == cpu.regs[A]); T(flags(&cpu, NF));
```

...like this, which IMHO is a lot nicer (especially since all of the
'regular' API for the 'cpu' object uses method call syntax):

```zig
    cpu.skip(7); 
    T(4==cpu.step()); T(0x00 == cpu.regs[A]); T(cpu.flags(ZF|NF));
    T(4==cpu.step()); T(0xFF == cpu.regs[A]); T(cpu.flags(SF|HF|NF|CF));
    T(4==cpu.step()); T(0x06 == cpu.regs[A]); T(cpu.flags(NF));
```

Another slight case of 'decision paralysis' was how to handle:

### Struct Initialization

I ended up with three variants:

For simple objects, I'm using a straight-forward data-initialization approach
without running any code. Zig allows default-intiialization of struct items,
while not allowing uninitialized items (unless explicitly declared via 'undefined'):

```zig
pub const Clock = struct {
    freq_hz:        i64,
    ticks_to_run:   i64 = 0,
    overrun_ticks:  i64 = 0,
    
    // ...
};
```

This sets two struct items to an initial value, but keeps one item for which a
default value makes no sense, and which *must* be provided by the user,
uninitialized. Trying to create a variable of this type fails with an error
that freq_hz is not initialized:

```zig
var clock = Clock{};
```
```sh
...error: missing field: 'freq_hz'
```

So API users know that they must at least provide a value for ```freq_hz```:

```zig
var clock = Clock{ .freq_hz = 1_750_000 };
```

The next initialization method is for objects which are more complex or need
to run code when created, an namespaced init() function which returns a fully
initialized object by value, and which may also take a description struct with
initialization parameters:

```zig
pub const Beeper = struct {
    pub const Desc = struct {
        tick_hz: u32,
        sound_hz: u32,
        volume: f32,
    };

    state: u1,
    period: i32,
    counter: i32,
    magnitude: f32,
    sample: f32,
    dcadjust_sum: f32,
    dcadjust_pos: u9,
    dcadjust_buf: [dcadjust_buflen]f32,

    pub fn init(desc: Desc) Beeper {
        return impl.init(desc);
    }
    // ...
```

Note that none of the struct items have default initialization values. This 
(hopefully) makes it clear that the struct shouldn't be 'data-initialized'.
Instead:

```zig
var beeper = Beeper.init(.{
    .tick_hz  = 1_750_000,
    .sound_hz = 44_100,
    .volume   = 0.5,
});
```

..and the last initialization method I'm using (only in the KC85 struct) creates
a new instance on the heap:

```zig
pub const KC85 = struct {
    const Desc = struct {
        // ...
    };
    // ...

    pub fn create(allocator: *std.mem.Allocator, desc: Desc) !*KC85 {
        // ...
    }
    pub fn destroy(sys: *KC85, allocator: *std.mem.Allocator) void {
        // ...
    }
}
```

Which can be used like this (note that an allocator must be provided in good
Zig style, and that creation can fail and must be handled - for the simple
reason that memory allocation can fail):

```zig
    var kc85 = try KC85.create(my_allocator, .{
        // initialization parameters...
    });
    defer kc85.destroy(my_allocator);
```

This last initialization method is the one I'm least sure about, should
heap-creation really be baked into the class like this? Or would it be
better to have generic alloc/free functions which take an object 'blueprint'
create with the init-method style initialization above?

But enough with the initialization and 'decision paralysis' topic. In the end
this isn't a big deal, and will probably become a complete non-topic as I'm
becoming more familiar with Zig. But it shows that there are a few areas in Zig
where there's not just one way to do things. It's still much better than in
many other modern languages, but hopefully this sort of thing will not become
common.

The next interesting topic in the emulator code is Zig's

### Arbitrary Bit-Width Integers

Home computer emulators are essentially 100% integer operations and bit twiddling
code, and old computer chips are full of odd-width registers (interestingly, not
so the Z80 CTC and PIO, which are mostly 8-bit wide counters and IO ports).

Nonetheless, Zig's arbitrary-width integers came in very handy, but not for
the reason I thought!

The reason I *thought* those integers would come in handy was odd-bitwidth
counters and wrap-around. For instance if I have a 5-bit counter which 
can wrap around, I'd do this in C:

```c
    uint8_t counter = 0;
    counter = (counter + 1) & 0x1F;
```

In Zig this is reduced to:

```zig
    var counter: u5 = 0;
    counter +%= 1;
```

The '5-bit-ness' is directly encoded in the type, and anybody reading the code 
sees immediately that this is a 5-bit counter. The ```+%=``` increments
with wrap-around (the vanilla ```+=``` would runtime-panic on overflow).

But the reason why arbitrary-width integers were *actually* useful was
type-checking. By using "just the right" bit-width for integers, Zig's 
explicit integer conversion rules may help catching a number of errors where
'incompatible' bit-width integers are assigned. For instance if I'm accidentally 
trying to stash a 3-bit integer into a 2-bit value, that's an error.

## Conclusions

...and that's about it I guess. In a way, writing the emulator was almost
boring, but in the very good sense that there were no big surprises.

Ok, one positive surprise was that the CPU emulator seems to be quite a bit
faster than my C emulator, even though it *should* be slower because the Zig
emulator uses a 'hand crafted' algorithmic decoder while the C emulator uses a
code-generated switch-case decoder which should be faster. I haven't explored
the exact reason for this performance difference yet, and for the entire KC85
emulator the CPU performance doesn't matter much and is lost in the noise, 
overall performance is pretty much identical with the C emulator.

Another nice experience was that Zig is 'transparent'. If you think that
something probably works in a specific way, then it's very likely that 
it indeed works that way. One example is the ```builtin module``` workaround:
A little bit of googling and looking around in build system sources made it
clear pretty quickly that the Zig build system is code-generating a module
for build-options defined in the build.zig file. And where would Zig most 
likely store the generated module sources? Probably in the ```zig-out``` directory. 
And that's exactly where they were.

Similar for the error unions and optional types. Coming from C those are new
concepts (even though I already knew them from my tinkering with Rust), but
somehow Zig manages that the same concepts feel natural much more quickly than
in Rust.

I only stumbled over one compiler error, which could easily be worked around:

[This struct](https://github.com/floooh/kc85.zig/blob/138035b72bd713b5c67b323d65761f235d8e8f2b/src/emu/kc85.zig#L1239-L1251)
should actually be a packed struct which looks like this:

```zig
const KCCHeader = packed struct {
    name:           [16]u8,
    num_addr:       u8,
    load_addr_l:    u8,
    load_addr_h:    u8,
    end_addr_l:     u8,
    end_addr_h:     u8,
    exec_addr_l:    u8,
    exec_addr_h:    u8,
    pad:            [105]u8, // pads to 128 byte
};
```

...but this resulted in a wrong struct size of 135 bytes, instead of 128 bytes. The
workaround is to use ```extern``` instead of ```packed```, which is actually
for C compatibility.

Other then that I have only minor nitpicks, some of them probably subjective:

- I still think UFCS would be handy, to allow method-style calls for functions
declared outside a struct
- the 'block expression syntax' to return a value from a code block is awkward (```blk: { break :blk result }```)

I think that's about it. When I started writing Zig code I was a bit miffed about
the explicit integer conversion rules, but I've come around full circle. It's
actually a good thing, and doesn't add much friction after getting used to it.

As I wrote above, my single one "better C" feature of Zig is 
"if and switch are expressions", but that's kinda expected :)

Ok, one final nitpick, which hasn't been much of a problem in the actual emulator
code, but which has bitten me again in the host-bindings code:

Consider [this struct initialization code](https://github.com/floooh/kc85.zig/blob/138035b72bd713b5c67b323d65761f235d8e8f2b/src/host/gfx.zig#L104-L107) for creating a sokol-gfx render pass object:

```zig
    var pass_desc = sg.PassDesc{ };
    pass_desc.color_attachments[0].image = state.display.bind.fs_images[0];
    state.upscale.pass = sg.makePass(pass_desc);
```

Note how the pass_desc struct can't be initialized in one go, because it has an embedded 
default-initialized color_attachments array where the first item needs to be
initialized and all other items should be default initialized. Normally I'd want to do this:

```zig
    state.upscale.pass = sg.makePass(.{
        .color_attachments = .{
            .{ state.display.bind.fs_images[0] }
        }
    });
```

...or alternatively this:

```zig
    state.upscale.pass = sg.makePass(.{
        .color_attachments[0] = .{ state.display.bind.fs_images[0] }
    });
```

...but currently this doesn't work, because Zig expects all array items to be present,
even though the array items can be fully default-initialized.

This is tracked in this ticket: https://github.com/ziglang/zig/issues/6068

Ideally, a fix for this problem would also simplify default-initialization of
arrays, especially multi-dimensional arrays. For instance consider [this default-initialization](https://github.com/floooh/kc85.zig/blob/138035b72bd713b5c67b323d65761f235d8e8f2b/src/emu/z80ctc.zig#L90) in z80ctc.zig:

```zig
pub const CTC = struct {
    channels: [NumChannels]Channel = [_]Channel{.{}} ** NumChannels,
    // ...
};
```

...since the ```Channel``` struct is fully default-initialized, it would be 
nice if one could write this instead:

```zig
pub const CTC = struct {
    channels: [NumChannels]Channel = .{},
    // ...
};
```

Over and out :)