This will become a little toy emulator for the KC85/2../4 home computer
series written in Zig.

For now (with Zig version 0.8.0):

Run the module-integrated unit tests:

```sh
> zig build tests
```

Run the high-level instruction tester (tests/z80test.zig):

```sh
> zig build z80test
```

Run the much more thorough ZEXDOC and ZEXALL tests (tests/z80zex.zig):

```sh
> zig build z80zexdoc -Drelease-safe=true
> zig build z80zexall -Drelease-safe=true
```

WIP emulators:

```sh
> zig build run-kc852 -Drelease-fast=true
> zig build run-kc853 -Drelease-fast=true
> zig build run-kc854 -Drelease-fast=true
```