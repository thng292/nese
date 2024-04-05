const std = @import("std");
const sdl = @import("zsdl");
const Nes = @import("nes/nes.zig");
const CPU = @import("nes/cpu6502.zig");

const base_screen_w = 256;
const base_screen_h = 240;
const scale = 4;
var count: u64 = 0;

fn audio_callback(
    userdata: ?*anyopaque,
    stream: [*c]u8,
    len: c_int,
) callconv(.C) void {
    _ = userdata;
    var i: usize = 0;
    var u64_stream: [*c]u64 = @alignCast(@ptrCast(stream));
    const new_len = @divTrunc(len, @sizeOf(u64));
    while (i < new_len) : (i += 1) {
        u64_stream[i] = count % 255;
        count +%= 1;
    }
    // std.debug.print("len: {}\n", .{len});
}

extern fn SDL_GetError() ?[*:0]const u8;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var args_it = try std.process.argsWithAllocator(allocator);
    defer args_it.deinit();
    var rom_name: ?[:0]const u8 = null;
    // Skip first args
    _ = args_it.next();
    if (args_it.next()) |arg| {
        rom_name = arg;
    }
    std.debug.print("\nRunning {?s}\n", .{rom_name});
    const out = try std.fs.cwd().createFile("log.txt", .{});
    defer out.close();
    // CPU.log_out = out.writer().any();

    try sdl.init(sdl.InitFlags.everything);
    defer sdl.quit();

    const audio_spec = sdl.AudioSpec{
        .channels = 1,
        .format = sdl.AUDIO_S16SYS,
        .freq = 44100,
        .samples = 1024,
        .callback = audio_callback,
    };
    var out_audio_spec: sdl.AudioSpec = undefined;

    const audio_dev_id = sdl.openAudioDevice(null, false, &audio_spec, &out_audio_spec, 0);
    // sdl.pauseAudioDevice(audio_dev_id, false);
    std.debug.print("audio_dev_id: {}, out_audio_spec: {}\n", .{ audio_dev_id, out_audio_spec });
    if (audio_dev_id == 0) {
        std.debug.print("{?s}\n", .{SDL_GetError()});
        return;
    }

    const main_wind = try Window.create(
        rom_name.?,
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
        sdl.showSimpleMessageBox(.{ .err = true }, "Create Texture Error", @errorName(err), main_wind.window) catch {};
        return;
    };
    defer game_screen.destroy();

    const testRomFile = std.fs.cwd().openFile(rom_name.?, .{}) catch |err| {
        sdl.showSimpleMessageBox(.{ .err = true }, "Open File Error", @errorName(err), main_wind.window) catch {};
        return;
    };
    defer testRomFile.close();
    var nes = Nes.init(allocator, testRomFile) catch |err| {
        sdl.showSimpleMessageBox(.{ .err = true }, "NES Init Error", @errorName(err), main_wind.window) catch {};
        return;
    };
    defer nes.deinit();
    nes.startup() catch |err| {
        sdl.showSimpleMessageBox(.{ .err = true }, "Startup Error", @errorName(err), main_wind.window) catch {};
        return;
    };
    // nes.cpu.pc = 0xc000;

    var event: sdl.Event = undefined;
    var run = true;
    var step = false;

    const frame_deadline = @as(f64, 1000) / 60;
    var start = sdl.getPerformanceCounter();
    var total_time: f64 = 0;
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
                            std.debug.print("count: {}\n", .{count});
                        },
                        .o => nes.bus.ppu.printOAM(),
                        .u => {
                            // if (CPU.log_out.context == CPU.no_log.context) {
                            //     CPU.log_out = out.writer().any();
                            // } else {
                            //     CPU.log_out = CPU.no_log;
                            // }
                        },
                        else => {},
                    }
                },
                else => {},
            }
            nes.handleKey(event);
        }

        if (total_time > frame_deadline) {
            total_time = 0;
            if (run) {
                // Run the whole frame at once
                nes.runFrame(game_screen) catch |err| {
                    sdl.showSimpleMessageBox(.{ .err = true }, "Error", @errorName(err), main_wind.window) catch {};
                    return;
                };
            }
            if (step) {
                step = false;
                run = false;
            }

            main_wind.renderer.copy(game_screen, null, &destiation_rect) catch |err| {
                sdl.showSimpleMessageBox(.{ .err = true }, "Error", @errorName(err), main_wind.window) catch {};
                return;
            };
            main_wind.renderer.present();
        }

        const performance_counter_freq: f64 = @floatFromInt(sdl.getPerformanceFrequency() / 1000);
        const now = sdl.getPerformanceCounter();
        const elapsed: f64 = @floatFromInt(now - start);
        const elapsedMS = elapsed / performance_counter_freq;
        total_time += elapsedMS;
        start = now;
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

test "NES Overall Test" {
    const allocator = std.testing.allocator;
    try sdl.init(sdl.InitFlags.everything);
    defer sdl.quit();

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

    const testRomFile = try std.fs.cwd().openFile("test-rom/donkey kong.nes", .{});
    defer testRomFile.close();
    var nes = try Nes.init(allocator, testRomFile);
    defer nes.deinit();
    try nes.startup();

    var event: sdl.Event = undefined;
    for (0..10000) |_| {
        while (sdl.pollEvent(&event)) {
            switch (event.type) {
                .quit => std.os.exit(0),
                else => {},
            }
        }

        try nes.runFrame(game_screen);

        try main_wind.renderer.copy(game_screen, null, &destiation_rect);
        main_wind.renderer.present();
    }
}
