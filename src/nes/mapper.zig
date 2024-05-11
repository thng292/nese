const std = @import("std");
const assert = std.debug.assert;

pub const MapperTag = enum(u8) {
    Mapper0,
    Mapper1,
    Mapper2,
    Mapper3,
    Mapper4,
    _,
};

const Mapper = @This();
context: *void,
cpu_read_fn: *const fn (context: *void, addr: u16) u8,
cpu_write_fn: *const fn (context: *void, addr: u16, data: u8) void,
ppu_read_fn: *const fn (context: *void, addr: u16) u8,
ppu_write_fn: *const fn (context: *void, addr: u16, data: u8) void,
resolve_nametable_addr_fn: *const fn (context: *void, addr: u16) u16,
get_nmi_scanline_fn: *const fn (context: *void) u16,

pub inline fn cpuRead(self: *Mapper, addr: u16) u8 {
    return self.cpu_read_fn(self.context, addr);
}

pub inline fn cpuWrite(self: *Mapper, addr: u16, data: u8) void {
    return self.cpu_write_fn(self.context, addr, data);
}

pub inline fn ppuRead(self: *Mapper, addr: u16) u8 {
    return self.ppu_read_fn(self.context, addr);
}

pub inline fn ppuWrite(self: *Mapper, addr: u16, data: u8) void {
    return self.ppu_write_fn(self.context, addr, data);
}

pub inline fn resolveNametableAddr(self: *Mapper, addr: u16) u16 {
    return self.resolve_nametable_addr_fn(self.context, addr);
}

pub inline fn getNMIScanline(self: *Mapper) u16 {
    return self.get_nmi_scanline_fn(self.context);
}

pub fn toMapper(ptr: anytype) Mapper {
    const Ptr = @TypeOf(ptr);
    assert(@typeInfo(Ptr) == .Pointer); // Must be a pointer
    assert(@typeInfo(Ptr).Pointer.size == .One); // Must be a single-item pointer
    assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct); // Must point to a struct
    const T = @TypeOf(ptr);
    const anon = struct {
        pub fn cpuRead(context: *void, address: u16) u8 {
            const tmp: T = @alignCast(@ptrCast(context));
            return tmp.cpuRead(address);
        }

        pub fn cpuWrite(context: *void, address: u16, data: u8) void {
            const tmp: T = @alignCast(@ptrCast(context));
            return tmp.cpuWrite(address, data);
        }

        pub fn ppuRead(context: *void, address: u16) u8 {
            const tmp: T = @alignCast(@ptrCast(context));
            return tmp.ppuRead(address);
        }

        pub fn ppuWrite(context: *void, address: u16, data: u8) void {
            const tmp: T = @alignCast(@ptrCast(context));
            return tmp.ppuWrite(address, data);
        }

        pub fn resolveNametableAddr(context: *void, address: u16) u16 {
            const tmp: T = @alignCast(@ptrCast(context));
            return tmp.resolveNametableAddr(address);
        }

        pub fn getNMIScanline(context: *void) u16 {
            const tmp: T = @alignCast(@ptrCast(context));
            return tmp.getNMIScanline();
        }
    };

    return Mapper{
        .context = @alignCast(@ptrCast(ptr)),
        .cpu_read_fn = anon.cpuRead,
        .cpu_write_fn = anon.cpuWrite,
        .ppu_read_fn = anon.ppuRead,
        .ppu_write_fn = anon.ppuWrite,
        .resolve_nametable_addr_fn = anon.resolveNametableAddr,
        .get_nmi_scanline_fn = anon.getNMIScanline,
    };
}

test "To Mapper Interface" {
    const anon = struct {
        const Self = @This();
        pub fn cpuRead(_: *Self, _: u16) u8 {
            return 42;
        }

        pub fn cpuWrite(_: *Self, _: u16, _: u8) void {}

        pub fn ppuRead(_: *Self, _: u16) u8 {
            return 0;
        }

        pub fn ppuWrite(_: *Self, _: u16, _: u8) void {}

        pub fn resolveNametableAddr(_: *Self, _: u16) u16 {
            return 0;
        }

        pub fn getNMIScanline(_: *Self) u16 {
            return 0;
        }
    };

    var tmp = anon{};

    var tt = toMapper(&tmp);
    try std.testing.expect(tt.cpuRead(0) == 42);
}
