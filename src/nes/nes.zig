const std = @import("std");
const sdl = @import("zsdl");

const Bus = @import("bus.zig").Bus;
const CPU = @import("cpu6502.zig");
const Rom = @import("ines.zig").ROM;
const Ram = @import("ram.zig");
const Control = @import("control.zig");
const PPU = @import("ppu2C02.zig");
const APU = @import("apu2A03.zig");

const Mapper = @import("mapper.zig");
const Mapper0 = @import("mapper0.zig");
const Mapper1 = @import("mapper1.zig");
const Mapper2 = @import("mapper2.zig");
const Mapper3 = @import("mapper3.zig");

const Nes = @This();
const dot_per_frame = 341 * 262;

rom: Rom = undefined,
cpu: CPU = undefined,
bus: Bus = undefined,
mapperMem: MapperUnion = undefined,
counter: u64 = 0,

pub inline fn init(allocator: std.mem.Allocator, rom_file: std.fs.File) !Nes {
    return Nes{
        .rom = try Rom.readFromFile(rom_file, allocator),
    };
}

pub fn startup(self: *Nes, apu: APU) !void {
    // std.debug.print("ROM Info: \n{}\n", .{self.rom.header});
    const mapper = try self.createMapper();
    self.bus = Bus{
        .mapper = mapper,
        .ram = Ram{},
        .ppu = try PPU.init(mapper),
        .control = Control{
            .controller2 = .{
                .Up = sdl.Keycode.up,
                .Down = sdl.Keycode.down,
                .Left = sdl.Keycode.left,
                .Right = sdl.Keycode.right,
                .A = sdl.Keycode.j,
                .B = sdl.Keycode.k,
                .Start = sdl.Keycode.slash,
                .Select = sdl.Keycode.l,
            },
        },
        .apu = apu,
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
    switch (event.type) {
        .keydown => self.bus.control.handleKeyDownEvent(event),
        .keyup => self.bus.control.handleKeyUpEvent(event),
        else => {},
    }
}

pub fn runFrame(self: *Nes, game_screen: *sdl.Texture) !void {
    const data = try game_screen.lock(null);
    defer game_screen.unlock();
    for (0..dot_per_frame) |_| {
        try self.bus.ppu.clock(data.pixels);
        if (self.counter % 3 == 0) {
            try self.cpu.step();
        }
        if (self.bus.ppu.nmiSend) {
            self.bus.ppu.nmiSend = false;
            self.bus.nmiSet = true;
        }
        self.counter +%= 1;
    }
}

const MapperTag = enum(u8) {
    mapper0,
    mapper1,
    mapper2,
    mapper3,
    // mapper4,
    _,
};

const MapperUnion = union(MapperTag) {
    mapper0: Mapper0,
    mapper1: Mapper1,
    mapper2: Mapper2,
    mapper3: Mapper3,
};

const CrateMapperError = error{
    MapperNotSupported,
};

fn createMapper(self: *Nes) !Mapper {
    switch (self.rom.header.getMapperID()) {
        0 => {
            self.mapperMem = MapperUnion{ .mapper0 = Mapper0.init(&self.rom) };
            return self.mapperMem.mapper0.toMapper();
        },
        1 => {
            self.mapperMem = MapperUnion{ .mapper1 = Mapper1.init(&self.rom) };
            return self.mapperMem.mapper1.toMapper();
        },
        2 => {
            self.mapperMem = MapperUnion{ .mapper2 = Mapper2.init(&self.rom) };
            return self.mapperMem.mapper2.toMapper();
        },
        3 => {
            self.mapperMem = MapperUnion{ .mapper3 = Mapper3.init(&self.rom) };
            return self.mapperMem.mapper3.toMapper();
        },
        else => {
            return CrateMapperError.MapperNotSupported;
        },
    }
}
