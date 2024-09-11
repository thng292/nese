const std = @import("std");
const GameConfig = @import("config.zig").GameConfig;

pub const Game = struct {
    path: []const u8,
    name: []const u8,
    playtime: u32,
    last_played: i64,
    play_count: u32,
    is_favorite: bool,
    config: ?GameConfig,

    pub fn clone(self: Game, allocator: std.mem.Allocator) !Game {
        var res = self;
        res.path = try allocator.dupe(u8, res.path);
        res.name = try allocator.dupe(u8, res.name);
        return res;
    }

    pub fn deinit(self: Game, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.name);
    }
};
