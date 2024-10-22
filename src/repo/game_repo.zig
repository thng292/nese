const std = @import("std");
const meta = @import("../data/meta.zig");
const builtin = @import("builtin");

const Game = @import("../data/game.zig");

const Self = @This();
pub const non_serializable_fields = .{"ns"};
pub const Serializable = meta.StructWithout(Self, non_serializable_fields);
const GameList = std.ArrayListUnmanaged(Game);
const DirList = std.ArrayListUnmanaged([]const u8);
const save_dir = "data/";
const save_file_name = "games.json";
const save_file_path = save_dir ++ save_file_name;
const bytes_limit = std.math.maxInt(u20); // 1GB

const SaveData = struct {
    games: []const Game,
    game_dirs: []const []const u8,
};

allocator: std.mem.Allocator,
games_list: GameList = .{},
game_dirs_list: DirList = .{}, // Path to the directory containing the games

pub fn init(allocator: std.mem.Allocator) !Self {
    var games_list = GameList{};
    var game_dirs_list = DirList{};

    const cwd = std.fs.cwd();
    cwd.access(save_dir, .{ .mode = .read_write }) catch {
        try cwd.makeDir(save_dir);
    };
    var should_load = true;
    cwd.access(save_file_path, .{ .mode = .read_write }) catch {
        should_load = false;
        const tmp = try cwd.createFile(save_file_path, .{});
        tmp.close();
    };

    if (should_load) blk: {
        const file_content = try cwd.readFileAlloc(allocator, save_file_path, bytes_limit);
        defer allocator.free(file_content);
        const parsed = std.json.parseFromSlice(
            SaveData,
            allocator,
            file_content,
            .{
                .allocate = .alloc_if_needed,
                .duplicate_field_behavior = .use_last,
                .ignore_unknown_fields = true,
            },
        ) catch break :blk;
        defer parsed.deinit();

        try games_list.appendSlice(allocator, parsed.value.games);
        for (games_list.items) |*game| {
            game.name = try allocator.dupe(u8, game.name);
            game.path = try allocator.dupe(u8, game.path);
        }
        try game_dirs_list.appendSlice(allocator, parsed.value.game_dirs);
        for (game_dirs_list.items) |*dir| {
            dir.* = try allocator.dupe(u8, dir.*);
        }

        std.log.info("Loaded games from file: {s}", .{save_file_path});
        std.log.info("{}", .{parsed.value});
    }

    return Self{
        .allocator = allocator,
        .game_dirs_list = game_dirs_list,
        .games_list = games_list,
    };
}

pub fn deinit(self: *Self) void {
    const cwd = std.fs.cwd();
    if (cwd.createFile(save_file_path, .{})) |file| {
        self.save(file) catch {};
    } else |_| {}

    for (self.getGames()) |game| {
        game.deinit(self.allocator);
    }
    self.games_list.deinit(self.allocator);
    for (self.getDirs()) |dir| {
        self.allocator.free(dir);
    }
    self.game_dirs_list.deinit(self.allocator);
}

pub fn save(self: Self, file: std.fs.File) !void {
    const save_data = SaveData{
        .game_dirs = self.getDirs(),
        .games = self.getGames(),
    };
    try std.json.stringify(save_data, .{ .whitespace = .indent_4 }, file.writer());
}

pub inline fn getGames(self: Self) []const Game {
    return self.games_list.items;
}

pub inline fn getDirs(self: Self) []const []const u8 {
    return self.game_dirs_list.items;
}

fn addGame(self: *Self, path: []const u8) !void {
    if (self.checkGameExists(path)) {
        return;
    }
    const name = std.fs.path.basename(path);
    const name_mem = try self.allocator.dupe(u8, name[0 .. name.len - 4]);

    try self.games_list.append(
        self.allocator,
        Game{
            .path = path,
            .name = name_mem,
            .playtime = 0,
            .last_played = 0,
            .play_count = 0,
            .is_favorite = false,
        },
    );
    self.sortGames();
}

pub fn addGameCopy(self: *Self, path: []const u8) !void {
    const path_mem = try self.allocator.dupe(u8, path);
    try self.addGame(path_mem);
}

pub fn removeGame(self: *Self, index: usize) void {
    const game = self.getGames()[index];
    _ = self.games_list.orderedRemove(index);
    game.deinit(self.allocator);
    self.sortGames();
}

fn renameGame(self: *Self, index: usize, new_name: []const u8) void {
    var game = &self.games_list.items[index];
    self.allocator.free(game.name);
    game.name = new_name;
    self.sortGames();
}

pub fn renameGameCopy(self: *Self, index: usize, new_name: []const u8) !void {
    const new_name_mem = try self.allocator.dupe(u8, new_name);
    self.renameGame(index, new_name_mem);
}

fn changePath(self: *Self, index: usize, new_path: []const u8) void {
    self.games_list.items[index].path = new_path;
}

pub fn changePathCopy(self: *Self, index: usize, new_path: []const u8) !void {
    const path = try self.allocator.dupe(u8, new_path);
    self.changePath(index, path);
}

pub fn toggleFavorite(self: *Self, index: usize) void {
    self.games_list.items[index].is_favorite = !self.games_list.items[index].is_favorite;
    self.sortGames();
}

pub fn sortGames(self: *Self) void {
    const funtions = struct {
        fn gameLessthan(_: void, lhs: Game, rhs: Game) bool {
            if (lhs.is_favorite == rhs.is_favorite) {
                return std.mem.lessThan(u8, lhs.name, rhs.name);
            }
            return @intFromBool(lhs.is_favorite) > @intFromBool(rhs.is_favorite);
        }
    };
    std.mem.sort(Game, self.games_list.items, {}, funtions.gameLessthan);
}

fn scanDirectory(self: *Self, path: []const u8) !void {
    const dir = try std.fs.cwd().openDir(path, .{
        .iterate = true,
    });
    var walker = try dir.walk(self.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            if (std.mem.endsWith(u8, entry.path, ".nes")) {
                const abs_path = try std.fs.path.join(
                    self.allocator,
                    &[_][]const u8{ path, entry.path },
                );
                try self.addGame(abs_path);
            }
        }
    }
}

fn addDirectory(self: *Self, path: []const u8) !void {
    for (self.getDirs()) |dir| {
        if (std.mem.eql(u8, dir, path)) {
            return;
        }
    }
    try self.game_dirs_list.append(
        self.allocator,
        path,
    );
    try self.scanDirectory(path);
}

pub fn addDirectoryCopy(self: *Self, path: []const u8) !void {
    const path_mem = try self.allocator.dupe(u8, path);
    try self.addDirectory(path_mem);
}

pub fn removeDirectory(self: *Self, index: usize) void {
    const dir = self.game_dirs_list.orderedRemove(index);
    self.allocator.free(dir);
}

pub fn rescanDirectories(self: *Self) !void {
    for (self.game_dirs) |dir| {
        self.scanDirectory(dir);
    }
}

fn checkGameExists(self: Self, path: []const u8) bool {
    for (self.getGames()) |game| {
        if (std.mem.eql(u8, game.path, path)) {
            return true;
        }
    }
    return false;
}
