const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");
const zglfw = @import("zglfw");

const LanguageRepo = @import("../repo/language_repo.zig");
const ConfigRepo = @import("../repo/config_repo.zig");
const GameRepo = @import("../repo/game_repo.zig");
const Game = @import("../data/game.zig");
const ControllerMap = @import("../nes/control.zig").ControllerMap;

const MainMenu = @import("main_menu.zig");
const ConfigMenu = @import("config_menu.zig");
const MenuBar = @import("menu_bar.zig");
const About = @import("about.zig");
const Nes = @import("../nes/nes.zig");

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

    _ = zgui.io.addFontFromFile("NotoSans.ttf", 16 * scale_factor);

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

    var current_screen = Screen{ .MenuScreen = null };
    defer current_screen.deinit(allocator);
    var game_pause = false;
    var full_screen = false;
    var current_game: ?Game = null;
    var menus_toggle = MenusToggle{};
    var config_menu_state: ?*ConfigMenu = null;
    var signal: Signal = .None;
    var screen_rect = getWindowRect(window);

    var openGameContext = OpenGameContext{
        .current_screen = &current_screen,
        .current_game = &current_game,
        .allocator = &allocator,
    };

    var apply_config_context = ApplyConfigContext{
        .signal = &signal,
    };

    // const frame_deadline = @as(f64, 1) / 60;
    // var frame_accumulated: f64 = 0;
    // var frame_rate: f64 = 0;
    // var start = zglfw.getTime();

    std.log.info("Starting main loop", .{});
    while (signal == .None) {
        if (window.shouldClose()) {
            signal = .Exit;
            continue;
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

            switch (MenuBar.drawMenuBar(
                window,
                strings.*,
                current_screen == .GameScreen,
                game_pause,
                full_screen,
            )) {
                .Exit => signal = .Exit,
                .OpenConfig => menus_toggle.config_menu = true,
                .Stop => {
                    current_screen.deinit(allocator);
                    current_screen = .{ .MenuScreen = null };
                },
                .FullScreen => {
                    std.log.debug("Fullscreened", .{});
                    full_screen = !full_screen;
                    var tmp = std.mem.zeroes(zglfw.VideoMode);
                    tmp.refresh_rate = 60;
                    tmp.height = 600;
                    tmp.width = 800;
                    const primary_monitor = zglfw.Monitor.getPrimary();
                    const video_mode = if (primary_monitor) |monitor|
                        try monitor.getVideoMode()
                    else
                        &tmp;
                    if (full_screen) {
                        screen_rect = getWindowRect(window);
                        window.setMonitor(
                            primary_monitor,
                            0,
                            0,
                            video_mode.width,
                            video_mode.height,
                            video_mode.refresh_rate,
                        );
                    } else {
                        window.setMonitor(
                            primary_monitor,
                            screen_rect.x,
                            screen_rect.y,
                            screen_rect.w,
                            screen_rect.h,
                            video_mode.refresh_rate,
                        );
                    }
                },
                .PauseContinue => game_pause = !game_pause,
                .About => menus_toggle.about = true,
                .None => {},
                else => {},
            }

            if (menus_toggle.config_menu) {
                if (config_menu_state) |config_menu| {
                    try config_menu.draw(&menus_toggle.config_menu, strings.*);
                } else {
                    const tmp = try allocator.create(ConfigMenu);
                    tmp.* = try ConfigMenu.init(
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
                    config_menu_state = tmp;
                }
            } else {
                if (config_menu_state) |config_menu| {
                    config_menu.deinit();
                    allocator.destroy(config_menu);
                    config_menu_state = null;
                }
            }

            if (menus_toggle.about) {
                About.drawAbout(&menus_toggle.about, strings.*);
            }

            if (config.general.show_metric) {
                zgui.showMetricsWindow(&config.general.show_metric);
            }

            std.log.info("Current screen: {}", .{current_screen == .GameScreen});
            switch (current_screen) {
                .MenuScreen => |main_menu_state_| {
                    if (main_menu_state_) |main_menu_state| {
                        try main_menu_state.draw(strings.*);
                    } else {
                        const main_menu_state = try allocator.create(MainMenu);
                        main_menu_state.* = try MainMenu.init(
                            allocator,
                            window,
                            game_repo,
                            shared_string_buffer,
                            default_style,
                            config,
                            MainMenu.Callback.init(
                                OpenGameContext.openGame,
                                &openGameContext,
                            ),
                        );
                        current_screen = Screen{ .MenuScreen = main_menu_state };
                    }
                },
                .GameScreen => |nes_state| {
                    if (nes_state) |nes| {
                        _ = try nes.runFrame();
                    } else {
                        const nes = try allocator.create(Nes);
                        const rom_file = try std.fs.cwd().openFile(current_game.?.path, .{ .mode = .read_only });
                        nes.* = try Nes.init(allocator, gctx, rom_file, [_]ControllerMap{
                            config.game.controller1_map,
                            config.game.controller2_map,
                        });
                    }
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

    return signal;
}

const MenusToggle = struct {
    config_menu: bool = false,
    about: bool = false,
};

const ScreenTag = enum {
    MenuScreen,
    GameScreen,
};

const Screen = union(ScreenTag) {
    MenuScreen: ?*MainMenu,
    GameScreen: ?*Nes,

    pub fn deinit(self: *Screen, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .MenuScreen => |main_menu_state| {
                if (main_menu_state) |mmt| {
                    mmt.deinit();
                    allocator.destroy(mmt);
                }
                self.MenuScreen = null;
            },
            .GameScreen => |nes_state| {
                if (nes_state) |nes| {
                    nes.deinit();
                    allocator.destroy(nes);
                }
                self.GameScreen = null;
            },
        }
    }
};

const Signal = enum {
    None,
    Exit,
    Restart,
};

const OpenGameContext = struct {
    const Self = @This();
    current_screen: *Screen,
    current_game: *?Game,
    allocator: *const std.mem.Allocator,

    pub fn openGame(self: *Self, game: Game) void {
        self.current_screen.MenuScreen.?.deinit();
        self.allocator.destroy(self.current_screen.MenuScreen.?);
        self.current_screen.* = Screen{ .GameScreen = null };
        self.current_game.* = game;
        std.log.info("Opening: {s}", .{game.path});
        std.log.info("Current screen: {}", .{self.current_screen});
    }
};

const ApplyConfigContext = struct {
    const Self = @This();
    signal: *Signal,

    pub fn call(self: *Self) void {
        self.signal.* = .Restart;
    }
};

const Rect = struct {
    x: i32 = 0,
    y: i32 = 0,
    w: i32 = 800,
    h: i32 = 600,
};

fn getWindowRect(window: *zglfw.Window) Rect {
    const pos: @Vector(2, i32) = window.getPos();
    const size: @Vector(2, i32) = window.getSize();
    return Rect{ .x = pos[0], .y = pos[1], .w = size[0], .h = size[1] };
}

// fn tmp() void {}
