const std = @import("std");
const mapperInterface = @import("../mapper.zig");
const ROM = @import("../ines.zig").ROM;

const Self = @This();
const start_addr: u16 = 0x8000;

rom: *ROM,
mirroring: Mirroring,
no_bank8kb: u8,

PRG_bank_offsets: [4]u32,
CHR_bank_offsets: [8]u32 = std.mem.zeroes([8]u32),
regs: [8]u8 = std.mem.zeroes([8]u8),

PRG_bank_mode: bool = false,
CHR_inversion: bool = false,
target_reg: u3 = 0,

irq_latch: u8 = 0,
irq_counter: u8 = 0,
irq_enable: bool = false,

const Mirroring = enum(u1) {
    Vertical,
    Horizontal,
};

pub fn init(rom: *ROM) Self {
    const no_bank8kb = rom.header.PRG_ROM_Size * 2;
    return .{
        .rom = rom,
        .mirroring = if (rom.header.mirroring) .Vertical else .Horizontal,
        .no_bank8kb = no_bank8kb,
        .PRG_bank_offsets = [4]u32{
            0 * BANK_8KB,
            1 * BANK_8KB,
            (no_bank8kb - 2) * BANK_8KB,
            (no_bank8kb - 1) * BANK_8KB,
        },
    };
}

pub fn cpuRead(self: *Self, addr: u16) u8 {
    if (addr < 0x8000) {
        return self.rom.PRG_Ram[addr - 0x6000];
    }
    const offset = addr - 0x8000;
    const PRG_Rom = self.rom.PRG_Rom;
    const bank = @divTrunc(offset, BANK_8KB);
    return PRG_Rom[self.PRG_bank_offsets[bank] + (offset % BANK_8KB)];
}

inline fn isEven(num: u64) bool {
    return num % 2 == 0;
}

pub fn cpuWrite(self: *Self, addr: u16, data: u8) void {
    if (addr < 0x8000) {
        self.rom.PRG_Ram[addr - 0x6000] = data;
    }
    switch (addr) {
        0x8000...0x9FFF => if (isEven(addr)) {
            self.target_reg = @truncate(data & 0b111);
            self.PRG_bank_mode = (data & 0x40) != 0;
            self.CHR_inversion = (data & 0x80) != 0;
        } else {
            self.regs[self.target_reg] = data;
            if (self.target_reg == 0 or self.target_reg == 1) {
                self.regs[self.target_reg] &= 0xFE;
            }
            self.updateOffsetTable();
        },
        0xA000...0xBFFF => if (isEven(addr)) {
            if (data & 1 == 0) {
                self.mirroring = .Vertical;
            } else {
                self.mirroring = .Horizontal;
            }
        } else {},
        0xC000...0xDFFF => if (isEven(addr)) {
            self.irq_latch = data;
        } else {
            self.irq_counter = self.irq_latch;
        },
        0xE000...0xFFFF => self.irq_enable = !isEven(addr),
        else => {},
    }
}

pub fn ppuRead(self: *Self, addr: u16) u8 {
    const CHR_Rom = self.rom.CHR_Rom;
    const bank = @divTrunc(addr, BANK_1KB);
    return CHR_Rom[self.CHR_bank_offsets[bank] + (addr % BANK_1KB)];
}

pub fn ppuWrite(self: *Self, addr: u16, data: u8) void {
    self.rom.CHR_Rom[addr] = data;
}

pub fn resolveNametableAddr(self: *Self, addr: u16) u16 {
    const ntaddr = addr & 0x0FFF;
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
    if (self.irq_counter == 0) {
        self.irq_counter = self.irq_latch;
    } else {
        self.irq_counter -= 1;
        if (self.irq_counter == 0 and self.irq_enable) {
            return true;
        }
    }
    return false;
}

inline fn updateOffsetTable(self: *Self) void {
    if (self.CHR_inversion) {
        self.CHR_bank_offsets[0] = self.regs[2] * BANK_1KB;
        self.CHR_bank_offsets[1] = self.regs[3] * BANK_1KB;
        self.CHR_bank_offsets[2] = self.regs[4] * BANK_1KB;
        self.CHR_bank_offsets[3] = self.regs[5] * BANK_1KB;
        self.CHR_bank_offsets[4] = (self.regs[0] & 0xFE) * BANK_1KB;
        self.CHR_bank_offsets[5] = (self.regs[0] + 1) * BANK_1KB;
        self.CHR_bank_offsets[6] = (self.regs[1] & 0xFE) * BANK_1KB;
        self.CHR_bank_offsets[7] = (self.regs[1] + 1) * BANK_1KB;
    } else {
        self.CHR_bank_offsets[0] = (self.regs[0] & 0xFE) * BANK_1KB;
        self.CHR_bank_offsets[1] = (self.regs[0] + 1) * BANK_1KB;
        self.CHR_bank_offsets[2] = (self.regs[1] & 0xFE) * BANK_1KB;
        self.CHR_bank_offsets[3] = (self.regs[1] + 1) * BANK_1KB;
        self.CHR_bank_offsets[4] = self.regs[2] * BANK_1KB;
        self.CHR_bank_offsets[5] = self.regs[3] * BANK_1KB;
        self.CHR_bank_offsets[6] = self.regs[4] * BANK_1KB;
        self.CHR_bank_offsets[7] = self.regs[5] * BANK_1KB;
    }

    if (self.PRG_bank_mode) {
        self.PRG_bank_offsets[0] = (self.no_bank8kb - 2) * BANK_8KB;
        self.PRG_bank_offsets[2] = (self.regs[6] & 0x3F) * BANK_8KB;
    } else {
        self.PRG_bank_offsets[0] = (self.regs[6] & 0x3F) * BANK_8KB;
        self.PRG_bank_offsets[2] = (self.no_bank8kb - 2) * BANK_8KB;
    }
    self.PRG_bank_offsets[1] = (self.regs[7] & 0x3F) * BANK_8KB;
    self.PRG_bank_offsets[3] = (self.no_bank8kb - 1) * BANK_8KB;
}

pub fn toMapper(self: *Self) mapperInterface {
    return mapperInterface.toMapper(self);
}

const BANK_1KB: u32 = 0x0400;
const BANK_2KB: u32 = BANK_1KB * 2;
const BANK_4KB: u32 = BANK_2KB * 2;
const BANK_8KB: u32 = BANK_4KB * 2;
const BANK_16KB: u32 = BANK_8KB * 2;
const BANK_32KB: u32 = BANK_16KB * 2;
