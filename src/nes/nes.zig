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
rom: Rom,
cpu: CPU,
bus: Bus,
mapperMem: MapperUnion,
counter: u128 = 0,

pub fn init(allocator: std.mem.Allocator, rom_file: std.fs.File) !Nes {
    var res = Nes{
        .rom = try Rom.readFromFile(rom_file, allocator),
        .cpu = undefined,
        .bus = undefined,
        .mapperMem = undefined,
    };
    const mapper = try createMapper(&res.rom, &res.mapperMem);
    res.bus = Bus{
        .mapper = mapper,
        .ram = Ram{},
        .ppu = try PPU.init(mapper, &res.rom),
        .control = Control{},
        .apu = APU{},
    };
    res.cpu = CPU{
        .bus = undefined,
    };
    return res;
}

pub fn startup(self: *Nes) void {
    self.cpu.bus = &self.bus;
    self.cpu.reset();
}

pub fn deinit(self: *Nes) void {
    self.rom.deinit();
}

pub fn handleKey(self: *Nes, event: sdl.Event) void {
    self.bus.control.handleKeyDownEvent(event);
}

pub fn runFrame(self: *Nes, renderer: *sdl.Renderer) !void {
    for (0..dot_per_frame) |_| {
        try self.bus.ppu.clock(renderer);
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
            return Mapper.toMapper(&mapperMem.*.mapper0);
        },
        else => {
            return CrateMapperError.MapperNotSupported;
        },
    }
}
