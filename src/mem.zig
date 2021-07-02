//------------------------------------------------------------------------------
//  mem.zig
//
//  A virtual memory system for 16-bit home computers with bank switching.
//------------------------------------------------------------------------------
const assert = @import("std").debug.assert;

const page_shift = 10;      // page size is 1 KB
const page_size = 1<<page_shift;
const page_mask = page_size - 1;
const addr_range = 1<<16;
const addr_mask = addr_range - 1;
const num_pages = addr_range / page_size;
const num_banks = 4;        // max number of memory bank layers

// dummy pages for unmapped reads and writes
const unmapped_page: [page_size]u8 = [_]u8{0xFF} ** page_size;
var junk_page: [page_size]u8 = [_]u8{0} ** page_size;

// an memory bank page with optional mappings to host memory
const BankPage = struct {
    read: ?[]const u8 = null,
    write: ?[] u8 = null,
};

// a CPU visible memory page with guaranteed mappings
const Page = struct {
    read: []const u8 = &unmapped_page,
    write: []u8 = &junk_page,
};

pub const Memory = struct {
    // the CPU visible memory pages resolved from the optionally mapped memory banks
    pages: [num_pages]Page = [_]Page{.{}} ** num_pages,
    // optionally mapped memory bank mapping to host memory
    banks: [num_banks][num_pages]BankPage = [_][num_pages]BankPage{[_]BankPage{.{}} ** num_pages} ** num_banks,

    // map a range of RAM
    pub fn mapRAM(self: *Memory, bank_index: usize, addr: u16, ram: []u8) void {
        // map both the read- and write-slice to host memory
        assert(ram.len <= addr_range);
        self.map(bank_index, addr, ram.len, ram, ram);
    }

    // map a range of ROM
    pub fn mapROM(self: *Memory, bank_index: usize, addr: u16, rom: []u8) void {
        assert(rom.len <= addr_range);
        self.map(bank_index, addr, rom.len, rom, null);
    }

    // internal memory mapping function for RAM, ROM and separate RW areas
    fn map(self: *Memory, bank_index: usize, addr: u16, size: usize, read: ?[]u8, write: ?[]u8) void {
        assert((addr & page_mask) == 0);    // start address must be at page boundary
        assert((size & page_mask) == 0);    // size must be multiple of page size
        assert((read != null) or (write != null));

        var offset: usize = 0;
        while (offset < size): (offset += page_size) {
            const page_index = ((addr + offset) & addr_mask) >> page_shift;
            const bank = &self.banks[bank_index][page_index];
            if (read) |r| {
                bank.read = r[offset .. (offset + page_size)];
            }
            else {
                bank.read = null;
            }
            if (write) |w| {
                bank.write = w[offset .. (offset + page_size)];
            }
            else {
                bank.write = null;
            }
            self.updatePageTable(offset / page_size);
        }
    }

    // helper function to update the CPU-visible page table for one memory page
    fn updatePageTable(self: *Memory, page_index: usize) void {
        // find highest priority bank page with valid mapping
        for (self.banks) |*bank| {
            if (bank[page_index].read) |_| {
                // highest priority mapped bank page found
                self.pages[page_index] = .{
                    .read = bank[page_index].read.?,
                    .write = bank[page_index].write orelse &junk_page,
                };
                break;
            }
        }
        else {
            // fallthrough: no mapped bank page found
            self.pages[page_index] = .{
                .read = &unmapped_page,
                .write = &junk_page,
            };
        }
    }
};


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
    for (mem.pages) |page, i| {
        if (i < 32) {
            try expect(&page.read[0] == &ram[i * page_size]);
            try expect(&page.write[0] == &ram[i * page_size]);
            try expect(&page.read[0] == &page.write[0]);
            try expect(page.read[0] == 23);
            try expect(page.read[1023] == 23);
            try expect(page.write[0] == 23);
            try expect(page.write[1023] == 23);
        }
        else {
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