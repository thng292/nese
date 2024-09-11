const std = @import("std");
const meta = @import("../data/meta.zig");

const Config = @import("../data/config.zig");

const Self = @This();
pub const non_serializable_fields = .{"ns"};
pub const Serializable = meta.StructWithout(Self, non_serializable_fields);
const save_dir = "data/";
const save_file_name = "config.json";
const save_file_path = save_dir ++ save_file_name;
const bytes_limit = std.math.maxInt(u20); // 1GB

allocator: std.mem.Allocator,
config: Config,

pub fn init(allocator: std.mem.Allocator) !Self {
    const cwd = std.fs.cwd();
    cwd.access(save_dir, .{ .mode = .read_write }) catch {
        try cwd.makeDir(save_dir);
    };
    var should_load = true;
    cwd.access(save_file_path, .{ .mode = .read_write }) catch {
        should_load = false;
    };

    const config = if (should_load) blk: {
        const file_content = try cwd.readFileAlloc(allocator, save_file_path, bytes_limit);
        defer allocator.free(file_content);
        const parsed = try std.json.parseFromSlice(
            Config,
            allocator,
            file_content,
            .{
                .allocate = .alloc_if_needed,
                .duplicate_field_behavior = .use_last,
                .ignore_unknown_fields = true,
            },
        );
        defer parsed.deinit();

        var loaded = parsed.value;
        loaded.general.language_file_path = allocator.dupe(loaded.general.language_file_path);

        break :blk loaded;
    } else Config{ .general = .{
        .language_file_path = try allocator.alloc(u8, 0),
    } };

    return Self{
        .allocator = allocator,
        .config = config,
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
    self.allocator.free(self.config.general.language_file_path);
}

pub fn save(self: Self, file: std.fs.File) !void {
    std.json.stringify(self.config, .{ .whitespace = .indent_4 }, file.writer());
}

pub fn changeLanguageFilePathCopy(self: *Self, path: []const u8) !void {
    self.allocator.free(self.config.general.language_file_path);
    self.config.general.language_file_path = try self.ns.allocator.dupe(u8, path);
}
