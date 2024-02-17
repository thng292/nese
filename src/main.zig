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
    try sdl.init(sdl.InitFlags.everything);
    defer sdl.quit();
    const window = try sdl.Window.create(
        "nese",
        sdl.Window.pos_undefined,
        sdl.Window.pos_undefined,
        base_screen_w * 3,
        base_screen_h * 3,
        .{ .allow_highdpi = true, .vulkan = true },
    );
    defer window.destroy();
    const renderer = try sdl.Renderer.create(window, -1, .{
        .accelerated = true,
        .present_vsync = false,
    });
    defer renderer.destroy();

    const scale = 2;
    const destiation_rect = sdl.Rect{
        .x = 0,
        .y = 0,
        .h = base_screen_h * scale,
        .w = base_screen_w * scale,
    };
    const game_screen = try renderer.createTexture(
        .rgba8888,
        .target,
        base_screen_w,
        base_screen_h,
    );
    defer game_screen.destroy();

    // const testRomFile = try std.fs.cwd().openFile("test-rom/nestest.nes", .{});
    const testRomFile = try std.fs.cwd().openFile("test-rom/donkey kong.nes", .{});
    defer testRomFile.close();
    var test_rom = try iNes.readFromFile(testRomFile, std.heap.page_allocator);
    defer test_rom.deinit();

    var mapper0 = Mapper0.init(&test_rom);
    const mapper = toMapper(&mapper0);
    var ppu = try PPU.init(mapper, &test_rom);
    var bus = Bus.init(mapper, &ppu);
    var cpu = CPU{
        .bus = &bus,
    };
    cpu.reset();

    // for (0xFFFA..0x10000) |i| {
    //     std.debug.print("{x}: {x}\n", .{ i, bus.read(@truncate(i)) });
    // }
    // std.os.exit(0);

    var event: sdl.Event = undefined;
    var run = true;
    var step = false;
    var counter: u128 = 0;
    const dot_per_frame = 341 * 262;

    var start = std.time.milliTimestamp();
    while (true) {
        while (sdl.pollEvent(&event)) {
            switch (event.type) {
                .quit => std.os.exit(0),
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

        if (run) {
            // Run the whole frame at once
            // Scanline by scanline
            try renderer.setTarget(game_screen);
            for (0..dot_per_frame) |_| {
                if (counter % 3 == 0) {
                    if (ppu.nmiSend) {
                        bus.nmiSet = true;
                        ppu.nmiSend = false;
                    }
                    try cpu.step();
                }
                try ppu.clock(renderer);
                // ppu.status.VBlank = true;
                counter += 1;
                if (counter == 1_000_000) {
                    std.os.exit(0);
                }
            }
        }
        if (step) {
            step = false;
            run = false;
        }

        try renderer.setTarget(null);
        try renderer.copyEx(game_screen, null, &destiation_rect, 0, null, .none);
        renderer.present();

        const now = std.time.milliTimestamp();
        const elapsed = now - start;
        start = now;
        const tmp = 16 - elapsed;
        if (tmp > 0) {
            const tt: u64 = @bitCast(tmp);
            sdl.delay(@truncate(tt));
        }
    }
}
