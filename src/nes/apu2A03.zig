const APU = @This();
const std = @import("std");

pub fn write(self: *APU, addr: u16, data: u8) void {
    _ = self;
    _ = addr;
    _ = data;
}
