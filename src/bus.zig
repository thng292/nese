const devInterfaceImport = @import("devInterface.zig");
const devInterface = devInterfaceImport.devInterface;
const std = @import("std");

pub const Bus = struct {
    devs: std.ArrayList(devInterface),

    pub fn init(allocator: std.mem.Allocator) Bus {
        return Bus{ .devs = std.ArrayList(devInterface).init(allocator) };
    }

    pub fn deinit(self: *Bus) void {
        self.devs.deinit();
    }

    pub fn read(self: *Bus, address: u16) u8 {
        for (self.devs.items) |*dev| {
            if (dev.inRange(address)) {
                return dev.read(address);
            }
        }
        std.debug.print("Missed 0x{x}\n", .{address});
        std.os.exit(1);
        return 0;
    }

    pub fn write(self: *Bus, address: u16, data: u8) void {
        for (self.devs.items) |*dev| {
            if (dev.inRange(address)) {
                return dev.write(address, data);
            }
        }
        std.debug.print("Missed 0x{x}", .{address});
    }

    pub fn register(self: *Bus, dev: anytype) !void {
        // comptime if (std.meta.trait.isSingleItemPtr(@TypeOf(dev)) == false) {
        //     @compileError("Accept pointer only");
        // };
        try self.devs.append(devInterfaceImport.toDevInterface(@TypeOf(dev.*), dev));
    }
};

test "bus test" {
    const testDev = struct {
        const Self = @This();
        min: u16,
        max: u16,

        pub fn inRange(self: *Self, address: u16) bool {
            return self.min <= address and address <= self.max;
        }

        pub fn read(self: *Self, address: u16) u8 {
            _ = address;
            _ = self;
            return 12;
        }

        pub fn write(self: *Self, address: u16, data: u8) void {
            _ = self;
            _ = data;
            _ = address;
        }
    };

    var tmp = testDev{ .min = 0, .max = 100 };

    var bus = Bus.init(std.testing.allocator);
    defer bus.deinit();
    try bus.register(&tmp);
}
