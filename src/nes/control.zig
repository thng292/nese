const std = @import("std");
const sdl = @import("zsdl");

pub const ControllerMap = struct {
    state: u8 = 0,
    buffer: u8 = 0,
    A: sdl.Keycode = @enumFromInt('e'),
    B: sdl.Keycode = sdl.Keycode.lshift,
    Select: sdl.Keycode = sdl.Keycode.lctrl,
    Start: sdl.Keycode = @enumFromInt(' '),
    Up: sdl.Keycode = @enumFromInt('w'),
    Down: sdl.Keycode = @enumFromInt('s'),
    Left: sdl.Keycode = @enumFromInt('a'),
    Right: sdl.Keycode = @enumFromInt('d'),

    pub inline fn updateState(self: *ControllerMap) void {
        // Testing
        // self.buffer |= 4; // Always pressing down button
        // std.debug.print("Buffer: {b:0>8}\n", .{self.buffer});
        self.state = self.buffer;
        // std.debug.print("State:  {b:0>8}\n", .{self.state});
        // self.buffer = 0;
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
    // std.debug.print("Readed\n", .{});
    const controller = if (addr == 0x4016) &self.controller1 else &self.controller2;
    const tmp = controller.state;
    // std.debug.print("tmp: {}\n", .{controller.*});
    controller.state <<= 1;
    // std.debug.print("State: {b:0>8}\n", .{controller.state});
    return tmp >> 7;
}

pub inline fn write(self: *Control, _: u16, data: u8) void {
    // std.debug.print("Data: {}\n", .{data});
    // std.debug.print("Wrote\n", .{});
    if (data & 0b1 == 0) {
        self.controller1.updateState();
        self.controller2.updateState();
    }
}

pub inline fn handleKeyDownEvent(self: *Control, event: sdl.Event) void {
    // std.debug.print("{}\n", .{event.key.type});
    // std.debug.print("{}\n", .{self.controller1});
    // if (self.polling == true) {
    self.controller1.handleKeyDown(event.key.keysym.sym);
    self.controller2.handleKeyDown(event.key.keysym.sym);
    // }
}

pub inline fn handleKeyUpEvent(self: *Control, event: sdl.Event) void {
    // std.debug.print("{}\n", .{event.key.type});
    // std.debug.print("{}\n", .{self.controller1});
    // if (self.polling == true) {
    self.controller1.handleKeyUp(event.key.keysym.sym);
    self.controller2.handleKeyUp(event.key.keysym.sym);
    // }
}
