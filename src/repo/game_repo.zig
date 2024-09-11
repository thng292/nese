const std = @import("std");
const meta = @import("../data/meta.zig");

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

ns: struct {
    // Not json serializable
    allocator: std.mem.Allocator,
    games_list: GameList = .{},
    game_dirs_list: DirList = .{}, // Path to the directory containing the games
},

games: []Game,
game_dirs: [][]const u8,

pub fn init(allocator: std.mem.Allocator) !Self {
    const games_list = GameList.init(allocator);
    const game_dirs_list = DirList.init(allocator);

    const cwd = std.fs.cwd();
    cwd.access(save_dir, .{ .mode = .read_write }) catch {
        try cwd.makeDir(save_dir);
    };
    var should_load = true;
    cwd.access(save_file_path, .{ .mode = .read_write }) catch {
        should_load = false;
    };

    if (should_load) {
        const file_content = try cwd.readFileAlloc(allocator, save_file_path, bytes_limit);
        defer allocator.free(file_content);
        const parsed = try std.json.parseFromSlice(
            Serializable,
            allocator,
            file_content,
            .{
                .allocate = .alloc_if_needed,
                .duplicate_field_behavior = .use_last,
                .ignore_unknown_fields = true,
            },
        );
        defer parsed.deinit();

        games_list.appendSlice(parsed.value.games);
        game_dirs_list.appendSlice(parsed.value.game_dirs_list);
    }

    return Self{
        .ns = .{
            .allocator = allocator,
            .game_dirs_list = game_dirs_list,
            .games_list = games_list,
        },
        .game_dirs = game_dirs_list.items,
        .games = games_list.items,
    };
}

pub fn deinit(self: *Self) void {
    const cwd = std.fs.cwd();
    if (cwd.openFile(
        save_file_path,
        .{ .mode = .write_only },
    )) |file| {
        self.save(file);
    } else |_| {}
    for (self.ns.games_list.items) |game| {
        game.deinit(self.ns.allocator);
    }
    for (self.ns.game_dirs_list.items) |dir| {
        self.ns.allocator.free(dir);
    }
}

pub fn save(self: Self, file: std.fs.File) void {
    const serializable = meta.initStructFrom(Serializable, self);
    std.json.stringify(serializable, .{ .whitespace = .indent_4 }, file.writer());
}

inline fn update_ref(self: *Self) void {
    self.games = self.ns.games_list.items;
    self.game_dirs = self.ns.game_dirs_list.items;
}

fn addGame(self: *Self, path: []const u8) !void {
    if (self.checkGameExists(path)) {
        return;
    }
    const name = std.fs.path.basename(path);
    const name_mem = try self.ns.allocator.dupe(u8, name[0 .. name.len - 4]);

    try self.ns.games_list.append(
        self.ns.allocator,
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
    self.update_ref();
}

pub fn addGameCopy(self: *Self, path: []const u8) !void {
    const path_mem = try self.ns.allocator.dupe(u8, path);
    try self.addGame(path_mem);
}

pub fn removeGame(self: *Self, index: usize) void {
    const game = self.games[index];
    _ = self.ns.games_list.orderedRemove(index);
    game.deinit(self.ns.allocator);
    self.sortGames();
    self.update_ref();
}

fn renameGame(self: *Self, index: usize, new_name: []const u8) void {
    const game = &self.games[index];
    self.ns.allocator.free(game.name);
    game.name = new_name;
    self.sortGames();
}

pub fn renameGameCopy(self: *Self, index: usize, new_name: []const u8) !void {
    const new_name_mem = try self.ns.allocator.dupe(u8, new_name);
    self.renameGame(index, new_name_mem);
}

fn changePath(self: *Self, index: usize, new_path: []const u8) void {
    self.ns.games_list.items[index].path = new_path;
}

pub fn changePathCopy(self: *Self, index: usize, new_path: []const u8) !void {
    const path = try self.ns.allocator.dupe(u8, new_path);
    self.changePath(index, path);
}

pub fn toggleFavorite(self: *Self, index: usize) void {
    self.ns.games_list.items[index].is_favorite = !self.ns.games_list.items[index].is_favorite;
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
    std.mem.sort(Game, self.ns.games_list.items, {}, funtions.gameLessthan);
}

fn scanDirectory(self: *Self, path: []const u8) !void {
    const dir = try std.fs.openDirAbsolute(
        path,
        .{ .iterate = true },
    );
    var walker = try dir.walk(self.ns.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            if (std.mem.endsWith(u8, entry.path, ".nes")) {
                var abs_path = try self.ns.allocator.alloc(
                    u8,
                    path.len + entry.path.len,
                );
                std.mem.copyForwards(u8, abs_path, path);
                std.mem.copyForwards(u8, abs_path[path.len..], entry.path);
                try self.addGame(abs_path);
            }
        }
    }
}

fn addDirectory(self: *Self, path: []const u8) !void {
    try self.ns.game_dirs_list.append(
        self.ns.allocator,
        path,
    );
    try self.scanDirectory(path);
    self.update_ref();
}

pub fn addDirectoryCopy(self: *Self, path: []const u8) !void {
    const path_mem = try self.ns.allocator.dupe(u8, path);
    try self.addDirectory(path_mem);
}

pub fn rescanDirectories(self: *Self) !void {
    self.update_ref();
    for (self.game_dirs) |dir| {
        self.scanDirectory(dir);
    }
}

fn checkGameExists(self: Self, path: []const u8) bool {
    for (self.games) |game| {
        if (std.mem.eql(u8, game.path, path)) {
            return true;
        }
    }
    return false;
}
