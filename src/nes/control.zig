const std = @import("std");
const zglfw = @import("zglfw");

pub const ControllerMap = struct {
    state: u8 = 0,
    buffer: u8 = 0,
    A: zglfw.Key = .space,
    B: zglfw.Key = .left_shift,
    Select: zglfw.Key = .left_control,
    Start: zglfw.Key = .e,
    Up: zglfw.Key = .w,
    Down: zglfw.Key = .s,
    Left: zglfw.Key = .a,
    Right: zglfw.Key = .d,

    pub inline fn updateState(self: *ControllerMap) void {
        self.state = self.buffer;
    }

    pub inline fn handleKey(self: *ControllerMap, window: *zglfw.Window) void {
        var mask: u8 = 0;
        if (window.getKey(self.A) == .press) mask |= 0x80;
        if (window.getKey(self.B) == .press) mask |= 0x40;
        if (window.getKey(self.Select) == .press) mask |= 0x20;
        if (window.getKey(self.Start) == .press) mask |= 0x10;
        if (window.getKey(self.Up) == .press) mask |= 0x08;
        if (window.getKey(self.Down) == .press) mask |= 0x04;
        if (window.getKey(self.Left) == .press) mask |= 0x02;
        if (window.getKey(self.Right) == .press) mask |= 0x01;

        if (window.getKey(self.A) == .release) mask &= (0xFF ^ 0x80);
        if (window.getKey(self.B) == .release) mask &= (0xFF ^ 0x40);
        if (window.getKey(self.Select) == .release) mask &= (0xFF ^ 0x20);
        if (window.getKey(self.Start) == .release) mask &= (0xFF ^ 0x10);
        if (window.getKey(self.Up) == .release) mask &= (0xFF ^ 0x08);
        if (window.getKey(self.Down) == .release) mask &= (0xFF ^ 0x04);
        if (window.getKey(self.Left) == .release) mask &= (0xFF ^ 0x02);
        if (window.getKey(self.Right) == .release) mask &= (0xFF ^ 0x01);

        self.buffer = mask;
    }
};

const Control = @This();
controller1: ControllerMap = ControllerMap{},
controller2: ControllerMap = ControllerMap{},

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
