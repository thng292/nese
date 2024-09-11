const std = @import("std");
const zgui = @import("zgui");

const Config = @import("config.zig");
const Strings = @import("i18n.zig");

const ConfigMenu = struct {
    config: *Config,

    pub fn draw(self: *ConfigMenu, strings: Strings) void {}
};
