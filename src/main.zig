const std = @import("std");
const sdl = @import("zsdl");

const base_screen_w = 256;
const base_screen_h = 240;
const scale = 3;

pub fn main() !void {
    try sdl.init(sdl.InitFlags.everything);
    defer sdl.quit();

    // const out = try std.fs.cwd().openFile("out2.txt", .{ .mode = .write_only });
    // defer out.close();
    // CPU.outf = out.writer().any();

    // CPU.outf = std.io.getStdOut().writer().any();

    const main_wind = try Window.create(
        "Nese",
        base_screen_w * scale,
        base_screen_h * scale,
    );
    defer main_wind.destroy();

    const destiation_rect = sdl.Rect{
        .x = 0,
        .y = 0,
        .h = base_screen_h * scale,
        .w = base_screen_w * scale,
    };
    const game_screen = try main_wind.renderer.createTexture(
        .rgba8888,
        .target,
        base_screen_w,
        base_screen_h,
    );
    defer game_screen.destroy();

    const testRomFile = try std.fs.cwd().openFile("test-rom/nestest.nes", .{});
    // const testRomFile = try std.fs.cwd().openFile("test-rom/donkey kong.nes", .{});
    defer testRomFile.close();
    var test_rom = try iNes.readFromFile(testRomFile, std.heap.page_allocator);
    defer test_rom.deinit();

    var mapper0 = Mapper0.init(&test_rom);
    const mapper = toMapper(&mapper0);
    var ppu = try PPU.init(mapper, &test_rom);
    var ram = Ram{};
    var io = Control{};
    var apu = APU{};
    var bus = Bus.init(mapper, &ppu, &ram, &io, &apu);
    var cpu = CPU{
        .bus = &bus,
    };
    cpu.reset();

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
                        // .s => {
                        //     step = true;
                        //     run = true;
                        // },
                        else => {
                            io.handleKeyDownEvent(event);
                        },
                    }
                },
                else => {},
            }
        }

        try main_wind.renderer.setDrawColor(.{
            .r = 255,
            .g = 255,
            .b = 255,
            .a = 255,
        });
        try main_wind.renderer.clear();

        if (run) {
            // Run the whole frame at once
            // Scanline by scanline
            try main_wind.renderer.setTarget(game_screen);
            for (0..dot_per_frame) |_| {
                try ppu.clock(main_wind.renderer);
                if (counter % 3 == 0) {
                    try cpu.step();
                }
                if (ppu.nmiSend) {
                    ppu.nmiSend = false;
                    bus.nmiSet = true;
                }
                // ppu.status.VBlank = true;
                counter += 1;
                // if (counter == 1_000_000) {
                //     std.os.exit(0);
                // }
            }
        }
        if (step) {
            step = false;
            run = false;
        }

        try main_wind.renderer.setTarget(null);
        try main_wind.renderer.copyEx(game_screen, null, &destiation_rect, 0, null, .none);
        main_wind.renderer.present();

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

const Window = struct {
    window: *sdl.Window,
    renderer: *sdl.Renderer,

    pub fn create(name: [:0]const u8, width: i32, height: i32) !Window {
        const window = try sdl.Window.create(
            name,
            sdl.Window.pos_undefined,
            sdl.Window.pos_undefined,
            width,
            height,
            .{ .allow_highdpi = true, .opengl = true },
        );
        const renderer = try sdl.Renderer.create(window, -1, .{
            .accelerated = true,
            .present_vsync = false,
        });
        return Window{
            .window = window,
            .renderer = renderer,
        };
    }

    pub fn destroy(self: *const Window) void {
        self.window.destroy();
        self.renderer.destroy();
    }
};

const Bus = @import("bus.zig").Bus;
const CPU = @import("cpu6502.zig");
const iNes = @import("ines.zig").ROM;
const Ram = @import("ram.zig");
const Control = @import("control.zig");
const Mapper0 = @import("mapper0.zig");
const PPU = @import("ppu2C02.zig");
const APU = @import("apu2A03.zig");
const toMapper = @import("mapper.zig").toMapper;
