const std = @import("std");
const zgui = @import("zgui");
const zglfw = @import("zglfw");
const Strings = @import("i18n.zig");

const Callable = @import("callable.zig").Callable;
const Config = @import("config.zig");
const Self = @This();

const nes_file_extentions = .{".nes"};
pub const OpenGameCallable = Callable(fn (file_path: []u8) void);

config: *Config,
open_game_callable: OpenGameCallable,
selected: usize = std.math.maxInt(usize),

table_flags: zgui.TableFlags = .{
    .sortable = false,
    .resizable = true,
    .sizing = .stretch_prop,
    .no_borders_in_body_until_resize = true,
    .scroll_y = true,
    .pad_outer_x = true,
    .borders = .{ .inner_h = true, .inner_v = false },
},
row_pad: struct { x: f32 = 32, y: f32 = 16 } = .{},

pub fn drawMenu(self: *Self, strings: Strings) void {
    const view_port = zgui.getMainViewport();
    const view_port_size = view_port.getWorkSize();
    const view_port_pos = view_port.getWorkPos();

    const screen_w = view_port_size[0];
    const screen_h = view_port_size[1];
    const style = zgui.getStyle();

    const mouse_pos = zgui.getMousePos();

    zgui.setNextWindowPos(.{
        .cond = .always,
        .x = view_port_pos[0],
        .y = view_port_pos[1],
    });
    zgui.setNextWindowSize(
        .{ .cond = .always, .w = screen_w, .h = screen_h },
    );

    zgui.pushStyleVar2f(.{ .idx = .window_padding, .v = [_]f32{ 0, 0 } });
    defer zgui.popStyleVar(.{});

    if (zgui.begin("Main Menu", .{ .flags = .{
        .no_resize = true,
        .no_move = true,
        .no_collapse = true,
        .no_title_bar = true,
    } })) {
        defer zgui.end();

        if (zgui.beginTable("MainMenu_Games", .{
            .column = 3,
            .flags = self.table_flags,
        })) {
            defer zgui.endTable();

            zgui.tableSetupScrollFreeze(0, 1);
            zgui.tableNextRow(.{
                .row_flags = .{ .headers = true },
            });
            _ = zgui.tableNextColumn();
            zgui.textWrapped("{s}", .{strings.main_menu.games});
            _ = zgui.tableNextColumn();
            zgui.textWrapped("{s}", .{strings.main_menu.time_played});
            _ = zgui.tableNextColumn();
            zgui.textWrapped("{s}", .{strings.main_menu.favorite});

            zgui.pushStyleVar2f(.{
                .idx = zgui.StyleVar.cell_padding,
                .v = [_]f32{ self.row_pad.x, self.row_pad.y },
            });
            defer zgui.popStyleVar(.{});

            for (self.config.games, 0..) |game, i| {
                zgui.tableNextRow(.{});
                var row_height: f32 = 0;

                _ = zgui.tableNextColumn();
                zgui.textWrapped("{s}", .{game.name});
                row_height = @max(row_height, zgui.getItemRectSize()[1] + self.row_pad.y * 2);
                const row_top = zgui.getItemRectMin()[1] - self.row_pad.y;

                _ = zgui.tableNextColumn();
                zgui.textWrapped("{d}", .{game.playtime});
                row_height = @max(row_height, zgui.getItemRectSize()[1] + self.row_pad.y * 2);

                _ = zgui.tableNextColumn();
                zgui.textWrapped("{}", .{game.is_favorite});
                row_height = @max(row_height, zgui.getItemRectSize()[1] + self.row_pad.y * 2);

                const relative_pos = mouse_pos[1] - row_top;
                const hovered = relative_pos > 0 and relative_pos <= row_height;

                if (hovered) {
                    zgui.tableSetBgColor(.{
                        .target = .row_bg0,
                        .color = zgui.colorConvertFloat4ToU32(
                            style.colors[@intFromEnum(zgui.StyleCol.tab_hovered)],
                        ),
                    });
                }

                if (hovered and zgui.isMouseClicked(.left)) {
                    self.selected = i;
                }

                if (hovered and zgui.isMouseDoubleClicked(.left)) {
                    self.open_game_callable.call(.{game.path});
                }

                if (hovered and zgui.isMouseClicked(.right)) {
                    zgui.openPopup("MainMenu_ContextMenu", .{ .mouse_button_right = true });
                }

                if (self.selected == i) {
                    zgui.tableSetBgColor(.{
                        .target = .row_bg0,
                        .color = zgui.colorConvertFloat4ToU32(
                            style.colors[@intFromEnum(zgui.StyleCol.tab_selected)],
                        ),
                    });
                }
            }
        }

        if (zgui.beginPopup("MainMenu_ContextMenu", .{})) {
            defer zgui.endPopup();
        }
    }
}
