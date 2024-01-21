const std = @import("std");
const Bus = @import("bus.zig").Bus;
const CPU = @import("cpu6502.zig").CPU;
const simple_prog = @import("cpu6502.zig").simple_prog;
const sdl = @import("zsdl");
const iNes = @import("ines.zig").ROM;

pub fn main() !void {
    try sdl.init(.{ .audio = true, .video = true });
    defer sdl.quit();
    const window = try sdl.Window.create(
        "zig-gamedev-window",
        sdl.Window.pos_undefined,
        sdl.Window.pos_undefined,
        600,
        600,
        .{ .opengl = true, .allow_highdpi = true },
    );
    defer window.destroy();
    const renderer = try sdl.Renderer.create(window, -1, .{
        .accelerated = false,
        .present_vsync = false,
    });
    const testRomFile = try std.fs.cwd().openFile("test-rom/nestest.nes", .{});
    defer testRomFile.close();
    var test_rom = try iNes.readFromFile(testRomFile, std.heap.page_allocator);
    defer test_rom.deinit();

    try renderer.setDrawColorRGB(255, 0, 0);
    try renderer.clear();

    var event = std.mem.zeroes(sdl.Event);
    const colors = [_]sdl.Color{
        .{ .r = 0xBB, .g = 0xBB, .b = 0xBB, .a = 0xBB },
        .{ .r = 0xEE, .g = 0xEE, .b = 0xEE, .a = 0xFF },
        .{ .r = 0xDD, .g = 0xDD, .b = 0xDD, .a = 0xFF },
        .{ .r = 0xCC, .g = 0xCC, .b = 0xCC, .a = 0xFF },
    };
    var x: u16 = 0;
    var y: u16 = 0;
    const width = 8;
    const scale = 3;
    for (0..test_rom.CHR_RomBanks.len / (width * 2)) |i| {
        const lsb = test_rom.CHR_RomBanks[i * 16 .. i * 16 + 8];
        const msb = test_rom.CHR_RomBanks[i * 16 + 8 .. (i + 1) * 16];
        for (0..8) |tmpY| {
            const yy: u3 = @truncate(tmpY);
            const currentByteLo = lsb[yy];
            const currentByteHi = msb[yy];
            for (0..8) |tmpX| {
                const xx: u3 = @truncate(tmpX);
                const j: u3 = @truncate(tmpX);
                var pixel: u2 = getBit(currentByteHi, j);
                pixel <<= 1;
                pixel |= getBit(currentByteLo, j);
                try renderer.setDrawColor(colors[pixel]);
                try renderer.fillRect(.{
                    .x = x + @as(i32, @intCast(xx)) * scale,
                    .y = y + @as(i32, @intCast(yy)) * scale,
                    .w = scale,
                    .h = scale,
                });
            }
        }
        x += 8 * scale;
        if (x == 256 * scale) {
            x = 0;
            y += 8 * scale;
        }
    }
    renderer.present();
    while (true) {
        defer sdl.delay(16);
        while (sdl.pollEvent(&event)) {
            switch (event.type) {
                .quit => {
                    return;
                },
                else => {},
            }
        }
    }
}

fn getBit(num: u8, idx: u3) u1 {
    return @truncate(num >> (7 - idx) & 1);
}

fn graphicTest() !void {
    try sdl.init(.{ .audio = true, .video = true });
    defer sdl.quit();
    const window = try sdl.Window.create(
        "zig-gamedev-window",
        sdl.Window.pos_undefined,
        sdl.Window.pos_undefined,
        600,
        600,
        .{ .opengl = true, .allow_highdpi = true },
    );
    defer window.destroy();
    const renderer = try sdl.Renderer.create(window, -1, .{
        .accelerated = false,
        .present_vsync = false,
    });

    var rect = sdl.Rect{ .x = 10, .y = 10, .w = 10, .h = 10 };
    var isUp = false;
    var isDown = false;
    var isLeft = false;
    var isRight = false;
    var event = std.mem.zeroes(sdl.Event);
    const bg_color = sdl.Color{
        .r = 30,
        .g = 30,
        .b = 30,
        .a = 255,
    };
    const rect_color = sdl.Color{
        .r = 0,
        .g = 0,
        .b = 255,
        .a = 255,
    };

    while (true) {
        while (sdl.pollEvent(&event)) {
            switch (event.type) {
                .quit => {
                    return;
                },
                .keydown, .keyup => {
                    if (event.key.repeat != 0) {
                        break;
                    }
                    switch (event.key.keysym.scancode) {
                        .a => {
                            isLeft = event.type == .keydown;
                        },
                        .d => {
                            isRight = event.type == .keydown;
                        },
                        .s => {
                            isDown = event.type == .keydown;
                        },
                        .w => {
                            isUp = event.type == .keydown;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        if (isUp) {
            rect.y -= 10;
        }
        if (isDown) {
            rect.y += 10;
        }
        if (isLeft) {
            rect.x -= 10;
        }
        if (isRight) {
            rect.x += 10;
        }

        try renderer.setDrawColor(bg_color);
        try renderer.clear();
        try renderer.setDrawColor(rect_color);
        try renderer.fillRect(rect);
        renderer.present();
        sdl.delay(16);
    }
}

fn cpu_test_all() !void {
    const Ram = @import("ram.zig").RAM;
    const testRomFile = try std.fs.cwd().openFile("test-rom/nestest.nes", .{});
    defer testRomFile.close();
    var test_rom = try iNes.readFromFile(testRomFile, std.heap.page_allocator);
    defer test_rom.deinit();
    var bus = Bus.init(std.heap.page_allocator);
    defer bus.deinit();
    var ram = Ram{};
    try bus.register(&ram);
    var cartridge_ram = test_rom.getCartridgeRamDev();
    try bus.register(&cartridge_ram);
    var prog_rom = test_rom.getProgramRomDev();
    try bus.register(&prog_rom);
    var cpu = CPU{ .bus = bus, .pc = 0xC000, .sp = 0xFF };
    try cpu.exec(0xA000);
    std.log.warn("0x02 0x03 {x}{x}", .{ bus.read(0x02), bus.read(0x03) });
}

test "CPU test all" {
    try cpu_test_all();
}
