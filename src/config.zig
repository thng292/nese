const std = @import("std");

const Self = @This();
pub const default_save_path = "./save";

scale: f32 = 2,
input_poll_rate: u32 = 400,
vsync: bool = false,
emulation_speed: u32 = 100,
save_path: [:0]const u8 = default_save_path,
game_path: ?[:0]u8 = null,
show_metric: bool = false,

pub fn load(file: std.fs.File, allocator: std.mem.Allocator) !Self {
    const file_content = try file.readToEndAlloc(allocator, std.json.default_max_value_len);
    defer allocator.free(file_content);
    const parsed = try std.json.parseFromSlice(Self, allocator, file_content, .{
        .ignore_unknown_fields = true,
        .duplicate_field_behavior = .use_last,
    });
    defer parsed.deinit();

    return parsed.value;
}

pub fn save(self: Self, file: std.fs.File) !void {
    try std.json.stringify(self, .{ .whitespace = .indent_4 }, file.writer());
}
