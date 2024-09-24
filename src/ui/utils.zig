const std = @import("std");
const zgui = @import("zgui");

pub fn Range(comptime T: type) type {
    return struct { min: T, max: T, step: T };
}

pub fn centeredTextSamelineWidget(style: *const zgui.Style, text: []const u8) void {
    const initial_cursor_pos: @Vector(2, f32) = zgui.getCursorPos();
    const pad: @Vector(2, f32) = style.frame_padding;

    zgui.setCursorPos(initial_cursor_pos + pad);
    zgui.text("{s}", .{text});

    const text_size = zgui.calcTextSize(text, .{});
    zgui.setCursorPosX(initial_cursor_pos[0] + text_size[0] + pad[0] * 2);
    zgui.setCursorPosY(initial_cursor_pos[1]);
}

pub fn comboRangeInt(
    comptime IntType: type,
    allocator: std.mem.Allocator,
    label: [:0]const u8,
    comptime fmt: []const u8,
    selected_value: *IntType,
    range: Range(IntType),
) !bool {
    const assert = std.debug.assert;
    assert(@typeInfo(IntType) == .Int);
    const num_items = (range.max - range.min) / range.step;
    assert(num_items > 0);

    const range_str = try allocator.alloc([:0]const u8, @intCast(num_items));
    var selected: usize = 0;
    for (range_str, 0..) |*str, i| {
        const val = range.min + i * range.step;
        str.* = try std.fmt.allocPrintZ(allocator, fmt, .{val});
        if (val == selected_value.*) {
            selected = i;
        }
    }
    if (zgui.beginCombo(label, .{ .preview_value = range_str[selected] })) {
        defer zgui.endCombo();
        for (range_str, 0..) |str, i| {
            if (zgui.selectable(str, .{ .selected = selected == i }) and selected != i) {
                selected_value.* = range.min + @as(IntType, @intCast(i)) * range.step;
                return true;
            }
        }
    }
    return false;
}

pub fn sliderFloatWithStep(label: [:0]const u8, v: *f32, range: Range(f32)) bool {
    const count_value: i32 = @intFromFloat((range.max - range.min) / range.step);
    var value: i32 = @intFromFloat((v.* - range.min) / range.step);
    const res = zgui.sliderInt(label, .{
        .v = &value,
        .min = 0,
        .max = count_value,
    });
    v.* = range.min + @as(f32, @floatFromInt(value)) * range.step;
    return res;
}

pub fn sliderIntWithStep(label: [:0]const u8, v: *i32, range: Range(i32)) bool {
    const count_value = @divFloor(range.max - range.min, range.step);
    var value = @divFloor(v.* - range.min, range.step);
    const res = zgui.sliderInt(label, .{
        .v = &value,
        .min = 0,
        .max = count_value,
    });
    v.* = range.min + value * range.step;
    return res;
}
