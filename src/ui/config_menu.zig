const std = @import("std");
const zgui = @import("zgui");

const Strings = @import("../data/i18n.zig");
const Callable = @import("../data/callable.zig").Callable;
const LanguageRepo = @import("../repo/language_repo.zig");
const GameRepo = @import("../repo/game_repo.zig");
const ConfigRepo = @import("../repo/config_repo.zig");
const Utils = @import("utils.zig");

const max_int = std.math.maxInt(usize);
const Self = @This();
const row_pad: struct { x: f32 = 32, y: f32 = 8 } = .{};
pub const ApplyCallback = Callable(fn () void);

arena: std.heap.ArenaAllocator,
config_repo: *ConfigRepo,
style: *const zgui.Style,
language_repo: *LanguageRepo,
game_repo: *GameRepo,
buffer: [:0]u8,
combo_buffer: std.ArrayListUnmanaged([:0]const u8),
apply_fn: ApplyCallback,

selected_lang: usize = 0,
hovering_folder: usize = max_int,

pub fn init(
    allocator_: std.mem.Allocator,
    style: *const zgui.Style,
    config_repo: *ConfigRepo,
    language_repo: *LanguageRepo,
    game_repo: *GameRepo,
    buffer: [:0]u8,
    apply_fn: ApplyCallback,
) !Self {
    const arena = std.heap.ArenaAllocator.init(allocator_);
    const allocator = arena.child_allocator;
    var combo = std.ArrayListUnmanaged([:0]const u8){};
    var current_selected: usize = 0;
    for (language_repo.getLanguages(), 0..) |lang, i| {
        try combo.append(allocator, try allocator.dupeZ(u8, lang));
        if (std.mem.eql(u8, lang, config_repo.config.general.language_file_path)) {
            current_selected = i;
        }
    }
    const total_len = combo.items.len;
    combo.shrinkAndFree(allocator, total_len);

    return Self{
        .arena = arena,
        .style = style,
        .config_repo = config_repo,
        .language_repo = language_repo,
        .game_repo = game_repo,
        .buffer = buffer,
        .combo_buffer = combo,
        .apply_fn = apply_fn,
        .selected_lang = current_selected,
    };
}

pub fn deinit(self: *Self) void {
    const allocator = self.arena.child_allocator;
    for (self.combo_buffer.items) |buffer| {
        allocator.free(buffer);
    }
    self.combo_buffer.deinit(allocator);
    self.arena.deinit();
}

pub fn draw(self: *Self, popen: *bool, strings: Strings) void {
    _ = self.arena.reset(.retain_capacity);
    if (zgui.begin("Config Menu", .{ .popen = popen, .flags = .{
        .no_collapse = true,
    } })) {
        defer zgui.end();
        if (zgui.beginTabBar("Config Tabs", .{
            .no_close_with_middle_mouse_button = true,
        })) {
            defer zgui.endTabBar();
            if (zgui.beginTabItem(
                strings.config_menu.tab_general,
                .{ .flags = .{ .no_reorder = true } },
            )) {
                defer zgui.endTabItem();
                self.drawGeneralConfig(strings);
                self.drawFolderManager(strings);
            }

            if (zgui.beginTabItem(
                strings.config_menu.tab_game,
                .{ .flags = .{ .no_reorder = true } },
            )) {
                defer zgui.endTabItem();
                zgui.textWrapped("This is a test for tab {s}", .{strings.config_menu.tab_game});
            }

            if (zgui.beginTabItem(
                strings.config_menu.tab_control,
                .{ .flags = .{ .no_reorder = true } },
            )) {
                defer zgui.endTabItem();
                zgui.textWrapped("This is a test for tab {s}", .{strings.config_menu.tab_control});
            }
        }
    }
}

fn drawGeneralConfig(self: *Self, strings: Strings) void {
    Utils.centeredTextSamelineWidget(
        self.style,
        strings.config_menu.language,
    );

    if (zgui.beginCombo("##language_select", .{
        .flags = .{ .width_fit_preview = false },
        .preview_value = self.combo_buffer.items[self.selected_lang],
    })) {
        defer zgui.endCombo();
        for (self.combo_buffer.items, 0..) |lang, i| {
            if (zgui.selectable(lang, .{})) {
                self.selected_lang = i;
                self.config_repo.changeLanguageFilePathCopy(
                    self.language_repo.getLanguages()[@intCast(self.selected_lang)],
                ) catch {};
                if (!std.mem.eql(u8, self.config_repo.config.general.language_file_path, lang)) {
                    self.apply_fn.call(.{});
                }
            }
        }
    }

    Utils.centeredTextSamelineWidget(self.style, strings.config_menu.ui_scale);
    if (zgui.dragFloat("##ui_scale", .{
        .speed = 0.2,
        .min = 0.2,
        .max = 5,
        .v = &self.config_repo.config.general.ui_scale,
    })) {
        self.apply_fn.call(.{});
    }
    if (zgui.checkbox(
        strings.config_menu.show_debug,
        .{ .v = &self.config_repo.config.general.show_metric },
    )) {
        self.apply_fn.call(.{});
    }
}

fn drawFolderManager(self: Self, strings: Strings) void {
    zgui.separatorText(strings.config_menu.all_folder);
    if (zgui.beginTable("##GameFolders", .{
        .column = 2,
        .flags = zgui.TableFlags{
            .sizing = .stretch_prop,
            .borders = .{ .outer_h = true, .outer_v = true },
            .scroll_y = true,
        },
    })) {
        defer zgui.endTable();
        zgui.pushStyleVar2f(.{
            .idx = zgui.StyleVar.cell_padding,
            .v = [_]f32{ row_pad.x, row_pad.y - self.style.frame_padding[1] },
        });
        if (zgui.tableNextColumn()) {
            _ = zgui.inputText("##AddDir", .{ .buf = self.buffer });
        }
        if (zgui.tableNextColumn()) {
            if (zgui.button(strings.config_menu.add, .{})) {
                self.game_repo.addDirectoryCopy(self.buffer) catch |e| {
                    std.debug.print("{s}", .{@errorName(e)});
                };
            }
        }
        zgui.popStyleVar(.{});

        zgui.pushStyleVar2f(.{
            .idx = zgui.StyleVar.cell_padding,
            .v = [_]f32{ row_pad.x, row_pad.y },
        });
        defer zgui.popStyleVar(.{});

        for (self.game_repo.getDirs(), 0..) |dir, i| {
            if (zgui.tableNextColumn()) {
                zgui.text("{s}", .{dir});
            }

            if (zgui.tableNextColumn()) {
                if (zgui.smallButton(zgui.formatZ("{s}##{d}", .{ strings.config_menu.remove, i }))) {
                    self.game_repo.removeDirectory(i);
                }
            }

            const alternating_colors = [_]usize{
                @intFromEnum(zgui.StyleCol.table_row_bg_alt),
                @intFromEnum(zgui.StyleCol.table_row_bg),
            };
            zgui.tableSetBgColor(.{
                .target = .row_bg0,
                .color = zgui.colorConvertFloat4ToU32(
                    self.style.colors[alternating_colors[i % 2]],
                ),
            });
        }
    }
}
