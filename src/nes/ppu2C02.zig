const std = @import("std");
const sdl = @import("zsdl");
const Mapper = @import("mapper.zig");
const Rom = @import("ines.zig").ROM;

const PPU = @This();
mapper: Mapper,
mirroring: Mapper.MirroringMode = .Vertical,

ctrl: PPUCTRL = std.mem.zeroes(PPUCTRL),
mask: PPUMASK = std.mem.zeroes(PPUMASK),
status: PPUSTATUS = std.mem.zeroes(PPUSTATUS),
nmiSend: bool = false,

CHR_ROM: []u8,
nametable: [2048]u8 = undefined,
oam: [256]u8 = undefined,
draw_list: [8]ToBeDrawn = undefined,
spritePalette: [16]u8 = undefined,
imagePalette: [16]u8 = undefined,

data: u8 = 0,
addr_latch: bool = false,
data_buff: u8 = 0,
oam_addr: u8 = 0,

scanline: i16 = 0,
cycle: i16 = 0,
vreg: VRamAddr = std.mem.zeroes(VRamAddr),
treg: VRamAddr = std.mem.zeroes(VRamAddr),
fine_x: u3 = 0,

texture_pixel_count: u64 = 0,

bg_shifter_pattern_lo: u16 = 0,
bg_shifter_pattern_hi: u16 = 0,
bg_shifter_attrib_lo: u16 = 0,
bg_shifter_attrib_hi: u16 = 0,
bg_next_title_id: u8 = 0,
bg_next_title_lsb: u8 = 0,
bg_next_title_msb: u8 = 0,
bg_next_title_attrib: u8 = 0,

pub fn init(mapper: Mapper, rom: *Rom) !PPU {
    return PPU{
        .mapper = mapper,
        .CHR_ROM = rom.CHR_RomBanks,
    };
}

pub fn clock(self: *PPU, texture_data: [*]u8) !void {
    if (self.scanline >= -1 and self.scanline < 240) {
        if (self.scanline == 0 and self.cycle == 0) {
            self.cycle = 1;
            self.mirroring = self.mapper.getMirroringMode();
            self.texture_pixel_count = 0;
        }

        if (self.scanline == -1 and self.cycle == 1) {
            self.status = std.mem.zeroes(PPUSTATUS);
        }

        if ((self.cycle >= 2 and self.cycle < 258) //
        or (self.cycle >= 321 and self.cycle < 338)) {
            self.UpdateShifter();
            if (@mod(self.cycle - 1, 8) == 7) {
                self.LoadBGShifter();
                const vreg: u16 = @bitCast(self.vreg);
                self.bg_next_title_id = self.internalRead(0x2000 | (vreg & 0x0FFF));

                self.bg_next_title_attrib = self.internalRead(0x23C0 //
                | @as(u16, self.vreg.nametable_y) << 11 //
                | @as(u16, self.vreg.nametable_x) << 10 //
                | @as(u6, self.vreg.coarse_y >> 2) << 3 //
                | self.vreg.coarse_x >> 2);
                if (self.vreg.coarse_y & 0x02 != 0) {
                    self.bg_next_title_attrib >>= 4;
                }
                if (self.vreg.coarse_x & 0x02 != 0) {
                    self.bg_next_title_attrib >>= 2;
                }
                self.bg_next_title_attrib &= 0b11;

                const tmp = @as(u16, self.bg_next_title_id) * 16 + @as(u16, self.ctrl.BGPatternTableAddr) * 0x1000;
                self.bg_next_title_lsb = self.internalRead(tmp + self.vreg.fine_y);
                self.bg_next_title_msb = self.internalRead(tmp + self.vreg.fine_y + 8);

                self.IncX();
            }
        }

        if (self.cycle == 256) {
            self.IncY();
            self.LoadBGShifter();
            if (self.mask.ShowBG or self.mask.ShowSprite) {
                self.vreg.coarse_x = self.treg.coarse_x;
                self.vreg.nametable_x = self.treg.nametable_x;
            }
        }

        if (self.cycle == 338 or self.cycle == 340) {
            const vreg: u16 = @bitCast(self.vreg);
            self.bg_next_title_id = self.internalRead(0x2000 | (vreg & 0x0FFF));
        }

        if (self.scanline == -1 and self.cycle >= 280 and self.cycle < 305) {
            if (self.mask.ShowBG or self.mask.ShowSprite) {
                self.vreg.fine_y = self.treg.fine_y;
                self.vreg.coarse_y = self.treg.coarse_y;
                self.vreg.nametable_y = self.treg.nametable_y;
            }
        }
    }

    // if (self.scanline == 240) {}

    // if (self.scanline >= 241 and self.scanline < 261) {
    if (self.scanline == 241 and self.cycle == 1) {
        self.status.VBlank = true;
        self.nmiSend = self.ctrl.NMIEnable;
    }
    // }

    // Draw
    var sprite_behind_bg = false;
    var color_out_sprite: u8 = 0;
    var color_out_bg: u8 = 0;
    if (self.scanline < 240 and self.cycle < 256) {
        if (self.mask.ShowBG and (self.cycle >= 8 or self.mask.ShowBGInLM)) {
            var pixel: u4 = 0;
            const bit_mux: u16 = @as(u16, 0x8000) >> self.fine_x;
            if (self.bg_shifter_pattern_lo & bit_mux != 0) {
                pixel |= 0b0001;
            }
            if (self.bg_shifter_pattern_hi & bit_mux != 0) {
                pixel |= 0b0010;
            }
            if (self.bg_shifter_attrib_lo & bit_mux != 0) {
                pixel |= 0b0100;
            }
            if (self.bg_shifter_attrib_hi & bit_mux != 0) {
                pixel |= 0b1000;
            }
            color_out_bg = pixel;
        }

        if (self.cycle == 0) {
            self.spriteEvaluate();
        }

        if (self.mask.ShowSprite) {
            for (&self.draw_list) |*val| {
                if (val.x != 0) {
                    val.x -= 1;
                    if (val.x == 0) {
                        if (val.attribute.drawing == false) {
                            val.x = 7;
                        }
                        val.attribute.drawing = !val.attribute.drawing;
                    }
                }
            }
            if (self.mask.ShowSpriteInLM or self.cycle >= 8) {
                for (&self.draw_list) |*val| {
                    if (val.attribute.drawing) {
                        var pixel: u8 = val.attribute.palette;
                        pixel <<= 2;
                        const hi = val.shifter_hi >> 7;
                        const lo = (val.shifter_lo >> 7) << 1;
                        pixel |= hi;
                        pixel |= lo;
                        color_out_sprite = pixel;
                        sprite_behind_bg = val.attribute.behindBG;
                        val.shifter_hi <<= 1;
                        val.shifter_lo <<= 1;
                        break;
                    }
                }
            }
        }

        // _ = texture_data;
        // const color_out = if (sprite_top) color_out_sprite else color_out_bg;
        const color_out = colors[self.imagePalette[color_out_bg]];
        texture_data[self.texture_pixel_count + 3] = color_out.r;
        texture_data[self.texture_pixel_count + 2] = color_out.g;
        texture_data[self.texture_pixel_count + 1] = color_out.b;
        texture_data[self.texture_pixel_count + 0] = color_out.a;
        self.texture_pixel_count += 4;
    }

    self.cycle += 1;
    if (self.cycle >= 341) {
        self.cycle = 0;
        self.scanline += 1;
        if (self.scanline >= 261) {
            self.scanline = -1;
        }
    }
}

inline fn IncX(self: *PPU) void {
    if (!self.mask.ShowBG and !self.mask.ShowSprite) {
        return;
    }

    if (self.vreg.coarse_x == 31) {
        self.vreg.coarse_x = 0;
        self.vreg.nametable_x = ~self.vreg.nametable_x;
    } else {
        self.vreg.coarse_x += 1;
    }
}

inline fn IncY(self: *PPU) void {
    if (!self.mask.ShowBG and !self.mask.ShowSprite) {
        return;
    }

    if (self.vreg.fine_y < 7) {
        self.vreg.fine_y += 1;
    } else {
        self.vreg.fine_y = 0;
        if (self.vreg.coarse_y == 29) {
            self.vreg.coarse_y = 0;
            self.vreg.nametable_y = ~self.vreg.nametable_y;
        } else {
            self.vreg.coarse_y +%= 1;
        }
    }
}

inline fn LoadBGShifter(self: *PPU) void {
    self.bg_shifter_pattern_lo = (self.bg_shifter_pattern_lo & 0xFF00) | self.bg_next_title_lsb;
    self.bg_shifter_pattern_hi = (self.bg_shifter_pattern_hi & 0xFF00) | self.bg_next_title_msb;
    const tmp: u16 = if (self.bg_next_title_attrib & 0b01 != 0) 0xFF else 0x00;
    self.bg_shifter_attrib_lo = (self.bg_shifter_attrib_lo & 0xFF00) | tmp;
    const tmp2: u16 = if (self.bg_next_title_attrib & 0b10 != 0) 0xFF else 0x00;
    self.bg_shifter_attrib_hi = (self.bg_shifter_attrib_hi & 0xFF00) | tmp2;
}

inline fn UpdateShifter(self: *PPU) void {
    if (self.mask.ShowBG) {
        self.bg_shifter_pattern_lo <<= 1;
        self.bg_shifter_pattern_hi <<= 1;
        self.bg_shifter_attrib_lo <<= 1;
        self.bg_shifter_attrib_hi <<= 1;
    }
}

fn spriteEvaluate(self: *PPU) void {
    var i: u16 = 0;
    var tail: u8 = 0;
    const spriteHeight: u8 = if (self.ctrl.height16) 16 else 8;
    while (i < 256 and tail < 8) : (i += 4) {
        const difference = self.scanline - self.oam[i];
        if (0 <= difference and difference < spriteHeight) {
            const offset_top_: i8 = @truncate(self.scanline - self.oam[i]);
            const offset_top: u8 = @bitCast(offset_top_);
            const title_id: u16 = self.oam[i + 1];
            self.draw_list[tail].attribute = @bitCast(self.oam[i + 2]);

            var addr: u16 = 0;
            if (self.ctrl.height16) {
                if (self.draw_list[tail].attribute.flip_vertical) {
                    const offset_real: u8 = @bitCast(15 - offset_top);
                    addr = (title_id + @divTrunc(offset_real, 8)) * 16 + @mod(offset_real, 8);
                } else {
                    addr = (title_id + @divTrunc(offset_top, 8)) * 16 + offset_top;
                }
            } else {
                addr = title_id * 16 + offset_top + @as(u16, self.ctrl.BGPatternTableAddr) * 0x1000;
                if (self.draw_list[tail].attribute.flip_vertical) {
                    addr += 7 - offset_top;
                } else {
                    addr += offset_top;
                }
            }

            self.draw_list[tail].shifter_lo = self.internalRead(addr);
            self.draw_list[tail].shifter_hi = self.internalRead(addr + 8);
            if (self.draw_list[tail].attribute.flip_horizontal) {
                self.draw_list[tail].shifter_lo = @bitReverse(self.draw_list[tail].shifter_lo);
                self.draw_list[tail].shifter_hi = @bitReverse(self.draw_list[tail].shifter_hi);
            }

            self.draw_list[tail].attribute.spriteZero = i == 0;
            self.draw_list[tail].x = self.oam[i + 3];
            self.draw_list[tail].attribute.drawing = false;

            tail += 1;
        }
    }
}

pub fn printNametable1(self: *PPU) !void {
    const stdout = std.io.getStdOut().writer();
    for (0..30) |y| {
        for (0..32) |x| {
            try std.fmt.format(stdout, "{x:2} ", .{self.nametable[y * 32 + x]});
        }
        try std.fmt.format(stdout, "\n", .{});
    }
}

pub fn read(self: *PPU, addr: u16) u8 {
    const real_addr = addr % 8 + 0x2000;
    return switch (real_addr) {
        0x2000 => @bitCast(self.ctrl),
        0x2001 => @bitCast(self.mask),
        0x2002 => blk: {
            const res = self.status;
            self.status.VBlank = false;
            self.addr_latch = false;
            break :blk @bitCast(res);
        },
        0x2004 => self.oam[self.oam_addr], // OAM SHIT HERE
        0x2007 => blk: {
            var res = self.data_buff;
            var tmp: u16 = @bitCast(self.vreg);
            self.data_buff = self.internalRead(tmp & 0x3FFF);

            if (tmp >= 0x3F00) {
                res = self.data_buff;
            }

            tmp += if (self.ctrl.VRAMAddrInc) 32 else 1;
            self.vreg = @bitCast(tmp);
            break :blk res;
        },
        else => 0,
    };
}

pub fn write(self: *PPU, addr: u16, data: u8) void {
    switch (addr) {
        0x2000 => {
            self.ctrl = @bitCast(data);
            self.treg.nametable_x = self.ctrl.nametable_x;
            self.treg.nametable_y = self.ctrl.nametable_y;
        },
        0x2001 => self.mask = @bitCast(data),
        0x2003 => self.oam_addr = data, // OAM SHIT
        0x2004 => {
            self.oam[self.oam_addr] = data;
            self.oam_addr +%= 1;
        }, // OAM SHIT HERE
        0x2005 => {
            if (self.addr_latch) {
                self.treg.coarse_y = @truncate(data >> 3);
                self.treg.fine_y = @truncate(data & 0b111);
            } else {
                // if (data <= 239) {
                self.treg.coarse_x = @truncate(data >> 3);
                self.fine_x = @truncate(data & 0b111);
                // }
            }
            self.addr_latch = !self.addr_latch;
        },
        0x2006 => {
            var tmp: u16 = data;
            var treg: u16 = @bitCast(self.treg);
            if (self.addr_latch) { // Hi byte
                treg &= 0xFF00;
                treg |= tmp;
                self.vreg = @bitCast(treg);
            } else { // Lo byte
                tmp &= 0x3F;
                treg &= 0x00FF;
                treg |= tmp << 8;
            }
            self.treg = @bitCast(treg);
            self.addr_latch = !self.addr_latch;
        },
        0x2007 => {
            var tmp: u16 = @bitCast(self.vreg);
            self.internalWrite(tmp & 0x3FFF, data);
            tmp += if (self.ctrl.VRAMAddrInc) 32 else 1;
            self.vreg = @bitCast(tmp);
        },
        else => {},
    }
}

fn resolveNametableAddr(self: *PPU, addr: u16) u16 {
    const ntaddr = addr - 0x2000;
    var nametable_num = ntaddr / 0x400;
    const ntindex = ntaddr % 0x400;
    switch (self.mirroring) {
        .Horizontal => {
            const ntmap = [_]u8{ 0, 0, 1, 1 };
            nametable_num = ntmap[nametable_num];
        },
        .Vertical => {
            const ntmap = [_]u8{ 0, 1, 0, 1 };
            nametable_num = ntmap[nametable_num];
        },
    }
    return nametable_num * 0x400 + ntindex;
}

const transparent_idx = [_]u8{ 0, 4, 8, 12 };
fn find(arr: []const u8, pred: anytype) bool {
    for (arr) |elem| {
        if (elem == pred) {
            return true;
        }
    }
    return false;
}

fn internalRead(self: *PPU, addr: u16) u8 {
    return switch (addr) {
        0x0000...0x1FFF => self.CHR_ROM[self.mapper.ppuDecode(addr)],
        0x2000...0x2FFF => self.nametable[self.resolveNametableAddr(addr)],
        0x3000...0x3EFF => self.nametable[self.resolveNametableAddr(addr - 0x3000 + 0x2000)],
        0x3F00...0x3F0F => self.imagePalette[addr - 0x3F00],
        0x3F10...0x3F1F => self.spritePalette[addr - 0x3F10],
        0x3F20...0x3FFF => blk: {
            const real_addr = addr - 0x3F20;
            const tmp = real_addr % 16;
            if (real_addr % 32 >= 16) {
                if (find(&transparent_idx, tmp)) {
                    break :blk self.spritePalette[0];
                }
                break :blk self.spritePalette[tmp];
            } else {
                if (find(&transparent_idx, tmp)) {
                    break :blk self.imagePalette[0];
                }
                break :blk self.imagePalette[tmp];
            }
        },
        else => unreachable,
    };
}

fn internalWrite(self: *PPU, addr: u16, data: u8) void {
    return switch (addr) {
        0x0000...0x1FFF => self.CHR_ROM[self.mapper.ppuDecode(addr)] = data,
        0x2000...0x2FFF => self.nametable[self.resolveNametableAddr(addr)] = data,
        0x3000...0x3EFF => self.nametable[self.resolveNametableAddr(addr - 0x3000 + 0x2000)] = data,
        0x3F00...0x3F0F => self.imagePalette[addr - 0x3F00] = data,
        0x3F10...0x3F1F => self.spritePalette[addr - 0x3F10] = data,
        0x3F20...0x3FFF => {
            const real_addr = addr - 0x3F20;
            const tmp = real_addr % 16;
            if (real_addr % 32 >= 16) {
                self.spritePalette[tmp] = data;
                if (find(&transparent_idx, tmp)) {
                    for (transparent_idx) |i| {
                        self.spritePalette[i] = data;
                    }
                }
            } else {
                self.imagePalette[tmp] = data;
                if (find(&transparent_idx, tmp)) {
                    for (transparent_idx) |i| {
                        self.imagePalette[i] = data;
                    }
                }
            }
        },
        else => unreachable,
    };
}

const ToBeDrawn = struct {
    x: u8,
    shifter_lo: u8,
    shifter_hi: u8,
    attribute: SpriteAttribute,
};

const SpriteAttribute = packed struct(u8) {
    palette: u2 = 0,
    spriteZero: bool = 0,
    drawing: bool = false,
    _zero: u1 = 0,
    behindBG: bool = false,
    flip_horizontal: bool = false,
    flip_vertical: bool = false,
};

const VRamAddr = packed struct(u16) {
    coarse_x: u5,
    coarse_y: u5,
    nametable_x: u1,
    nametable_y: u1,
    fine_y: u3,
    _pad: u1,
};

const PPUCTRL = packed struct(u8) {
    nametable_x: u1,
    nametable_y: u1,
    VRAMAddrInc: bool,
    SpritePatternTableAddr: u1,
    BGPatternTableAddr: u1,
    height16: bool,
    SM: bool,
    NMIEnable: bool,
};

const PPUMASK = packed struct(u8) {
    Grayscale: bool,
    ShowBGInLM: bool,
    ShowSpriteInLM: bool,
    ShowBG: bool,
    ShowSprite: bool,
    EmRed: bool,
    EmGreen: bool,
    EmBlue: bool,
};

const PPUSTATUS = packed struct(u8) {
    _pad: u5,
    SpriteOverflow: bool,
    SpriteZeroHit: bool,
    VBlank: bool,
};

const colors = [_]sdl.Color{
    sdl.Color{ .r = 84, .g = 84, .b = 84, .a = 255 },
    sdl.Color{ .r = 0, .g = 30, .b = 116, .a = 255 },
    sdl.Color{ .r = 8, .g = 16, .b = 144, .a = 255 },
    sdl.Color{ .r = 48, .g = 0, .b = 136, .a = 255 },
    sdl.Color{ .r = 68, .g = 0, .b = 100, .a = 255 },
    sdl.Color{ .r = 92, .g = 0, .b = 48, .a = 255 },
    sdl.Color{ .r = 84, .g = 4, .b = 0, .a = 255 },
    sdl.Color{ .r = 60, .g = 24, .b = 0, .a = 255 },
    sdl.Color{ .r = 32, .g = 42, .b = 0, .a = 255 },
    sdl.Color{ .r = 8, .g = 58, .b = 0, .a = 255 },
    sdl.Color{ .r = 0, .g = 64, .b = 0, .a = 255 },
    sdl.Color{ .r = 0, .g = 60, .b = 0, .a = 255 },
    sdl.Color{ .r = 0, .g = 50, .b = 60, .a = 255 },
    sdl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 },
    sdl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 },
    sdl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 },
    sdl.Color{ .r = 152, .g = 150, .b = 152, .a = 255 },
    sdl.Color{ .r = 8, .g = 76, .b = 196, .a = 255 },
    sdl.Color{ .r = 48, .g = 50, .b = 236, .a = 255 },
    sdl.Color{ .r = 92, .g = 30, .b = 228, .a = 255 },
    sdl.Color{ .r = 136, .g = 20, .b = 176, .a = 255 },
    sdl.Color{ .r = 160, .g = 20, .b = 100, .a = 255 },
    sdl.Color{ .r = 152, .g = 34, .b = 32, .a = 255 },
    sdl.Color{ .r = 120, .g = 60, .b = 0, .a = 255 },
    sdl.Color{ .r = 84, .g = 90, .b = 0, .a = 255 },
    sdl.Color{ .r = 40, .g = 114, .b = 0, .a = 255 },
    sdl.Color{ .r = 8, .g = 124, .b = 0, .a = 255 },
    sdl.Color{ .r = 0, .g = 118, .b = 40, .a = 255 },
    sdl.Color{ .r = 0, .g = 102, .b = 120, .a = 255 },
    sdl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 },
    sdl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 },
    sdl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 },
    sdl.Color{ .r = 236, .g = 238, .b = 236, .a = 255 },
    sdl.Color{ .r = 76, .g = 154, .b = 236, .a = 255 },
    sdl.Color{ .r = 120, .g = 124, .b = 236, .a = 255 },
    sdl.Color{ .r = 176, .g = 98, .b = 236, .a = 255 },
    sdl.Color{ .r = 228, .g = 84, .b = 236, .a = 255 },
    sdl.Color{ .r = 236, .g = 88, .b = 180, .a = 255 },
    sdl.Color{ .r = 236, .g = 106, .b = 100, .a = 255 },
    sdl.Color{ .r = 212, .g = 136, .b = 32, .a = 255 },
    sdl.Color{ .r = 160, .g = 170, .b = 0, .a = 255 },
    sdl.Color{ .r = 116, .g = 196, .b = 0, .a = 255 },
    sdl.Color{ .r = 76, .g = 208, .b = 32, .a = 255 },
    sdl.Color{ .r = 56, .g = 204, .b = 108, .a = 255 },
    sdl.Color{ .r = 56, .g = 180, .b = 204, .a = 255 },
    sdl.Color{ .r = 60, .g = 60, .b = 60, .a = 255 },
    sdl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 },
    sdl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 },
    sdl.Color{ .r = 236, .g = 238, .b = 236, .a = 255 },
    sdl.Color{ .r = 168, .g = 204, .b = 236, .a = 255 },
    sdl.Color{ .r = 188, .g = 188, .b = 236, .a = 255 },
    sdl.Color{ .r = 212, .g = 178, .b = 236, .a = 255 },
    sdl.Color{ .r = 236, .g = 174, .b = 236, .a = 255 },
    sdl.Color{ .r = 236, .g = 174, .b = 212, .a = 255 },
    sdl.Color{ .r = 236, .g = 180, .b = 176, .a = 255 },
    sdl.Color{ .r = 228, .g = 196, .b = 144, .a = 255 },
    sdl.Color{ .r = 204, .g = 210, .b = 120, .a = 255 },
    sdl.Color{ .r = 180, .g = 222, .b = 120, .a = 255 },
    sdl.Color{ .r = 168, .g = 226, .b = 144, .a = 255 },
    sdl.Color{ .r = 152, .g = 226, .b = 180, .a = 255 },
    sdl.Color{ .r = 160, .g = 214, .b = 228, .a = 255 },
    sdl.Color{ .r = 160, .g = 162, .b = 160, .a = 255 },
    sdl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 },
    sdl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 },
};
