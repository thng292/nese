const std = @import("std");
const Self = @This();
const meta = @import("meta.zig");
const non_serializable_fields = .{"allocator"};
const SelfSerializeable = meta.StructWithout(Self, non_serializable_fields);

pub const default_save_path = "save/";
allocator: std.mem.Allocator,

scale: f32 = 2,
input_poll_rate: u32 = 400,
vsync: bool = false,
emulation_speed: u32 = 100,
show_metric: bool = false,
save_path: []u8,
game_path: []u8,

pub fn initDefault(allocator: std.mem.Allocator) !Self {
    const save_path_mem = try allocator.alloc(u8, default_save_path.len);
    @memcpy(save_path_mem, default_save_path);
    const game_path_mem = try allocator.alloc(u8, 0);
    return Self{
        .allocator = allocator,
        .save_path = save_path_mem,
        .game_path = game_path_mem,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.save_path);
    self.allocator.free(self.game_path);
}

pub fn load(file: std.fs.File, allocator: std.mem.Allocator) !Self {
    const file_content = try file.readToEndAlloc(allocator, std.json.default_max_value_len);
    std.log.info("Config file content: {s}", .{file_content});
    defer allocator.free(file_content);

    const parsed = try std.json.parseFromSlice(SelfSerializeable, allocator, file_content, .{
        .ignore_unknown_fields = true,
        .duplicate_field_behavior = .use_last,
        .allocate = .alloc_if_needed,
    });

    var result = meta.initStructFrom(Self, parsed.value);
    result.allocator = allocator;
    result.game_path = try allocator.dupe(u8, result.game_path);
    result.save_path = try allocator.dupe(u8, result.save_path);

    std.log.info("Loaded Config: {}", .{result});
    return result;
}

pub fn save(self: Self, file: std.fs.File) !void {
    try std.json.stringify(
        meta.initStructFrom(SelfSerializeable, self),
        .{ .whitespace = .indent_4 },
        file.writer(),
    );
}
