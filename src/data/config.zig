const std = @import("std");
const meta = @import("meta.zig");

const ControllerMap = @import("../nes/control.zig").ControllerMap;

const Self = @This();

pub const GeneralConfig = struct {
    ui_scale: f32 = 1,
    show_metric: bool = false,
    language_file_path: []const u8,
};

pub const GameConfig = struct {
    game_scale: f32 = 2,
    emulation_speed: u32 = 100,
    input_poll_rate: u32 = 400,
    controller1_map: ControllerMap,
    controller2_map: ControllerMap,
};

general: GeneralConfig,
game: GameConfig,
