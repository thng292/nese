const std = @import("std");
const sdl = @import("zsdl");
const Bus = @import("bus.zig").Bus;
const CPU = @import("cpu6502.zig");
const Rom = @import("ines.zig").ROM;
const Ram = @import("ram.zig");
const Control = @import("control.zig");
const Mapper0 = @import("mapper0.zig");
const PPU = @import("ppu2C02.zig");
const APU = @import("apu2A03.zig");
const Mapper = @import("mapper.zig");

const Nes = @This();
const dot_per_frame = 341 * 262;

rom: Rom = undefined,
cpu: CPU = undefined,
bus: Bus = undefined,
mapperMem: MapperUnion = undefined,
game_screen: *sdl.Texture = undefined,
counter: u64 = 0,

pub fn init(allocator: std.mem.Allocator, rom_file: std.fs.File, game_screen: *sdl.Texture) !Nes {
    var format: sdl.PixelFormatEnum = undefined;
    var access: sdl.TextureAccess = undefined;
    try game_screen.query(&format, &access, null, null);
    if (format != .rgba8888) {
        @panic("Wrong texture format");
    }
    if (access != .streaming) {
        @panic("Wrong texture access");
    }
    return Nes{
        .rom = try Rom.readFromFile(rom_file, allocator),
        .game_screen = game_screen,
    };
}

pub fn startup(self: *Nes) !void {
    const mapper = try createMapper(&self.rom, &self.mapperMem);
    self.bus = Bus{
        .mapper = mapper,
        .ram = Ram{},
        .ppu = try PPU.init(mapper, &self.rom),
        .control = Control{},
        .apu = APU{},
    };
    self.cpu = CPU{
        .bus = &self.bus,
    };
    self.cpu.reset();
}

pub fn deinit(self: *Nes) void {
    self.rom.deinit();
}

pub fn handleKey(self: *Nes, event: sdl.Event) void {
    self.bus.control.handleKeyDownEvent(event);
}

pub fn runFrame(self: *Nes) !void {
    const data = try self.game_screen.lock(null);
    defer self.game_screen.unlock();
    for (0..dot_per_frame) |_| {
        try self.bus.ppu.clock(data.pixels);
        if (self.counter % 3 == 0) {
            try self.cpu.step();
        }
        if (self.bus.ppu.nmiSend) {
            self.bus.ppu.nmiSend = false;
            self.bus.nmiSet = true;
        }
        self.counter += 1;
    }
}

const MapperTag = enum(u8) {
    mapper0,
    // mapper1,
    // mapper2,
    // mapper3,
    // mapper4,
    _,
};

const MapperUnion = union(MapperTag) {
    mapper0: Mapper0,
};

const CrateMapperError = error{
    MapperNotSupported,
};

fn createMapper(rom: *Rom, mapperMem: *MapperUnion) !Mapper {
    switch (rom.header.getMapperID()) {
        0 => {
            mapperMem.* = MapperUnion{ .mapper0 = Mapper0.init(rom) };
            return Mapper.toMapper(&mapperMem.mapper0);
        },
        else => {
            return CrateMapperError.MapperNotSupported;
        },
    }
}
