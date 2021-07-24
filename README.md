A simple KC85/2, /3 and /4 emulator for Windows, macOS and Linux, written in Zig. Uses the [sokol headers](https://github.com/floooh/sokol) for platform abstraction.

## Build

With Zig version 0.8.0, on Windows, macOS or Linux:
```
zig build
```

The default debug version will usually be fast enough, to build with optimizations 
use any of:

```
zig build -Drelease-safe=true
zig build -Drelease-fast=true
zig build -Drelease-small=true
```
(NOTE: on Linux you also need to install the ALSA, X11 and GL development packages)

## Build and start into KC85/2, /3 and /4

```
zig build run-kc852
zig build run-kc853
zig build run-kc854
```

Run ```zig build --help``` to see the remaining build targets.

> NOTE: when running any of the games, turn down your sound volume first. The raw square-wave sound can be a bit "aggressive". You have been warned ;)

## Run Digger

```
zig build run-kc853 -- -slot8 m022 -file data/digger3.tap
```
![Digger Screenshot](screenshots/digger.png)

Press [Enter] to start a new game round, and [Esc] to continue
after you died. Use the arrows keys to navigate.

## Run Jungle
```
zig build run-kc853 -- -slot8 m022 -file data/jungle.kcc
```
![Jungle Screenshot](screenshots/jungle.png)

Navigate with arrow keys, jump with [Space].

