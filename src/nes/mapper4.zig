const std = @import("std");
const mapperInterface = @import("mapper.zig");
const ROM = @import("ines.zig").ROM;

const Self = @This();

rom: *ROM,
start_addr: u16,
mirroring: mapperInterface.MirroringMode,

pub fn init(rom: *ROM) Self {
    return .{
        .start_addr = if (rom.header.PRG_ROM_Size != 1) 0x8000 else 0xC000,
        .rom = rom,
        .mirroring = if (rom.header.mirroring) .Vertical else .Horizontal,
    };
}

pub fn cpuRead(self: *Self, addr: u16) u8 {
    // if (0x8000 <= addr) {
    //     return self.rom.PRG_RomBanks[addr - self.start_addr];
    // }
    // return 0;
    return switch (addr) {
        0x6000...0x7FFF => self.rom.PRG_RamBanks[addr - 0x6000],

        else => 0,
    };
}

pub fn cpuWrite(self: *Self, addr: u16, data: u8) void {
    _ = data;
    _ = addr;
    _ = self;
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
