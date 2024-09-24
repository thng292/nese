const std = @import("std");
const zgui = @import("zgui");
const zglfw = @import("zglfw");

const ControllerMap = @import("../nes/control.zig").ControllerMap;
const Strings = @import("../data/i18n.zig");
const Callable = @import("../data/callable.zig").Callable;
const LanguageRepo = @import("../repo/language_repo.zig");
const GameRepo = @import("../repo/game_repo.zig");
const ConfigRepo = @import("../repo/config_repo.zig");
const Utils = @import("utils.zig");
const drawControlConfig = @import("control_config.zig").drawControlConfig;
pub const ApplyCallback = Callable(fn () void);
const Self = @This();

arena: std.heap.ArenaAllocator,
style: *const zgui.Style,
config_repo: *ConfigRepo,
language_repo: *LanguageRepo,
game_repo: *GameRepo,
window: *zglfw.Window,

buffer: [:0]u8,
combo_buffer: std.ArrayListUnmanaged([:0]const u8),
apply_fn: ApplyCallback,

changed: Changed = .{},
selected_lang: usize,
changing_key: ?*zglfw.Key = null,
selected_ui_scale: u32,
hovering_folder: usize = max_usize,

pub fn init(
    allocator_: std.mem.Allocator,
    window: *zglfw.Window,
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
        .window = window,
        .arena = arena,
        .style = style,
        .config_repo = config_repo,
        .language_repo = language_repo,
        .game_repo = game_repo,
        .buffer = buffer,
        .combo_buffer = combo,
        .apply_fn = apply_fn,
        .selected_lang = current_selected,
        .selected_ui_scale = config_repo.config.general.ui_scale,
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

pub fn draw(self: *Self, popen: *bool, strings: Strings) !void {
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
                try self.drawGeneralConfig(strings);
                zgui.separatorText(strings.config_menu.game_config);
                try self.drawGameConfig(strings);
                self.drawFolderManager(strings);
            }

            if (zgui.beginTabItem(
                strings.config_menu.tab_control,
                .{ .flags = .{ .no_reorder = true } },
            )) {
                defer zgui.endTabItem();
                try drawControlConfig(
                    self.arena.allocator(),
                    [2]*ControllerMap{
                        &self.config_repo.config.game.controller1_map,
                        &self.config_repo.config.game.controller2_map,
                    },
                    self.window,
                    &self.changing_key,
                    strings,
                );
            }
        }
    }
}

fn drawGeneralConfig(self: *Self, strings: Strings) !void {
    const total_w = zgui.getContentRegionAvail()[0];

    Utils.centeredTextSamelineWidget(self.style, strings.config_menu.language);
    addSpacingAndSetNextItemWidth(total_w);
    if (zgui.beginCombo("##Change_language", .{
        .flags = .{ .width_fit_preview = false },
        .preview_value = self.combo_buffer.items[self.selected_lang],
    })) {
        defer zgui.endCombo();
        for (self.combo_buffer.items, 0..) |lang, i| {
            if (zgui.selectable(lang, .{ .selected = i == self.selected_lang })) {
                self.selected_lang = i;
                if (!std.mem.eql(u8, self.config_repo.config.general.language_file_path, lang)) {
                    self.changed.changed_language = true;
                }
            }
        }
    }

    const allocator = self.arena.allocator();

    Utils.centeredTextSamelineWidget(self.style, strings.config_menu.ui_scale);
    addSpacingAndSetNextItemWidth(total_w);
    if (try Utils.comboRangeInt(
        u32,
        allocator,
        "##UI_Scale",
        "{d}%",
        &self.selected_ui_scale,
        ui_scale_range,
    )) {
        self.changed.changed_ui_scale = true;
    }

    Utils.centeredTextSamelineWidget(self.style, strings.config_menu.show_debug);
    addSpacingAndSetNextItemWidth(total_w);
    if (zgui.checkbox(
        "##Show_debug",
        .{ .v = &self.config_repo.config.general.show_metric },
    )) {}

    const button_w = (total_w - self.style.frame_padding[0]) / 2;
    zgui.beginDisabled(.{ .disabled = !self.changed.anyChange() });
    if (zgui.button(strings.config_menu.apply, .{ .w = button_w })) {
        if (self.changed.changed_language) {
            try self.config_repo.changeLanguageFilePathCopy(
                self.language_repo.getLanguages()[@intCast(self.selected_lang)],
            );
        }
        self.config_repo.config.general.ui_scale = self.selected_ui_scale;
        self.apply_fn.call(.{});
    }
    zgui.sameLine(.{ .spacing = self.style.frame_padding[0] });
    if (zgui.button(strings.config_menu.restore_last, .{ .w = button_w })) {
        for (self.language_repo.getLanguages(), 0..) |lang, i| {
            if (std.mem.eql(u8, lang, self.config_repo.config.general.language_file_path)) {
                self.selected_lang = i;
            }
        }
        self.selected_ui_scale = self.config_repo.config.general.ui_scale;
        self.changed = @bitCast(@as(u8, 0));
    }
    zgui.endDisabled();
}

fn drawGameConfig(self: *Self, strings: Strings) !void {
    const total_w = zgui.getContentRegionAvail()[0];
    const allocator = self.arena.allocator();
    Utils.centeredTextSamelineWidget(self.style, strings.config_menu.emulation_speed);
    addSpacingAndSetNextItemWidth(total_w);
    if (try Utils.comboRangeInt(
        u32,
        allocator,
        "##Game_speed",
        "{}%",
        &self.config_repo.config.game.emulation_speed,
        game_speed_range,
    )) {}

    Utils.centeredTextSamelineWidget(self.style, strings.config_menu.input_poll_rate);
    addSpacingAndSetNextItemWidth(total_w);
    if (try Utils.comboRangeInt(
        u32,
        allocator,
        "##Input_poll_rate",
        "{}",
        &self.config_repo.config.game.input_poll_rate,
        input_poll_rate_range,
    )) {}
    zgui.bullet();
    zgui.sameLine(.{});
    zgui.textWrapped("{s}", .{strings.config_menu.input_poll_rate_unlimit});
}

fn drawFolderManager(self: Self, strings: Strings) void {
    zgui.separatorText(strings.config_menu.all_folder);
    if (zgui.beginTable("##GameFolders", .{
        .column = 2,
        .flags = zgui.TableFlags{
            .sizing = .stretch_prop,
            .borders = .{ .outer_h = true, .outer_v = true },
            .scroll_y = true,
            .row_bg = true,
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
        }
    }
}

fn addSpacingAndSetNextItemWidth(total_w: f32) void {
    zgui.setCursorPosX(total_w * widget_non_width_percent);
    zgui.setNextItemWidth(total_w * widget_width_percent);
}

const max_usize = std.math.maxInt(usize);
const widget_width_percent = 0.35;
const widget_non_width_percent = 1 - widget_width_percent;
const row_pad: struct { x: f32 = 32, y: f32 = 8 } = .{};
const ui_scale_range = Utils.Range(u32){
    .min = 20,
    .max = 500,
    .step = 20,
};
const game_speed_range = Utils.Range(u32){
    .min = 20,
    .max = 1000,
    .step = 20,
};
const input_poll_rate_range = Utils.Range(u32){
    .min = 0,
    .max = 600,
    .step = 60,
};
const Changed = packed struct(u8) {
    changed_language: bool = false,
    changed_ui_scale: bool = false,
    _pad: u6 = 0,

    pub fn anyChange(self: Changed) bool {
        return @as(u8, @bitCast(self)) != 0;
    }
};
