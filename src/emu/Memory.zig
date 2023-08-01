// A virtual memory system for computers with 16-bit address space
// and optional bank switching.
//
const assert = @import("std").debug.assert;

const Memory = @This();
/// the CPU visible memory pages resolved from the optionally mapped memory banks
pages: [num_pages]Page = [_]Page{.{}} ** num_pages,
/// optionally mapped memory bank mapping to host memory
banks: [num_banks][num_pages]BankPage = [_][num_pages]BankPage{[_]BankPage{.{}} ** num_pages} ** num_banks,

/// map a range of host memory to a 16-bit address as RAM
pub fn mapRAM(self: *Memory, bank_index: usize, addr: u16, ram: []u8) void {
    // map both the read- and write-slice to host memory
    assert(ram.len <= addr_range);
    self.map(bank_index, addr, ram.len, ram, ram);
}

/// map a range of host memory to a 16-bit address as ROM
pub fn mapROM(self: *Memory, bank_index: usize, addr: u16, rom: []const u8) void {
    assert(rom.len <= addr_range);
    self.map(bank_index, addr, rom.len, rom, null);
}

/// read an 8-bit value from mapped memory
pub fn r8(self: *Memory, addr: u16) u8 {
    return self.pages[addr >> page_shift].read[addr & page_mask];
}

/// write an 8-bit value to mapped memory
pub fn w8(self: *Memory, addr: u16, val: u8) void {
    self.pages[addr >> page_shift].write[addr & page_mask] = val;
}

/// read a 16-bit value from mapped memory
pub fn r16(self: *Memory, addr: u16) u16 {
    const l: u16 = self.r8(addr);
    const h: u16 = self.r8(addr +% 1);
    return (h << 8) | l;
}

/// write a 16-bit value to mapped memory
pub fn w16(self: *Memory, addr: u16, val: u16) void {
    self.w8(addr, @truncate(val));
    self.w8(addr +% 1, @truncate(val >> 8));
}

/// write a whole range of bytes to mapped memory
pub fn writeBytes(self: *Memory, addr: u16, bytes: []const u8) void {
    var a = addr;
    for (bytes) |byte| {
        self.w8(a, byte);
        a +%= 1;
    }
}

/// unmap one memory bank
pub fn unmapBank(self: *Memory, bank_index: usize) void {
    for (&self.banks[bank_index], 0..) |*page, page_index| {
        page.read = null;
        page.write = null;
        self.updatePage(page_index);
    }
}

/// unmap all memory banks
pub fn unmapAll(self: *Memory) void {
    for (&self.banks) |*bank| {
        for (bank) |*page| {
            page.read = null;
            page.write = null;
        }
    }
    for (self.pages, 0..) |_, page_index| {
        self.updatePage(page_index);
    }
}

// a memory bank page with optional mappings to host memory
const BankPage = struct {
    read: ?[]const u8 = null,
    write: ?[]u8 = null,
};

// a CPU visible memory page with guaranteed mappings
const Page = struct {
    read: []const u8 = &unmapped_page,
    write: []u8 = &junk_page,
};

const page_shift = 10; // page size is 1 KB
const page_size = 1 << page_shift;
const page_mask = page_size - 1;
const addr_range = 1 << 16;
const addr_mask = addr_range - 1;
const num_pages = addr_range / page_size;
const num_banks = 4; // max number of memory bank layers

// dummy pages for unmapped reads and writes
const unmapped_page: [page_size]u8 = [_]u8{0xFF} ** page_size;
var junk_page: [page_size]u8 = [_]u8{0} ** page_size;

// internal memory mapping function for RAM, ROM and separate RW areas
fn map(self: *Memory, bank_index: usize, addr: u16, size: usize, read: ?[]const u8, write: ?[]u8) void {
    assert((addr & page_mask) == 0); // start address must be at page boundary
    assert((size & page_mask) == 0); // size must be multiple of page size
    assert((read != null) or (write != null));

    var offset: usize = 0;
    while (offset < size) : (offset += page_size) {
        const page_index = ((addr + offset) & addr_mask) >> page_shift;
        const bank = &self.banks[bank_index][page_index];
        if (read) |r| {
            bank.read = r[offset..(offset + page_size)];
        } else {
            bank.read = null;
        }
        if (write) |w| {
            bank.write = w[offset..(offset + page_size)];
        } else {
            bank.write = null;
        }
        self.updatePage(page_index);
    }
}

// helper function to update the CPU-visible page table for one memory page
fn updatePage(self: *Memory, page_index: usize) void {
    // find highest priority bank page with valid mapping
    for (&self.banks) |*bank| {
        if (bank[page_index].read) |_| {
            // highest priority mapped bank page found
            self.pages[page_index] = .{
                .read = bank[page_index].read.?,
                .write = bank[page_index].write orelse &junk_page,
            };
            break;
        }
    } else {
        // fallthrough: no mapped bank page found
        self.pages[page_index] = .{
            .read = &unmapped_page,
            .write = &junk_page,
        };
    }
}

//=== TESTS ====================================================================
const expect = @import("std").testing.expect;

test "initial state" {
    try expect(unmapped_page[0] == 0xFF);
    try expect(unmapped_page[1023] == 0xFF);
    try expect(junk_page[0] == 0);
    try expect(junk_page[1023] == 0);

    var mem = Memory{};
    try expect(mem.pages[0].read[0] == 0xFF);
    try expect(mem.pages[63].read[1023] == 0xFF);
    mem.pages[0].write[0] = 23;
    try expect(mem.pages[0].read[0] == 0xFF);
    try expect(junk_page[0] == 23);
}

test "RAM mapping" {
    var ram = [_]u8{23} ** 0x10000;
    var mem = Memory{};

    // map the first 32 KB of the address range as RAM
    mem.mapRAM(0, 0x0000, ram[0..0x8000]);
    for (mem.pages, 0..) |page, i| {
        if (i < 32) {
            try expect(&page.read[0] == &ram[i * page_size]);
            try expect(&page.write[0] == &ram[i * page_size]);
            try expect(&page.read[0] == &page.write[0]);
            try expect(page.read[0] == 23);
            try expect(page.read[1023] == 23);
            try expect(page.write[0] == 23);
            try expect(page.write[1023] == 23);
        } else {
            try expect(&page.read[0] == &unmapped_page[0]);
            try expect(&page.write[0] == &junk_page[0]);
            try expect(page.read[0] == 0xFF);
            try expect(page.read[1023] == 0xFF);
        }
    }
    ram[1024] = 42;
    try expect(mem.pages[1].read[0] == 42);
    mem.pages[1].write[0] = 46;
    try expect(ram[1024] == 46);
}

test "ROM mapping" {
    var rom = [_]u8{23} ** 0x10000;
    var mem = Memory{};

    // map the first 32 KB of the address range as ROM
    mem.mapROM(0, 0x0000, rom[0..0x8000]);
    try expect(mem.pages[0].read[0] == 23);
    // writing to ROM has no effect
    mem.pages[0].write[0] = 42;
    try expect(mem.pages[0].read[0] == 23);
    // but the write should go to the hidden junk page
    try expect(junk_page[0] == 42);
}

test "read/write bytes" {
    var ram = [_]u8{0} ** 0x10000;
    var mem = Memory{};

    mem.mapRAM(0, 0x0000, &ram);
    mem.w8(0x0000, 23);
    try expect(mem.r8(0x0000) == 23);
    mem.w8(0x8000, 42);
    try expect(mem.r8(0x8000) == 42);
}

test "read/write words" {
    var ram = [_]u8{0} ** 0x10000;
    var mem = Memory{};

    mem.mapRAM(0, 0x0000, &ram);
    mem.w16(0x0000, 0x1234);
    try expect(mem.r16(0x0000) == 0x1234);
    try expect(mem.r8(0x0000) == 0x34);
    try expect(mem.r8(0x0001) == 0x12);
    mem.w16(0x8000, 0x5678);
    try expect(mem.r16(0x8000) == 0x5678);
    try expect(mem.r8(0x8000) == 0x78);
    try expect(mem.r8(0x8001) == 0x56);
    // test with wraparound
    mem.w16(0xFFFF, 0x2345);
    try expect(mem.r16(0xFFFF) == 0x2345);
    try expect(mem.r8(0xFFFF) == 0x45);
    try expect(mem.r8(0x0000) == 0x23);
}

test "bank visibility" {
    var bank0 = [_]u8{0} ** 0x10000;
    var bank1 = [_]u8{1} ** 0x10000;
    var bank2 = [_]u8{2} ** 0x10000;
    var mem = Memory{};

    mem.mapRAM(0, 0x0000, bank0[0..0x4000]);
    mem.mapRAM(1, 0x0000, bank1[0..0x8000]);
    mem.mapRAM(2, 0x0000, bank2[0..0xC000]);
    try expect(mem.r8(0x0000) == 0);
    try expect(mem.r8(0x3FFF) == 0);
    try expect(mem.r8(0x4000) == 1);
    try expect(mem.r8(0x7FFF) == 1);
    try expect(mem.r8(0x8000) == 2);
    try expect(mem.r8(0xBFFF) == 2);
    try expect(mem.r8(0xC000) == 0xFF);
    try expect(mem.r8(0xFFFF) == 0xFF);
    mem.w8(0x0000, 55);
    mem.w8(0x4000, 55);
    mem.w8(0x8000, 55);
    try expect(bank0[0x0000] == 55);
    try expect(bank1[0x0000] == 1);
    try expect(bank2[0x0000] == 2);
    try expect(bank0[0x4000] == 0);
    try expect(bank1[0x4000] == 55);
    try expect(bank2[0x4000] == 2);
    try expect(bank0[0x8000] == 0);
    try expect(bank1[0x8000] == 1);
    try expect(bank2[0x8000] == 55);
}

test "unmap bank" {
    var bank0 = [_]u8{1} ** 0x10000;
    var bank1 = [_]u8{2} ** 0x10000;
    var mem = Memory{};

    mem.mapRAM(0, 0x0000, &bank0);
    mem.mapRAM(1, 0x0000, &bank1);

    try expect(mem.r8(0x0000) == 1);
    try expect(mem.r8(0x8000) == 1);
    try expect(mem.r8(0xFFFF) == 1);
    mem.w8(0x0000, 42);
    mem.w8(0x8000, 42);
    mem.w8(0xFFFF, 42);
    try expect(mem.r8(0x0000) == 42);
    try expect(mem.r8(0x8000) == 42);
    try expect(mem.r8(0xFFFF) == 42);

    mem.unmapBank(0);
    try expect(mem.r8(0x0000) == 2);
    try expect(mem.r8(0x8000) == 2);
    try expect(mem.r8(0xFFFF) == 2);
    mem.w8(0x0000, 42);
    mem.w8(0x8000, 42);
    mem.w8(0xFFFF, 42);
    try expect(mem.r8(0x0000) == 42);
    try expect(mem.r8(0x8000) == 42);
    try expect(mem.r8(0xFFFF) == 42);

    mem.unmapBank(1);
    try expect(mem.r8(0x0000) == 0xFF);
    try expect(mem.r8(0x8000) == 0xFF);
    try expect(mem.r8(0xFFFF) == 0xFF);
    mem.w8(0x0000, 42);
    mem.w8(0x8000, 42);
    mem.w8(0xFFFF, 42);
    try expect(mem.r8(0x0000) == 0xFF);
    try expect(mem.r8(0x8000) == 0xFF);
    try expect(mem.r8(0xFFFF) == 0xFF);
}

test "unmap all" {
    var bank0 = [_]u8{0} ** 0x10000;
    var bank1 = [_]u8{1} ** 0x10000;
    var bank2 = [_]u8{2} ** 0x10000;
    var bank3 = [_]u8{3} ** 0x10000;
    var mem = Memory{};

    mem.mapRAM(0, 0x0000, &bank0);
    mem.mapRAM(1, 0x0000, &bank1);
    mem.mapRAM(2, 0x0000, &bank2);
    mem.mapRAM(3, 0x0000, &bank3);
    try expect(mem.r8(0x0000) == 0);
    try expect(mem.r8(0xFFFF) == 0);
    mem.w8(0x0000, 23);
    mem.w8(0xFFFF, 23);
    try expect(mem.r8(0x0000) == 23);
    try expect(mem.r8(0xFFFF) == 23);

    mem.unmapAll();
    try expect(mem.r8(0x0000) == 0xFF);
    try expect(mem.r8(0xFFFF) == 0xFF);
    mem.w8(0x0000, 23);
    mem.w8(0xFFFF, 23);
    try expect(mem.r8(0x0000) == 0xFF);
    try expect(mem.r8(0xFFFF) == 0xFF);
}

test "write bytes" {
    var ram = [_]u8{0} ** 0x10000;
    var mem = Memory{};
    mem.mapRAM(0, 0x0000, &ram);

    const bytes = [_]u8{23} ** 0x1000;
    mem.writeBytes(0x4000, &bytes);
    try expect(mem.r8(0x3FFF) == 0);
    try expect(mem.r8(0x4000) == 23);
    try expect(mem.r8(0x4FFF) == 23);
    try expect(mem.r8(0x5000) == 0);
}

test "write bytes wraparound" {
    var ram = [_]u8{0} ** 0x10000;
    var mem = Memory{};
    mem.mapRAM(0, 0x0000, &ram);

    const bytes = [_]u8{23} ** 0x1000;
    mem.writeBytes(0xF800, &bytes);
    try expect(mem.r8(0xF7FF) == 0);
    try expect(mem.r8(0xF800) == 23);
    try expect(mem.r8(0x07FF) == 23);
    try expect(mem.r8(0x0800) == 0);
}
