const RAM = @This();
data: [2048]u8 = @import("std").mem.zeroes([2048]u8),

inline fn getAddr(addr: u16) u16 {
    return addr % 2048;
}

pub inline fn read(self: *RAM, addr: u16) u8 {
    return self.data[getAddr(addr)];
}

pub inline fn write(self: *RAM, addr: u16, data: u8) void {
    // if (getAddr(addr) <= 0xFF) {
    //     std.debug.print("0x{x} = {x:2}\n", .{ getAddr(addr), data });
    // }
    self.data[getAddr(addr)] = data;
}
