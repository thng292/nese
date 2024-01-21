const std = @import("std");
const Bus = @import("bus.zig").Bus;
const devInterfaceImport = @import("devInterface.zig");
const devInterface = devInterfaceImport.devInterface;
const toDevInterface = devInterfaceImport.toDevInterface;

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
    mapperNumLo: u4,
    fourScreenVram: bool,
    hasTrainer: bool,
    hasPersistentMem: bool,
    mirroring: bool,
    // Flag 7
    mapperNumHi: u4,
    version: u2,
    consoleFam: NESConsoleFamily,

    // Flag 8
    PRG_RAM_Size: u8,
    // Flag 9
    CHR_ROM_SizeMSB: u4,
    PRG_ROM_SizeMSB: u4,
    // Flag 10
    PRG_EEPROM_Size: u4,
    PRG_RAM_Size2: u4,
    // Flag 11
    CHR_NVRAM_Size: u4,
    CHR_RAM_Size: u4,
    // Flag 12
    _pad1: u6,
    timingMode: TimingMode,
    // Flag 13
    VS_HW_Type: u4,
    VS_PPU_Type: u4,
    // Flag 14
    micsRom: u8,
    defaultExpandsionDev: u8,

    pub fn getPRGSize(self: *const Header) u32 {
        if (self.version == @as(u2, 2)) {
            var res: u32 = 0;
            res = self.PRG_ROM_SizeMSB;
            res <<= 8;
            res |= self.PRG_ROM_Size;
            return res;
        } else {
            return @as(u32, @intCast(self.PRG_ROM_Size)) * 16 * 1024;
        }
    }

    pub fn getCHRSize(self: *const Header) u32 {
        if (self.version == @as(u2, 2)) {
            var res: u32 = 0;
            res = self.CHR_ROM_SizeMSB;
            res <<= 8;
            res |= self.CHR_ROM_Size;
            return res;
        } else {
            return @max(@as(u32, @intCast(self.CHR_ROM_Size)), 1) * 8 * 1024;
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
    trainer: []u8,
    PRG_RomBanks: []u8,
    CHR_RomBanks: []u8,
    misc: []u8,
    cartRam: []u8,
    allocator: std.mem.Allocator,

    pub const romError = error{
        FileCorrupted,
        FileNotNESRom,
    };

    const CartridgeRAMDev = struct {
        const Self = @This();
        const lower_bound = 0x6000;
        data: []u8,

        pub fn inRange(cram: *Self, addr: u16) bool {
            _ = cram;
            return lower_bound <= addr and addr <= 0x7FFF;
        }

        pub fn read(cram: *Self, addr: u16) u8 {
            return cram.data[addr - lower_bound];
        }

        pub fn write(cram: *Self, addr: u16, data: u8) void {
            cram.data[addr - lower_bound] = data;
        }
    };

    pub fn getCartridgeRamDev(self: *ROM) CartridgeRAMDev {
        return CartridgeRAMDev{ .data = self.cartRam };
    }

    const ProgramRomDev = struct {
        const Self = @This();
        data: []u8,
        lower_bound: u16 = 0x8000,

        pub fn inRange(pg: *Self, addr: u16) bool {
            return pg.lower_bound <= addr;
        }

        pub fn read(pg: *Self, addr: u16) u8 {
            return pg.data[addr - pg.lower_bound];
        }

        pub fn write(pg: *Self, addr: u16, data: u8) void {
            pg.data[addr - pg.lower_bound] = data;
        }
    };

    pub fn getProgramRomDev(self: *ROM) ProgramRomDev {
        return ProgramRomDev{
            .data = self.PRG_RomBanks,
            .lower_bound = if (self.header.PRG_ROM_Size == 1) 0xC000 else 0x8000,
        };
    }

    pub fn readFromFile(file: std.fs.File, allocator: std.mem.Allocator) !ROM {
        var self = ROM{
            .header = std.mem.zeroes(Header),
            .trainer = &[_]u8{},
            .PRG_RomBanks = &[_]u8{},
            .CHR_RomBanks = &[_]u8{},
            .misc = &[_]u8{},
            .cartRam = &[_]u8{},
            .allocator = allocator,
        };
        errdefer {
            self.deinit();
        }
        var buff = std.mem.zeroes([16]u8);
        var read = try file.read(&buff);
        if (read != 16) {
            std.debug.print("{}\n", .{read});
            return romError.FileCorrupted;
        }
        self.header = @bitCast(buff);
        if (self.header.name != 441664846) {
            return romError.FileNotNESRom;
        }

        if (self.header.hasTrainer) {
            self.trainer = try self.allocator.alloc(u8, 512);
            read = try file.read(self.trainer);
            if (read != 512) {
                std.debug.print("{}\n", .{read});
                return romError.FileCorrupted;
            }
        }

        self.PRG_RomBanks = try self.allocator.alloc(u8, self.header.getPRGSize());
        read = try file.read(self.PRG_RomBanks);
        if (read != self.header.getPRGSize()) {
            return romError.FileCorrupted;
        }

        self.CHR_RomBanks = try self.allocator.alloc(u8, self.header.getCHRSize());
        read = try file.read(self.CHR_RomBanks);
        if (read != self.header.getCHRSize()) {
            return romError.FileCorrupted;
        }

        const miscSize = (try file.getEndPos() - try file.getPos());
        if (miscSize > 0) {
            self.misc = try self.allocator.alloc(u8, miscSize);
            read = try file.read(self.misc);
            if (read != miscSize) {
                return romError.FileCorrupted;
            }
        }

        if (self.header.PRG_RAM_Size != 0) {
            self.cartRam = try self.allocator.alloc(u8, 8192);
        }
        return self;
    }

    pub fn deinit(self: *ROM) void {
        self.allocator.free(self.trainer);
        self.allocator.free(self.PRG_RomBanks);
        self.allocator.free(self.CHR_RomBanks);
        self.allocator.free(self.misc);
        self.allocator.free(self.cartRam);
    }
};
