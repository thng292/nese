const std = @import("std");
const Bus = @import("bus.zig").Bus;
const CPU = @import("cpu6502.zig").CPU;
const simple_prog = @import("cpu6502.zig").simple_prog;
const sdl = @import("zsdl");
const iNes = @import("ines.zig").ROM;
const Ram = @import("ram.zig");
const IO = @import("io.zig");
const Mapper0 = @import("mapper0.zig");
const PPU = @import("ppu2C02.zig");
const toMapper = @import("mapper.zig").toMapper;

const base_screen_w = 256;
const base_screen_h = 240;
const ppu_clock = 21477272 / 4;
const cpu_clock = ppu_clock / 3;

pub fn main() !void {
    try sdl.init(.{ .audio = true, .video = true });
    defer sdl.quit();
    const window = try sdl.Window.create(
        "nese",
        sdl.Window.pos_undefined,
        sdl.Window.pos_undefined,
        base_screen_w * 3,
        base_screen_h * 3,
        .{ .opengl = true, .allow_highdpi = true },
    );
    defer window.destroy();
    const renderer = try sdl.Renderer.create(window, -1, .{
        .accelerated = true,
        .present_vsync = false,
    });
    defer renderer.destroy();

    const testRomFile = try std.fs.cwd().openFile("test-rom/nestest.nes", .{});
    defer testRomFile.close();
    var test_rom = try iNes.readFromFile(testRomFile, std.heap.page_allocator);
    defer test_rom.deinit();

    var mapper0 = Mapper0.init(&test_rom);
    const mapper = toMapper(&mapper0);
    var ppu = try PPU.init(std.heap.page_allocator, mapper, &test_rom);
    defer ppu.deinit();
    var bus = Bus.init(mapper, &ppu);
    var cpu = CPU{
        .bus = &bus,
        .sp = 0xFF - 3,
    };
    cpu.reset();

    var event: sdl.Event = undefined;
    var start_frame = std.time.milliTimestamp();
    var run = true;
    var step = false;
    var thread = try std.Thread.spawn(
        .{ .allocator = std.heap.page_allocator },
        nesLogic,
        .{ &cpu, &ppu, &bus, &run, &step },
    );
    thread.detach();
    while (true) {
        while (sdl.pollEvent(&event)) {
            switch (event.type) {
                .quit => return,
                .keydown => {
                    switch (event.key.keysym.scancode) {
                        .h => try ppu.printNametable1(),
                        .p => run = !run,
                        .s => {
                            step = true;
                            run = true;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        try renderer.setDrawColor(.{
            .r = 255,
            .g = 255,
            .b = 255,
            .a = 255,
        });
        try renderer.clear();
        const now = std.time.milliTimestamp();
        const fps = @as(f32, 1.0) / @as(f32, @floatFromInt(now - start_frame));
        start_frame = now;
        try drawFPS(renderer, fps);
        renderer.present();
        sdl.delay(16);
    }
}

fn nesLogic(cpu: *CPU, ppu: *PPU, bus: *Bus, run: *bool, step: *bool) !void {
    const delay_time = std.time.ns_per_s / cpu_clock;
    while (true) {
        if (run.*) {
            const start = std.time.nanoTimestamp();
            bus.nmiSet = ppu.nmiSend;
            ppu.nmiSend = false;
            try cpu.step();
            ppu.clock();
            ppu.clock();
            ppu.clock();
            const now = std.time.nanoTimestamp();
            const elapsed = now - start;
            const tmp: i32 = @truncate(@divTrunc(delay_time - elapsed, std.time.ns_per_ms));
            sdl.delay(@bitCast(tmp));
        }
        if (step.*) {
            step.* = false;
            run.* = false;
        }
    }
}

fn drawFPS(renderer: *sdl.Renderer, fps: f32) !void {
    _ = renderer;
    _ = fps;
}
