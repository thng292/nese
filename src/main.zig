const std = @import("std");

const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

const ConfigRepo = @import("repo/config_repo.zig");
const GameRepo = @import("repo/game_repo.zig");
const LanguageRepo = @import("repo/language_repo.zig");

const UI = @import("ui/ui_main.zig");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var config_repo = try ConfigRepo.init(gpa);
    var language_repo = try LanguageRepo.init(gpa);
    var game_repo = try GameRepo.init(gpa);

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

    while (true) {
        const signal = try UI.ui_main(
            gpa,
            window,
            gctx,
            &config_repo,
            &language_repo,
            &game_repo,
        );
        switch (signal) {
            .Exit => break,
            else => {},
        }
    }
}
