//
//  Simple hardwired cmdline args parser
//
const std = @import("std");
const print = std.debug.print;
const warn  = std.debug.warn;
const mem = std.mem;

pub const Args = struct {
    help:  bool = false,
    slot8: ?[]const u8 = null, // name of module to insert into slot 8 (m006, m011, ...)
    slotC: ?[]const u8 = null, // same of slot C
    file:  ?[]const u8 = null, // path to .kcc or .tap file
    
    pub fn parse(a: *std.mem.Allocator) !Args {
        return impl.parse(a);
    }
};
    
//== IMPLEMENTATION ============================================================
const impl = struct {

pub fn parse(a: *std.mem.Allocator) !Args {
    var res = Args{};
    var arg_iter = std.process.args();
    _ = arg_iter.skip();
    while (arg_iter.next(a)) |error_or_arg| {
        const arg = error_or_arg catch |err| {
            warn("Error parsing arguments: {s}", .{ err });
            return err;
        };
        if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "-help") or mem.eql(u8, arg, "--help")) {
            printHelp();
            res.help = true;
        }
        else if (mem.eql(u8, arg, "-slot8")) {
            const mod_name = arg_iter.next(a) orelse {
                warn("Expected module name after '-slot8'\n", .{});
                return error.InvalidArgs;
            };
        }
        else if (mem.eql(u8, arg, "-slotc")) {
            const mod_name = arg_iter.next(a) orelse {
                warn("Expected module name after '-slotC'\n", .{});
                return error.InvalidArgs;
            };
        }
        else if (mem.eql(u8, arg, "-load")) {
            const file = arg_iter.next(a) orelse {
                warn("Expected path to .kcc or .tap file after '-load'\n", .{});
                return error.InvalidArgs;
            };
        }
        else {
            warn("Unknown argument: {s}\n", .{ arg });
        }
    }
    return res;
}

fn printHelp() void {
    print(\\
          \\Command line args:
          \\  -slot8 [module_name] [rom file]: insert a module into slot 8
          \\  -slotc [module_name] [rom file]: insert a module into slot 8
          \\  -file  [path to file]: path to .kcc or .tap file
          \\
          \\Valid module names:
          \\  m006:   BASIC ROM for KC85/2
          \\  m011:   64 KByte RAM module
          \\  m012:   TEXOR text editor ROM module
          \\  m022:   16 KByte RAM module
          \\  m026:   FORTH ROM module
          \\  m027:   assembler development module
          \\
          \\
          , .{});
}

}; // impl
