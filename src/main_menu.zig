const std = @import("std");
const zgui = @import("zgui");
const zglfw = @import("zglfw");

const Callable = @import("callable.zig").Callable;
const Config = @import("config.zig");
const Self = @This();

const nes_file_extentions = .{".nes"};
pub const OpenGameCallable = Callable(fn (file_path: []u8) void);

arena: std.heap.ArenaAllocator,
config: *Config,
open_game_callable: OpenGameCallable,

pub fn init(
    allocator: std.mem.Allocator,
    config: *Config,
    open_game_callable: OpenGameCallable,
) !Self {
    return Self{
        .arena = std.heap.ArenaAllocator.init(allocator),
        .config = config,
        .open_game_callable = open_game_callable,
    };
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
}

pub fn drawMenu(self: *Self, window: *zglfw.Window) void {
    _ = self.arena.reset(.retain_capacity);
    const allocator = self.arena.allocator();

    const size_tuple = window.getSize();
    const screen_w = @as(f32, @floatFromInt(size_tuple[0]));
    const screen_h = @as(f32, @floatFromInt(size_tuple[1]));
    const style = zgui.getStyle();
    const button_text_align_style = style.button_text_align;
    style.button_text_align = [_]f32{ 0, 0.5 };
    defer style.button_text_align = button_text_align_style;

    zgui.setNextWindowPos(.{ .cond = .always, .x = 0, .y = 0 });
    zgui.setNextWindowSize(.{ .cond = .always, .w = screen_w, .h = screen_h });
    if (zgui.begin("Main Menu", .{ .flags = .{
        .no_resize = true,
        .no_move = true,
        .no_collapse = true,
        .no_title_bar = true,
    } })) {
        defer zgui.end();
        if (self.config.games.len == 0) {
            zgui.text("It's empty here, try adding some games.", .{});
            return;
        }
        for (self.config.games) |game| {
            const button_id = allocator.dupeZ(u8, game.name) catch "Some error occured";
            const button_size = .{ .w = screen_w, .h = 40 };

            // Set button color to almost black
            zgui.pushStyleColor4f(.{ .idx = .button, .c = [_]f32{ 0.1, 0.1, 0.1, 1.0 } });

            // Draw button with border on hover
            if (zgui.button(button_id, button_size)) {
                self.open_game_callable.call(.{game.path});
            }

            zgui.popStyleColor(.{});
            // Check for right-click to open context menu
            if (zgui.isItemClicked(.right)) {
                zgui.openPopup(button_id, .{});
            }

            // Context menu
            if (zgui.beginPopup(button_id, .{})) {
                if (zgui.menuItem("Open", .{})) {
                    self.open_game_callable.call(.{game.path});
                }
                zgui.endPopup();
            }
        }
    }
}
