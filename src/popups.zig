const std = @import("std");
const zgui = @import("zgui");

const Strings = @import("i18n.zig");
const Callable = @import("callable.zig").Callable;
const Config = @import("config.zig");

pub const AddGamePopup = struct {
    pub const Callback = Callable(fn ([]u8) anyerror!void);
    config: *Config,
    path_buffer: [:0]u8,
    callback: Callback,
    @"error": ?anyerror = null,

    pub fn draw(self: *AddGamePopup, strings: Strings) void {
        zgui.setNextWindowSize(.{ .cond = .always, .w = 300, .h = -1 });
        const is_change_path = zgui.beginPopupModal(strings.add_game_popup.change_path, .{});
        const is_add_game = zgui.beginPopupModal(strings.add_game_popup.add_game, .{});
        if (is_change_path or is_add_game) {
            defer zgui.endPopup();
            if (self.@"error") |e| {
                zgui.textWrapped("{s}: {s}", .{
                    strings.add_game_popup.@"error",
                    @errorName(e),
                });
            }

            _ = zgui.inputText(strings.add_game_popup.game_path, .{
                .buf = self.path_buffer,
                .flags = .{ .auto_select_all = true },
            });
            if (zgui.button(
                if (is_add_game)
                    strings.add_game_popup.add_game
                else
                    strings.add_game_popup.change_path,
                .{},
            )) {
                const strlen = std.mem.indexOfSentinel(u8, 0, self.path_buffer);
                if (self.callback.call(.{self.path_buffer[0..strlen]})) {
                    @memset(self.path_buffer, 0);
                    zgui.closeCurrentPopup();
                } else |e| {
                    self.@"error" = e;
                }
            }

            zgui.sameLine(.{ .spacing = 4 });

            if (zgui.button(strings.add_game_popup.cancel, .{}) or zgui.isKeyDown(.escape)) {
                zgui.closeCurrentPopup();
            }
        }
    }
};

pub const ManageDirectoryPopup = struct {};
