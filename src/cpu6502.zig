const std = @import("std");
const Bus = @import("bus.zig").Bus;

pub const CPU = struct {
    bus: *Bus,
    a: u8 = 0,
    x: u8 = 0,
    y: u8 = 0,
    pc: u16 = 0,
    sp: u8 = 0xFF - 3,
    status: CPUStatus = CPUStatus{},
    wait_cycle: u8 = 7,
    cycle_count: u64 = 7,

    const CPUStatus = packed struct(u8) {
        carry: u1 = 0,
        zero: u1 = 0,
        interruptDisable: u1 = 0,
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
        self.sp = 0xFF - 3;
        self.status = CPUStatus{};
        self.wait_cycle = 7;
        self.cycle_count = 7;
        self.pc = self.bus.read(0xFFFC);
        var tmp: u16 = self.bus.read(0xFFFD);
        tmp <<= 8;
        self.pc |= tmp;
    }

    fn getStackAddr(self: *CPU, offset: i8) u16 {
        const res: i16 = @intCast(self.sp);
        return @intCast(res + 256 + offset);
    }

    const AddressingMode = enum(u8) {
        Implied,
        Accumulator,
        Immediate,
        ZeroPage,
        ZeroPageX,
        ZeroPageY,
        Relative,
        Absolute,
        AbsoluteX,
        AbsoluteY,
        Indirect,
        IndexedIndirect,
        IndirectIndexed,
    };

    const AMRes = struct {
        res: u8 = 0,
        addr: u16 = 0,
        additionalCycle: u8 = 0,
        res_fetched: bool = false,
    };

    fn NMI(self: *CPU) u8 {
        var tmp = self.status;
        tmp.breakCommand = 0;
        self.sp -= 3;
        self.bus.write(self.getStackAddr(0), @bitCast(tmp));
        self.bus.write(self.getStackAddr(1), @truncate(self.pc));
        self.bus.write(self.getStackAddr(2), @truncate(self.pc >> 8));
        self.status.interruptDisable = 1;
        var nmi_handler_addr: u16 = self.bus.read(0xFFFA);
        nmi_handler_addr |= @as(u16, @intCast(self.bus.read(0xFFFB))) << 8;
        self.pc = nmi_handler_addr;
        self.logDbg("NMI", 0, AMRes{ .addr = nmi_handler_addr }, g1_addr_mode_tag);
        return 7;
    }

    fn IRQ(self: *CPU) u8 {
        var tmp = self.status;
        tmp.breakCommand = 0;
        self.sp -= 3;
        self.bus.write(self.getStackAddr(0), @bitCast(tmp));
        self.bus.write(self.getStackAddr(1), @truncate(self.pc));
        self.bus.write(self.getStackAddr(2), @truncate(self.pc >> 8));
        self.status.interruptDisable = 1;
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
        const final_addr = (hi << 8) | lo +% self.y;
        return AMRes{
            .addr = final_addr,
            .additionalCycle = if (final_addr & 0xFF00 != hi << 8) 1 else 0,
        };
    }

    fn AM_None(self: *CPU) AMRes {
        _ = self;
        return std.mem.zeroes(AMRes);
    }

    const AddressingModes = [_](fn (self: *CPU) AMRes){
        CPU.AM_Implied,
        CPU.AM_Accumulator,
        CPU.AM_Immediate,
        CPU.AM_ZeroPage,
        CPU.AM_ZeroPageX,
        CPU.AM_ZeroPageY,
        CPU.AM_Relative,
        CPU.AM_Absolute,
        CPU.AM_AbsoluteX,
        CPU.AM_AbsoluteY,
        CPU.AM_Indirect,
        CPU.AM_IndexedIndirect,
        CPU.AM_IndirectIndexed,
    };

    pub fn init(bus: Bus) CPU {
        return CPU{
            .bus = bus,
            .status = std.mem.zeroes(CPUStatus),
        };
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
        if (comptime @import("builtin").mode != .Debug) {
            return;
        }
        if (true) {
            std.debug.print("{X:0>4} {s} {s:16} r:{X:0>2} a:{X:0>4},A:{X:0>2} X:{X:0>2} Y:{X:0>2} SP:{X:0>2} F:{X:0>2},2002:{X:0>2},PPU:{d:3},{d:3},CYC:{}\n", .{
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
                @as(u8, @bitCast(self.bus.ppu.status)),
                self.bus.ppu.scanline,
                self.bus.ppu.cycle,
                self.cycle_count,
            });
        } else {
            std.debug.print("{s}\n", .{instruction_name});
        }
    }

    fn ORA(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
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

    fn EOR(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
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
            const tmp: u16 = @as(u16, @intCast(self.a)) + am_res.res + self.status.carry;
            const old_accumulator = self.a;
            self.a = @truncate(tmp);
            if (tmp >> 7 != 0) {
                self.status.carry = 1;
            } else {
                self.status.carry = 0;
            }
            self.status.overflow = if ((old_accumulator >> 7 ^ self.a >> 7) & ~(old_accumulator >> 7 ^ am_res.res >> 7) != 0) 1 else 0;
        }
        self.status.zero = if (self.a == 0) 1 else 0;
        self.status.negative = if (self.a >> 7 == 1) 1 else 0;

        const instruction_cycle = [8]u8{ 6, 3, 2, 4, 5, 4, 4, 4 };
        return instruction_cycle[addr_mode];
    }

    fn STA(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
        self.bus.write(cam_res.addr, self.a);
        const instruction_cycle = [8]u8{ 6, 3, 0, 4, 6, 4, 5, 5 };
        return instruction_cycle[addr_mode];
    }

    fn LDA(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
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

    fn CMP(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
        var am_res = cam_res;
        if (!am_res.res_fetched) {
            am_res.res = self.bus.read(am_res.addr);
        }
        const tmp = @as(i16, @intCast(self.a)) - am_res.res;
        self.status.zero = if (tmp == 0) 1 else 0;
        self.status.carry = if (self.a >= am_res.res) 1 else 0;
        self.status.negative = if (tmp >> 7 != 0) 1 else 0;
        const instruction_cycle = [8]u8{ 6, 3, 2, 4, 5, 4, 4, 4 };
        return instruction_cycle[addr_mode];
    }

    fn SBC(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
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
            var tmp = @as(u16, @intCast(self.a)) -% am_res.res;
            tmp -%= (1 - self.status.carry);
            const old_accumulator = self.a;
            self.a = @truncate(tmp);
            if (tmp >> 7 != 0) {
                self.status.carry = 1;
            } else {
                self.status.carry = 0;
            }
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

    fn ASL(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
        var am_res = cam_res;
        if (!am_res.res_fetched) {
            am_res.res = self.bus.read(am_res.addr);
        }
        const res = am_res.res *% 2;
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

    fn ROL(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
        var am_res = cam_res;
        if (!am_res.res_fetched) {
            am_res.res = self.bus.read(am_res.addr);
        }
        var res = am_res.res *% 2;
        const last = am_res.res & 0x80;
        res |= last >> 7;
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

    fn LSR(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
        var am_res = cam_res;
        if (!am_res.res_fetched) {
            am_res.res = self.bus.read(am_res.addr);
        }
        const res = am_res.res / 2;
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

    fn ROR(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
        var am_res = cam_res;
        if (!am_res.res_fetched) {
            am_res.res = self.bus.read(am_res.addr);
        }
        var res = am_res.res / 2;
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

    fn STX(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
        self.bus.write(cam_res.addr, self.x);
        const instruction_cycle = [8]u8{ 0, 3, 0, 4, 0, 4, 0, 0 };
        return instruction_cycle[addr_mode];
    }

    fn LDX(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
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

    fn DEC(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
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

    fn INC(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
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

    fn BIT(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        self.status.zero = if (self.a & am_res.res != 0) 1 else 0;
        self.status.overflow = if (am_res.res & 0x40 != 0) 1 else 0;
        self.status.negative = if (am_res.res & 0x80 != 0) 1 else 0;
        const instruction_cycle = [8]u8{ 0, 3, 0, 4, 0, 0, 0, 0 };
        return instruction_cycle[addr_mode];
    }

    fn JMP(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        self.pc = am_res.addr;
        const instruction_cycle = [8]u8{ 0, 3, 0, 4, 0, 0, 0, 0 };
        return instruction_cycle[addr_mode];
    }

    fn STY(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        self.bus.write(am_res.addr, self.y);
        const instruction_cycle = [8]u8{ 0, 3, 0, 4, 0, 4, 0, 0 };
        return instruction_cycle[addr_mode];
    }

    fn LDY(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
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

    fn CPY(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
        var am_res = cam_res;
        if (!am_res.res_fetched) {
            am_res.res = self.bus.read(am_res.addr);
        }
        const tmp = @as(i16, @intCast(self.y)) - am_res.res;
        self.status.zero = if (tmp == 0) 1 else 0;
        self.status.carry = if (self.y >= am_res.res) 1 else 0;
        self.status.negative = if (tmp >> 7 != 0) 1 else 0;
        const instruction_cycle = [8]u8{ 2, 3, 0, 4, 0, 0, 0, 0 };
        return instruction_cycle[addr_mode];
    }

    fn CPX(self: *CPU, addr_mode: u8, cam_res: AMRes) u8 {
        var am_res = cam_res;
        if (!am_res.res_fetched) {
            am_res.res = self.bus.read(am_res.addr);
        }
        const tmp = @as(i16, @intCast(self.x)) - am_res.res;
        self.status.zero = if (tmp == 0) 1 else 0;
        self.status.carry = if (self.x >= am_res.res) 1 else 0;
        self.status.negative = if (tmp >> 7 != 0) 1 else 0;
        const instruction_cycle = [8]u8{ 2, 3, 0, 4, 0, 0, 0, 0 };
        return instruction_cycle[addr_mode];
    }

    fn NOP(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        _ = am_res;
        _ = addr_mode;
        _ = self;
        return 2;
    }

    fn DEStuff(self: *CPU, stuff: *u8) void {
        stuff.* -%= 1;
        self.status.zero = if (stuff.* == 0) 1 else 0;
        self.status.negative = if (stuff.* >> 7 != 0) 1 else 0;
    }

    fn INStuff(self: *CPU, stuff: *u8) void {
        stuff.* +%= 1;
        self.status.zero = if (stuff.* == 0) 1 else 0;
        self.status.negative = if (stuff.* >> 7 != 0) 1 else 0;
    }

    pub fn step(self: *CPU) !void {
        if (self.wait_cycle != 0) {
            self.wait_cycle -= 1;
            return;
        }
        if (self.bus.nmiSet) {
            self.bus.nmiSet = false;
            self.wait_cycle += self.NMI();
            return;
        }
        if (self.bus.irqSet and self.status.interruptDisable == 0) {
            self.bus.irqSet = false;
            self.wait_cycle += self.IRQ();
            return;
        }
        // std.debug.print("Next: {x} {x} {x} {x}\n", .{ self.bus.read(self.pc + 1), self.bus.read(self.pc + 2), self.bus.read(self.pc + 3), self.bus.read(self.pc + 4) });
        const instruction = self.bus.read(self.pc);
        self.pc +%= 1;
        const group = instruction & 3;
        const op_code = (instruction & 0b11100000) >> 5;
        const addr_mode = (instruction & 0b11100) >> 2;
        switch (group) {
            // Group 1
            0b01 => {
                const am_res = switch (@as(g1_addr_mode_tag, @enumFromInt(addr_mode))) {
                    .IndexedIndirect => self.AM_IndexedIndirect(),
                    .ZeroPage => self.AM_ZeroPage(),
                    .Immediate => self.AM_Immediate(),
                    .Absolute => self.AM_Absolute(),
                    .IndirectIndexed => self.AM_IndirectIndexed(),
                    .ZeroPageX => self.AM_ZeroPageX(),
                    .AbsoluteY => self.AM_AbsoluteY(),
                    .AbsoluteX => self.AM_AbsoluteX(),
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
                    else => 0,
                };
                self.wait_cycle += am_res.additionalCycle;
            },
            // Group 2
            0b10 => {
                const am_res = switch (@as(g2_addr_mode_tag, @enumFromInt(addr_mode))) {
                    .Immediate => self.AM_Immediate(),
                    .ZeroPage => self.AM_ZeroPage(),
                    .Accumulator => self.AM_Accumulator(),
                    .Absolute => self.AM_Absolute(),
                    .None => AMRes{},
                    .ZeroPageX => if (op_code == 4 or op_code == 5) self.AM_ZeroPageY() else self.AM_ZeroPageX(),
                    .None2 => AMRes{},
                    .AbsoluteX => if (op_code == 4 or op_code == 5) self.AM_AbsoluteY() else self.AM_AbsoluteX(),
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
                            else => 0,
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
                        self.pc += 1;
                        self.status.breakCommand = 1;
                        self.bus.write(self.getStackAddr(0), @bitCast(self.status));
                        const hi: u8 = @truncate(self.pc >> 8);
                        self.bus.write(self.getStackAddr(-1), hi);
                        const lo: u8 = @truncate(self.pc);
                        self.bus.write(self.getStackAddr(-2), lo);
                        self.status.interruptDisable = 1;
                        self.sp -%= 3;
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
                        const pc_lo = self.bus.read(self.getStackAddr(1));
                        const pc_hi: u16 = self.bus.read(self.getStackAddr(2));
                        self.sp +%= 2;
                        self.pc = pc_hi << 8 | pc_lo;
                        self.wait_cycle = 6;
                    },
                    0x60 => { // RTS
                        self.logDbg("RTS", 2, AMRes{}, g3_addr_mode_tag);
                        self.sp +%= 1;
                        const pc_lo = self.bus.read(self.getStackAddr(0));
                        const pc_hi: u16 = self.bus.read(self.getStackAddr(1));
                        self.sp +%= 1;
                        self.pc = (pc_hi << 8 | pc_lo) + 1;
                        self.wait_cycle = 6;
                    },
                    0x08 => { // PHP not the language
                        self.logDbg("PHP", 2, AMRes{}, g3_addr_mode_tag);
                        self.status.breakCommand = 1;
                        self.bus.write(self.getStackAddr(0), @bitCast(self.status));
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
                        else switch (@as(g3_addr_mode_tag, @enumFromInt(addr_mode))) {
                            .Immediate => self.AM_Immediate(),
                            .ZeroPage => self.AM_ZeroPage(),
                            .Implied => self.AM_Implied(),
                            .Absolute => self.AM_Absolute(),
                            .Relative => self.AM_Relative(),
                            .ZeroPageX => self.AM_ZeroPageX(),
                            .Indirect => self.AM_Indirect(),
                            .AbsoluteX => self.AM_AbsoluteX(),
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
                                3 => self.JMP(addr_mode, am_res),
                                4 => self.STY(addr_mode, am_res),
                                5 => self.LDY(addr_mode, am_res),
                                6 => self.CPY(addr_mode, am_res),
                                7 => self.CPX(addr_mode, am_res),
                                else => 0,
                            };
                            self.wait_cycle += am_res.additionalCycle;
                        }
                    },
                }
            },
            else => {},
        }
        self.cycle_count += self.wait_cycle;
    }

    pub fn exec(self: *CPU, end_after_: u16) !void {
        var end_after = end_after_;
        while (true) {
            if (end_after != 0) {
                end_after -= 1;
                if (end_after == 0) {
                    break;
                }
            }
            try self.step();
        }
    }
};

pub const simple_prog = struct {
    const Self = @This();
    const lower_bound = 0xC000;
    data: []const u8,

    pub fn inRange(self: *Self, address: u16) bool {
        _ = self;
        return lower_bound <= address;
    }

    pub fn read(self: *Self, address: u16) u8 {
        if (address - lower_bound < self.data.len) {
            return self.data[address - lower_bound];
        }
        return 0;
    }

    pub fn write(self: *Self, address: u16, data: u8) void {
        _ = data;
        _ = address;
        _ = self;
    }
};

fn cpu_test_all() !void {
    const iNes = @import("ines.zig").ROM;
    const Mapper0 = @import("mapper0.zig");
    const PPU = @import("ppu2C02.zig");
    const toMapper = @import("mapper.zig").toMapper;
    const testRomFile = try std.fs.cwd().openFile("test-rom/nestest.nes", .{});
    defer testRomFile.close();
    var test_rom = try iNes.readFromFile(testRomFile, std.heap.page_allocator);
    defer test_rom.deinit();

    var mapper0 = Mapper0.init(&test_rom);
    const mapper = toMapper(&mapper0);
    var ppu = try PPU.init(std.heap.page_allocator, mapper, &test_rom);
    defer ppu.deinit();
    var bus = Bus.init(mapper, &ppu);

    var cpu = CPU{
        .bus = &bus,
        .pc = mapper.startPC,
        .sp = 0xFF - 3,
    };
    try cpu.exec(0xA000);
    std.log.warn("0x02 0x03 {x}{x}", .{ bus.read(0x02), bus.read(0x03) });
}

test "CPU test all" {
    try cpu_test_all();
}
