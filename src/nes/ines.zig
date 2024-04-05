const std = @import("std");
const Bus = @import("bus.zig").Bus;

pub const NESConsoleFamily = enum(u2) { NES, VS, PlayChoice10, Extended };

pub const TimingMode = enum(u2) {
    RP2C02,
    RP2C07,
    Multiple_region,
    UA6538,
};

pub const Header = packed struct(u128) {
    name: u32,
    PRG_ROM_Size: u8,
    CHR_ROM_Size: u8,
    // Flag 6
    mirroring: bool,
    hasPersistentMem: bool,
    hasTrainer: bool,
    fourScreenVram: bool,
    mapperNumLo: u4,

    // Flag 7
    consoleFam: NESConsoleFamily,
    version: u2,
    mapperNumHi: u4,

    // Flag 8
    PRG_RAM_Size: u8,

    __unused09: u8,
    __unused10: u8,
    __unused11: u8,
    __unused12: u8,
    __unused13: u8,
    __unused14: u8,
    __unused15: u8,

    pub fn getPRGROMSize(self: *const Header) u32 {
        if (self.version == @as(u2, 2)) {
            var res: u32 = 0;
            res = self.PRG_ROM_SizeMSB;
            res <<= 8;
            res |= self.PRG_ROM_Size;
            return res;
        } else {
            return @as(u32, self.PRG_ROM_Size) * 16 * 1024;
        }
    }

    pub fn getCHRROMSize(self: *const Header) u32 {
        if (self.version == @as(u2, 2)) {
            var res: u32 = 0;
            res = self.CHR_ROM_SizeMSB;
            res <<= 8;
            res |= self.CHR_ROM_Size;
            return res;
        } else {
            return @as(u32, self.CHR_ROM_Size) * 8 * 1024;
        }
    }

    pub fn getMapperID(self: *const Header) u8 {
        var res: u8 = self.mapperNumHi;
        res <<= 4;
        res |= self.mapperNumLo;
        return res;
    }
};

pub const ROM = struct {
    header: Header,
    PRG_RomBanks: []u8,
    PRG_RamBanks: []u8,
    CHR_RomBanks: []u8,
    allocator: std.mem.Allocator,

    pub const romError = error{
        FileCorrupted,
        FileNotNESRom,
    };

    pub fn readFromFile(file: std.fs.File, allocator: std.mem.Allocator) !ROM {
        var self = ROM{
            .header = std.mem.zeroes(Header),
            .PRG_RomBanks = undefined,
            .PRG_RamBanks = undefined,
            .CHR_RomBanks = undefined,
            .allocator = allocator,
        };
        var buff = std.mem.zeroes([16]u8);
        var read = try file.read(&buff);
        if (read != 16) {
            debug(@src());
            return romError.FileCorrupted;
        }
        self.header = @bitCast(buff);
        if (self.header.name != 441664846) {
            return romError.FileNotNESRom;
        }

        self.PRG_RamBanks = try self.allocator.alloc(u8, self.header.PRG_RAM_Size);
        errdefer {
            self.allocator.free(self.PRG_RamBanks);
        }

        self.PRG_RomBanks = try self.allocator.alloc(u8, self.header.getPRGROMSize());
        read = try file.read(self.PRG_RomBanks);
        if (read != self.header.getPRGROMSize()) {
            debug(@src());
            return romError.FileCorrupted;
        }
        errdefer {
            self.allocator.free(self.PRG_RomBanks);
        }

        const CHR_ROM_size = self.header.getCHRROMSize();
        read = 0;
        if (CHR_ROM_size == 0) {
            self.CHR_RomBanks = try self.allocator.alloc(u8, 0x2000);
        } else {
            self.CHR_RomBanks = try self.allocator.alloc(u8, CHR_ROM_size);
            read = try file.read(self.CHR_RomBanks);
        }
        if (read != CHR_ROM_size) {
            debug(@src());
            return romError.FileCorrupted;
        }
        errdefer {
            self.allocator.free(self.CHR_RomBanks);
        }

        return self;
    }

    pub fn deinit(self: *ROM) void {
        self.allocator.free(self.PRG_RomBanks);
        self.allocator.free(self.PRG_RamBanks);
        self.allocator.free(self.CHR_RomBanks);
    }
};

inline fn debug(src: std.builtin.SourceLocation) void {
    if (comptime @import("builtin").mode == .Debug) {
        std.debug.print("{s}: {}, {}\n", .{ src.file, src.line, src.column });
    }
}
