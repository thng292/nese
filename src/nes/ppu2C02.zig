const std = @import("std");
const sdl = @import("zsdl");
const Mapper = @import("mapper.zig");
const Rom = @import("ines.zig").ROM;

const PPU = @This();
mapper: Mapper,

ctrl: PPUCTRL = std.mem.zeroes(PPUCTRL),
mask: PPUMASK = std.mem.zeroes(PPUMASK),
status: PPUSTATUS = std.mem.zeroes(PPUSTATUS),
nmiSend: bool = false,
irqSend: bool = false,
odd_frame: bool = false,

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

texture_pixel_count: usize = 0,

bg_shifter_pattern_lo: u16 = 0,
bg_shifter_pattern_hi: u16 = 0,
bg_shifter_attrib_lo: u16 = 0,
bg_shifter_attrib_hi: u16 = 0,
bg_next_title_id: u8 = 0,
bg_next_title_lsb: u8 = 0,
bg_next_title_msb: u8 = 0,
bg_next_title_attrib: u8 = 0,

pub fn init(mapper: Mapper) !PPU {
    return PPU{
        .mapper = mapper,
    };
}

pub fn clock(self: *PPU, texture_data: [*]u8) !void {
    if (self.scanline >= -1 and self.scanline < 240) {
        if (self.scanline == 0 and self.cycle == 0) {
            self.texture_pixel_count = 0;
            if (self.odd_frame) {
                self.cycle = 1;
            }
            self.odd_frame = !self.odd_frame;
        }

        if (self.scanline == -1 and self.cycle == 1) {
            self.status = std.mem.zeroes(PPUSTATUS);
        }

        if ((self.cycle >= 2 and self.cycle < 258) //
        or (self.cycle >= 321 and self.cycle < 338)) {
            self.UpdateShifter();
            // Fetching the new title
            switch (@mod(self.cycle - 1, 8)) {
                0 => {
                    self.LoadBGShifter();
                    const vreg: u16 = @bitCast(self.vreg);
                    self.bg_next_title_id = self.internalRead(0x2000 | (vreg & 0x0FFF));
                },
                2 => {
                    self.bg_next_title_attrib = self.internalRead(0x23C0 //
                    | @as(u16, self.vreg.nametable_y) << 11 //
                    | @as(u16, self.vreg.nametable_x) << 10 //
                    | @as(u6, self.vreg.coarse_y >> 2) << 3 //
                    | self.vreg.coarse_x >> 2);
                    if (self.vreg.coarse_y & 0b10 != 0) {
                        self.bg_next_title_attrib >>= 4;
                    }
                    if (self.vreg.coarse_x & 0b10 != 0) {
                        self.bg_next_title_attrib >>= 2;
                    }
                    self.bg_next_title_attrib &= 0b11;
                },
                4 => {
                    const tmp = @as(u16, self.bg_next_title_id) * 16 //
                    + @as(u16, self.ctrl.BGPatternTableAddr) * 0x1000;
                    self.bg_next_title_lsb = self.internalRead(tmp + self.vreg.fine_y);
                },
                6 => {
                    const tmp = @as(u16, self.bg_next_title_id) * 16 //
                    + @as(u16, self.ctrl.BGPatternTableAddr) * 0x1000;
                    self.bg_next_title_msb = self.internalRead(tmp + self.vreg.fine_y + 8);
                },
                7 => {
                    self.IncX();
                },
                else => {},
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

    if (self.mapper.shouldIrq() and self.cycle == 0) {
        self.nmiSend = true;
    }

    // Draw
    var sprite_behind_bg = false;
    var color_out_sprite: u8 = 0;
    var color_out_bg: u8 = 0;
    if (self.mask.ShowBG and (self.cycle > 8 or self.mask.ShowBGInLM)) {
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

    if (self.mask.ShowSprite) blk: {
        for (&self.draw_list) |*sprite| {
            if (sprite.x != 0) {
                sprite.x -%= 1;
            } else {
                if (sprite.attribute.drawing == false) {
                    sprite.x = 8;
                }
                sprite.attribute.drawing = !sprite.attribute.drawing;
            }
        }
        if (!self.mask.ShowSpriteInLM and self.cycle <= 8) {
            break :blk;
        }
        for (&self.draw_list) |*sprite| {
            if (!sprite.attribute.drawing) {
                continue;
            }
            var pixel: u8 = sprite.attribute.palette;
            pixel += 4;
            pixel <<= 2;
            const lo = sprite.shifter_lo >> 7;
            const hi = (sprite.shifter_hi >> 7) << 1;
            pixel |= lo;
            pixel |= hi;
            sprite.shifter_hi <<= 1;
            sprite.shifter_lo <<= 1;
            // Sprite 0 hit
            if (self.status.SpriteZeroHit == false) {
                self.status.SpriteZeroHit = sprite.attribute.spriteZero //
                and self.cycle != 255 //
                and (color_out_bg & pixel & 0b11) != 0;

                // if (self.status.SpriteZeroHit) {
                //     std.debug.print("Sprite Zero Hitted\n", .{});
                // }
            }
            if (color_out_sprite & 0b11 == 0) {
                color_out_sprite = pixel;
                sprite_behind_bg = sprite.attribute.behindBG;
            }
        }
    }

    // _ = texture_data;
    var color_out: u8 = 0;
    const palette_offset: u16 = 0x3F00;
    if (sprite_behind_bg) {
        if (color_out_bg & 0b11 == 0) { // BG's pixel is transparent
            color_out = color_out_sprite;
        } else {
            color_out = color_out_bg;
        }
    } else {
        if (color_out_sprite & 0b11 == 0) { // Sprite's pixel is transparent
            color_out = color_out_bg;
        } else {
            color_out = color_out_sprite;
        }
    }
    // color_out = color_out_sprite;
    if (0 <= self.cycle - 1 and self.cycle - 1 < 256 and self.scanline <= 240) {
        const pixel = colors[self.internalRead(palette_offset + @as(u16, color_out))];
        texture_data[self.texture_pixel_count + 3] = pixel.r;
        texture_data[self.texture_pixel_count + 2] = pixel.g;
        texture_data[self.texture_pixel_count + 1] = pixel.b;
        texture_data[self.texture_pixel_count + 0] = pixel.a;
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

inline fn spriteEvaluate(self: *PPU) void {
    var i: u16 = 0;
    var tail: u8 = 0;
    const spriteHeight: u8 = if (self.ctrl.height16) 16 else 8;
    @memset(&self.draw_list, ToBeDrawn{
        .x = 0xFF,
        .shifter_hi = 0,
        .shifter_lo = 0,
        .attribute = SpriteAttribute{},
    });
    while (i < 256 and tail < 9) : (i += 4) {
        const difference = self.scanline - self.oam[i] - 1;
        if (0 > difference or spriteHeight <= difference) {
            continue;
        }
        if (tail == 8) {
            self.status.SpriteOverflow = true;
            break;
        }
        const offset_top_: i8 = @truncate(difference);
        const offset_top: u8 = @bitCast(offset_top_);
        const title_id: u16 = self.oam[i + 1];
        const currentSprite = &self.draw_list[tail];
        currentSprite.attribute = @bitCast(self.oam[i + 2]);

        var addr: u16 = 0;
        if (self.ctrl.height16) {
            addr = if (title_id & 1 != 0) 0x1000 else 0;
            const reminder = title_id % 2;
            if (currentSprite.attribute.flip_vertical) {
                if (offset_top >= 8) {
                    addr += (title_id - reminder) * 16 + 7 - (offset_top - 8);
                } else {
                    addr += (title_id - reminder + 1) * 16 + 7 - offset_top;
                }
            } else {
                if (offset_top >= 8) {
                    addr += (title_id - reminder + 1) * 16 + offset_top - 8;
                } else {
                    addr += (title_id - reminder) * 16 + offset_top;
                }
            }
        } else {
            addr = title_id * 16 + @as(u16, self.ctrl.SpritePatternTableAddr) * 0x1000;
            if (currentSprite.attribute.flip_vertical) {
                addr += 7 - offset_top;
            } else {
                addr += offset_top;
            }
        }

        currentSprite.shifter_lo = self.internalRead(addr);
        currentSprite.shifter_hi = self.internalRead(addr + 8);
        currentSprite.attribute.spriteZero = i == 0;
        currentSprite.attribute.drawing = false;
        currentSprite.x = self.oam[i + 3] +% 1;
        if (currentSprite.attribute.flip_horizontal) {
            currentSprite.shifter_lo = @bitReverse(currentSprite.shifter_lo);
            currentSprite.shifter_hi = @bitReverse(currentSprite.shifter_hi);
        }

        tail += 1;
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
        0x2004 => self.oam[self.oam_addr],
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
        },
        0x2005 => {
            if (self.addr_latch) {
                self.treg.coarse_y = @truncate(data >> 3);
                self.treg.fine_y = @truncate(data & 0b111);
            } else {
                // if (data <= 239) {
                self.treg.coarse_x = @truncate(data >> 3);
                self.fine_x = @truncate(data & 0b111);
                // std.debug.print("coarse_x, fine_x: {}, {}\n", .{ self.treg.coarse_x, self.fine_x });
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
                // std.debug.print("Vreg is now: {}\n", .{treg});
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

fn internalRead(self: *PPU, addr: u16) u8 {
    return switch (addr) {
        0x0000...0x1FFF => self.mapper.ppuRead(addr),
        0x2000...0x2FFF => self.nametable[self.mapper.resolveNametableAddr(addr)],
        0x3000...0x3EFF => self.nametable[self.mapper.resolveNametableAddr(addr - 0x3000 + 0x2000)],
        0x3F00...0x3F0F => self.imagePalette[addr - 0x3F00],
        0x3F10...0x3F1F => self.spritePalette[addr - 0x3F10],
        0x3F20...0x3FFF => blk: {
            const real_addr = addr - 0x3F20;
            const tmp = real_addr % 16;
            if (real_addr % 32 >= 16) {
                break :blk self.spritePalette[tmp];
            } else {
                break :blk self.imagePalette[tmp];
            }
        },
        else => unreachable,
    };
}

fn internalWrite(self: *PPU, addr: u16, data: u8) void {
    return switch (addr) {
        0x0000...0x1FFF => self.mapper.ppuWrite(addr, data),
        0x2000...0x2FFF => self.nametable[self.mapper.resolveNametableAddr(addr)] = data,
        0x3000...0x3EFF => self.nametable[self.mapper.resolveNametableAddr(addr - 0x3000 + 0x2000)] = data,
        0x3F00...0x3F0F => {
            const tmp = addr - 0x3F00;
            self.imagePalette[tmp] = data;
            self.assignBGColor(tmp, data);
        },
        0x3F10...0x3F1F => {
            const tmp = addr - 0x3F10;
            self.spritePalette[tmp] = data;
            self.assignBGColor(tmp, data);
        },
        0x3F20...0x3FFF => {
            const real_addr = addr - 0x3F20;
            const tmp = real_addr % 16;
            if (real_addr % 32 >= 16) {
                self.spritePalette[tmp] = data;
            } else {
                self.imagePalette[tmp] = data;
            }
            self.assignBGColor(tmp, data);
        },
        else => unreachable,
    };
}

fn assignBGColor(self: *PPU, tmp: u16, data: u8) void {
    if (tmp == 0) {
        self.spritePalette[0] = data;
        self.spritePalette[4] = data;
        self.spritePalette[8] = data;
        self.spritePalette[12] = data;
        self.imagePalette[0] = data;
        self.imagePalette[4] = data;
        self.imagePalette[8] = data;
        self.imagePalette[12] = data;
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

fn printStruct(struc: anytype) void {
    std.debug.print("{{\n", .{});
    inline for (std.meta.fields(@TypeOf(struc))) |f| {
        std.debug.print("\t" ++ f.name ++ ": {}\n", .{@field(struc, f.name)});
    }
    std.debug.print("}}\n", .{});
}

fn printColor(value: u8, color: sdl.Color) void {
    std.debug.print("{X:0>2}: #{X:0>2}{X:0>2}{X:0>2}\n", .{ value, color.r, color.g, color.b });
}

pub fn printPPUDebug(self: *PPU) void {
    std.debug.print("\n", .{});
    std.debug.print("Sprite Palette================================\n", .{});
    for (self.spritePalette) |value| {
        printColor(value, colors[value]);
    }

    std.debug.print("BG Palette====================================\n", .{});
    for (self.imagePalette) |value| {
        printColor(value, colors[value]);
    }

    std.debug.print("State========================================\n", .{});
    std.debug.print("CTRL:\n", .{});
    printStruct(self.ctrl);

    std.debug.print("MASK:\n", .{});
    printStruct(self.mask);

    std.debug.print("STATUS:\n", .{});
    printStruct(self.status);

    std.debug.print("OAM==========================================\n", .{});
    var i: u16 = 0;
    while (i < 256) : (i += 4) {
        std.debug.print("{{x: {: >3}, y: {: >3}, id: {X:0>2}, attr: {b:0>8}}}\n", .{
            .x = self.oam[i + 3],
            .y = self.oam[i + 0],
            .id = self.oam[i + 1],
            .attribute = self.oam[i + 2],
        });
    }
    std.debug.print("OAM==========================================\n", .{});
    self.printNametable1() catch {};
}

const tmp_color = [_]sdl.Color{
    .{ .r = 0, .g = 0, .b = 0, .a = 255 },
    .{ .r = 84, .g = 13, .b = 110, .a = 255 },
    .{ .r = 238, .g = 66, .b = 102, .a = 255 },
    .{ .r = 255, .g = 210, .b = 63, .a = 255 },
};

pub fn draw_chr(self: *PPU, texture_data: [*]u8) void {
    // Draw first pattern table
    var x: u16 = 0;
    var y: u8 = 0;
    for (0..256) |i| {
        self.draw_sprite(@truncate(i), @truncate(x), y, texture_data);
        x += 8;
        if (x == 128) {
            x = 0;
            y += 8;
        }
    }
    x = 128;
    y = 0;
    // Draw second pattern table
    for (256..512) |i| {
        self.draw_sprite(@truncate(i), @truncate(x), y, texture_data);
        x += 8;
        if (x == 256) {
            x = 128;
            y += 8;
        }
    }
}

fn draw_sprite(self: *PPU, spriteNum: u16, x: u8, y: u8, texture_data: [*]u8) void {
    var addr: u16 = spriteNum * 16;
    var xx: u32 = 0;
    var yy: u32 = 0;
    for (0..8) |_| {
        var lsb = self.mapper.ppuRead(addr);
        var msb = self.mapper.ppuRead(addr + 8);
        addr += 1;
        for (0..8) |_| {
            const pixel = tmp_color[((msb & 0x80) >> 6) | (lsb & 0x80) >> 7];
            msb <<= 1;
            lsb <<= 1;
            const anchor = (x + xx + (y + yy) * 256) * 4;
            texture_data[anchor + 3] = pixel.r;
            texture_data[anchor + 2] = pixel.g;
            texture_data[anchor + 1] = pixel.b;
            texture_data[anchor + 0] = pixel.a;
            xx = (xx + 1) % 8;
        }
        yy += 1;
    }
}

const ToBeDrawn = struct {
    x: u8,
    shifter_lo: u8,
    shifter_hi: u8,
    attribute: SpriteAttribute,
};

const SpriteAttribute = packed struct(u8) {
    palette: u2 = 0,
    spriteZero: bool = false,
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
