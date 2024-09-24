const std = @import("std");
const meta = @import("meta.zig");

const ControllerMap = @import("../nes/control.zig").ControllerMap;

const Self = @This();

pub const GeneralConfig = struct {
    ui_scale: u32 = 140,
    show_metric: bool = false,
    language_file_path: []const u8,
};

pub const GameConfig = struct {
    emulation_speed: u32 = 100,
    input_poll_rate: u32 = 400,
    controller1_map: ControllerMap = .{},
    controller2_map: ControllerMap = .{
        .Up = .up,
        .Down = .down,
        .Left = .left,
        .Right = .right,
        .A = .j,
        .B = .k,
        .Start = .slash,
        .Select = .l,
    },
};

general: GeneralConfig,
game: GameConfig = .{},

pub fn getUIScale(self: Self) f32 {
    const scale_percent: f32 = @floatFromInt(self.general.ui_scale);
    return scale_percent / 100;
}

pub fn getGameScale(self: Self) f32 {
    const scale_percent: f32 = @floatFromInt(self.game.game_scale);
    return scale_percent / 100;
}

pub fn getGameSpeed(self: Self) f32 {
    const speed_percent: f32 = @floatFromInt(self.game.emulation_speed);
    return speed_percent / 100;
}
