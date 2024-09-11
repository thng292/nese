const std = @import("std");

const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");

const Config = @import("config.zig");
const MainMenu = @import("main_menu.zig");
const Callable = @import("callable.zig").Callable;
const Strings = @import("i18n.zig");

const Nes = @import("nes/nes.zig");
const CPU = @import("nes/cpu6502.zig");
const APU = @import("nes/apu2A03.zig");

const config_file_path = "./config.json";

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const cwd = std.fs.cwd();

    const strings = Strings{};

    const config_file = cwd.openFile(config_file_path, .{
        .mode = .read_only,
    }) catch undefined;
    var config = Config.load(config_file, gpa) catch
        try Config.initDefault(gpa);
    defer {
        var err: anyerror = undefined;
        if (cwd.openFile(config_file_path, .{ .mode = .write_only })) |file| {
            config.save(file) catch |e| {
                err = e;
            };
        } else |e| {
            err = e;
        }
        config.deinit();
    }

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
        .{ .present_mode = .fifo },
    );

    // const primary_monitor_maybe = zglfw.Monitor.getPrimary();
    // const refresh_rate = out: {
    //     if (primary_monitor_maybe) |primary_monitor| {
    //         if (primary_monitor.getVideoMode()) |video_mode| {
    //             break :out video_mode.refresh_rate;
    //         } else |_| {
    //             try std.fmt.format(stdout_writer, "Can't get video mode! Setting refresh rate to 60", .{});
    //             break :out 60;
    //         }
    //     } else {
    //         try std.fmt.format(stdout_writer, "No primary monitor found! Setting refresh rate to 60", .{});
    //         break :out 60;
    //     }
    // };

    defer gctx.destroy(gpa);
    std.log.info("Created Graphics Context", .{});

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    zgui.init(gpa);
    defer zgui.deinit();
    zgui.io.setConfigFlags(.{
        .nav_enable_keyboard = true,
        .nav_enable_gamepad = true,
        .dpi_enable_scale_fonts = true,
        .dpi_enable_scale_viewport = true,
    });
    std.log.info("Initialized ImGUI", .{});

    zgui.backend.init(
        window,
        gctx.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
        @intFromEnum(wgpu.TextureFormat.undef),
    );
    defer zgui.backend.deinit();
    std.log.info("Initialized ImGUI's backend", .{});

    zgui.getStyle().scaleAllSizes(scale_factor * config.ui_scale);

    // var arg_it = try std.process.argsWithAllocator(gpa);
    // _ = arg_it.next(); // skip first arg

    // const rom_file = try cwd.openFile(
    //     arg_it.next().?,
    //     .{ .mode = .read_only },
    // );
    // arg_it.deinit();
    // var nes = try Nes.init(gpa, rom_file, gctx);
    // defer nes.deinit();
    // try nes.startup(APU{});
    std.log.info("Initialized Nes", .{});

    const OpenGameContext = struct {
        const Self = @This();
        pub fn openGame(self: *Self, game_path: []u8) void {
            _ = self;
            std.log.info("Opening: {s}", .{game_path});
        }
    };
    var openGameContext = OpenGameContext{};

    var main_menu_state = try MainMenu.init(
        gpa,
        &config,
        MainMenu.OpenGameCallable.init(
            OpenGameContext.openGame,
            &openGameContext,
            null,
        ),
    );
    defer main_menu_state.deinit();

    // const frame_deadline = @as(f64, 1) / 60;
    // var frame_accumulated: f64 = 0;
    // var frame_rate: f64 = 0;
    // var start = zglfw.getTime();

    std.log.info("Starting main loop", .{});
    while (!window.shouldClose()) {
        zglfw.pollEvents();
        // nes.handleKey(window);

        // const now = zglfw.getTime();
        // const delta = now - start;
        // frame_accumulated += delta;
        // start = now;

        // if (refresh_rate == 60 or frame_accumulated >= frame_deadline) {
        //     defer {
        //         frame_rate = @as(f32, 1) / frame_accumulated;
        //         frame_accumulated -= frame_deadline;
        //         while (frame_accumulated >= frame_deadline) {
        //             frame_accumulated -= frame_deadline;
        //         }
        //     }
        zgui.backend.newFrame(
            gctx.swapchain_descriptor.width,
            gctx.swapchain_descriptor.height,
        );

        if (zgui.beginMainMenuBar()) {
            defer zgui.endMainMenuBar();
            if (zgui.beginMenu(strings.main_menu_bar.file, true)) {
                defer zgui.endMenu();
                if (zgui.menuItem(strings.file_menu_items.load_game, .{})) {
                    // Handle open action
                }
                if (zgui.menuItem(strings.file_menu_items.load_dir, .{})) {
                    // Handle open action
                }
                if (zgui.menuItem(strings.file_menu_items.exit, .{})) {
                    return;
                }
            }
            if (zgui.beginMenu(strings.main_menu_bar.emulation, true)) {
                defer zgui.endMenu();
                if (zgui.menuItem(strings.emulation_menu_items.pause, .{})) {
                    // Handle about action
                }
                if (zgui.menuItem(strings.emulation_menu_items.stop, .{})) {
                    // Handle about action
                }
                if (zgui.menuItem(strings.emulation_menu_items.take_snapshot, .{})) {
                    // Handle about action
                }
                if (zgui.menuItem(strings.emulation_menu_items.config, .{})) {
                    // Handle about action
                }
            }
            if (zgui.beginMenu(strings.main_menu_bar.help, true)) {
                defer zgui.endMenu();
                if (zgui.menuItem(strings.help_menu_items.about, .{})) {
                    // Handle about action
                }
            }
        }

        main_menu_state.draw(strings);

        if (config.show_metric) {
            zgui.showMetricsWindow(null);
        }

        zgui.setNextWindowSize(.{
            .w = Nes.SCREEN_SIZE.width,
            .h = Nes.SCREEN_SIZE.height,
            .cond = .first_use_ever,
        });

        // const texture_id = try nes.runFrame();
        // if (zgui.begin("Main Game", .{})) {
        //     zgui.image(texture_id, .{
        //         .w = Nes.SCREEN_SIZE.width * config.scale,
        //         .h = Nes.SCREEN_SIZE.height * config.scale,
        //     });
        // }
        // zgui.end();

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
    // }
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
