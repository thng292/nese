const std = @import("std");
const zglfw = @import("zglfw");

pub const ControllerMap = struct {
    A: zglfw.Key = .space,
    B: zglfw.Key = .left_shift,
    Select: zglfw.Key = .left_control,
    Start: zglfw.Key = .e,
    Up: zglfw.Key = .w,
    Down: zglfw.Key = .s,
    Left: zglfw.Key = .a,
    Right: zglfw.Key = .d,
};

pub const ControllerState = struct {
    state: u8 = 0,
    buffer: u8 = 0,
    map: ControllerMap = .{},

    pub inline fn updateState(self: *ControllerState) void {
        self.state = self.buffer;
    }

    pub inline fn handleKey(self: *ControllerState, window: *zglfw.Window) void {
        var mask: u8 = 0;
        if (window.getKey(self.map.A) == .press) mask |= 0x80;
        if (window.getKey(self.map.B) == .press) mask |= 0x40;
        if (window.getKey(self.map.Select) == .press) mask |= 0x20;
        if (window.getKey(self.map.Start) == .press) mask |= 0x10;
        if (window.getKey(self.map.Up) == .press) mask |= 0x08;
        if (window.getKey(self.map.Down) == .press) mask |= 0x04;
        if (window.getKey(self.map.Left) == .press) mask |= 0x02;
        if (window.getKey(self.map.Right) == .press) mask |= 0x01;

        if (window.getKey(self.map.A) == .release) mask &= (0xFF ^ 0x80);
        if (window.getKey(self.map.B) == .release) mask &= (0xFF ^ 0x40);
        if (window.getKey(self.map.Select) == .release) mask &= (0xFF ^ 0x20);
        if (window.getKey(self.map.Start) == .release) mask &= (0xFF ^ 0x10);
        if (window.getKey(self.map.Up) == .release) mask &= (0xFF ^ 0x08);
        if (window.getKey(self.map.Down) == .release) mask &= (0xFF ^ 0x04);
        if (window.getKey(self.map.Left) == .release) mask &= (0xFF ^ 0x02);
        if (window.getKey(self.map.Right) == .release) mask &= (0xFF ^ 0x01);

        self.buffer = mask;
    }
};

const Control = @This();
controller1: ControllerState = ControllerState{},
controller2: ControllerState = ControllerState{},

pub inline fn read(self: *Control, addr: u16) u8 {
    const controller = if (addr == 0x4016) &self.controller1 else &self.controller2;
    const tmp = controller.state;
    controller.state <<= 1;
    return tmp >> 7;
}

pub inline fn write(self: *Control, _: u16, data: u8) void {
    if (data & 0b1 == 0) {
        self.controller1.updateState();
        self.controller2.updateState();
    }
}

pub inline fn handleKeyEvent(self: *Control, window: *zglfw.Window) void {
    self.controller1.handleKey(window);
    self.controller2.handleKey(window);
}
