//
//  Simple hardwired cmdline args parser
//
const std = @import("std");
const print = std.debug.print;
const warn = std.log.warn;
const mem = std.mem;

const Args = @This();

const Slot = struct {
    addr: u8,
    mod_name: ?[]const u8 = null,
    mod_path: ?[]const u8 = null,
};

help: bool = false,
slots: [2]Slot = [_]Slot{ .{ .addr = 0x08 }, .{ .addr = 0x0C } },
file: ?[]const u8 = null, // path to .kcc or .tap file

pub fn parse(a: std.mem.Allocator) !Args {
    var res = Args{};
    var arg_iter = try std.process.argsWithAllocator(a);
    defer arg_iter.deinit();
    _ = arg_iter.skip();
    while (arg_iter.next()) |arg| {
        if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "-help") or mem.eql(u8, arg, "--help")) {
            printHelp();
            res.help = true;
        } else if (mem.eql(u8, arg, "-slot8")) {
            const next = arg_iter.next() orelse {
                warn("Expected module name after '-slot8'\n", .{});
                return error.InvalidArgs;
            };
            res.slots[0].mod_name = try a.dupe(u8, next);
            if (!validateModuleName(res.slots[0].mod_name.?)) {
                warn("Didn't recognize module name: {s}\n", .{res.slots[0].mod_name.?});
                return error.InvalidArgs;
            }
            if (isRomModule(res.slots[0].mod_name.?)) {
                res.slots[0].mod_path = arg_iter.next() orelse {
                    warn("Expected module file after '-slot8 {s}'\n", .{res.slots[0].mod_name.?});
                    return error.InvalidArgs;
                };
            }
        } else if (mem.eql(u8, arg, "-slotc")) {
            const next = arg_iter.next() orelse {
                warn("Expected module name after '-slotC'\n", .{});
                return error.InvalidArgs;
            };
            res.slots[1].mod_name = try a.dupe(u8, next);
            if (!validateModuleName(res.slots[1].mod_name.?)) {
                warn("Didn't recognize module name: {s}\n", .{res.slots[1].mod_name.?});
                return error.InvalidArgs;
            }
            if (isRomModule(res.slots[1].mod_name.?)) {
                res.slots[1].mod_path = arg_iter.next() orelse {
                    warn("Expected module file after '-slotc {s}'\n", .{res.slots[1].mod_name.?});
                    return error.InvalidArgs;
                };
            }
        } else if (mem.eql(u8, arg, "-file")) {
            const next = arg_iter.next() orelse {
                warn("Expected path to .kcc or .tap file after '-load'\n", .{});
                return error.InvalidArgs;
            };
            res.file = try a.dupe(u8, next);
        } else {
            warn("Unknown argument: {s} (run with '-help' to show valid args)\n", .{arg});
            return error.InvalidArgs;
        }
    }
    return res;
}

fn printHelp() void {
    print(
        \\
        \\Command line args:
        \\  -slot8 [module_name] [rom file]: insert a module into slot 8
        \\  -slotc [module_name] [rom file]: insert a module into slot C
        \\  -file  [path to file]: path to .kcc or .tap file
        \\
        \\Valid module names:
        \\  m006: BASIC ROM for KC85/2
        \\  m011: 64 KByte RAM module
        \\  m012: TEXOR text editor ROM module
        \\  m022: 16 KByte RAM module
        \\  m026: FORTH ROM module (needs 'data/forth.853')
        \\  m027: asm development module (needs 'data/develop.853')
        \\
        \\
    , .{});
}

fn validateModuleName(name: []const u8) bool {
    const valid_names = [_][]const u8{ "m006", "m011", "m012", "m022", "m026", "m027" };
    for (valid_names) |valid_name| {
        if (mem.eql(u8, valid_name, name)) {
            return true;
        }
    } else {
        return false;
    }
}

fn isRomModule(name: []const u8) bool {
    return !(mem.eql(u8, name, "m011") or mem.eql(u8, name, "m022"));
}
