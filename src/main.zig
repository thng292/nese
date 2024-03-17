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

    // CPU.outf = std.io.getStdErr().writer().any();

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
    const game_screen = main_wind.renderer.createTexture(
        .rgba8888,
        .streaming,
        base_screen_w,
        base_screen_h,
    ) catch |err| {
        sdl.showSimpleMessageBox(.{ .err = true }, "Error", @errorName(err), main_wind.window) catch {};
        return;
    };
    defer game_screen.destroy();

    const testRomFile = std.fs.cwd().openFile("test-rom/donkey kong.nes", .{}) catch |err| {
        // const testRomFile = std.fs.cwd().openFile("test-rom/nestest.nes", .{}) catch |err| {
        sdl.showSimpleMessageBox(.{ .err = true }, "Error", @errorName(err), main_wind.window) catch {};
        return;
    };
    defer testRomFile.close();
    var nes = Nes.init(std.heap.page_allocator, testRomFile) catch |err| {
        sdl.showSimpleMessageBox(.{ .err = true }, "Error", @errorName(err), main_wind.window) catch {};
        return;
    };
    defer nes.deinit();
    nes.startup() catch |err| {
        sdl.showSimpleMessageBox(.{ .err = true }, "Error", @errorName(err), main_wind.window) catch {};
        return;
    };
    // nes.cpu.pc = 0xc000;

    var event: sdl.Event = undefined;
    var run = true;
    var step = false;

    var start = sdl.getPerformanceCounter();
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
            nes.runFrame(game_screen) catch |err| {
                sdl.showSimpleMessageBox(.{ .err = true }, "Error", @errorName(err), main_wind.window) catch {};
                return;
            };
        }
        if (step) {
            step = false;
            run = false;
        }

        main_wind.renderer.copyEx(game_screen, null, &destiation_rect, 0, null, .none) catch |err| {
            sdl.showSimpleMessageBox(.{ .err = true }, "Error", @errorName(err), main_wind.window) catch {};
            return;
        };
        main_wind.renderer.present();

        const performance_counter_freq: f64 = @floatFromInt(sdl.getPerformanceFrequency() / 1000);
        const now = sdl.getPerformanceCounter();
        const elapsed: f64 = @floatFromInt(now - start);
        const elapsedMS = elapsed / performance_counter_freq;
        start = now;
        const frame_deadline = @as(f64, 1000) / 60;
        const delay: i64 = @intFromFloat(@floor(frame_deadline - elapsedMS));
        if (delay > 0) {
            const tmp: u64 = @bitCast(delay);
            sdl.delay(@truncate(tmp));
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
