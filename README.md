This will become a little toy emulator for the KC85/2../4 home computer
series written in Zig.

For now (with Zig version 0.8.0):

Run the high-level instruction tester (tests/z80test.zig):

zig build z80test

Run the much more thorough ZEXDOC test (tests/z80zex.zig):

zig build z80zexdoc -Drelease-fast=true