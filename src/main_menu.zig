const std = @import("std");
const builtin = @import("builtin");
const zgui = @import("zgui");
const zglfw = @import("zglfw");

const Strings = @import("i18n.zig");
const Callable = @import("callable.zig").Callable;
const Config = @import("config.zig");
const ChangeGamePathPopup = @import("popups.zig").AddGamePopup;
const Self = @This();

const max_usize = std.math.maxInt(usize);

arena: std.heap.ArenaAllocator,
buffer: [:0]u8,
config: *Config,
change_path_popup: ChangeGamePathPopup,
open_game_callable: OpenGameCallable,
selected: usize = max_usize,
hovering: usize = max_usize,
renaming: usize = max_usize,
changing: usize = max_usize,

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

pub fn init(allocator: std.mem.Allocator, config: *Config, callback: OpenGameCallable) !Self {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const buffer = try arena.child_allocator.allocSentinel(u8, 1024, 0);
    @memset(buffer, 0);
    return Self{
        .config = config,
        .open_game_callable = callback,
        .arena = arena,
        .buffer = buffer,
        .change_path_popup = ChangeGamePathPopup{
            .config = config,
            .callback = ChangeGamePathPopup.Callback
                .init(Self.changeGamePath, null, null),
            .path_buffer = buffer,
        },
    };
}

pub fn deinit(self: *Self) void {
    self.arena.child_allocator.free(self.buffer);
    self.arena.deinit();
}

pub fn draw(self: *Self, strings: Strings) void {
    _ = self.arena.reset(.retain_capacity);
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
    var style_popped = false;
    defer {
        if (!style_popped) {
            zgui.popStyleVar(.{});
        }
    }

    if (self.renaming != max_usize and zgui.isKeyDown(.escape)) {
        self.renaming = max_usize;
    }

    if (zgui.begin("Main Menu", .{ .flags = .{
        .no_resize = true,
        .no_move = true,
        .no_collapse = true,
        .no_title_bar = true,
    } })) {
        defer zgui.end();
        zgui.popStyleVar(.{});
        style_popped = true;

        if (zgui.beginTable("MainMenu_Games", .{
            .column = 3,
            .flags = self.table_flags,
        })) {
            defer zgui.endTable();

            drawTableHeader(strings);

            zgui.pushStyleVar2f(.{
                .idx = zgui.StyleVar.cell_padding,
                .v = [_]f32{ self.row_pad.x, self.row_pad.y },
            });
            defer zgui.popStyleVar(.{});

            for (self.config.games, 0..) |*game, i| {
                self.drawGameRow(game, i, mouse_pos, style);
            }

            self.drawContextMenu(strings);
            self.change_path_popup.draw(strings);
        }
    }
}

inline fn drawGameRow(
    self: *Self,
    game: *Config.Game,
    i: usize,
    mouse_pos: [2]f32,
    style: *zgui.Style,
) void {
    zgui.tableNextRow(.{});
    var row_height: f32 = 0;

    _ = zgui.tableNextColumn();
    if (self.renaming == i) {
        if (zgui.inputText("##RenameInput", .{
            .buf = self.buffer,
            .flags = zgui.InputTextFlags{
                .auto_select_all = true,
                .enter_returns_true = true,
            },
        })) {
            const strlen = std.mem.indexOfSentinel(u8, 0, self.buffer);
            self.config.renameGameCopy(i, self.buffer[0..strlen]) catch {};
            self.renaming = max_usize;
            @memset(self.buffer, 0);
        }
    } else {
        zgui.textWrapped("{s}", .{game.name});
    }
    row_height = @max(row_height, zgui.getItemRectSize()[1] + self.row_pad.y * 2);
    const row_top = zgui.getItemRectMin()[1] - self.row_pad.y;

    _ = zgui.tableNextColumn();
    zgui.textWrapped("{d}", .{@divTrunc(game.playtime, std.time.s_per_min)});
    row_height = @max(row_height, zgui.getItemRectSize()[1] + self.row_pad.y * 2);

    _ = zgui.tableNextColumn();
    const checkbox_label = blk: {
        const allocator = self.arena.allocator();
        if (comptime builtin.mode == .Debug) {
            break :blk std.fmt.allocPrintZ(allocator, "##MainMenu_FavoriteCheckBox_{}", .{i});
        } else {
            break :blk std.fmt.allocPrintZ(allocator, "##CB{}", .{i});
        }
    } catch |e| {
        std.process.exit(@intFromError(e));
    };

    if (zgui.checkbox(checkbox_label, .{ .v = &game.is_favorite })) {
        self.config.sortGames();
    }
    row_height = @max(row_height, zgui.getItemRectSize()[1] + self.row_pad.y * 2);

    const relative_pos = mouse_pos[1] - row_top;
    const hovered = relative_pos > 0 and relative_pos <= row_height //
    and zgui.isWindowHovered(.{});

    if (hovered) {
        self.hovering = i;
        zgui.tableSetBgColor(.{
            .target = .row_bg0,
            .color = zgui.colorConvertFloat4ToU32(
                style.colors[@intFromEnum(zgui.StyleCol.tab_hovered)],
            ),
        });
    }

    if (self.hovering == i and zgui.isPopupOpen(
        context_menu_id,
        .{ .mouse_button_right = true },
    )) {
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
        zgui.openPopup(
            context_menu_id,
            .{ .mouse_button_right = true },
        );
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

inline fn drawContextMenu(self: *Self, strings: Strings) void {
    var should_popup = false;
    if (zgui.beginPopup(context_menu_id, .{})) {
        defer zgui.endPopup();
        if (zgui.menuItem(strings.main_menu_context_menu.open, .{})) {
            self.open_game_callable.call(.{self.config.games[self.hovering].path});
        }
        if (zgui.menuItem(strings.main_menu_context_menu.remove, .{})) {
            self.config.removeGame(self.hovering);
        }
        const is_favorite = self.config.ns.games_list.items[self.hovering].is_favorite;
        if (zgui.menuItem(if (is_favorite) strings.main_menu_context_menu.unmark_favorite //
        else strings.main_menu_context_menu.mark_favorite, .{})) {
            self.config.toggleFavorite(self.hovering);
        }
        if (zgui.menuItem(strings.main_menu_context_menu.rename, .{})) {
            self.renaming = self.hovering;
            std.mem.copyForwards(
                u8,
                self.buffer,
                self.config.games[self.renaming].name,
            );
        }

        if (zgui.menuItem(strings.main_menu_context_menu.change_path, .{})) {
            self.changing = self.hovering;
            std.mem.copyForwards(u8, self.buffer, self.config.games[self.changing].path);
            self.change_path_popup.callback.context = self;
            should_popup = true;
        }
    }
    if (should_popup) {
        zgui.openPopup(strings.add_game_popup.change_path, .{});
    }
}

fn changeGamePath(self_: *anyopaque, path: []u8) !void {
    var self: *Self = @ptrCast(@alignCast(self_));
    try std.fs.cwd().access(path, .{ .mode = .read_only });
    try self.config.changePathCopy(self.changing, path);
    self.changing = max_usize;
}

inline fn drawTableHeader(strings: Strings) void {
    zgui.tableSetupScrollFreeze(0, 1);
    zgui.tableNextRow(.{
        .row_flags = .{ .headers = true },
    });
    _ = zgui.tableNextColumn();
    zgui.textWrapped("{s}", .{strings.main_menu.games});
    _ = zgui.tableNextColumn();
    zgui.textWrapped("{s} (minutes)", .{strings.main_menu.time_played});
    _ = zgui.tableNextColumn();
    zgui.textWrapped("{s}", .{strings.main_menu.favorite});
}

const nes_file_extentions = .{".nes"};
pub const OpenGameCallable = Callable(fn (file_path: []u8) void);
const context_menu_id = "MainMenu_ContextMenu";
