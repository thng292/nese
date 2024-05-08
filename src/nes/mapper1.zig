const std = @import("std");
const mapperInterface = @import("mapper.zig");
const ROM = @import("ines.zig").ROM;

const Self = @This();
const CPU_BANK_SIZE: u32 = 0x4000;
const PPU_BANK_SIZE: u32 = 0x1000;

rom: *ROM,
start_addr: u16,
mirroring: mapperInterface.MirroringMode,
cpu_bank_select_0: u8 = 0,
cpu_bank_select_1: u8,
ppu_bank_select_0: u8 = 0,
ppu_bank_select_1: u8 = 0,
shift_reg: u8 = 0,
control_reg: ControlReg = std.mem.zeroes(ControlReg),

const ControlReg = packed struct(u8) {
    mirroring: MirrorMode,
    PRG_bank_mode: PRG_bank_mode,
    ppu_switch_4kb: bool,
    _pad: u3,
};

pub fn init(rom: *ROM) Self {
    return .{
        .start_addr = if (rom.header.PRG_ROM_Size != 1) 0x8000 else 0xC000,
        .rom = rom,
        .mirroring = if (rom.header.mirroring) .Vertical else .Horizontal,
        .cpu_bank_select_1 = @truncate(@divTrunc(rom.header.PRG_ROM_Size, CPU_BANK_SIZE)),
    };
}

pub fn cpuRead(self: *Self, addr: u16) u8 {
    const is32k_mode = self.control_reg.PRG_bank_mode == .switch32_0 or self.control_reg.PRG_bank_mode == .switch32_1;
    if (0x6000 <= addr and addr <= 0x7FFF) {
        if (addr - 0x6000 < self.rom.PRG_RamBanks.len) {
            return self.rom.PRG_RamBanks[addr - 0x6000];
        } else {
            return 0;
        }
    }
    if (is32k_mode) {
        return self.rom.PRG_RomBanks[addr - self.start_addr + self.cpu_bank_select_0 * CPU_BANK_SIZE * 2];
    }
    return switch (addr) {
        0x8000...0xBFFF => {
            if (self.control_reg.PRG_bank_mode == .fix_first_bank) {
                return self.rom.PRG_RomBanks[addr - 0x8000];
            } else {
                return self.rom.PRG_RomBanks[addr - self.start_addr + self.cpu_bank_select_0 * CPU_BANK_SIZE];
            }
        },
        0xC000...0xFFFF => {
            if (self.control_reg.PRG_bank_mode == .fix_last_bank) {
                return self.rom.PRG_RomBanks[
                    addr - self.start_addr + self.cpu_bank_select_1 * CPU_BANK_SIZE
                ];
            } else {
                return self.rom.PRG_RomBanks[
                    addr - self.start_addr + self.cpu_bank_select_0 * CPU_BANK_SIZE
                ];
            }
        },
        else => 0,
    };
}

pub fn cpuWrite(self: *Self, addr: u16, data: u8) void {
    if (addr < 0x8000) {
        return;
    }
    if (data & 0x80 != 0) {
        self.shift_reg = 1;
    } else {
        self.shift_reg <<= 1;
        self.shift_reg |= data & 0b1;

        if (self.shift_reg & 0b100000 != 0) {
            switch (addr & 0xF000) {
                0x8000, 0x9000 => self.control_reg = @bitCast(self.shift_reg),
                0xA000, 0xB000 => self.ppu_bank_select_0 = self.shift_reg & 0x1F,
                0xC000, 0xD000 => self.ppu_bank_select_1 = self.shift_reg & 0x1F,
                0xE000, 0xF000 => self.cpu_bank_select_0 = self.shift_reg & 0xF,
                else => {},
            }
            self.shift_reg = 1;
        }
    }
}

pub fn ppuRead(self: *Self, addr: u16) u8 {
    if (self.control_reg.ppu_switch_4kb) {
        return switch (addr) {
            0x0000...0x0FFF => self.rom.CHR_RomBanks[addr + self.ppu_bank_select_0 * PPU_BANK_SIZE],
            0x1000...0x1FFF => self.rom.CHR_RomBanks[addr + self.ppu_bank_select_1 * PPU_BANK_SIZE],
            else => 0,
        };
    }
    return self.rom.CHR_RomBanks[addr + self.ppu_bank_select_0 * PPU_BANK_SIZE * 2];
}

pub fn ppuWrite(self: *Self, addr: u16, data: u8) void {
    self.rom.CHR_RomBanks[addr] = data;
}

pub fn getMirroringMode(self: *Self) mapperInterface.MirroringMode {
    return switch (self.control_reg.mirroring) {
        .lower_bank => .Vertical,
        .upper_bank => .Vertical,
        .vertical => .Vertical,
        .horizontal => .Horizontal,
    };
}

pub fn getNMIScanline(self: *Self) u16 {
    _ = self;
    return 400;
}

pub fn toMapper(self: *Self) mapperInterface {
    return mapperInterface.toMapper(self);
}

const MirrorMode = enum(u2) {
    lower_bank = 0,
    upper_bank = 1,
    vertical = 2,
    horizontal = 3,
};

const PRG_bank_mode = enum(u2) {
    switch32_0 = 0,
    switch32_1 = 1,
    fix_first_bank = 2,
    fix_last_bank = 3,
};
