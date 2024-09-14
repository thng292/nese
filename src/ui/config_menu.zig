const std = @import("std");
const zgui = @import("zgui");

const Config = @import("../data/config.zig");
const Strings = @import("../data/i18n.zig");
const Callable = @import("../data/callable.zig").Callable;

const Self = @This();
const Callback = Callable(fn ([]const u8) void);
config: *Config,
change_language_callback: Callback,

pub fn draw(self: *Self, strings: Strings) void {
    if (zgui.beginTabBar("Config Tabs", .{
        .no_tab_list_scrolling_buttons = true,
        .draw_selected_overline = true,
    })) {
        defer zgui.endTabBar();
        if (zgui.beginTabItem(
            strings.config_menu.tab_general,
            .{ .flags = .{ .no_reorder = true } },
        )) {
            defer zgui.endTabItem();
            zgui.textWrapped("This is a test for tab {s}", .{strings.config_menu.tab_general});
        }

        if (zgui.beginTabItem(
            strings.config_menu.tab_game,
            .{ .flags = .{ .no_reorder = true } },
        )) {
            defer zgui.endTabItem();
            zgui.textWrapped("This is a test for tab {s}", .{strings.config_menu.tab_game});
        }

        if (zgui.beginTabItem(
            strings.config_menu.tab_game,
            .{ .flags = .{ .no_reorder = true } },
        )) {
            defer zgui.endTabItem();
            zgui.textWrapped("This is a test for tab {s}", .{strings.config_menu.tab_game});
        }
    }
}
