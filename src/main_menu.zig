const std = @import("std");
const zgui = @import("zgui");
const zglfw = @import("zglfw");

const Config = @import("config.zig");
const Self = @This();

const nes_file_extentions = .{".nes"};
const OpenGameFn = fn (file_path: []u8) void;

config: *Config,
allocator: std.mem.Allocator,
file_paths: std.ArrayListUnmanaged([]u8),
open_game_fn: *OpenGameFn,

pub fn init(allocator: std.mem.Allocator, config: *Config, open_game_fn: *OpenGameFn) !Self {
    return Self{
        .config = config,
        .allocator = allocator,
        .file_paths = try std.ArrayListUnmanaged([]u8).initCapacity(allocator, 0),
        .open_game_fn = open_game_fn,
    };
}

pub fn deinit(self: *Self) void {
    for (self.file_paths.items) |file_path| {
        self.allocator.free(file_path);
    }
    self.file_paths.deinit(self.allocator);
}

pub fn drawMenu(self: *Self, window: *zglfw.Window) void {
    const size_tuple = window.getSize();
    const screen_w = @as(f32, @floatFromInt(size_tuple[0]));
    const screen_h = @as(f32, @floatFromInt(size_tuple[1]));

    zgui.setNextWindowPos(.{ .cond = .always, .x = 0, .y = 0 });
    zgui.setNextWindowSize(.{ .cond = .always, .w = screen_w, .h = screen_h });
    if (zgui.begin("Main Menu", .{ .flags = .{
        .no_resize = true,
        .no_move = true,
        .no_collapse = true,
        .no_title_bar = true,
    } })) {
        for (self.file_paths.items) |file_path| {
            if (zgui.button(
                @ptrCast(file_path),
                .{ .w = screen_w, .h = 40 },
            )) {}
        }
    }
    zgui.end();
    zgui.DrawCallback
}

pub fn findNesFile(self: *Self) !void {
    const cwd = std.fs.cwd();
    for (self.file_paths.items) |file_path| {
        self.allocator.free(file_path);
    }
    self.file_paths.clearAndFree(self.allocator);

    if (self.config.game_path.len == 0) {
        return;
    }

    const game_dir = try cwd.openDir(self.config.game_path, .{ .iterate = true });
    var dir_walker = try game_dir.walk(self.allocator);
    defer dir_walker.deinit();

    while (try dir_walker.next()) |entry| {
        if (entry.kind == .file) {
            var is_nes_file = true;
            inline for (nes_file_extentions) |extentions| {
                is_nes_file = is_nes_file and std.mem.endsWith(
                    u8,
                    entry.basename[0..],
                    extentions[0..],
                );
            }
            if (is_nes_file) {
                const memory = try self.allocator.alloc(u8, entry.path.len);
                @memcpy(memory, entry.path);
                try self.file_paths.append(self.allocator, memory);
            }
        }
    }
}
