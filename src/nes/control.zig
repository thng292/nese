const std = @import("std");
const sdl = @import("zsdl");

pub const ControllerMap = struct {
    state: u8 = 0,
    buffer: u8 = 0,
    A: sdl.Keycode = @enumFromInt(' '),
    B: sdl.Keycode = sdl.Keycode.lshift,
    Select: sdl.Keycode = sdl.Keycode.lctrl,
    Start: sdl.Keycode = @enumFromInt('e'),
    Up: sdl.Keycode = @enumFromInt('w'),
    Down: sdl.Keycode = @enumFromInt('s'),
    Left: sdl.Keycode = @enumFromInt('a'),
    Right: sdl.Keycode = @enumFromInt('d'),

    pub inline fn updateState(self: *ControllerMap) void {
        self.state = self.buffer;
    }

    pub inline fn handleKeyDown(self: *ControllerMap, key: sdl.Keycode) void {
        var bit: u3 = 0;
        if (key == self.A) bit = 7;
        if (key == self.B) bit = 6;
        if (key == self.Select) bit = 5;
        if (key == self.Start) bit = 4;
        if (key == self.Up) bit = 3;
        if (key == self.Down) bit = 2;
        if (key == self.Left) bit = 1;
        if (key == self.Right) bit = 0;

        const mask: u8 = 1;
        self.buffer |= mask << bit;
    }

    pub inline fn handleKeyUp(self: *ControllerMap, key: sdl.Keycode) void {
        var bit: u3 = 0;
        if (key == self.A) bit = 7;
        if (key == self.B) bit = 6;
        if (key == self.Select) bit = 5;
        if (key == self.Start) bit = 4;
        if (key == self.Up) bit = 3;
        if (key == self.Down) bit = 2;
        if (key == self.Left) bit = 1;
        if (key == self.Right) bit = 0;

        const mask: u8 = 1;
        self.buffer &= 0xFF ^ (mask << bit);
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

pub inline fn handleKeyDownEvent(self: *Control, event: sdl.Event) void {
    self.controller1.handleKeyDown(event.key.keysym.sym);
    self.controller2.handleKeyDown(event.key.keysym.sym);
}

pub inline fn handleKeyUpEvent(self: *Control, event: sdl.Event) void {
    self.controller1.handleKeyUp(event.key.keysym.sym);
    self.controller2.handleKeyUp(event.key.keysym.sym);
}
