const std = @import("std");
const mapperInterface = @import("mapper.zig");
const ROM = @import("ines.zig").ROM;

const Self = @This();
const BANK_16KB: u32 = 0x4000;
const BANK_4KB: u32 = 0x1000;
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
// control_reg: u8 = 0x1C,
control_reg: ControlReg = @bitCast(@as(u8, 0x1C)),

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

    const is32k_mode = self.control_reg.PRG_bank_mode == .switch32_0 //
    or self.control_reg.PRG_bank_mode == .switch32_1;

    if (is32k_mode) {
        return self.rom.PRG_RomBanks[
            addr - start_addr + self.cpu_bank_32k * BANK_16KB * 2
        ];
    }
    return switch (addr) {
        0x8000...0xBFFF => self.rom.PRG_RomBanks[
            addr - 0x8000 + self.cpu_bank_0 * BANK_16KB
        ],
        0xC000...0xFFFF => self.rom.PRG_RomBanks[
            addr - 0xC000 + self.cpu_bank_1 * BANK_16KB
        ],
        else => 0,
    };
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
        const tmp: u8 = @bitCast(self.control_reg);
        self.control_reg = @bitCast(tmp | 0x0C);
    } else {
        self.shift_reg >>= 1;
        self.shift_reg |= (data & 0b1) << 4;
        self.write_count += 1;

        if (self.write_count != 5) {
            return;
        }
        switch (addr & 0xF000) {
            0x8000, 0x9000 => {
                self.control_reg = @bitCast(self.shift_reg & 0x1F);
                std.debug.print("Updated: {}\n", .{self.control_reg});
            },
            0xA000, 0xB000 => {
                if (self.control_reg.ppu_switch_4kb) {
                    self.ppu_bank_0 = self.shift_reg & 0x1F;
                } else {
                    self.ppu_bank_8k = self.shift_reg & 0x1E;
                }
            },
            0xC000, 0xD000 => {
                if (self.control_reg.ppu_switch_4kb) {
                    self.ppu_bank_1 = self.shift_reg & 0x1F;
                }
            },
            0xE000, 0xF000 => {
                if (self.control_reg.PRG_bank_mode == .fix_first_bank) {
                    self.cpu_bank_0 = 0;
                    self.cpu_bank_1 = self.shift_reg & 0xF;
                } else if (self.control_reg.PRG_bank_mode == .fix_last_bank) {
                    self.cpu_bank_0 = 0;
                    self.cpu_bank_1 = self.rom.header.PRG_ROM_Size - 1;
                } else {
                    self.cpu_bank_32k = (self.shift_reg & 0xE) >> 1;
                }
            },
            else => {},
        }

        // std.debug.print("{}\n", .{self.control_reg});
        // std.debug.print("ppu_bank_0: {}\n", .{self.ppu_bank_0});
        // std.debug.print("ppu_bank_1: {}\n", .{self.ppu_bank_1});
        // std.debug.print("cpu_bank_0: {}\n", .{self.cpu_bank_0});
        // std.debug.print("cpu_bank_1: {}\n", .{self.cpu_bank_1});
        self.write_count = 0;
        self.shift_reg = 0;
    }
}

pub fn ppuRead(self: *Self, addr: u16) u8 {
    if (self.control_reg.ppu_switch_4kb) {
        return switch (addr) {
            0x0000...0x0FFF => self.rom.CHR_RomBanks[
                addr + self.ppu_bank_0 * BANK_4KB
            ],
            0x1000...0x1FFF => self.rom.CHR_RomBanks[
                addr + self.ppu_bank_1 * BANK_4KB
            ],
            else => 0,
        };
    }
    return self.rom.CHR_RomBanks[
        addr + self.ppu_bank_8k * BANK_4KB * 2
    ];
}

pub fn ppuWrite(self: *Self, addr: u16, data: u8) void {
    if (self.control_reg.ppu_switch_4kb) {
        if (addr < 0x1000) {
            self.rom.CHR_RomBanks[addr + self.ppu_bank_0 * BANK_4KB] = data;
        } else {
            self.rom.CHR_RomBanks[addr + self.ppu_bank_0 * BANK_4KB] = data;
        }
    } else {
        self.rom.CHR_RomBanks[addr + self.ppu_bank_8k * BANK_4KB * 2] = data;
    }
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
