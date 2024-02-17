const std = @import("std");
const sdl = @import("zsdl");
const Mapper = @import("mapper.zig");
const Rom = @import("ines.zig").ROM;
const Bus = @import("bus.zig").Bus;

const PPU = @This();
mapper: Mapper,
mirroring: Mapper.MirroringMode = .Vertical,

ctrl: PPUCTRL = std.mem.zeroes(PPUCTRL),
mask: PPUMASK = std.mem.zeroes(PPUMASK),
status: PPUSTATUS = std.mem.zeroes(PPUSTATUS),
nmiSend: bool = false,

CHR_ROM: []u8,
nametable: [2048]u8 = undefined,
spritePalette: [16]u8 = undefined,
imagePalette: [16]u8 = undefined,

data: u8 = 0,
addr_latch: bool = false,
data_buff: u8 = 0,

scanline: u16 = 0,
cycle: u16 = 0,
vreg: VRamAddr = std.mem.zeroes(VRamAddr),
treg: VRamAddr = std.mem.zeroes(VRamAddr),
fine_x: u3 = 0,
even_frame: bool = true,

render_cache: RenderCache = RenderCache{},

pub fn init(mapper: Mapper, rom: *Rom) !PPU {
    // const noTitles = rom.CHR_RomBanks.len / 16;
    // const chr_rom = try a.alloc(Title, noTitles);
    // for (0..noTitles) |i| {
    //     chr_rom[i] = Title.init(rom.CHR_RomBanks[i * 16 .. (i + 1) * 16]);
    // }
    return PPU{
        .mapper = mapper,
        .CHR_ROM = rom.CHR_RomBanks,
    };
}

inline fn fetchRenderData(self: *PPU) void {
    if (self.vreg.coarse_x != self.render_cache.coarse_x or self.render_cache.first_time) {
        const vreg: u16 = @bitCast(self.vreg);
        const title_id: u16 = self.internalRead(0x2000 + (vreg & 0x0FFF));

        const CHR_index = title_id * 16 + @as(u16, self.ctrl.BGPatternTableAddr) * 0x1000;
        self.render_cache.lsb = self.CHR_ROM[self.mapper.ppuDecode(CHR_index + self.vreg.fine_y)];
        self.render_cache.msb = self.CHR_ROM[self.mapper.ppuDecode(CHR_index + self.vreg.fine_y + 8)];

        var attrbute_index: u16 = self.vreg.coarse_x >> 2;
        const tmp: u6 = self.vreg.coarse_y >> 2;
        attrbute_index |= tmp << 3;
        attrbute_index |= @as(u16, self.vreg.nametable_y) << 11;
        attrbute_index |= @as(u16, self.vreg.nametable_x) << 10;

        var current_attrbute = self.internalRead(0x23C0 | attrbute_index);
        if (self.vreg.coarse_y & 0b10 != 0) {
            current_attrbute >>= 4;
        }
        if (self.vreg.coarse_x & 0b10 != 0) {
            current_attrbute >>= 2;
        }
        current_attrbute &= 0b11;

        self.render_cache.attr = @truncate(current_attrbute);
        self.render_cache.first_time = false;
    }
}

inline fn IncX(self: *PPU) void {
    if (!self.mask.ShowBG and !self.mask.ShowSprite) {
        return;
    }

    if (self.fine_x == 7) {
        self.fine_x = 0;
        if (self.vreg.coarse_x == 31) {
            self.vreg.coarse_x = 0;
            self.vreg.nametable_x = ~self.vreg.nametable_x;
        } else {
            self.vreg.coarse_x += 1;
        }
    } else {
        self.fine_x += 1;
    }
}

inline fn IncY(self: *PPU) void {
    if (!self.mask.ShowBG and !self.mask.ShowSprite) {
        return;
    }

    self.render_cache = RenderCache{};

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

pub fn clock(self: *PPU, renderer: *sdl.Renderer) !void {
    const scanline_max_cycle = 341;
    const max_scanline = 262;

    if (self.scanline == 0 and self.cycle == 0) {
        self.even_frame = !self.even_frame;
        self.mirroring = self.mapper.getMirroringMode();
    }

    if (self.cycle == 0) {
        self.cycle = 1;
    }

    if (self.scanline == 241 and self.cycle == 1) {
        self.status.VBlank = true;
        self.nmiSend = self.ctrl.NMIEnable;
    }

    // if (self.scanline == self.mapper.getNMIScanline()) {
    //     self.nmiSend = self.ctrl.NMIEnable;
    // }

    if (self.scanline == 261) {
        if (self.cycle == 1) {
            self.status = std.mem.zeroes(PPUSTATUS);
            // self.status.VBlank = false;
        }
        if (self.cycle >= 280 and self.cycle <= 304) {
            if (self.mask.ShowBG or self.mask.ShowSprite) {
                self.vreg.fine_y = self.treg.fine_y;
                self.vreg.coarse_y = self.treg.coarse_y;
                self.vreg.nametable_y = self.treg.nametable_y;
            }
        }
    }

    if (self.cycle == 256) {
        self.IncY();
        if (self.mask.ShowBG or self.mask.ShowSprite) {
            self.vreg.coarse_x = self.treg.coarse_x;
            self.vreg.nametable_x = self.treg.nametable_x;
        }
    }

    if (self.scanline < 240 and self.cycle <= 256 and self.mask.ShowBG) {
        // Draw dot @ self.vreg
        self.fetchRenderData();
        var pixel: u8 = self.render_cache.attr << 2;
        pixel |= (self.render_cache.lsb >> (7 - self.fine_x)) & 0b1;
        pixel |= ((self.render_cache.msb >> (7 - self.fine_x)) << 1) & 0b10;
        try renderer.setDrawColor(colors[self.imagePalette[pixel]]);
        try renderer.drawPoint(self.cycle - 1, self.scanline);
        self.IncX();
    }

    self.cycle += 1;
    if (self.cycle == scanline_max_cycle) {
        self.cycle = 0;
        self.scanline += 1;
        self.scanline %= max_scanline;
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
    //     std.debug.print("CPU reading from {x}\n", .{addr});
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
        0x2004 => self.data, // OAM SHIT HERE
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
    //     std.debug.print("CPU writing to {x}\n", .{addr});
    switch (addr) {
        0x2000 => {
            self.ctrl = @bitCast(data);
            self.treg.nametable_x = self.ctrl.nametable_x;
            self.treg.nametable_y = self.ctrl.nametable_y;
        },
        0x2001 => self.mask = @bitCast(data),
        0x2003 => {}, // OAM SHIT
        0x2004 => {}, // OAM SHIT HERE
        0x2005 => {
            if (self.addr_latch) {
                self.treg.coarse_y = @truncate(data >> 3);
                self.treg.fine_y = @truncate(data & 0b111);
            } else {
                if (data <= 239) {
                    self.treg.coarse_x = @truncate(data >> 3);
                    self.fine_x = @truncate(data & 0b111);
                }
            }
            self.addr_latch = !self.addr_latch;
        },
        0x2006 => {
            const tmp: u16 = data;
            var treg: u16 = @bitCast(self.treg);
            if (self.addr_latch) { // Lo byte
                treg &= 0xFF00;
                treg |= tmp;
                self.vreg = @bitCast(treg);
            } else { // Hi byte
                treg &= 0x003F;
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

const RenderCache = struct {
    coarse_x: u5 = 0,
    lsb: u8 = 0,
    msb: u8 = 0,
    attr: u4 = 0,
    first_time: bool = true,
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
    SpriteHeight: bool,
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

const Title = struct {
    data: [8]u16,

    inline fn set(raw: []u16, x: u3, y: u3, data: u2) void {
        const xx: u4 = x;
        const index = ~(@as(u16, 3) << (@as(u4, 14) - xx * 2));
        const data_shifted = @as(u16, @intCast(data)) << (@as(u4, 14) - xx * 2);
        raw[y] = raw[y] & index | data_shifted;
    }

    inline fn getBit(num: u8, idx: u3) u1 {
        return @truncate(num >> (7 - idx) & 1);
    }

    pub fn init(raw: []u8) Title {
        var res: [8]u16 = undefined;
        const lsb = raw[0..8];
        const msb = raw[8..16];
        for (0..8) |tmpY| {
            const yy: u3 = @truncate(tmpY);
            const currentByteLo = lsb[yy];
            const currentByteHi = msb[yy];
            for (0..8) |tmpX| {
                const xx: u3 = @truncate(tmpX);
                const j: u3 = @truncate(tmpX);
                var pixel: u2 = getBit(currentByteHi, j);
                pixel <<= 1;
                pixel |= getBit(currentByteLo, j);
                set(&res, xx, yy, pixel);
            }
        }
        return Title{ .data = res };
    }

    pub inline fn get(self: *Title, index: usize) u4 {
        const tmp = self.data[index / 4];
        return (tmp >> (index % 4 * 2)) & 0x0F;
    }

    pub fn draw(self: *Title, renderer: *sdl.Renderer, pos_x: i32, pos_y: i32, attribute: u2) !void {
        const attr: u4 = attribute;
        for (0..8) |y| {
            const yy: i32 = @truncate(y);
            for (0..8) |x| {
                const xx: i32 = @truncate(x);
                var colorIndex = self.get(y * 8 + x);
                if (colorIndex == 0) {
                    continue;
                }
                colorIndex |= attr << 2;
                try renderer.setDrawColor(colors[colorIndex]);
                try renderer.drawPoint(xx + pos_x, yy + pos_y);
            }
        }
    }
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
