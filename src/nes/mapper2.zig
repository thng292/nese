const std = @import("std");
const mapperInterface = @import("mapper.zig");
const ROM = @import("ines.zig").ROM;

const Self = @This();

rom: *ROM,
start_addr: u16,
mirroring: mapperInterface.MirroringMode,
bank_select: u8,

pub fn init(rom: *ROM) Self {
    return .{
        .start_addr = if (rom.header.PRG_ROM_Size != 1) 0x8000 else 0xC000,
        .rom = rom,
        .mirroring = if (rom.header.mirroring) .Vertical else .Horizontal,
        .bank_select = 0,
    };
}

pub fn cpuRead(self: *Self, addr: u16) u8 {
    const index = addr - self.start_addr;
    if (index > 0x3FFF) {
        const short = self.rom.PRG_RomBanks;
        return short[short.len - 0x4000 + index - 0x4000];
    }
    return self.rom.PRG_RomBanks[index + @as(u32, self.bank_select) * 0x4000];
}

pub fn cpuWrite(self: *Self, addr: u16, data: u8) void {
    self.bank_select = data;
    _ = addr;
}

pub fn ppuRead(self: *Self, addr: u16) u8 {
    return self.rom.CHR_RomBanks[addr];
}

pub fn ppuWrite(self: *Self, addr: u16, data: u8) void {
    self.rom.CHR_RomBanks[addr] = data;
}

pub fn getMirroringMode(self: *Self) mapperInterface.MirroringMode {
    return self.mirroring;
}

pub fn getNMIScanline(self: *Self) u16 {
    _ = self;
    return 400;
}

pub fn toMapper(self: *Self) mapperInterface {
    return mapperInterface.toMapper(self);
}
