const std = @import("std");

const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");

const Callable = @import("data/callable.zig").Callable;
const Config = @import("data/config.zig");
const Strings = @import("data/i18n.zig");

const ConfigRepo = @import("repo/config_repo.zig");
const GameRepo = @import("repo/game_repo.zig");
const LanguageRepo = @import("repo/language_repo.zig");

const MainMenu = @import("ui/main_menu.zig");
const ConfigMenu = @import("ui/config_menu.zig");
const MenuBar = @import("ui/menu_bar.zig");

const Nes = @import("nes/nes.zig");
const CPU = @import("nes/cpu6502.zig");
const APU = @import("nes/apu2A03.zig");

const config_file_path = "./config.json";

const Screen = enum {
    MainMenuScreen,
    GameScreen,
};

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const shared_string_buffer = try gpa.allocSentinel(u8, 1024, 0);
    defer gpa.free(shared_string_buffer);
    @memset(shared_string_buffer, 0);

    var config_repo = try ConfigRepo.init(gpa);
    var language_repo = try LanguageRepo.init(gpa);
    var game_repo = try GameRepo.init(gpa);
    // try game_repo.addDirectoryCopy(
    //     try std.fs.cwd().realpathAlloc(gpa, "test-rom"),
    // );

    defer {
        config_repo.deinit();
        language_repo.deinit();
        game_repo.deinit();
    }

    language_repo.loadLangugeFromFile(
        config_repo.config.general.language_file_path,
    ) catch {
        try language_repo.useDefaultLanguage();
    };
    const config = &config_repo.config;
    const strings = &language_repo.parsed.?.value;

    try zglfw.init();
    defer zglfw.terminate();
    zglfw.windowHintTyped(.client_api, .no_api);
    std.log.info("Initialized GLFW", .{});

    const window = try zglfw.Window.create(800, 600, "Nese", null);
    defer window.destroy();
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
    var default_style = zgui.getStyle();

    default_style.scaleAllSizes(scale_factor * config.general.ui_scale);

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

    var current_screen = Screen.MainMenuScreen;
    var game_path = std.ArrayList(u8).init(gpa);
    defer game_path.deinit();
    var menus_toggle = MenusToggle{};

    const OpenGameContext = struct {
        const Self = @This();
        current_screen: *Screen,
        game_path: *std.ArrayList(u8),

        pub fn openGame(self: *Self, path: []const u8) void {
            self.current_screen.* = Screen.GameScreen;
            self.game_path.clearRetainingCapacity();
            self.game_path.appendSlice(path) catch std.process.exit(1);
            std.log.info("Opening: {s}", .{path});
        }
    };
    var openGameContext = OpenGameContext{
        .current_screen = &current_screen,
        .game_path = &game_path,
    };
    var main_menu_state = try MainMenu.init(
        gpa,
        &game_repo,
        shared_string_buffer,
        default_style,
        MainMenu.Callback.init(
            OpenGameContext.openGame,
            &openGameContext,
        ),
    );
    defer main_menu_state.deinit();

    var config_menu = try ConfigMenu.init(
        gpa,
        default_style,
        &config_repo,
        &language_repo,
        &game_repo,
        shared_string_buffer,
        ConfigMenu.ApplyCallback.initNoContext(&tmp),
    );
    defer config_menu.deinit();

    // const frame_deadline = @as(f64, 1) / 60;
    // var frame_accumulated: f64 = 0;
    // var frame_rate: f64 = 0;
    // var start = zglfw.getTime();
    var exit = false;

    std.log.info("Starting main loop", .{});
    while (!window.shouldClose() and !exit) {
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
        { // In between begin and end frame
            zgui.pushStyleVar1f(.{ .idx = .scrollbar_size, .v = 10 });
            defer zgui.popStyleVar(.{});

            switch (MenuBar.drawMenuBar(strings.*, .{
                .in_game = false,
                .is_pause = false,
            })) {
                .Exit => exit = true,
                .OpenConfig => menus_toggle.config_menu = true,
                .None => {},
                else => {},
            }

            if (menus_toggle.config_menu) {
                config_menu.draw(&menus_toggle.config_menu, strings.*);
            }

            if (config.general.show_metric) {
                zgui.showMetricsWindow(&config.general.show_metric);
            }
            // zgui.showDemoWindow(null);

            switch (current_screen) {
                .MainMenuScreen => {
                    main_menu_state.draw(strings.*);
                },
                .GameScreen => {
                    std.process.cleanExit();
                },
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

        }

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

const MenusToggle = struct {
    config_menu: bool = true,
};

fn tmp() void {
    std.debug.print("tmp called\n", .{});
}
