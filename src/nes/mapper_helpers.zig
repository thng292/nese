const Mapper = @import("mappers/mapper_interface.zig");
const Rom = @import("ines.zig").ROM;
const Mapper0 = @import("mappers/mapper0.zig");
const Mapper1 = @import("mappers/mapper1.zig");
const Mapper2 = @import("mappers/mapper2.zig");
const Mapper3 = @import("mappers/mapper3.zig");
const Mapper4 = @import("mappers/mapper4.zig");

pub const MapperTag = enum(u8) {
    mapper0,
    mapper1,
    mapper2,
    mapper3,
    mapper4,
    _,
};

pub const MapperUnion = union(MapperTag) {
    mapper0: Mapper0,
    mapper1: Mapper1,
    mapper2: Mapper2,
    mapper3: Mapper3,
    mapper4: Mapper4,
};

pub const CrateMapperError = error{
    MapperNotSupported,
};

pub fn createMapper(mapperID: u8, mapperMem: *MapperUnion, rom: *Rom) !Mapper {
    switch (mapperID) {
        0 => {
            mapperMem.* = MapperUnion{ .mapper0 = Mapper0.init(rom) };
            return mapperMem.mapper0.toMapper();
        },
        1 => {
            mapperMem.* = MapperUnion{ .mapper1 = Mapper1.init(rom) };
            return mapperMem.mapper1.toMapper();
        },
        2 => {
            mapperMem.* = MapperUnion{ .mapper2 = Mapper2.init(rom) };
            return mapperMem.mapper2.toMapper();
        },
        3 => {
            mapperMem.* = MapperUnion{ .mapper3 = Mapper3.init(rom) };
            return mapperMem.mapper3.toMapper();
        },
        4 => {
            mapperMem.* = MapperUnion{ .mapper4 = Mapper4.init(rom) };
            return mapperMem.mapper4.toMapper();
        },
        else => {
            return CrateMapperError.MapperNotSupported;
        },
    }
}
