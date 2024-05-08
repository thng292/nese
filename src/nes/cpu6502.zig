const std = @import("std");
const Bus = @import("bus.zig").Bus;

const log_full = true;

pub const no_log = std.io.null_writer.any();
pub var log_out: std.io.AnyWriter = no_log;
const CPU = @This();
bus: *Bus,
a: u8 = 0,
x: u8 = 0,
y: u8 = 0,
pc: u16 = 0,
sp: u8 = 0xFF - 3,
status: CPUStatus = CPUStatus{},
wait_cycle: u16 = 7,
cycle_count: u64 = 7,

const CPUStatus = packed struct(u8) {
    carry: u1 = 0,
    zero: u1 = 0,
    interruptDisable: u1 = 1,
    decimalMode: u1 = 0,
    breakCommand: u1 = 0,
    reserved: u1 = 1,
    overflow: u1 = 0,
    negative: u1 = 0,
};

pub fn reset(self: *CPU) void {
    self.a = 0;
    self.x = 0;
    self.y = 0;
    self.sp = 0xFD;
    self.status = CPUStatus{};
    self.wait_cycle = 7;
    self.cycle_count = 7;
    self.pc = self.bus.read(0xFFFC);
    var tmp: u16 = self.bus.read(0xFFFD);
    tmp <<= 8;
    self.pc |= tmp;
}

inline fn getStackAddr(self: *CPU, offset: i8) u16 {
    const res: i16 = @intCast(self.sp);
    return @intCast(res + 256 + offset);
}

const AMRes = struct {
    res: u8 = 0,
    addr: u16 = 0,
    additionalCycle: u8 = 0,
    res_fetched: bool = false,
};

inline fn NMI(self: *CPU) u8 {
    var tmp = self.status;
    tmp.breakCommand = 0;
    tmp.interruptDisable = 1;
    tmp.reserved = 1;

    self.bus.write(self.getStackAddr(0), @truncate(self.pc >> 8));
    self.sp -%= 1;

    self.bus.write(self.getStackAddr(0), @truncate(self.pc));
    self.sp -%= 1;

    self.bus.write(self.getStackAddr(0), @bitCast(tmp));
    self.sp -%= 1;

    var nmi_handler_addr: u16 = self.bus.read(0xFFFA);
    nmi_handler_addr |= @as(u16, @intCast(self.bus.read(0xFFFB))) << 8;
    self.pc = nmi_handler_addr;
    self.logDbg("NMI", 0, AMRes{ .addr = nmi_handler_addr }, g1_addr_mode_tag);
    return 7;
}

inline fn IRQ(self: *CPU) u8 {
    var tmp = self.status;
    tmp.breakCommand = 0;
    tmp.interruptDisable = 1;
    tmp.reserved = 1;
    self.bus.write(self.getStackAddr(0), @truncate(self.pc >> 8));
    self.sp -%= 1;
    self.bus.write(self.getStackAddr(0), @truncate(self.pc));
    self.sp -%= 1;
    self.bus.write(self.getStackAddr(0), @bitCast(tmp));
    self.sp -%= 1;
    var irq_handler_addr: u16 = self.bus.read(0xFFFE);
    irq_handler_addr |= @as(u16, @intCast(self.bus.read(0xFFFF))) << 8;
    self.pc = irq_handler_addr;
    self.logDbg("IRQ", 0, AMRes{ .addr = irq_handler_addr }, g1_addr_mode_tag);
    return 7;
}

fn AM_Implied(self: *CPU) AMRes {
    return AMRes{
        .res = self.a,
        .addr = 0,
        .additionalCycle = 0,
        .res_fetched = true,
    };
}

fn AM_Accumulator(self: *CPU) AMRes {
    return AMRes{
        .res = self.a,
        .addr = 0,
        .additionalCycle = 0,
        .res_fetched = true,
    };
}

fn AM_Immediate(self: *CPU) AMRes {
    const val = self.bus.read(self.pc);
    self.pc += 1;
    return AMRes{
        .res = val,
        .addr = 0,
        .additionalCycle = 0,
        .res_fetched = true,
    };
}

fn AM_ZeroPage(self: *CPU) AMRes {
    const val = self.bus.read(self.pc);
    self.pc += 1;
    return AMRes{
        .addr = val,
        .additionalCycle = 0,
    };
}

fn AM_ZeroPageX(self: *CPU) AMRes {
    const addr = self.bus.read(self.pc);
    self.pc += 1;
    const res: u8 = addr +% self.x;
    return AMRes{
        .addr = res,
        .additionalCycle = 0,
    };
}

fn AM_ZeroPageY(self: *CPU) AMRes {
    const addr = self.bus.read(self.pc);
    self.pc += 1;
    const res: u8 = addr +% self.y;
    return AMRes{
        .addr = res,
        .additionalCycle = 0,
    };
}

fn AM_Relative(self: *CPU) AMRes {
    const offset: i8 = @bitCast(self.bus.read(self.pc));
    self.pc += 1;
    const res = @as(i16, @bitCast(self.pc)) + offset;
    return AMRes{
        .addr = @bitCast(res),
        .additionalCycle = if (res > 0xFF) 1 else 0,
    };
}

fn AM_Absolute(self: *CPU) AMRes {
    const lo = self.bus.read(self.pc);
    self.pc += 1;
    const hi: u16 = self.bus.read(self.pc);
    self.pc += 1;
    const abs_addr = (hi << 8) | lo;
    return AMRes{
        .addr = abs_addr,
        .additionalCycle = 0,
    };
}

fn AM_AbsoluteX(self: *CPU) AMRes {
    const lo = self.bus.read(self.pc);
    self.pc += 1;
    const hi: u16 = self.bus.read(self.pc);
    self.pc += 1;
    const addr = ((hi << 8) | lo) +% self.x;
    return AMRes{
        .addr = addr,
        .additionalCycle = if (addr & 0xFF00 != (hi << 8)) 1 else 0,
    };
}

fn AM_AbsoluteY(self: *CPU) AMRes {
    const lo = self.bus.read(self.pc);
    self.pc += 1;
    const hi: u16 = self.bus.read(self.pc);
    self.pc += 1;
    const addr = ((hi << 8) | lo) +% self.y;
    return AMRes{
        .addr = addr,
        .additionalCycle = if (addr & 0xFF00 != (hi << 8)) 1 else 0,
    };
}

// JMP specific
fn AM_Indirect(self: *CPU) AMRes {
    const lo = self.bus.read(self.pc);
    self.pc += 1;
    const hi: u16 = self.bus.read(self.pc);
    self.pc += 1;
    const addr = (hi << 8) | lo;
    const final_addr_lo = self.bus.read(addr);
    const final_addr_hi: u16 = if (lo == 0xFF) self.bus.read(addr & 0xFF00) else self.bus.read(addr + 1);
    const final_addr = (final_addr_hi << 8) | final_addr_lo;
    return AMRes{
        .addr = final_addr,
        .additionalCycle = 0,
    };
}

/// Indirect X
fn AM_IndexedIndirect(self: *CPU) AMRes {
    const imm = self.bus.read(self.pc);
    self.pc += 1;
    const lo = self.bus.read(self.x +% imm);
    const hi: u16 = self.bus.read(self.x +% imm +% 1);
    const final_addr = (hi << 8) | lo;
    return AMRes{
        .addr = final_addr,
        .additionalCycle = 0,
    };
}

/// Indirect Y
fn AM_IndirectIndexed(self: *CPU) AMRes {
    const imm = self.bus.read(self.pc);
    self.pc += 1;
    const lo = self.bus.read(imm);
    const hi: u16 = self.bus.read(imm +% 1);
    const final_addr = ((hi << 8) | lo) +% self.y;
    return AMRes{
        .addr = final_addr,
        .additionalCycle = if ((final_addr & 0xFF00) != (hi << 8)) 1 else 0,
    };
}

fn AM_None(self: *CPU) AMRes {
    _ = self;
    return std.mem.zeroes(AMRes);
}

const g1_addr_mode_tag = enum(u8) {
    IndexedIndirect,
    ZeroPage,
    Immediate,
    Absolute,
    IndirectIndexed,
    ZeroPageX,
    AbsoluteY,
    AbsoluteX,
};

fn logDbg(self: *CPU, instruction_name: []const u8, addr_mode: u8, am_res: AMRes, comptime enum_tag: type) void {

    // if (comptime @import("builtin").mode != .Debug) {
    //     return;
    // }
    if (comptime log_full) {
        std.fmt.format(log_out, "{X:0>4} {s} {s:16} r:{X:0>2} a:{X:0>4},A:{X:0>2} X:{X:0>2} Y:{X:0>2} SP:{X:0>2} F:{X:0>2},PPU:{:3},{:3},CYC:{}\n", .{
            self.pc,
            instruction_name,
            @tagName(@as(enum_tag, (@enumFromInt(addr_mode)))),
            am_res.res,
            am_res.addr,
            self.a,
            self.x,
            self.y,
            self.sp,
            @as(u8, @bitCast(self.status)),
            self.bus.ppu.scanline,
            self.bus.ppu.cycle,
            self.cycle_count,
        }) catch {};
    } else {
        std.fmt.format(log_out, "{s}\n", .{instruction_name}) catch {};
    }
}

inline fn ORA(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    self.a |= am_res.res;
    self.status.zero = if (self.a == 0) 1 else 0;
    self.status.negative = if ((self.a >> 7) != 0) 1 else 0;
    const instruction_cycle = [8]u8{ 6, 3, 2, 4, 5, 4, 4, 4 };
    return instruction_cycle[addr_mode];
}

fn AND(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    self.a &= am_res.res;
    self.status.zero = if (self.a == 0) 1 else 0;
    self.status.negative = if ((self.a >> 7) != 0) 1 else 0;
    const instruction_cycle = [8]u8{ 6, 3, 2, 4, 5, 4, 4, 4 };
    return instruction_cycle[addr_mode];
}

inline fn EOR(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    self.a ^= am_res.res;
    self.status.zero = if (self.a == 0) 1 else 0;
    self.status.negative = if ((self.a >> 7) != 0) 1 else 0;
    const instruction_cycle = [8]u8{ 6, 3, 2, 4, 5, 4, 4, 4 };
    return instruction_cycle[addr_mode];
}

fn ADC(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    if (self.status.decimalMode == 1 and false) {
        const first_a = self.a >> 4;
        const second_a = self.a & 0xFF;
        const first_res = am_res.res >> 4;
        const second_res = am_res.res & 0xFF;
        var res = second_a + second_res + self.status.carry;
        var carry: u8 = 0;
        if (res >= 10) {
            carry = 1;
            res -= 10;
        }
        var tmp = (first_a + first_res + carry);
        if (tmp >= 10) {
            tmp -= 10;
            self.status.carry = 1;
        } else {
            self.status.carry = 0;
        }
        self.a = tmp << 4 | res;
        self.status.overflow = 0;
    } else {
        const tmp: u16 = @as(u16, self.a) + am_res.res + self.status.carry;
        const old_accumulator = self.a;
        self.a = @truncate(tmp);
        self.status.carry = if (tmp > 255) 1 else 0;
        self.status.overflow = if ((old_accumulator >> 7 ^ self.a >> 7) & ~(old_accumulator >> 7 ^ am_res.res >> 7) != 0) 1 else 0;
    }
    self.status.zero = if (self.a == 0) 1 else 0;
    self.status.negative = if (self.a >> 7 == 1) 1 else 0;

    const instruction_cycle = [8]u8{ 6, 3, 2, 4, 5, 4, 4, 4 };
    return instruction_cycle[addr_mode];
}

inline fn STA(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    self.bus.write(cam_res.addr, self.a);
    const instruction_cycle = [8]u8{ 6, 3, 0, 4, 6, 4, 5, 5 };
    return instruction_cycle[addr_mode] - cam_res.additionalCycle;
}

inline fn LDA(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    self.a = am_res.res;
    self.status.zero = if (am_res.res == 0) 1 else 0;
    self.status.negative = if (am_res.res & 0x80 != 0) 1 else 0;
    const instruction_cycle = [8]u8{ 6, 3, 2, 4, 5, 4, 4, 4 };
    return instruction_cycle[addr_mode];
}

inline fn CMP(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    const tmp = @as(i16, @intCast(self.a)) - am_res.res;
    self.status.zero = if ((tmp & 0xFF) == 0) 1 else 0;
    self.status.carry = if (self.a >= am_res.res) 1 else 0;
    self.status.negative = if (tmp & 0x80 != 0) 1 else 0;
    const instruction_cycle = [8]u8{ 6, 3, 2, 4, 5, 4, 4, 4 };
    return instruction_cycle[addr_mode];
}

inline fn SBC(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    if (self.status.decimalMode == 1 and false) {
        const first_a = self.a >> 4;
        const second_a = self.a & 0xFF;
        const first_res = am_res.res >> 4;
        const second_res = am_res.res & 0xFF;
        var res = second_a -% second_res -% 1 +% self.status.carry;
        var carry: u8 = 0;
        if (res >= 10) {
            carry = 1;
            res -= 10;
        }
        var tmp = (first_a -% first_res -% 1 +% carry);
        if (tmp >= 10) {
            tmp -= 10;
            self.status.carry = 1;
        } else {
            self.status.carry = 0;
        }
        self.a = tmp << 4 | res;
        self.status.overflow = 0;
    } else {
        am_res.res = ~am_res.res;
        const tmp: u16 = @as(u16, self.a) + @as(u16, am_res.res) + @as(u16, self.status.carry);
        const old_accumulator = self.a;
        self.a = @truncate(tmp);
        self.status.carry = if (tmp > 255) 1 else 0;
        self.status.overflow = if ((old_accumulator >> 7 ^ self.a >> 7) & ~(old_accumulator >> 7 ^ am_res.res >> 7) != 0) 1 else 0;
    }
    self.status.zero = if (self.a == 0) 1 else 0;
    self.status.negative = if (self.a >> 7 == 1) 1 else 0;

    const instruction_cycle = [8]u8{ 6, 3, 2, 4, 5, 4, 4, 4 };
    return instruction_cycle[addr_mode];
}

const g2_addr_mode_tag = enum(u8) {
    Immediate,
    ZeroPage,
    Accumulator,
    Absolute,
    None,
    ZeroPageX,
    None2,
    AbsoluteX,
};

inline fn ASL(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    const res = am_res.res << 1;
    if (addr_mode == 2) { // Mode is accumulator
        self.a = res;
    } else {
        self.bus.write(am_res.addr, res);
    }
    self.status.zero = if (res == 0) 1 else 0;
    self.status.carry = if (am_res.res & 0x80 != 0) 1 else 0;
    self.status.negative = if (res & 0x80 != 0) 1 else 0;
    const instruction_cycle = [8]u8{ 0, 5, 2, 6, 0, 6, 0, 7 };
    return instruction_cycle[addr_mode];
}

inline fn ROL(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    const res: u8 = am_res.res << 1 | self.status.carry;
    if (addr_mode == 2) { // Mode is accumulator
        self.a = res;
    } else {
        self.bus.write(am_res.addr, res);
    }
    self.status.zero = if (res == 0) 1 else 0;
    self.status.carry = if ((am_res.res >> 7) != 0) 1 else 0;
    self.status.negative = if (res & 0x80 != 0) 1 else 0;
    const instruction_cycle = [8]u8{ 0, 5, 2, 6, 0, 6, 0, 7 };
    return instruction_cycle[addr_mode];
}

inline fn LSR(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    const res: u8 = am_res.res >> 1;
    if (addr_mode == 2) { // Mode is accumulator
        self.a = res;
    } else {
        self.bus.write(am_res.addr, res);
    }
    self.status.zero = if (res == 0) 1 else 0;
    self.status.carry = if (am_res.res & 0b1 != 0) 1 else 0;
    self.status.negative = if (res & 0x80 != 0) 1 else 0;
    const instruction_cycle = [8]u8{ 0, 5, 2, 6, 0, 6, 0, 7 };
    return instruction_cycle[addr_mode];
}

inline fn ROR(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    var res: u8 = am_res.res >> 1;
    const carry = am_res.res & 1;
    res |= @as(u8, self.status.carry) << 7;
    if (addr_mode == 2) { // Mode is accumulator
        self.a = res;
    } else {
        self.bus.write(am_res.addr, res);
    }
    self.status.zero = if (res == 0) 1 else 0;
    self.status.carry = if (carry != 0) 1 else 0;
    self.status.negative = if (res & 0x80 != 0) 1 else 0;
    const instruction_cycle = [8]u8{ 0, 5, 2, 6, 0, 6, 0, 7 };
    return instruction_cycle[addr_mode];
}

inline fn STX(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    self.bus.write(cam_res.addr, self.x);
    const instruction_cycle = [8]u8{ 0, 3, 0, 4, 0, 4, 0, 0 };
    return instruction_cycle[addr_mode];
}

inline fn LDX(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    self.x = am_res.res;
    self.status.zero = if (am_res.res == 0) 1 else 0;
    self.status.negative = if (am_res.res & 0x80 != 0) 1 else 0;
    const instruction_cycle = [8]u8{ 2, 3, 0, 4, 0, 4, 0, 4 };
    return instruction_cycle[addr_mode];
}

inline fn DEC(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    const res = am_res.res -% 1;
    self.status.zero = if (res == 0) 1 else 0;
    self.status.negative = if (res & 0x80 != 0) 1 else 0;
    self.bus.write(am_res.addr, res);
    const instruction_cycle = [8]u8{ 0, 5, 0, 6, 0, 6, 0, 7 };
    return instruction_cycle[addr_mode];
}

inline fn INC(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    const res = am_res.res +% 1;
    self.status.zero = if (res == 0) 1 else 0;
    self.status.negative = if (res & 0x80 != 0) 1 else 0;
    self.bus.write(am_res.addr, res);
    const instruction_cycle = [8]u8{ 0, 5, 0, 6, 0, 6, 0, 7 };
    return instruction_cycle[addr_mode];
}

const g3_addr_mode_tag = enum(u8) {
    Immediate,
    ZeroPage,
    Implied,
    Absolute,
    Relative,
    ZeroPageX,
    Indirect,
    AbsoluteX,
};

inline fn BIT(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    self.status.zero = if (self.a & am_res.res == 0) 1 else 0;
    self.status.overflow = if (am_res.res & 0b0100_0000 != 0) 1 else 0;
    self.status.negative = if (am_res.res & 0b1000_0000 != 0) 1 else 0;
    const instruction_cycle = [8]u8{ 0, 3, 0, 4, 0, 0, 0, 0 };
    return instruction_cycle[addr_mode];
}

inline fn JMP(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
    self.pc = am_res.addr;
    const instruction_cycle = [8]u8{ 0, 0, 0, 3, 0, 0, 5, 0 };
    return instruction_cycle[addr_mode];
}

inline fn STY(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
    self.bus.write(am_res.addr, self.y);
    const instruction_cycle = [8]u8{ 0, 3, 0, 4, 0, 4, 0, 0 };
    return instruction_cycle[addr_mode];
}

inline fn LDY(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    self.y = am_res.res;
    self.status.zero = if (am_res.res == 0) 1 else 0;
    self.status.negative = if (am_res.res & 0x80 != 0) 1 else 0;
    const instruction_cycle = [8]u8{ 2, 3, 0, 4, 0, 4, 0, 4 };
    return instruction_cycle[addr_mode];
}

inline fn CPY(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    const tmp = @as(i16, @intCast(self.y)) - am_res.res;
    self.status.zero = if ((tmp & 0xFF) == 0) 1 else 0;
    self.status.carry = if (self.y >= am_res.res) 1 else 0;
    self.status.negative = if (tmp & 0x80 != 0) 1 else 0;
    const instruction_cycle = [8]u8{ 2, 3, 0, 4, 0, 0, 0, 0 };
    return instruction_cycle[addr_mode];
}

inline fn CPX(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
    var am_res = cam_res;
    if (!am_res.res_fetched) {
        am_res.res = self.bus.read(am_res.addr);
    }
    const tmp = @as(i16, @intCast(self.x)) - am_res.res;
    self.status.zero = if ((tmp & 0xFF) == 0) 1 else 0;
    self.status.carry = if (self.x >= am_res.res) 1 else 0;
    self.status.negative = if (tmp & 0x80 != 0) 1 else 0;
    const instruction_cycle = [8]u8{ 2, 3, 0, 4, 0, 0, 0, 0 };
    return instruction_cycle[addr_mode];
}

inline fn NOP(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
    _ = am_res;
    _ = addr_mode;
    _ = self;
    return 2;
}

inline fn DEStuff(self: *CPU, stuff: *u8) void {
    stuff.* -%= 1;
    self.status.zero = if (stuff.* == 0) 1 else 0;
    self.status.negative = if (stuff.* >> 7 != 0) 1 else 0;
}

inline fn INStuff(self: *CPU, stuff: *u8) void {
    stuff.* +%= 1;
    self.status.zero = if (stuff.* == 0) 1 else 0;
    self.status.negative = if (stuff.* >> 7 != 0) 1 else 0;
}

pub fn step(self: *CPU) !void {
    if (self.wait_cycle != 0) {
        self.wait_cycle -%= 1;
        return;
    }

    if (self.bus.nmiSet) {
        self.bus.nmiSet = false;
        const cycle = self.NMI();
        self.wait_cycle += cycle;
        self.cycle_count += cycle + 1;
        return;
    }

    if (self.bus.irqSet and self.status.interruptDisable == 0) {
        self.bus.irqSet = false;
        const cycle = self.IRQ();
        self.wait_cycle += cycle;
        self.cycle_count += cycle + 1;
        return;
    }

    if (self.bus.dmaReq) {
        self.bus.dmaReq = false;
        const cycle: u16 = 512 + @as(u16, @truncate(self.cycle_count % 2));
        self.wait_cycle += cycle;
        self.cycle_count += cycle;
    }

    const instruction = self.bus.read(self.pc);
    self.pc +%= 1;
    const group = instruction & 3;
    const op_code = (instruction & 0b11100000) >> 5;
    const addr_mode = (instruction & 0b11100) >> 2;
    switch (group) {
        // Group 1
        0b01 => {
            const am_res = switch (addr_mode) {
                0 => self.AM_IndexedIndirect(),
                1 => self.AM_ZeroPage(),
                2 => self.AM_Immediate(),
                3 => self.AM_Absolute(),
                4 => self.AM_IndirectIndexed(),
                5 => self.AM_ZeroPageX(),
                6 => self.AM_AbsoluteY(),
                7 => self.AM_AbsoluteX(),
                else => self.AM_None(),
            };
            const g1_instruction_str = [_][]const u8{
                "ORA", "AND", "EOR", "ADC", "STA", "LDA", "CMP", "SBC",
            };
            self.logDbg(g1_instruction_str[op_code], addr_mode, am_res, g1_addr_mode_tag);
            self.wait_cycle = switch (op_code) {
                0 => self.ORA(addr_mode, am_res),
                1 => self.AND(addr_mode, am_res),
                2 => self.EOR(addr_mode, am_res),
                3 => self.ADC(addr_mode, am_res),
                4 => self.STA(addr_mode, am_res),
                5 => self.LDA(addr_mode, am_res),
                6 => self.CMP(addr_mode, am_res),
                7 => self.SBC(addr_mode, am_res),
                else => 1,
            };
            self.wait_cycle += am_res.additionalCycle;
        },
        // Group 2
        0b10 => {
            const am_res = switch (addr_mode) {
                0 => self.AM_Immediate(),
                1 => self.AM_ZeroPage(),
                2 => self.AM_Accumulator(),
                3 => self.AM_Absolute(),
                5 => if (op_code == 4 or op_code == 5) self.AM_ZeroPageY() else self.AM_ZeroPageX(),
                7 => if (op_code == 4 or op_code == 5) self.AM_AbsoluteY() else self.AM_AbsoluteX(),
                else => self.AM_None(),
            };

            switch (instruction) {
                0x8A => { // TXA
                    self.logDbg("TXA", addr_mode, am_res, g2_addr_mode_tag);
                    self.a = self.x;
                    self.status.zero = if (self.a == 0) 1 else 0;
                    self.status.negative = if (self.a >> 7 != 0) 1 else 0;
                    self.wait_cycle = 2;
                },
                0x9A => { // TXS
                    self.logDbg("TXS", addr_mode, am_res, g2_addr_mode_tag);
                    self.sp = self.x;
                    self.wait_cycle = 2;
                },
                0xAA => { // TAX
                    self.logDbg("TAX", addr_mode, am_res, g2_addr_mode_tag);
                    self.x = self.a;
                    self.status.zero = if (self.a == 0) 1 else 0;
                    self.status.negative = if (self.a >> 7 != 0) 1 else 0;
                    self.wait_cycle = 2;
                },
                0xBA => { // TSX
                    self.logDbg("TSX", addr_mode, am_res, g2_addr_mode_tag);
                    self.x = self.sp;
                    self.status.zero = if (self.x == 0) 1 else 0;
                    self.status.negative = if (self.x >> 7 != 0) 1 else 0;
                    self.wait_cycle = 2;
                },
                0xCA => { // DEX
                    self.logDbg("DEX", addr_mode, am_res, g2_addr_mode_tag);
                    self.DEStuff(&self.x);
                    self.wait_cycle = 2;
                },
                0xEA => { // NOP
                    self.logDbg("NOP", addr_mode, am_res, g2_addr_mode_tag);
                    self.wait_cycle = 2;
                },
                else => {
                    const g2_instruction_str = [_][]const u8{
                        "ASL", "ROL", "LSR", "ROR", "STX", "LDX", "DEC", "INC",
                    };
                    self.logDbg(g2_instruction_str[op_code], addr_mode, am_res, g2_addr_mode_tag);
                    self.wait_cycle = switch (op_code) {
                        0 => self.ASL(addr_mode, am_res),
                        1 => self.ROL(addr_mode, am_res),
                        2 => self.LSR(addr_mode, am_res),
                        3 => self.ROR(addr_mode, am_res),
                        4 => self.STX(addr_mode, am_res),
                        5 => self.LDX(addr_mode, am_res),
                        6 => self.DEC(addr_mode, am_res),
                        7 => self.INC(addr_mode, am_res),
                        else => 1,
                    };
                    self.wait_cycle += am_res.additionalCycle;
                },
            }
        },
        // Group 3
        0b00 => {
            switch (instruction) {
                0x00 => { // BRK is a 2-byte opcode
                    self.logDbg("BRK", 2, AMRes{}, g3_addr_mode_tag);
                    self.pc +%= 1;

                    const hi: u8 = @truncate(self.pc >> 8);
                    self.bus.write(self.getStackAddr(0), hi);
                    self.sp -%= 1;

                    const lo: u8 = @truncate(self.pc);
                    self.bus.write(self.getStackAddr(0), lo);
                    self.sp -%= 1;

                    self.status.breakCommand = 1;
                    self.bus.write(self.getStackAddr(0), @bitCast(self.status));
                    self.status.interruptDisable = 1;
                    self.sp -%= 1;

                    self.pc = @as(u16, @intCast(self.bus.read(0xFFFF))) << 8 | self.bus.read(0xFFFE);
                    self.wait_cycle = 7;
                },
                0x20 => { // JSR
                    const am_res = self.AM_Absolute();
                    self.logDbg("JSR", 3, am_res, g3_addr_mode_tag);
                    self.pc -= 1;
                    const hi: u8 = @truncate(self.pc >> 8);
                    self.bus.write(self.getStackAddr(0), hi);
                    const lo: u8 = @truncate(self.pc);
                    self.bus.write(self.getStackAddr(-1), lo);
                    self.sp -%= 2;
                    self.pc = am_res.addr;
                    self.wait_cycle = 6;
                },
                0x40 => { // RTI
                    self.logDbg("RTI", 2, AMRes{}, g3_addr_mode_tag);

                    self.sp +%= 1;
                    self.status = @bitCast(self.bus.read(self.getStackAddr(0)));
                    self.status.reserved = 1;
                    self.status.breakCommand = 0;

                    self.sp +%= 1;
                    const pc_lo = self.bus.read(self.getStackAddr(0));

                    self.sp +%= 1;
                    const pc_hi: u16 = self.bus.read(self.getStackAddr(0));

                    self.pc = (pc_hi << 8) | pc_lo;
                    self.wait_cycle = 6;
                },
                0x60 => { // RTS
                    self.logDbg("RTS", 2, AMRes{}, g3_addr_mode_tag);
                    self.sp +%= 1;
                    const pc_lo = self.bus.read(self.getStackAddr(0));
                    const pc_hi: u16 = self.bus.read(self.getStackAddr(1));
                    self.sp +%= 1;
                    self.pc = ((pc_hi << 8) | pc_lo) + 1;
                    self.wait_cycle = 6;
                },
                0x08 => { // PHP not the language
                    self.logDbg("PHP", 2, AMRes{}, g3_addr_mode_tag);
                    self.status.breakCommand = 1;
                    self.bus.write(self.getStackAddr(0), @bitCast(self.status));
                    self.status.breakCommand = 0;
                    self.sp -%= 1;
                    self.wait_cycle = 3;
                },
                0x18 => { // CLC
                    self.logDbg("CLC", 2, AMRes{}, g3_addr_mode_tag);
                    self.status.carry = 0;
                    self.wait_cycle = 2;
                },
                0x28 => { // PLP
                    self.logDbg("PLP", 2, AMRes{}, g3_addr_mode_tag);
                    self.sp +%= 1;
                    self.status = @bitCast(self.bus.read(self.getStackAddr(0)));
                    self.status.breakCommand = 0;
                    self.status.reserved = 1;
                    self.wait_cycle = 4;
                },
                0x38 => { // SEC
                    self.logDbg("SEC", 2, AMRes{}, g3_addr_mode_tag);
                    self.status.carry = 1;
                    self.wait_cycle = 2;
                },
                0x48 => { // PHA
                    self.logDbg("PHA", 2, AMRes{}, g3_addr_mode_tag);
                    self.bus.write(self.getStackAddr(0), self.a);
                    self.sp -%= 1;
                    self.wait_cycle = 3;
                },
                0x58 => { // CLI
                    self.logDbg("CLI", 2, AMRes{}, g3_addr_mode_tag);
                    self.status.interruptDisable = 0;
                    self.wait_cycle = 2;
                },
                0x68 => { // PLA
                    self.logDbg("PLA", 2, AMRes{}, g3_addr_mode_tag);
                    self.sp +%= 1;
                    self.a = self.bus.read(self.getStackAddr(0));
                    self.status.zero = if (self.a == 0) 1 else 0;
                    self.status.negative = if (self.a >> 7 != 0) 1 else 0;
                    self.wait_cycle = 4;
                },
                0x78 => { // SEI
                    self.logDbg("SEI", 2, AMRes{}, g3_addr_mode_tag);
                    self.status.interruptDisable = 1;
                    self.wait_cycle = 2;
                },
                0x88 => { // DEY
                    self.logDbg("DEY", 2, AMRes{}, g3_addr_mode_tag);
                    self.DEStuff(&self.y);
                    self.wait_cycle = 2;
                },
                0x98 => { // TYA
                    self.logDbg("TYA", 2, AMRes{}, g3_addr_mode_tag);
                    self.a = self.y;
                    self.status.zero = if (self.y == 0) 1 else 0;
                    self.status.negative = if (self.y >> 7 != 0) 1 else 0;
                    self.wait_cycle = 2;
                },
                0xA8 => { // TAY
                    self.logDbg("TAY", 2, AMRes{}, g3_addr_mode_tag);
                    self.y = self.a;
                    self.status.zero = if (self.y == 0) 1 else 0;
                    self.status.negative = if (self.y >> 7 != 0) 1 else 0;
                    self.wait_cycle = 2;
                },
                0xB8 => { // CLV
                    self.logDbg("CLV", 2, AMRes{}, g3_addr_mode_tag);
                    self.status.overflow = 0;
                    self.wait_cycle = 2;
                },
                0xC8 => { // INY
                    self.logDbg("INY", 2, AMRes{}, g3_addr_mode_tag);
                    self.INStuff(&self.y);
                    self.wait_cycle = 2;
                },
                0xD8 => { // CLD
                    self.logDbg("CLD", 2, AMRes{}, g3_addr_mode_tag);
                    self.status.decimalMode = 0;
                    self.wait_cycle = 2;
                },
                0xE8 => { // INX
                    self.logDbg("INX", 2, AMRes{}, g3_addr_mode_tag);
                    self.INStuff(&self.x);
                    self.wait_cycle = 2;
                },
                0xF8 => { // SED
                    self.logDbg("SED", 2, AMRes{}, g3_addr_mode_tag);
                    self.status.decimalMode = 1;
                    self.wait_cycle = 2;
                },
                else => {
                    const am_res = if (instruction == 0x6C) self.AM_Indirect() //
                    else switch (addr_mode) {
                        0 => self.AM_Immediate(),
                        1 => self.AM_ZeroPage(),
                        3 => self.AM_Absolute(),
                        4 => self.AM_Relative(),
                        5 => self.AM_ZeroPageX(),
                        7 => self.AM_AbsoluteX(),
                        else => self.AM_None(),
                    };

                    if (addr_mode == 4) { // Branch it all
                        const branch_instruction_name = [_][]const u8{
                            "BPL", "BMI", "BVC", "BVS", "BCC", "BCS", "BNE", "BEQ",
                        };
                        self.logDbg(branch_instruction_name[op_code], addr_mode, am_res, g2_addr_mode_tag);
                        const comp_what = instruction >> 6;
                        var comp_with: u8 = 0;
                        if (instruction & 0b00100000 != 0) {
                            comp_with = 1;
                        }
                        const comp_val: u8 = switch (comp_what) {
                            0 => self.status.negative,
                            1 => self.status.overflow,
                            2 => self.status.carry,
                            3 => self.status.zero,
                            else => unreachable,
                        };
                        if (comp_val == comp_with) {
                            self.pc = am_res.addr;
                            self.wait_cycle = 3 + am_res.additionalCycle;
                        } else {
                            self.wait_cycle = 2;
                        }
                    } else {
                        const g3_instruction_str = [_][]const u8{
                            "NOP", "BIT", "JMP", "JMP", "STY", "LDY", "CPY", "CPX",
                        };
                        self.logDbg(g3_instruction_str[op_code], if (instruction == 0x6C) 6 else addr_mode, am_res, g3_addr_mode_tag);
                        self.wait_cycle = switch (op_code) {
                            0 => self.NOP(addr_mode, am_res),
                            1 => self.BIT(addr_mode, am_res),
                            2 => self.JMP(addr_mode, am_res),
                            3 => self.JMP(6, am_res),
                            4 => self.STY(addr_mode, am_res),
                            5 => self.LDY(addr_mode, am_res),
                            6 => self.CPY(addr_mode, am_res),
                            7 => self.CPX(addr_mode, am_res),
                            else => 1,
                        };
                        self.wait_cycle += am_res.additionalCycle;
                    }
                },
            }
        },
        else => {},
    }
    self.cycle_count += self.wait_cycle;
    if (self.wait_cycle > 0) {
        self.wait_cycle -= 1;
    }
}
