const std = @import("std");
const meta = @import("meta.zig");

const Self = @This();
const Str = [:0]const u8;

main_menu_bar: struct {
    file: Str = "File",
    emulation: Str = "Emulation",
    help: Str = "Help",
} = .{},

file_menu_items: struct {
    add_game: Str = "Add game",
    exit: Str = "Exit",
} = .{},

emulation_menu_items: struct {
    @"continue": Str = "Continue",
    pause: Str = "Pause",
    stop: Str = "Stop",
    take_snapshot: Str = "Take snapshot",
    full_screen: Str = "Full screen",
    config: Str = "Config",
} = .{},

help_menu_items: struct {
    about: Str = "About",
} = .{},

main_menu: struct {
    games: Str = "Games",
    time_played: Str = "Time played",
    favorite: Str = "Favorite",
} = .{},

main_menu_context_menu: struct {
    open: Str = "Open",
    remove: Str = "Remove",
    mark_favorite: Str = "Add to favorite",
    unmark_favorite: Str = "Remove from favorite",
    rename: Str = "Rename",
    change_path: Str = "Change Path",
} = .{},

add_game_popup: struct {
    game_path: Str = "Game Path",
    add_game: Str = "Add game",
    change_path: Str = "Update path",
    @"error": Str = "Error",
    cancel: Str = "Cancel",
} = .{},

config_menu: struct {
    tab_general: Str = "General",
    tab_game: Str = "Game",
    tab_control: Str = "Control",
    dpad_up: Str = "D-Pad Up",
    dpad_down: Str = "D-Pad Down",
    dpad_left: Str = "D-Pad Left",
    dpad_right: Str = "D-Pad Right",
    button_start: Str = "Start",
    button_sellect: Str = "Select",
    button_A: Str = "A",
    button_B: Str = "B",
} = .{},

pub fn save(self: Self, file: std.fs.File) !void {
    try std.json.stringify(self, .{ .whitespace = .indent_4 }, file.writer());
}
