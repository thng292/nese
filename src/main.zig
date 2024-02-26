const std = @import("std");
const sdl = @import("zsdl");
const Nes = @import("nes/nes.zig");
const CPU = @import("nes/cpu6502.zig");

const base_screen_w = 256;
const base_screen_h = 240;
const scale = 3;

pub fn main() !void {
    try sdl.init(sdl.InitFlags.everything);
    defer sdl.quit();

    // const out = try std.fs.cwd().openFile("me.txt", .{ .mode = .write_only });
    // defer out.close();
    // CPU.outf = out.writer().any();

    CPU.outf = std.io.getStdErr().writer().any();

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
        .streaming,
        base_screen_w,
        base_screen_h,
    );
    defer game_screen.destroy();

    const testRomFile = try std.fs.cwd().openFile("test-rom/nestest.nes", .{});
    // const testRomFile = try std.fs.cwd().openFile("test-rom/donkey kong.nes", .{});
    defer testRomFile.close();
    var nes = try Nes.init(std.heap.page_allocator, testRomFile);
    defer nes.deinit();
    try nes.startup();
    // nes.cpu.pc = 0xc000;

    var event: sdl.Event = undefined;
    var run = true;
    var step = false;

    var start = std.time.milliTimestamp();
    while (true) {
        while (sdl.pollEvent(&event)) {
            switch (event.type) {
                .quit => std.os.exit(0),
                .keydown => {
                    switch (event.key.keysym.scancode) {
                        .p => run = !run,
                        .i => {
                            step = true;
                            run = true;
                        },
                        else => {
                            nes.handleKey(event);
                        },
                    }
                },
                else => {},
            }
        }

        if (run) {
            // Run the whole frame at once
            // Scanline by scanline
            try nes.runFrame(game_screen);
        }
        if (step) {
            step = false;
            run = false;
        }

        try main_wind.renderer.copyEx(game_screen, null, &destiation_rect, 0, null, .none);
        main_wind.renderer.present();

        const now = std.time.milliTimestamp();
        const elapsed = now - start;
        start = now;
        const tmp = 17 - elapsed;
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
