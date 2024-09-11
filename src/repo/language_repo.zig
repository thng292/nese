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
        english.save(file);
    };

    var result = Self{
        .allocator = allocator,
        .language_list = LanguageList.init(allocator),
    };
    result.rescan();

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

pub fn getLanguages(self: *Self) [][]const u8 {
    return self.language_list.items;
}

pub fn getStrings(self: Self) ?Strings {
    if (self.parsed) |parsed| {
        return parsed.value;
    }
    return null;
}

pub fn loadLanguge(self: *Self, index: usize) !void {
    const cwd = std.fs.cwd();
    const dir = try cwd.openDir(
        language_dir,
        .{ .access_sub_paths = false },
    );
    const file_content = try dir.readFileAlloc(
        self.allocator,
        self.getLanguages()[index],
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
}

pub fn rescan(self: *Self) !void {
    const cwd = std.fs.cwd();
    const dir = try cwd.openDir(
        &language_dir,
        .{ .access_sub_paths = false, .iterate = true },
    );
    var iter = dir.iterate();

    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".json")) {
            try self.language_list.append(try self.allocator.dupe(entry.name));
        }
    }
}

pub fn iterate(self: *Self) Iterator {
    return Iterator{
        .index = 0,
        .parent = self,
    };
}

const Iterator = struct {
    index: usize,
    parent: *Self,

    pub fn next(self: Iterator) ?[]const u8 {
        const index = self.index;
        if (index >= self.parent.language_list.items.len) {
            return null;
        }
        self.index += 1;
        return self.parent.language_list.items[index];
    }

    pub fn peek(self: Iterator) ?[]const u8 {
        if (self.index >= self.parent.language_list.items.len) {
            return null;
        }
        return self.parent.language_list.items[self.index];
    }

    pub fn reset(self: Iterator) void {
        self.index = 0;
    }
};

test "Language Repo" {
    var language_repo = try Self.init(std.testing.allocator);
    defer language_repo.deinit();
}
