const std = @import("std");
const sdl = @import("zsdl");

pub const ControllerMap = struct {
    A: sdl.Keycode,
    B: sdl.Keycode,
    Select: sdl.Keycode,
    Start: sdl.Keycode,
    Up: sdl.Keycode,
    Down: sdl.Keycode,
    Left: sdl.Keycode,
    Right: sdl.Keycode,
};

const IO = @This();

pub inline fn read(self: *const IO, addr: u16) u8 {
    _ = addr;
    _ = self;
    return 0;
}

pub inline fn write(self: *IO, addr: u16, data: u8) void {
    _ = data;
    _ = addr;
    _ = self;
}
