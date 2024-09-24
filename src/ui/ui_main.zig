const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");
const zglfw = @import("zglfw");

const LanguageRepo = @import("../repo/language_repo.zig");
const ConfigRepo = @import("../repo/config_repo.zig");
const GameRepo = @import("../repo/game_repo.zig");

const MainMenu = @import("main_menu.zig");
const ConfigMenu = @import("config_menu.zig");
const MenuBar = @import("menu_bar.zig");

const MenusToggle = struct {
    config_menu: bool = false,
};

const Screen = enum {
    MainMenuScreen,
    GameScreen,
};

const Signal = enum {
    Exit,
    Restart,
};

pub fn ui_main(
    allocator: std.mem.Allocator,
    window: *zglfw.Window,
    gctx: *zgpu.GraphicsContext,
    config_repo: *ConfigRepo,
    language_repo: *LanguageRepo,
    game_repo: *GameRepo,
) !Signal {
    const config = &config_repo.config;
    const strings = &language_repo.parsed.?.value;
    const scale_factor = blk: {
        const scale = window.getContentScale();
        break :blk @max(scale[0], scale[1]) * config.getUIScale();
    };

    const shared_string_buffer = try allocator.allocSentinel(u8, 1024, 0);
    defer allocator.free(shared_string_buffer);
    @memset(shared_string_buffer, 0);

    zgui.init(allocator);
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
    default_style.scaleAllSizes(scale_factor);

    const font = zgui.io.addFontFromFile("NotoSans.ttf", 16 * scale_factor);
    _ = font;

    // var arg_it = try std.process.argsWithAllocator(allocator);
    // _ = arg_it.next(); // skip first arg

    // const rom_file = try cwd.openFile(
    //     arg_it.next().?,
    //     .{ .mode = .read_only },
    // );
    // arg_it.deinit();
    // var nes = try Nes.init(allocator, rom_file, gctx);
    // defer nes.deinit();
    // try nes.startup(APU{});

    var current_screen = Screen.MainMenuScreen;
    var game_path = std.ArrayList(u8).init(allocator);
    defer game_path.deinit();
    var menus_toggle = MenusToggle{};
    var signal: ?Signal = null;

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
        allocator,
        game_repo,
        shared_string_buffer,
        default_style,
        MainMenu.Callback.init(
            OpenGameContext.openGame,
            &openGameContext,
        ),
    );
    defer main_menu_state.deinit();

    const ApplyConfigContext = struct {
        const Self = @This();
        signal: *?Signal,

        pub fn call(self: *Self) void {
            self.signal.* = .Restart;
        }
    };
    var apply_config_context = ApplyConfigContext{ .signal = &signal };
    var config_menu = try ConfigMenu.init(
        allocator,
        window,
        default_style,
        config_repo,
        language_repo,
        game_repo,
        shared_string_buffer,
        ConfigMenu.ApplyCallback.init(
            &ApplyConfigContext.call,
            &apply_config_context,
        ),
    );
    defer config_menu.deinit();

    // const frame_deadline = @as(f64, 1) / 60;
    // var frame_accumulated: f64 = 0;
    // var frame_rate: f64 = 0;
    // var start = zglfw.getTime();

    std.log.info("Starting main loop", .{});
    while (!window.shouldClose()) {
        if (signal) |sig| {
            return sig;
        }
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

            zgui.pushStyleVar1f(.{
                .idx = .scrollbar_size,
                .v = 10 * scale_factor,
            });
            defer zgui.popStyleVar(.{});

            switch (MenuBar.drawMenuBar(strings.*, .{
                .in_game = false,
                .is_pause = false,
            })) {
                .Exit => signal = .Exit,
                .OpenConfig => menus_toggle.config_menu = true,
                .None => {},
                else => {},
            }

            if (menus_toggle.config_menu) {
                try config_menu.draw(&menus_toggle.config_menu, strings.*);
            }

            if (config.general.show_metric) {
                zgui.showMetricsWindow(&config.general.show_metric);
            }

            switch (current_screen) {
                .MainMenuScreen => {
                    try main_menu_state.draw(strings.*);
                },
                .GameScreen => {
                    std.process.cleanExit();
                },
            }

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

    return .Exit;
}

fn tmp() void {}
