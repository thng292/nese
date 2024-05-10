const std = @import("std");
const mapperInterface = @import("mapper.zig");
const ROM = @import("ines.zig").ROM;

const Self = @This();
const start_addr: u16 = 0x8000;
rom: *ROM,

cpu_bank_0: u8 = 0,
cpu_bank_1: u8 = 0,
cpu_bank_32k: u8 = 0,

ppu_bank_0: u8 = 0,
ppu_bank_1: u8 = 0,
ppu_bank_8k: u8 = 0,

shift_reg: u8 = 0,
write_count: u8 = 0,
control_reg: u8 = 0x1C,
// control_reg: ControlReg = @bitCast(@as(u8, 0x1C)),

const ControlReg = packed struct(u8) {
    mirroring: MirrorMode,
    PRG_bank_mode: PRG_bank_mode,
    ppu_switch_4kb: bool,
    _pad: u3,
};

pub fn init(rom: *ROM) Self {
    // std.debug.print("Control: {}\n", .{@as(ControlReg, @bitCast(@as(u8, 0x1C)))});
    // std.debug.print("Init: {}\n", .{rom.header.PRG_ROM_Size - 1});
    return .{
        .rom = rom,
        .cpu_bank_1 = rom.header.PRG_ROM_Size - 1,
    };
}

pub fn cpuRead(self: *Self, addr: u16) u8 {
    if (addr <= 0x7FFF) {
        if (addr - 0x6000 < self.rom.PRG_RamBanks.len) {
            return self.rom.PRG_RamBanks[addr - 0x6000];
        } else {
            return 0;
        }
    }

    if (self.control_reg & 0b1000 != 0) {
        // 16KB mode
        if (addr <= 0xBFFF) {
            return self.rom.PRG_RomBanks[
                self.cpu_bank_0 * BANK_16KB + addr - start_addr
            ];
        } else {
            return self.rom.PRG_RomBanks[
                self.cpu_bank_1 * BANK_16KB + addr - (start_addr + BANK_16KB)
            ];
        }
    }
    // 32KB mode
    return self.rom.PRG_RomBanks[
        self.cpu_bank_32k * BANK_32KB + addr - start_addr
    ];
}

pub fn cpuWrite(self: *Self, addr: u16, data: u8) void {
    if (addr < 0x8000) {
        if (addr - 0x6000 < self.rom.PRG_RamBanks.len) {
            self.rom.PRG_RamBanks[addr - 0x6000] = data;
        }
        return;
    }
    if (data & 0x80 != 0) {
        self.shift_reg = 0;
        self.write_count = 0;
        self.control_reg = data | 0x0C;
    } else {
        self.shift_reg >>= 1;
        self.shift_reg |= (data & 0b1) << 4;
        self.write_count += 1;

        if (self.write_count != 5) {
            return;
        }

        const target_register: u2 = @truncate((addr >> 13) & 0b11);
        switch (target_register) {
            0 => {
                self.control_reg = self.shift_reg & 0x1F;
            },
            1 => {
                if (self.control_reg & 0b10000 != 0) {
                    self.ppu_bank_0 = self.shift_reg & 0x1F;
                } else {
                    self.ppu_bank_8k = self.shift_reg & 0x1E;
                }
            },
            2 => {
                if (self.control_reg & 0b10000 != 0) {
                    self.ppu_bank_1 = self.shift_reg & 0x1F;
                }
            },
            3 => {
                const PRG_mode: u2 = @truncate(self.control_reg >> 2 & 0b11);
                switch (PRG_mode) {
                    0, 1 => {
                        self.cpu_bank_32k = (self.shift_reg & 0xE) >> 1;
                    },
                    2 => {
                        self.cpu_bank_0 = 0;
                        self.cpu_bank_1 = self.shift_reg & 0xF;
                    },
                    3 => {
                        self.cpu_bank_0 = self.shift_reg & 0xF;
                        self.cpu_bank_1 = self.rom.header.PRG_ROM_Size - 1;
                    },
                }
            },
        }

        // std.debug.print("self ptr: {*}\n", .{self});
        // std.debug.print("{b:0>8}\n", .{self.control_reg});
        // std.debug.print("ppu_bank_0: {}\n", .{self.ppu_bank_0});
        // std.debug.print("ppu_bank_1: {}\n", .{self.ppu_bank_1});
        // std.debug.print("ppu_bank_8k: {}\n", .{self.ppu_bank_8k});
        // std.debug.print("cpu_bank_0: {}\n", .{self.cpu_bank_0});
        // std.debug.print("cpu_bank_1: {}\n", .{self.cpu_bank_1});
        // std.debug.print("cpu_bank_32k: {}\n", .{self.cpu_bank_32k});
        // std.debug.print("\n", .{});
        self.write_count = 0;
        self.shift_reg = 0;
    }
}

pub fn ppuRead(self: *Self, addr: u16) u8 {
    if (self.rom.header.CHR_ROM_Size == 0) {
        return self.rom.CHR_RomBanks[addr];
    }
    if (self.control_reg & 0b10000 != 0) {
        if (addr < 0x1000) {
            return self.rom.CHR_RomBanks[self.ppu_bank_0 * BANK_4KB + addr];
        } else {
            return self.rom.CHR_RomBanks[self.ppu_bank_1 * BANK_4KB + addr - BANK_4KB];
        }
    } else {
        return self.rom.CHR_RomBanks[self.ppu_bank_8k * BANK_8KB + addr];
    }
}

pub fn ppuWrite(self: *Self, addr: u16, data: u8) void {
    self.rom.CHR_RomBanks[addr] = data;
}

pub fn getMirroringMode(self: *Self) mapperInterface.MirroringMode {
    const tmp: u2 = @truncate(self.control_reg & 0b11);
    return switch (tmp) {
        0 => .Vertical,
        1 => .Vertical,
        2 => .Vertical,
        3 => .Horizontal,
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

const BANK_4KB: u32 = 0x1000;
const BANK_8KB: u32 = BANK_4KB * 2;
const BANK_16KB: u32 = BANK_8KB * 2;
const BANK_32KB: u32 = BANK_16KB * 2;
