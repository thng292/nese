const std = @import("std");

pub const RAM = struct {
    data: [2048]u8 = undefined,

    pub fn inRange(self: *RAM, addr: u16) bool {
        _ = self;
        return addr <= 0x2000;
    }

    fn getAddr(addr: u16) u16 {
        return addr % 2048;
    }

    pub fn read(self: *RAM, addr: u16) u8 {
        return self.data[getAddr(addr)];
    }

    pub fn write(self: *RAM, addr: u16, data: u8) void {
        if (getAddr(addr) <= 0xFF) {
            std.debug.print("0x{x} = {x:2}\n", .{ getAddr(addr), data });
        }
        self.data[getAddr(addr)] = data;
    }
};
