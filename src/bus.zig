const std = @import("std");
const Mapper = @import("mapper.zig");
const Ram = @import("ram.zig");
const PPU = @import("ppu2C02.zig");
const Control = @import("control.zig");
const APU = @import("apu2A03.zig");

pub const Bus = struct {
    mapper: Mapper,
    ram: *Ram,
    ppu: *PPU,
    control: *Control,
    apu: *APU,
    nmiSet: bool = false,
    irqSet: bool = false,
    dmaReq: bool = false,

    pub fn init(mapper: Mapper, ppu: *PPU, ram: *Ram, control: *Control, apu: *APU) Bus {
        return Bus{
            .ram = ram,
            .control = control,
            .apu = apu,
            .ppu = ppu,
            .mapper = mapper,
        };
    }

    pub fn read(self: *Bus, addr: u16) u8 {
        return switch (addr) {
            0x0000...0x1FFF => self.ram.read(addr),
            0x2000...0x3FFF => self.ppu.read(addr),
            0x4016, 0x4017 => self.control.read(addr),
            0x4020...0xFFFF => self.mapper.cpuRead(addr),
            else => 0,
        };
    }

    pub fn write(self: *Bus, addr: u16, data: u8) void {
        switch (addr) {
            0x0000...0x1FFF => self.ram.write(addr, data),
            0x2000...0x3FFF => self.ppu.write(addr, data),
            0x4000...0x4013, 0x4015, 0x4017 => self.apu.write(addr, data),
            0x4014 => {
                self.dmaReq = true;
                for (0..256) |ii| {
                    const i: u16 = @truncate(ii);
                    self.ppu.oam[i] = self.ram.read(i + data);
                }
            }, // COPY OAM DATA
            0x4016 => self.control.write(addr, data),
            0x4020...0xFFFF => self.mapper.cpuWrite(addr, data),
            else => {},
        }
    }
};
