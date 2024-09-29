const std = @import("std");
const zgui = @import("zgui");
const builtin = @import("builtin");

const Strings = @import("../data/i18n.zig");
const project_link = "https://github.com/thng292/nese";

pub fn drawAbout(popen: *bool, strings: Strings) void {
    if (zgui.begin(strings.about.title, .{ .popen = popen })) {
        defer zgui.end();
        zgui.textWrapped("{s}: 0.2.0", .{strings.about.version});
        zgui.textWrapped("{s}: thng292", .{strings.about.made_by});
        zgui.textWrapped("{s}: {s}", .{ strings.about.source_code, project_link });
        if (zgui.isItemClicked(.left)) {
            zgui.setClipboardText(project_link);
        }
    }
}

extern fn TextLinkOpenURL(label: [*:0]const u8, url: [*:0]const u8) void;
