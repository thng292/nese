const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");

const CPU = @import("cpu6502.zig");
const PPU = @import("ppu2C02.zig");
const APU = @import("apu2A03.zig");
const Bus = @import("bus.zig").Bus;
const Rom = @import("ines.zig").ROM;
const Ram = @import("ram.zig");
const Control = @import("control.zig");
const mapper_helpers = @import("mapper_helpers.zig");

const Nes = @This();
const dot_per_frame = 341 * 262;
const channel = 4;
pub const SCREEN_SIZE = .{ .width = 256, .height = 240 };

cpu: CPU = undefined,
rom: Rom = undefined,
bus: Bus = undefined,
mapperMem: mapper_helpers.MapperUnion = undefined,
counter: u64 = 0,
gctx: *zgpu.GraphicsContext,
screen_texture_handle: zgpu.TextureHandle,
screen_texture_view_handle: zgpu.TextureViewHandle,
texture_data: []u8,
allocator: std.mem.Allocator,

pub fn init(
    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    rom_file: std.fs.File,
    controllers: [2]Control.ControllerMap,
) !Nes {
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

    var result = Nes{
        .allocator = allocator,
        .rom = try Rom.readFromFile(rom_file, allocator),
        .gctx = gctx,
        .screen_texture_handle = texture_handle,
        .screen_texture_view_handle = texture_view,
        .texture_data = try allocator.alloc(u8, SCREEN_SIZE.width * SCREEN_SIZE.height * channel),
    };
    try result.startup(controllers);
    return result;
}

pub fn deinit(self: *Nes) void {
    self.rom.deinit(self.allocator);
    self.allocator.free(self.texture_data);
    self.gctx.destroyResource(self.screen_texture_handle);
}

fn startup(
    self: *Nes,
    controllers: [2]Control.ControllerMap,
) !void {
    std.log.info("ROM Info: {}\n", .{self.rom.header});
    const mapper = try mapper_helpers.createMapper(self.rom.header.getMapperID(), &self.mapperMem, &self.rom);
    self.bus = Bus{
        .mapper = mapper,
        .ram = Ram{},
        .ppu = try PPU.init(mapper),
        .control = Control{
            .controller1 = Control.ControllerState{ .map = controllers[0] },
            .controller2 = Control.ControllerState{ .map = controllers[1] },
        },
        .apu = APU{},
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
