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
        return @as(u32, self.PRG_ROM_Size) * BANK_16KB;
    }

    pub fn getCHRROMSize(self: *const Header) u32 {
        return @as(u32, self.CHR_ROM_Size) * BANK_8KB;
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
    PRG_Rom: []u8,
    PRG_Ram: []u8,
    CHR_Rom: []u8,

    pub const romError = error{
        FileCorrupted,
        FileNotNESRom,
    };

    pub fn readFromFile(file: std.fs.File, allocator: std.mem.Allocator) !ROM {
        var self = ROM{
            .header = std.mem.zeroes(Header),
            .PRG_Rom = undefined,
            .PRG_Ram = undefined,
            .CHR_Rom = undefined,
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

        self.PRG_Rom = try allocator.alloc(u8, self.header.getPRGROMSize());
        read = try file.read(self.PRG_Rom);
        if (read != self.header.getPRGROMSize()) {
            debug(@src());
            return romError.FileCorrupted;
        }
        errdefer {
            allocator.free(self.PRG_Rom);
        }

        self.PRG_Ram = try allocator.alloc(
            u8,
            if (self.header.PRG_RAM_Size != 0) self.header.PRG_RAM_Size * BANK_8KB else BANK_32KB,
        );
        errdefer {
            allocator.free(self.PRG_Ram);
        }
        const hashed = jenkinsHash(self.PRG_Rom);
        const save_file_path = try std.fmt.allocPrint(
            allocator,
            save_path ++ "{X:0>8}.bin",
            .{hashed},
        );
        defer allocator.free(save_file_path);
        if (std.fs.cwd().openFile(save_file_path, .{})) |ff| {
            _ = try ff.readAll(self.PRG_Ram);
            ff.close();
        } else |_| {}

        const CHR_ROM_size = self.header.getCHRROMSize();
        read = 0;
        if (CHR_ROM_size == 0) {
            self.CHR_Rom = try allocator.alloc(u8, 0x2000);
        } else {
            self.CHR_Rom = try allocator.alloc(u8, CHR_ROM_size);
            read = try file.read(self.CHR_Rom);
        }
        if (read != CHR_ROM_size) {
            debug(@src());
            return romError.FileCorrupted;
        }
        errdefer {
            allocator.free(self.CHR_Rom);
        }

        return self;
    }

    pub fn deinit(self: *ROM, allocator: std.mem.Allocator) void {
        if (self.header.hasPersistentMem) save_fail: {
            // Dump the ram
            const hashed = jenkinsHash(self.PRG_Rom);
            const save_file_name = std.fmt.allocPrint(
                allocator,
                save_path ++ "{X:0>8}.bin",
                .{hashed},
            ) catch save_path ++ "last_save.bin";
            const cwd = std.fs.cwd();
            cwd.makeDir("saves") catch {};
            const save_file = cwd.createFile(save_file_name, .{}) catch break :save_fail;
            defer save_file.close();
            save_file.writeAll(self.PRG_Ram) catch break :save_fail;
        }

        allocator.free(self.PRG_Rom);
        allocator.free(self.PRG_Ram);
        allocator.free(self.CHR_Rom);
    }
};

inline fn debug(src: std.builtin.SourceLocation) void {
    if (comptime @import("builtin").mode == .Debug) {
        std.debug.print("{s}: {}, {}\n", .{ src.file, src.line, src.column });
    }
}

const BANK_4KB: u32 = 0x1000;
const BANK_8KB: u32 = BANK_4KB * 2;
const BANK_16KB: u32 = BANK_8KB * 2;
const BANK_32KB: u32 = BANK_16KB * 2;

const save_path = "saves/";

pub fn jenkinsHash(in: []const u8) u32 {
    var hash: u32 = 0;
    for (in) |byte| {
        hash +%= byte;
        hash +%= hash << 10;
        hash ^= hash >> 6;
    }

    hash +%= hash << 3;
    hash ^= hash >> 11;
    hash +%= hash << 15;
    return hash;
}
