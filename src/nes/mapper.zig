const std = @import("std");
const assert = std.debug.assert;

pub const MirroringMode = enum(u1) {
    Horizontal,
    Vertical,
};

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
get_mirroring_mode_fn: *const fn (context: *void) MirroringMode,
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

pub inline fn getMirroringMode(self: *Mapper) MirroringMode {
    return self.get_mirroring_mode_fn(self.context);
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

        pub fn getMirroringMode(context: *void) MirroringMode {
            const tmp: T = @alignCast(@ptrCast(context));
            return tmp.getMirroringMode();
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
        .get_mirroring_mode_fn = anon.getMirroringMode,
        .get_nmi_scanline_fn = anon.getNMIScanline,
    };
}

test "To Mapper Interface" {
    const anon = struct {
        const Self = @This();
        pub fn cpuRead(context: *Self, address: u16) u8 {
            _ = address;
            _ = context;
            return 42;
        }

        pub fn cpuWrite(context: *Self, address: u16, data: u8) void {
            _ = data;
            _ = address;
            _ = context;
        }

        pub fn ppuDecode(context: *Self, addr: u16) u16 {
            _ = context;
            return addr;
        }

        pub fn getMirroringMode(context: *Self) MirroringMode {
            _ = context;
            return .Vertical;
        }

        pub fn getNMIScanline(context: *Self) u16 {
            _ = context;
            return 400;
        }
    };

    var tmp = anon{};

    var tt = toMapper(&tmp);
    try std.testing.expect(tt.cpuRead(0) == 42);
}
