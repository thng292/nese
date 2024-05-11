const std = @import("std");
const mapperInterface = @import("mapper.zig");
const ROM = @import("ines.zig").ROM;

const Self = @This();

rom: *ROM,
start_addr: u16,
bank_select: u8,
mirroring: Mirroring,

const Mirroring = enum(u1) {
    Vertical,
    Horizontal,
};

pub fn init(rom: *ROM) Self {
    return .{
        .start_addr = if (rom.header.PRG_ROM_Size != 1) 0x8000 else 0xC000,
        .rom = rom,
        .mirroring = if (rom.header.mirroring) .Vertical else .Horizontal,
        .bank_select = 0,
    };
}

pub fn cpuRead(self: *Self, addr: u16) u8 {
    if (addr < 0x8000) {
        return 0;
    }
    const index = addr - self.start_addr;
    if (index > 0x3FFF) {
        const short = self.rom.PRG_Rom;
        return short[short.len - 0x4000 + index - 0x4000];
    }
    return self.rom.PRG_Rom[index + @as(u32, self.bank_select) * 0x4000];
}

pub fn cpuWrite(self: *Self, addr: u16, data: u8) void {
    if (0x8000 <= addr) {
        self.bank_select = data;
    }
}

pub fn ppuRead(self: *Self, addr: u16) u8 {
    return self.rom.CHR_Rom[addr];
}

pub fn ppuWrite(self: *Self, addr: u16, data: u8) void {
    self.rom.CHR_Rom[addr] = data;
}

pub fn resolveNametableAddr(self: *Self, addr: u16) u16 {
    const ntaddr = addr - 0x2000;
    var nametable_num = ntaddr / 0x400;
    const ntindex = ntaddr % 0x400;
    const ntmap_h = [_]u8{ 0, 0, 1, 1 };
    const ntmap_v = [_]u8{ 0, 1, 0, 1 };
    switch (self.mirroring) {
        .Horizontal => nametable_num = ntmap_h[nametable_num],
        .Vertical => nametable_num = ntmap_v[nametable_num],
    }
    return nametable_num * 0x400 + ntindex;
}

pub fn shouldIrq(self: *Self) bool {
    _ = self;
    return false;
}

pub fn toMapper(self: *Self) mapperInterface {
    return mapperInterface.toMapper(self);
}
