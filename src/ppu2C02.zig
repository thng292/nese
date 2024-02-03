const std = @import("std");
const sdl = @import("zsdl");
const Mapper = @import("mapper.zig");
const Rom = @import("ines.zig").ROM;
const Bus = @import("bus.zig").Bus;

const PPU = @This();
mapper: Mapper,
ctrl: PPUCTRL,
mask: PPUMASK,
status: PPUSTATUS,
chr_rom: []Title,
CHR_ROM: []u8,
nametable: [2048]u8,
spritePalette: [16]u8,
imagePalette: [16]u8,
data: u8,
scroll_offset_x: u8,
scroll_offset_y: u8,
addr_buff: u16,
addr_latch: bool,
mirroring: Mapper.MirroringMode,
allocator: std.mem.Allocator,
data_buff: u8,
scanline: i16 = 0,
dot: i16 = 0,
nmiSend: bool = false,

pub fn init(a: std.mem.Allocator, mapper: Mapper, rom: *Rom) !PPU {
    const noTitles = rom.CHR_RomBanks.len / 16;
    const chr_rom = try a.alloc(Title, noTitles);
    for (0..noTitles) |i| {
        chr_rom[i] = Title.init(rom.CHR_RomBanks[i * 16 .. (i + 1) * 16]);
    }
    return PPU{
        .mapper = mapper,
        .chr_rom = chr_rom,
        .CHR_ROM = rom.CHR_RomBanks,
        .nametable = undefined,
        .spritePalette = undefined,
        .imagePalette = undefined,
        .ctrl = std.mem.zeroes(PPUCTRL),
        .mask = std.mem.zeroes(PPUMASK),
        .status = std.mem.zeroes(PPUSTATUS),
        .data = 0,
        .scroll_offset_x = 0,
        .scroll_offset_y = 0,
        .addr_buff = 0,
        .addr_latch = false,
        .mirroring = .Vertical,
        .allocator = a,
        .data_buff = 0,
    };
}

pub fn deinit(self: *PPU) void {
    self.allocator.free(self.chr_rom);
}

pub fn clock(self: *PPU, renderer: *sdl.Renderer) void {
    const scanline_max_cycle = 341;

    if (self.scanline == 0 and self.dot == 0) {
        self.dot = 1;
    }

    if (self.scanline == -1 and self.dot == 1) {
        self.status.VBlank = false;
    }

    self.dot += 1;
    if (self.dot == scanline_max_cycle) {
        self.scanline += 1;
        self.dot = 0;
    }
    self.nmiSend = self.scanline == 240 and self.ctrl.NMIEnable;
    self.status.VBlank = self.scanline == 240;
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
            self.data_buff = self.internalRead(self.addr_buff);

            if (self.addr_buff >= 0x3F00) {
                res = self.data_buff;
            }

            self.addr_buff += if (self.ctrl.VRAMAddrInc) 32 else 1;
            break :blk res;
        },
        else => 0,
    };
}

pub fn write(self: *PPU, addr: u16, data: u8) void {
    //     std.debug.print("CPU writing to {x}\n", .{addr});
    switch (addr) {
        0x2000 => self.ctrl = @bitCast(data),
        0x2001 => self.mask = @bitCast(data),
        0x2003 => {}, // OAM SHIT
        0x2004 => {}, // OAM SHIT HERE
        0x2005 => {
            if (self.addr_latch) {
                self.scroll_offset_y = data;
            } else {
                if (data <= 239) {
                    self.scroll_offset_x = data;
                }
            }
            self.addr_latch = !self.addr_latch;
        },
        0x2006 => {
            const tmp: u16 = data;
            if (self.addr_latch) { // Lo byte
                self.addr_buff &= 0xFF00;
                self.addr_buff |= tmp;
            } else { // Hi byte
                self.addr_buff &= 0x00FF;
                self.addr_buff |= tmp << 8;
            }
            self.addr_latch = !self.addr_latch;
        },
        0x2007 => {
            self.internalWrite(self.addr_buff, data);
            self.addr_buff += if (self.ctrl.VRAMAddrInc) 32 else 1;
        },
        else => {},
    }
}

fn internalRead(self: *PPU, addr: u16) u8 {
    return switch (addr) {
        0x0000...0x1FFF => self.CHR_ROM[self.mapper.ppuDecode(addr)],
        0x2000...0x27FF => self.nametable[addr - 0x2000],
        0x2800...0x2FFF => self.nametable[addr - 0x2800],
        0x3000...0x3EFF => self.nametable[addr - 0x3000],
        0x3F00...0x3F0F => self.imagePalette[addr - 0x3F00],
        0x3F10...0x3F1F => self.spritePalette[addr - 0x3F10],
        0x3F20...0x3FFF => if (addr % 32 >= 16) self.spritePalette[addr % 16] else self.imagePalette[addr % 16],
        else => 0,
    };
}

fn internalWrite(self: *PPU, addr: u16, data: u8) void {
    //     std.debug.print("Writing to {x}\n", .{addr});
    return switch (addr) {
        0x0000...0x1FFF => self.CHR_ROM[self.mapper.ppuDecode(addr)] = data,
        0x2000...0x27FF => self.nametable[addr - 0x2000] = data,
        0x2800...0x2FFF => self.nametable[addr - 0x2800] = data,
        0x3000...0x3EFF => self.nametable[addr - 0x3000] = data,
        0x3F00...0x3F0F => self.imagePalette[addr - 0x3F00] = data,
        0x3F10...0x3F1F => self.spritePalette[addr - 0x3F10] = data,
        0x3F20...0x3FFF => {
            if (addr % 32 >= 16) {
                self.spritePalette[addr % 16] = data;
            } else {
                self.imagePalette[addr % 16] = data;
            }
        },
        else => {},
    };
}

const PPUCTRL = packed struct(u8) {
    BaseNameTableAddr: u2,
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

    pub fn draw(self: *Title, renderer: *sdl.Renderer, pos_x: i32, pos_y: i32, scale: u8) !void {
        for (0..8) |y| {
            const yy: i32 = @truncate(y);
            for (0..8) |x| {
                const xx: i32 = @truncate(x);
                try renderer.setDrawColor(colors[self.get(y * 8 + x)]);
                try renderer.fillRect(.{
                    .w = scale,
                    .h = scale,
                    .x = xx * scale + pos_x,
                    .y = yy * scale + pos_y,
                });
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
