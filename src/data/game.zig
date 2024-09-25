const std = @import("std");
const ControllerMap = @import("../nes/control.zig").ControllerMap;

const Self = @This();
path: []const u8,
name: []const u8,
playtime: u32 = 0,
last_played: i64 = 0,
play_count: u32 = 0,
is_favorite: bool = false,
controller_map: ?[2]ControllerMap = null,

pub fn clone(self: Self, allocator: std.mem.Allocator) !Self {
    var res = self;
    res.path = try allocator.dupe(u8, res.path);
    res.name = try allocator.dupe(u8, res.name);
    return res;
}

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.path);
    allocator.free(self.name);
}

test "Game" {
    const allocator = std.testing.allocator;
    const tmp = std.mem.zeroes(Self);
    tmp.deinit(allocator);
}
