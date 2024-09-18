const std = @import("std");
const zgui = @import("zgui");

pub fn centeredTextSamelineWidget(style: *const zgui.Style, text: []const u8) void {
    const initial_cursor_pos: @Vector(2, f32) = zgui.getCursorPos();
    const pad: @Vector(2, f32) = style.frame_padding;

    zgui.setCursorPos(initial_cursor_pos + pad);
    zgui.text("{s}", .{text});

    const text_size = zgui.calcTextSize(text, .{});
    zgui.setCursorPosX(initial_cursor_pos[0] + text_size[0] + pad[0] * 2);
    zgui.setCursorPosY(initial_cursor_pos[1]);
}
