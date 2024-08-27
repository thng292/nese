const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");

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
const Mapper4 = @import("mapper4.zig");

const Nes = @This();
const dot_per_frame = 341 * 262;
const channel = 4;
pub const SCREEN_SIZE = .{ .width = 256, .height = 240 };

rom: Rom = undefined,
cpu: CPU = undefined,
bus: Bus = undefined,
mapperMem: MapperUnion = undefined,
counter: u64 = 0,
gctx: *zgpu.GraphicsContext,
screen_texture_handle: zgpu.TextureHandle,
screen_texture_view_handle: zgpu.TextureViewHandle,
texture_data: []u8,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, rom_file: std.fs.File, gctx: *zgpu.GraphicsContext) !Nes {
    const texture_handle = gctx.createTexture(.{
        .format = zgpu.imageInfoToTextureFormat(4, 1, false),
        .size = .{
            .width = SCREEN_SIZE.width,
            .height = SCREEN_SIZE.height,
            .depth_or_array_layers = 1,
        },
        .usage = .{ .copy_dst = true, .texture_binding = true },
        .mip_level_count = 1,
    });
    const texture_view = gctx.createTextureView(texture_handle, .{});
    std.log.info("Created screen texture\n", .{});

    return Nes{
        .allocator = allocator,
        .rom = try Rom.readFromFile(rom_file, allocator),
        .gctx = gctx,
        .screen_texture_handle = texture_handle,
        .screen_texture_view_handle = texture_view,
        .texture_data = try allocator.alloc(u8, SCREEN_SIZE.width * SCREEN_SIZE.height * channel),
    };
}

pub fn deinit(self: *Nes) void {
    self.rom.deinit();
    self.allocator.free(self.texture_data);
    self.gctx.destroyResource(self.screen_texture_handle);
}

pub fn startup(self: *Nes, apu: APU) !void {
    std.log.info("ROM Info: {}\n", .{self.rom.header});
    const mapper = try self.createMapper();
    self.bus = Bus{
        .mapper = mapper,
        .ram = Ram{},
        .ppu = try PPU.init(mapper),
        .control = Control{
            .controller2 = .{
                .Up = .up,
                .Down = .down,
                .Left = .left,
                .Right = .right,
                .A = .j,
                .B = .k,
                .Start = .slash,
                .Select = .l,
            },
        },
        .apu = apu,
    };
    self.cpu = CPU{
        .bus = &self.bus,
    };
    self.cpu.reset();
}

pub fn handleKey(self: *Nes, window: *zglfw.Window) void {
    self.bus.control.handleKeyEvent(window);
}

fn clock(self: *Nes) void {
    try self.bus.ppu.clock(self.texture_data);
    if (self.counter % 3 == 0) {
        try self.cpu.step();
    }
    if (self.bus.ppu.nmiSend) {
        self.bus.ppu.nmiSend = false;
        self.bus.nmiSet = true;
    }
    if (self.bus.ppu.irqSend) {
        self.bus.ppu.irqSend = false;
        self.bus.irqSet = true;
    }
    self.counter +%= 1;
}

pub fn runFrame(self: *Nes) !zgpu.wgpu.TextureView {
    for (0..dot_per_frame) |_| {
        self.clock();
    }

    self.gctx.queue.writeTexture(
        .{ .texture = self.gctx.lookupResource(self.screen_texture_handle).? },
        .{
            .bytes_per_row = SCREEN_SIZE.width * channel,
            .rows_per_image = SCREEN_SIZE.height,
        },
        .{ .width = SCREEN_SIZE.width, .height = SCREEN_SIZE.height },
        u8,
        self.texture_data,
    );
    return self.gctx.lookupResource(self.screen_texture_view_handle).?;
}
//
// pub fn draw_CHR(self: *Nes, game_screen: *sdl.Texture) !void {
//     const data = try game_screen.lock(null);
//     defer game_screen.unlock();
//     self.bus.ppu.draw_chr(data.pixels);
// }

const MapperTag = enum(u8) {
    mapper0,
    mapper1,
    mapper2,
    mapper3,
    mapper4,
    _,
};

const MapperUnion = union(MapperTag) {
    mapper0: Mapper0,
    mapper1: Mapper1,
    mapper2: Mapper2,
    mapper3: Mapper3,
    mapper4: Mapper4,
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
        4 => {
            self.mapperMem = MapperUnion{ .mapper4 = Mapper4.init(&self.rom) };
            return self.mapperMem.mapper4.toMapper();
        },
        else => {
            return CrateMapperError.MapperNotSupported;
        },
    }
}
