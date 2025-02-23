const std = @import("std");
const zgui = @import("zgui");
const zglfw = @import("zglfw");

const Strings = @import("../data/i18n.zig");

const MenuAction = enum {
    None,
    AddGame,
    Exit,
    PauseContinue,
    Stop,
    TakeSnapshot,
    FullScreen,
    OpenConfig,
    About,
};

pub fn drawMenuBar(
    window: *zglfw.Window,
    strings: Strings,
    in_game: bool,
    is_pause: bool,
    full_screen: bool,
) MenuAction {
    if (!full_screen and zgui.beginMainMenuBar()) {
        defer zgui.endMainMenuBar();
        if (zgui.beginMenu(strings.main_menu_bar.file, true)) {
            defer zgui.endMenu();
            if (zgui.menuItem(strings.file_menu_items.add_game, .{})) {
                return .AddGame;
            }
            if (zgui.menuItem(strings.file_menu_items.exit, .{})) {
                return .Exit;
            }
        }
        if (zgui.beginMenu(strings.main_menu_bar.emulation, true)) {
            defer zgui.endMenu();
            if (zgui.menuItem(
                if (is_pause)
                    strings.emulation_menu_items.@"continue"
                else
                    strings.emulation_menu_items.pause,
                .{ .enabled = in_game, .shortcut = "F5" },
            )) {
                return .PauseContinue;
            }
            if (zgui.menuItem(
                strings.emulation_menu_items.stop,
                .{ .enabled = in_game, .shortcut = "F6" },
            )) {
                return .Stop;
            }
            if (zgui.menuItem(
                strings.emulation_menu_items.take_snapshot,
                .{ .enabled = in_game, .shortcut = "F7" },
            )) {
                return .TakeSnapshot;
            }
            if (zgui.menuItem(
                strings.emulation_menu_items.full_screen,
                .{ .shortcut = "F11" },
            )) {
                return .FullScreen;
            }
            if (zgui.menuItem(strings.emulation_menu_items.config, .{})) {
                return .OpenConfig;
            }
        }
        if (zgui.beginMenu(strings.help_menu_items.about, true)) {
            defer zgui.endMenu();
            return .About;
        }
    }

    if (window.getKey(.F11) == .press) {
        return .FullScreen;
    }
    if (window.getKey(.F5) == .press) {
        return .PauseContinue;
    }
    if (window.getKey(.F6) == .press) {
        return .Stop;
    }
    if (window.getKey(.F7) == .press) {
        return .OpenConfig;
    }
    return .None;
}
