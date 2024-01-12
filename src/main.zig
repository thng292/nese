const std = @import("std");
const Bus = @import("bus.zig").Bus;
const CPU = @import("cpu6502.zig").CPU;
const simple_prog = @import("cpu6502.zig").simple_prog;

pub fn main() !void {
    return cpu_test_all();
}

fn cpu_test() !void {
    const Ram = @import("ram.zig").RAM;
    var bus = Bus.init(std.heap.page_allocator);
    defer bus.deinit();
    var ram = Ram{};
    try bus.register(&ram);
    var test_prog = simple_prog{ .data = &[_]u8{ 0xA9, 0x05, 0x69, 0x05 } };
    try bus.register(&test_prog);
    var cpu = CPU{ .bus = bus, .pc = 0xC000, .sp = 0xFF };
    try cpu.exec(5);
    std.debug.print("{}\n", .{cpu.a});
}

fn cpu_test_all() !void {
    const iNes = @import("ines.zig").ROM;
    const Ram = @import("ram.zig").RAM;
    const testRomFile = try std.fs.cwd().openFile("test-rom/nestest.nes", .{});
    defer testRomFile.close();
    var test_rom = try iNes.readFromFile(testRomFile, std.heap.page_allocator);
    defer test_rom.deinit();
    // std.debug.print("{}\n", .{test_rom.header});
    // var count: u8 = 0;
    // for (test_rom.PRG_RomBanks) |byte| {
    //     std.debug.print("{0x:2}", .{byte});
    //     count += 1;
    //     if (count == 16) {
    //         count = 0;
    //         std.debug.print("\n", .{});
    //     } else {
    //         std.debug.print(" ", .{});
    //     }
    // }
    // std.os.exit(0);
    var bus = Bus.init(std.heap.page_allocator);
    defer bus.deinit();
    var ram = Ram{};
    try bus.register(&ram);
    var cartridge_ram = test_rom.getCartridgeRamDev();
    try bus.register(&cartridge_ram);
    var prog_rom = test_rom.getProgramRomDev();
    try bus.register(&prog_rom);
    var cpu = CPU{ .bus = bus, .pc = 0xC000, .sp = 0xFF };
    try cpu.exec(0x4000);
    std.log.warn("0x02 0x03 {x}{x}", .{ bus.read(0x02), bus.read(0x03) });
}
