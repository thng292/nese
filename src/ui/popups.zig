const std = @import("std");
const zgui = @import("zgui");

const Strings = @import("../data/i18n.zig");
const Callable = @import("../data/callable.zig").Callable;

pub const AddGamePopup = struct {
    pub const Callback = Callable(fn ([]u8) anyerror!void);
    path_buffer: [:0]u8,
    callback: Callback,
    @"error": ?anyerror = null,

    pub fn draw(self: *AddGamePopup, strings: Strings) void {
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
                if (self.callback.call(.{std.mem.span(self.path_buffer.ptr)})) {
                    @memset(self.path_buffer, 0);
                    zgui.closeCurrentPopup();
                } else |e| {
                    self.@"error" = e;
                }
            }

            zgui.sameLine(.{ .spacing = 4 });

            if (zgui.button(strings.add_game_popup.cancel, .{}) or zgui.isKeyDown(.escape)) {
                @memset(self.path_buffer, 0);
                zgui.closeCurrentPopup();
            }
        }
    }
};
