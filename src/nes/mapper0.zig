const std = @import("std");
const mapperInterface = @import("mapper.zig");
const ROM = @import("ines.zig").ROM;

const Self = @This();

prg_rom: []u8,
startPC: u16,
mirroring: mapperInterface.MirroringMode,

pub fn init(rom: *ROM) Self {
    var res = std.mem.zeroes(Self);
    res.startPC = if (rom.header.PRG_ROM_Size != 1) 0x8000 else 0xC000;
    res.prg_rom = rom.PRG_RomBanks;
    res.mirroring = if (rom.header.mirroring) .Vertical else .Horizontal;
    return res;
}

pub fn mapperHandle(self: *Self, addr: u16) bool {
    return self.startPC <= addr;
}

pub fn cpuRead(self: *Self, addr: u16) u8 {
    return self.prg_rom[addr - self.startPC];
}

pub fn cpuWrite(self: *Self, addr: u16, data: u8) void {
    _ = data;
    _ = addr;
    _ = self;
}

pub fn ppuDecode(self: *Self, addr: u16) u16 {
    _ = self;
    return addr;
}

pub fn getMirroringMode(self: *Self) mapperInterface.MirroringMode {
    return self.mirroring;
}

pub fn getNMIScanline(self: *Self) u16 {
    _ = self;
    return 400;
}
