const std = @import("std");

const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");

const Config = @import("config.zig");

const Nes = @import("nes/nes.zig");
const CPU = @import("nes/cpu6502.zig");
const APU = @import("nes/apu2A03.zig");

const config_file_path = "./config.json";

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const cwd = std.fs.cwd();

    if (cwd.access(config_file_path, .{ .mode = .read_only })) |_| {} else |_| {
        const file = try cwd.createFile(config_file_path, .{});
        const config = Config{};
        try config.save(file);
        file.close();
        std.log.info("Created Config file", .{});
    }

    const config_file = try cwd.openFile(config_file_path, .{
        .mode = .read_only,
    });
    const config = try Config.load(config_file, gpa);

    try zglfw.init();
    defer zglfw.terminate();
    zglfw.windowHintTyped(.client_api, .no_api);
    std.log.info("Initialized GLFW", .{});

    const window = try zglfw.Window.create(
        @intFromFloat(Nes.SCREEN_SIZE.width * config.scale),
        @intFromFloat(Nes.SCREEN_SIZE.height * config.scale),
        "Nese",
        null,
    );
    defer window.destroy();
    window.setSizeLimits(Nes.SCREEN_SIZE.width, Nes.SCREEN_SIZE.height, -1, -1);
    std.log.info("Created Window", .{});

    const gctx = try zgpu.GraphicsContext.create(
        gpa,
        .{
            .window = window,
            .fn_getTime = @ptrCast(&zglfw.getTime),
            .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
            .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
            .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
            .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
            .fn_getWaylandDisplay = @ptrCast(&zglfw.getWaylandDisplay),
            .fn_getWaylandSurface = @ptrCast(&zglfw.getWaylandWindow),
            .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
        },
        .{ .present_mode = if (config.vsync) .fifo else .mailbox },
    );
    defer gctx.destroy(gpa);
    std.log.info("Created Graphics Context", .{});

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    zgui.init(gpa);
    defer zgui.deinit();
    std.log.info("Initialized ImGUI", .{});

    zgui.backend.init(
        window,
        gctx.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
        @intFromEnum(wgpu.TextureFormat.undef),
    );
    defer zgui.backend.deinit();
    std.log.info("Initialized ImGUI's backend", .{});

    zgui.getStyle().scaleAllSizes(scale_factor);

    var arg_it = std.process.args();
    _ = arg_it.next(); // skip first arg

    const rom_file = try cwd.openFile(
        arg_it.next().?,
        .{ .mode = .read_only },
    );
    var nes = try Nes.init(gpa, rom_file, gctx);
    defer nes.deinit();
    try nes.startup(APU{});
    std.log.info("Initialized Nes", .{});

    const frame_deadline = @as(f64, 1) / 60;
    const input_deadline = @as(f64, 1) / @as(f64, @floatFromInt(config.input_poll_rate));

    var start = zglfw.getTime();
    var input_accumulated: f64 = 0;
    var frame_accumulated: f64 = 0;

    var delta: f64 = 0;
    var input_poll_rate: f64 = 0;
    var frame_rate: f64 = 0;

    std.log.info("Starting main loop", .{});
    while (!window.shouldClose()) {
        defer {
            const now = zglfw.getTime();
            delta = now - start;
            frame_accumulated += delta;
            input_accumulated += delta;
            start = now;

            input_poll_rate = @as(f64, 1) / input_accumulated;
            input_accumulated -= input_deadline;
            while (input_accumulated >= input_deadline) {
                input_accumulated -= input_deadline;
            }

            preciseSleep(@min(input_deadline - delta, frame_deadline - delta));
        }

        zglfw.pollEvents();
        nes.handleKey(window);

        if (frame_accumulated >= frame_deadline) {
            defer {
                frame_rate = @as(f32, 1) / frame_accumulated;
                frame_accumulated -= frame_deadline;
                while (frame_accumulated >= frame_deadline) {
                    frame_accumulated -= frame_deadline;
                }
            }
            zgui.backend.newFrame(
                gctx.swapchain_descriptor.width,
                gctx.swapchain_descriptor.height,
            );

            // zgui.showMetricsWindow(null);

            if (config.show_metric) {
                if (zgui.begin("Metric", .{})) {
                    zgui.bulletText("Input poll rate: {d:.2}", .{input_poll_rate});
                    zgui.bulletText("Frame rate: {d:.2}", .{frame_rate});
                }
                zgui.end();
            }

            // Set the starting window position and size to custom values

            zgui.setNextWindowSize(.{
                .w = Nes.SCREEN_SIZE.width,
                .h = Nes.SCREEN_SIZE.height,
                .cond = .first_use_ever,
            });

            const texture_id = try nes.runFrame();
            if (zgui.begin("Main Game", .{})) {
                zgui.image(texture_id, .{
                    .w = Nes.SCREEN_SIZE.width * config.scale,
                    .h = Nes.SCREEN_SIZE.height * config.scale,
                });
            }
            zgui.end();

            const swapchain_texv = gctx.swapchain.getCurrentTextureView();
            defer swapchain_texv.release();

            const commands = commands: {
                const encoder = gctx.device.createCommandEncoder(null);
                defer encoder.release();

                // GUI pass
                {
                    const pass = zgpu.beginRenderPassSimple(encoder, .load, swapchain_texv, null, null, null);
                    defer zgpu.endReleasePass(pass);
                    zgui.backend.draw(pass);
                }

                break :commands encoder.finish(null);
            };
            defer commands.release();

            gctx.submit(&.{commands});
            _ = gctx.present();
        }
    }
}

// https://blog.bearcats.nl/accurate-sleep-function/

fn preciseSleep(time_second: f64) void {
    var time_s = time_second;
    const StaticState = struct {
        var estimate: f64 = 5e-3;
        var mean: f64 = 5e-3;
        var m2: f64 = 0;
        var count: u64 = 1;
    };

    while (time_s > StaticState.estimate) {
        const start = zglfw.getTime();
        std.time.sleep(1 * std.time.ns_per_s);
        const end = zglfw.getTime();

        const observed = end - start;
        time_s -= observed;

        StaticState.count += 1;
        const delta = observed - StaticState.mean;
        StaticState.mean += delta / @as(f64, @floatFromInt(StaticState.count));
        StaticState.m2 += delta * (observed - StaticState.mean);
        const stddev = std.math.sqrt(
            StaticState.m2 / @as(f64, @floatFromInt(StaticState.count)),
        );
        StaticState.estimate = StaticState.mean + stddev;
    }

    const start = zglfw.getTime();
    while (zglfw.getTime() - start < time_s) {}
}
