const std = @import("std");

const Strings = @import("../data/i18n.zig");
const Self = @This();

pub const language_dir = "language/";
pub const default_language_file_name = "English.json";
pub const default_language_file_path = language_dir ++ default_language_file_name;
const bytes_limit = std.math.maxInt(u20); // 1GB

const LanguageList = std.ArrayListUnmanaged([]const u8);

language_list: LanguageList,
allocator: std.mem.Allocator,
parsed: ?std.json.Parsed(Strings) = null,

pub fn init(allocator: std.mem.Allocator) !Self {
    const cwd = std.fs.cwd();
    cwd.access(
        language_dir ++ default_language_file_name,
        .{ .mode = .read_write },
    ) catch {
        try cwd.makeDir(language_dir);
        const file = try cwd.createFile(language_dir ++ default_language_file_name, .{});
        const english = Strings{};
        try english.save(file);
    };

    var result = Self{
        .allocator = allocator,
        .language_list = LanguageList{},
    };
    try result.rescan();

    return result;
}

pub fn deinit(self: *Self) void {
    for (self.getLanguages()) |language| {
        self.allocator.free(language);
    }
    self.language_list.deinit(self.allocator);
    if (self.parsed) |parsed| {
        parsed.deinit();
    }
}

pub fn getLanguages(self: *Self) []const []const u8 {
    return self.language_list.items;
}

pub fn getStrings(self: *const Self) ?*const Strings {
    if (self.parsed) |parsed| {
        return &parsed.value;
    }
    return null;
}

pub fn useDefaultLanguage(self: *Self) !void {
    const arena = try self.allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(self.allocator);
    self.parsed = .{ .arena = arena, .value = Strings{} };
}

pub fn loadLangugeFromFile(self: *Self, file_name: []const u8) !void {
    const cwd = std.fs.cwd();
    const dir = try cwd.openDir(
        language_dir,
        .{ .access_sub_paths = false },
    );
    const file_content = try dir.readFileAlloc(
        self.allocator,
        file_name,
        bytes_limit,
    );
    defer self.allocator.free(file_content);

    const new_language = try std.json.parseFromSlice(
        Strings,
        self.allocator,
        file_content,
        .{
            .allocate = .alloc_if_needed,
            .duplicate_field_behavior = .use_last,
            .ignore_unknown_fields = true,
        },
    );

    if (self.parsed) |parsed| {
        parsed.deinit();
    }

    self.parsed = new_language;
    std.log.info("Loaded language from file: {s}", .{file_name});
    std.log.info("{}", .{self.parsed.?.value});
}

pub fn switchLanguge(self: *Self, index: usize) !void {
    try self.loadLangugeFromFile(self.getLanguages()[index]);
}

pub fn rescan(self: *Self) !void {
    self.language_list.clearRetainingCapacity();
    const cwd = std.fs.cwd();
    const dir = try cwd.openDir(
        language_dir,
        .{ .access_sub_paths = false, .iterate = true },
    );
    var iter = dir.iterate();

    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".json")) {
            try self.language_list.append(
                self.allocator,
                try self.allocator.dupe(u8, entry.name),
            );
        }
    }
}

test "Language Repo" {
    var language_repo = try Self.init(std.testing.allocator);
    defer language_repo.deinit();
}
