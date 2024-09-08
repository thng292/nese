const std = @import("std");
const Self = @This();
const meta = @import("meta.zig");
pub const non_serializable_fields = .{"ns"};
pub const Serializeable = meta.StructWithout(Self, non_serializable_fields);

ns: struct {
    // Not json serializable
    allocator: std.mem.Allocator,
    games_list: GameList = .{},
    game_dirs_list: DirList = .{}, // Path to the directory containing the games
},

scale: f32 = 2,
ui_scale: f32 = 1,
input_poll_rate: u32 = 400,
vsync: bool = false,
emulation_speed: u32 = 100,
show_metric: bool = false,
games: []Game,
game_dirs: [][]u8,

pub fn initDefault(allocator: std.mem.Allocator) !Self {
    const games_list = try GameList.initCapacity(allocator, 0);
    const games_dir_list = try DirList.initCapacity(allocator, 0);

    return Self{
        .ns = .{
            .allocator = allocator,
            .game_dirs_list = games_dir_list,
            .games_list = games_list,
        },
        .game_dirs = games_dir_list.items,
        .games = games_list.items,
    };
}

pub fn deinit(self: *Self) void {
    for (self.ns.game_dirs_list.items) |dir| {
        self.ns.allocator.free(dir);
    }
    self.ns.game_dirs_list.deinit(self.ns.allocator);
    for (self.ns.games_list.items) |game| {
        game.deinit(self.ns.allocator);
    }
    self.ns.games_list.deinit(self.ns.allocator);
}

inline fn update_ref(self: *Self) void {
    self.games = self.ns.games_list.items;
    self.game_dirs = self.ns.game_dirs_list.items;
    std.debug.assert(self.games.len == self.ns.games_list.items.len);
    std.debug.assert(self.game_dirs.len == self.ns.game_dirs_list.items.len);
}

pub fn load(file: std.fs.File, allocator: std.mem.Allocator) !Self {
    const file_content = try file.readToEndAlloc(allocator, std.json.default_max_value_len);
    std.log.info("Config file content: {s}", .{file_content});
    defer allocator.free(file_content);

    const parsed = try std.json.parseFromSlice(
        Serializeable,
        allocator,
        file_content,
        .{
            .ignore_unknown_fields = true,
            .duplicate_field_behavior = .use_last,
            .allocate = .alloc_if_needed,
        },
    );
    defer parsed.deinit();

    var result = meta.initStructFrom(Self, parsed.value);
    result.ns = .{
        .allocator = allocator,
        .game_dirs_list = DirList{},
        .games_list = GameList{},
    };

    try result.ns.game_dirs_list.appendSlice(allocator, parsed.value.game_dirs);
    for (result.ns.game_dirs_list.items) |*dir| {
        dir.* = try allocator.dupe(u8, dir.*);
    }
    try result.ns.games_list.appendSlice(allocator, parsed.value.games);
    for (result.ns.games_list.items) |*game| {
        game.* = try game.clone(allocator);
    }
    result.update_ref();

    std.log.info("Loaded Config: {}", .{result});
    return result;
}

pub fn save(self: Self, file: std.fs.File) !void {
    try std.json.stringify(
        meta.initStructFrom(Serializeable, self),
        .{ .whitespace = .indent_4 },
        file.writer(),
    );
}

pub fn addGame(self: *Self, path: []u8) !void {
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
    self.shortGames();
    self.update_ref();
}

pub fn addGameCopy(self: *Self, path: []u8) !void {
    const path_mem = try self.ns.allocator.dupe(u8, path);
    try self.addGame(path_mem);
}

pub fn removeGame(self: *Self, index: usize) void {
    const game = self.games[index];
    _ = self.ns.games_list.orderedRemove(index);
    game.deinit(self.ns.allocator);
    self.shortGames();
    self.update_ref();
}

pub fn renameGame(self: *Self, index: usize, new_name: []u8) void {
    const game = &self.games[index];
    self.ns.allocator.free(game.name);
    game.name = new_name;
    self.shortGames();
}

pub fn renameGameCopy(self: *Self, index: usize, new_name: []u8) !void {
    const new_name_mem = try self.ns.allocator.dupe(u8, new_name);
    self.renameGame(index, new_name_mem);
}

pub fn toggleFavorite(self: *Self, index: usize) void {
    self.ns.games_list.items[index].is_favorite = !self.ns.games_list.items[index].is_favorite;
    self.shortGames();
}

pub fn updateGameListAfterInlineChange(self: *Self) void {
    self.shortGames();
}

fn scanDirectory(self: *Self, path: []u8) !void {
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

pub fn addDirectory(self: *Self, path: []u8) !void {
    try self.ns.game_dirs_list.append(
        self.ns.allocator,
        path,
    );
    try self.scanDirectory(path);
    self.update_ref();
}

pub fn addDirectoryCopy(self: *Self, path: []u8) !void {
    const path_mem = try self.ns.allocator.dupe(u8, path);
    try self.addDirectory(path_mem);
}

pub fn rescanDirectories(self: *Self) !void {
    self.update_ref();
    for (self.game_dirs) |dir| {
        self.scanDirectory(dir);
    }
}

fn checkGameExists(self: Self, path: []u8) bool {
    for (self.games) |game| {
        if (std.mem.eql(u8, game.path, path)) {
            return true;
        }
    }
    return false;
}

fn shortGames(self: *Self) void {
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

const GameList = std.ArrayListUnmanaged(Game);
const DirList = std.ArrayListUnmanaged([]u8);

pub const Game = struct {
    path: []u8,
    name: []u8,
    playtime: u32,
    last_played: i64,
    play_count: u32,
    is_favorite: bool,

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

pub const config_file_path = "config.json";
pub const default_save_path = "save/";

test "Test init" {
    const allocator = std.testing.allocator;
    var config = try Self.initDefault(allocator);
    defer config.deinit();
}

test "Test save, load" {
    const cwd = std.fs.cwd();
    const allocator = std.testing.allocator;
    const test_file_path = "config.json";
    {
        const file = try cwd.createFile(test_file_path, .{});
        defer file.close();
        var config = try Self.initDefault(allocator);
        defer config.deinit();
        try std.testing.expect(config.games.len == 0);
        try std.testing.expect(config.game_dirs.len == 0);
        try config.addDirectory(try cwd.realpathAlloc(allocator, "."));
        try config.addGame(try allocator.dupe(u8, "test.nes"));
        try config.save(file);
    }

    {
        const file = try cwd.openFile(
            test_file_path,
            .{ .mode = .read_only },
        );
        defer file.close();
        var config = try Self.load(file, std.testing.allocator);
        // try std.testing.expect(config.games.len == 1);
        // try std.testing.expectEqualStrings(config.games[0].name, "test");
        // try std.testing.expect(config.game_dirs.len == 1);
        // try std.testing.expectEqualStrings(config.game_dirs[0], ".");
        defer config.deinit();
    }
    // try cwd.deleteFile(test_file_path);
}
