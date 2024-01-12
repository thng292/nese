pub const devInterface = struct {
    context: *void,
    inRangeFn: *const fn (context: *void, address: u16) bool,
    readFn: *const fn (context: *void, address: u16) u8,
    writeFn: *const fn (context: *void, address: u16, data: u8) void,

    pub fn inRange(self: *devInterface, address: u16) bool {
        return self.inRangeFn(self.context, address);
    }

    pub fn read(self: *devInterface, address: u16) u8 {
        return self.readFn(self.context, address);
    }

    pub fn write(self: *devInterface, address: u16, data: u8) void {
        self.writeFn(self.context, address, data);
    }
};

pub fn toDevInterface(comptime T: type, Context: *T) devInterface {
    const anon = struct {
        pub fn inRange(context: *void, address: u16) bool {
            const tmp: *T = @alignCast(@ptrCast(context));
            return tmp.inRange(address);
        }

        pub fn read(context: *void, address: u16) u8 {
            const tmp: *T = @alignCast(@ptrCast(context));
            return tmp.read(address);
        }

        pub fn write(context: *void, address: u16, data: u8) void {
            const tmp: *T = @alignCast(@ptrCast(context));
            return tmp.write(address, data);
        }
    };
    return devInterface{ .context = @ptrCast(Context), .inRangeFn = anon.inRange, .readFn = anon.read, .writeFn = anon.write };
}

test "devInterface" {
    const std = @import("std");
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
    var devInter = toDevInterface(testDev, &tmp);
    try std.testing.expect(devInter.inRange(5));
}
