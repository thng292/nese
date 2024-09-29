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

about: struct {
    title: Str = "About",
    version: Str = "Version",
    made_by: Str = "This program was made by",
    source_code: Str = "Source code",
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
    change_control: Str = "Change control",
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
    game_config: Str = "Game",
    tab_control: Str = "Control",
    apply: Str = "Apply",
    restore_last: Str = "Restore last",
    all_folder: Str = "All games folders",
    add: Str = "Add folder",
    remove: Str = "Remove",
    language: Str = "Language",
    ui_scale: Str = "Ui Scale",
    show_debug: Str = "Show debug window",
    emulation_speed: Str = "Emulation speed",
    game_scale: Str = "Game Scale",
    input_poll_rate: Str = "Input poll rate",
    input_poll_rate_unlimit: Str = "0 means Unlimited",
    controller: Str = "Controller",
    press_key: Str = "Press key to map",
    cancel: Str = "Cancel",
    controller_button: struct {
        Up: Str = "D-Pad Up",
        Down: Str = "D-Pad Down",
        Left: Str = "D-Pad Left",
        Right: Str = "D-Pad Right",
        Start: Str = "Start",
        Select: Str = "Select",
        A: Str = "A",
        B: Str = "B",
    } = .{},
    map_key: Str = "Map key",
    map_new_key: Str = "Map a new key for",
} = .{},

pub fn save(self: Self, file: std.fs.File) !void {
    try std.json.stringify(self, .{ .whitespace = .indent_4 }, file.writer());
}
