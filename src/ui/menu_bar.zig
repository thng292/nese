const std = @import("std");
const zgui = @import("zgui");

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

pub fn drawMenuBar(strings: Strings, args: packed struct(u8) {
    in_game: bool,
    is_pause: bool,
    _padding: u6 = 0,
}) MenuAction {
    if (zgui.beginMainMenuBar()) {
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
                if (args.is_pause)
                    strings.emulation_menu_items.@"continue"
                else
                    strings.emulation_menu_items.pause,
                .{ .enabled = args.in_game, .shortcut = "F5" },
            )) {
                return .PauseContinue;
            }
            if (zgui.menuItem(
                strings.emulation_menu_items.stop,
                .{ .enabled = args.in_game, .shortcut = "F6" },
            )) {
                return .Stop;
            }
            if (zgui.menuItem(
                strings.emulation_menu_items.take_snapshot,
                .{ .enabled = args.in_game, .shortcut = "F7" },
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
        if (zgui.beginMenu(strings.main_menu_bar.help, true)) {
            defer zgui.endMenu();
            if (zgui.menuItem(strings.help_menu_items.about, .{})) {
                return .About;
            }
        }
    }
    return .None;
}
