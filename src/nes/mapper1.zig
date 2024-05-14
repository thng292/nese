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

shift_reg: u8 = 0,
control: ControlReg = @bitCast(@as(u8, 0x1C)),

const ControlReg = packed struct(u8) {
    mirroring: Mirroring,
    PRG_bank_mode: PRG_bank_mode,
    ppu_switch_4kb: bool,
    _pad: u3,
};

pub fn init(rom: *ROM) Self {
    return .{
        .rom = rom,
        .cpu_bank_1 = rom.header.PRG_ROM_Size - 1,
    };
}

pub fn cpuRead(self: *Self, addr: u16) u8 {
    if (addr <= 0x7FFF) {
        return self.rom.PRG_Ram[addr - 0x6000];
    }

    if (self.control.PRG_bank_mode == .fix_first_bank //
    or self.control.PRG_bank_mode == .fix_last_bank) {
        // 16KB mode
        if (addr <= 0xBFFF) {
            return self.rom.PRG_Rom[
                self.cpu_bank_0 * BANK_16KB + addr - start_addr
            ];
        } else {
            return self.rom.PRG_Rom[
                self.cpu_bank_1 * BANK_16KB + addr - (start_addr + BANK_16KB)
            ];
        }
    }
    // 32KB mode
    return self.rom.PRG_Rom[
        self.cpu_bank_0 * BANK_32KB + (addr - start_addr)
    ];
}

pub fn cpuWrite(self: *Self, addr: u16, data: u8) void {
    if (addr < 0x8000) {
        self.rom.PRG_Ram[addr - 0x6000] = data;
        return;
    }
    if (data & 0x80 != 0) { // Reset
        self.shift_reg = 1;
        self.control.PRG_bank_mode = .fix_last_bank;
        return;
    }

    self.shift_reg <<= 1;
    self.shift_reg |= data & 0b1;

    if (self.shift_reg & 0b100000 == 0) {
        return;
    }

    self.shift_reg = @bitReverse(self.shift_reg) >> 3;
    defer self.shift_reg = 1;

    const target_register: u2 = @truncate((addr >> 13) & 0b11);
    switch (target_register) {
        0 => {
            self.control = @bitCast(self.shift_reg & 0x1F);
            // std.debug.print("Updated ctrl: {}\n", .{self.control});
        },
        1 => {
            if (self.control.ppu_switch_4kb) {
                self.ppu_bank_0 = self.shift_reg & 0x1F;
            } else {
                self.ppu_bank_0 = self.shift_reg & 0x1E;
            }
        },
        2 => {
            if (self.control.ppu_switch_4kb) {
                self.ppu_bank_1 = self.shift_reg & 0x1F;
            }
        },
        3 => {
            switch (self.control.PRG_bank_mode) {
                .switch32_0, .switch32_1 => {
                    self.cpu_bank_0 = (self.shift_reg & 0xE) >> 1;
                },
                .fix_first_bank => {
                    self.cpu_bank_0 = 0;
                    self.cpu_bank_1 = self.shift_reg & 0xF;
                },
                .fix_last_bank => {
                    self.cpu_bank_0 = self.shift_reg & 0xF;
                    self.cpu_bank_1 = self.rom.header.PRG_ROM_Size - 1;
                },
            }
        },
    }
}

pub fn ppuRead(self: *Self, addr: u16) u8 {
    if (self.rom.header.CHR_ROM_Size == 0) {
        return self.rom.CHR_Rom[addr];
    }
    if (self.control.ppu_switch_4kb) {
        if (addr < 0x1000) {
            return self.rom.CHR_Rom[self.ppu_bank_0 * BANK_4KB + addr];
        } else {
            return self.rom.CHR_Rom[self.ppu_bank_1 * BANK_4KB + addr - BANK_4KB];
        }
    } else {
        return self.rom.CHR_Rom[self.ppu_bank_0 * BANK_8KB + addr];
    }
}

pub fn ppuWrite(self: *Self, addr: u16, data: u8) void {
    self.rom.CHR_Rom[addr] = data;
}

pub fn resolveNametableAddr(self: *Self, addr: u16) u16 {
    const ntaddr = addr - 0x2000;
    var nametable_num = ntaddr / 0x400;
    const ntindex = ntaddr % 0x400;
    const ntmap_h = [_]u8{ 0, 0, 1, 1 };
    const ntmap_v = [_]u8{ 0, 1, 0, 1 };
    switch (self.control.mirroring) {
        .Single_lower => nametable_num = 0,
        .Single_upper => nametable_num = 1,
        .Horizontal => nametable_num = ntmap_h[nametable_num],
        .Vertical => nametable_num = ntmap_v[nametable_num],
    }
    return nametable_num * 0x400 + ntindex;
}

pub fn shouldIrq(self: *Self) bool {
    _ = self;
    return false;
}

pub fn toMapper(self: *Self) mapperInterface {
    return mapperInterface.toMapper(self);
}

const Mirroring = enum(u2) {
    Single_lower,
    Single_upper,
    Vertical,
    Horizontal,
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

test "ControlReg test 0" {
    const expect = std.testing.expect;
    const ctrl_reg: ControlReg = @bitCast(@as(u8, 0x1C));
    try expect(ctrl_reg._pad == 0);
    try expect(ctrl_reg.mirroring == .Single_lower);
    try expect(ctrl_reg.PRG_bank_mode == .fix_last_bank);
    try expect(ctrl_reg.ppu_switch_4kb == true);
}

test "ControlReg test 1" {
    const expect = std.testing.expect;
    const ctrl_reg: ControlReg = @bitCast(@as(u8, 0x1C));
    try expect(ctrl_reg._pad == 0);
    try expect(@intFromEnum(ctrl_reg.mirroring) == 0);
    try expect(@intFromEnum(ctrl_reg.PRG_bank_mode) == 0b11);
    try expect(ctrl_reg.ppu_switch_4kb == true);
}
