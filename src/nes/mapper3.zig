const std = @import("std");
const mapperInterface = @import("mapper.zig");
const ROM = @import("ines.zig").ROM;

const Self = @This();

rom: *ROM,
start_addr: u16,
chr_bank_select: u8,
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
        .chr_bank_select = 0,
    };
}

pub fn cpuRead(self: *Self, addr: u16) u8 {
    if (0x8000 <= addr) {
        return self.rom.PRG_Rom[addr - self.start_addr];
    }
    return 0;
}

pub fn cpuWrite(self: *Self, addr: u16, data: u8) void {
    if (0x8000 <= addr) {
        self.chr_bank_select = data;
    }
}

pub fn ppuRead(self: *Self, addr: u16) u8 {
    return self.rom.CHR_Rom[addr + @as(u16, self.chr_bank_select) * 0x2000];
}

pub fn ppuWrite(self: *Self, addr: u16, data: u8) void {
    _ = self;
    _ = addr;
    _ = data;
    // self.rom.CHR_Rom[addr] = data;
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
