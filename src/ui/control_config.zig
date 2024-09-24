const std = @import("std");
const zglfw = @import("zglfw");
const zgui = @import("zgui");
const ControllerMap = @import("../nes/control.zig").ControllerMap;
const Strings = @import("../data/i18n.zig");

const widget_width_percent = 0.35;
const widget_non_width_percent = 1 - widget_width_percent;

pub fn drawControlConfig(
    allocator: std.mem.Allocator,
    controllers_map: [2]*ControllerMap,
    window: *zglfw.Window,
    changing_key: *?*zglfw.Key,
    strings: Strings,
) !void {
    const total_w = zgui.getContentRegionAvail()[0];
    const widget_x = total_w * widget_non_width_percent;
    const controller_fields_name = comptime std.meta.fieldNames(ControllerMap);
    var changing_field_name = controller_fields_name[0];
    var popen = false;
    var cnt: usize = 0;

    for (controllers_map, 1..) |controller_map, i| {
        zgui.separatorText(try std.fmt.allocPrintZ(
            allocator,
            "{s} {}",
            .{ strings.config_menu.controller, i },
        ));
        inline for (controller_fields_name) |field_name| {
            defer cnt += 1;
            zgui.text("{s}", .{@field(
                strings.config_menu.controller_button,
                field_name,
            )});
            zgui.sameLine(.{});
            zgui.setCursorPosX(widget_x);
            if (zgui.button(try std.fmt.allocPrintZ(
                allocator,
                "{s}",
                .{@tagName(@field(controller_map, field_name))},
            ), .{ .w = widget_width_percent * total_w })) {
                changing_key.* = &@field(controller_map, field_name);
                zgui.openPopup(strings.config_menu.map_key, .{});
            }
            if (changing_key.* == &@field(controller_map, field_name)) {
                changing_field_name = field_name;
            }
            if (changing_key.* != null) {
                popen = true;
            }
        }
    }
    if (zgui.beginPopupModal(strings.config_menu.map_key, .{ .popen = &popen })) {
        defer zgui.endPopup();
        zgui.text("{s} {s}", .{
            strings.config_menu.map_new_key,
            changing_field_name,
        });
        _ = window.setKeyCallback(&glfw_key_fn);
        defer _ = window.setKeyCallback(null);
        zglfw.waitEvents();
        if (key_pressed) |key| {
            changing_key.*.?.* = key;
            key_pressed = null;
            popen = false;
        }
    }
    if (popen == false) {
        changing_key.* = null;
    }
}

var key_pressed: ?zglfw.Key = null;

fn glfw_key_fn(
    _: *zglfw.Window,
    key: zglfw.Key,
    _: i32,
    action: zglfw.Action,
    _: zglfw.Mods,
) callconv(.C) void {
    if (action == .press) {
        key_pressed = key;
    }
}
