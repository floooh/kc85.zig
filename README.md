A simple KC85/2, /3 and /4 emulator for Windows, macOS and Linux, written in Zig. Uses the [sokol headers](https://github.com/floooh/sokol) for platform abstraction.

## Build

With Zig version 0.8.0, on Windows, macOS or Linux:

```
zig build -Drelease-fast=true
```

(NOTE: on Linux you also need to install the ALSA, X11 and GL development packages)

## Digger
```
zig-out/bin/kc853 -slot8 m022 -file data/digger3.tap
```
![Digger Screenshot](screenshots/digger.png)

Press [Enter] to start a new game round, and [Esc] to continue
after you died. Use the arrows keys to navigate.
