const std = @import("std");
const meta = @import("meta.zig");

const Self = @This();
const Str = [:0]const u8;
pub const non_serializable_fields = .{"parsed"};
pub const Serializable = meta.StructWithout(Self, non_serializable_fields);

parsed: ?*anyopaque = null,

main_menu_bar: struct {
    file: Str = "File",
    emulation: Str = "Emulation",
    help: Str = "Help",
} = .{},

file_menu_items: struct {
    load_game: Str = "Load game",
    load_dir: Str = "Load directory",
    exit: Str = "Exit",
} = .{},

emulation_menu_items: struct {
    @"continue": Str = "Continue",
    pause: Str = "Pause",
    stop: Str = "Stop",
    take_snapshot: Str = "Take snapshot",
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

pub fn deinit(self: Self) void {
    if (self.parsed) |parsed_| {
        const parsed: *std.json.Parsed(Serializable) = @ptrCast(parsed_);
        parsed.deinit();
    }
}

pub fn save(self: Self, file: std.fs.File) !void {
    try std.json.stringify(self, .{ .whitespace = .indent_4 }, file.writer());
}

pub fn load(file: std.fs.File, allocator: std.mem.Allocator) !void {
    const file_content = file.readToEndAlloc(allocator, std.json.default_max_value_len);
    const parsed = try std.json.parseFromSlice(
        Self,
        allocator,
        file_content,
        .{
            .allocate = .alloc_if_needed,
            .duplicate_field_behavior = .use_last,
            .ignore_unknown_fields = true,
        },
    );

    return parsed.value;
}
