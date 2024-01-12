const std = @import("std");
const Bus = @import("bus.zig").Bus;
const rom = @import("ines.zig").ROM;

pub const CPU = struct {
    bus: Bus,
    a: u8 = 0,
    x: u8 = 0,
    y: u8 = 0,
    pc: u16 = 0,
    sp: u8 = 0xFF,
    status: CPUStatus = CPUStatus{},

    const CPUStatus = packed struct(u8) {
        negative: u1 = 0,
        overflow: u1 = 0,
        reserved: u1 = 1,
        breakCommand: u1 = 0,
        decimalMode: u1 = 0,
        interruptDisable: u1 = 0,
        zero: u1 = 0,
        carry: u1 = 0,
    };

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
    };

    fn AM_Implied(self: *CPU) AMRes {
        return AMRes{ .res = self.a, .addr = 0, .additionalCycle = 0 };
    }

    fn AM_Accumulator(self: *CPU) AMRes {
        return AMRes{ .res = self.a, .addr = 0, .additionalCycle = 0 };
    }

    fn AM_Immediate(self: *CPU) AMRes {
        const val = self.bus.read(self.pc);
        self.pc += 1;
        return AMRes{ .res = val, .addr = 0, .additionalCycle = 0 };
    }

    fn AM_ZeroPage(self: *CPU) AMRes {
        const val = self.bus.read(self.pc);
        self.pc += 1;
        return AMRes{ .res = self.bus.read(val), .addr = val, .additionalCycle = 0 };
    }

    fn AM_ZeroPageX(self: *CPU) AMRes {
        const addr = self.bus.read(self.pc);
        self.pc += 1;
        const res: u8 = addr +% self.x;
        return AMRes{ .addr = res, .res = self.bus.read(res), .additionalCycle = 0 };
    }

    fn AM_ZeroPageY(self: *CPU) AMRes {
        const addr = self.bus.read(self.pc);
        self.pc += 1;
        const res: u8 = addr +% self.y;
        return AMRes{
            .addr = res,
            .res = self.bus.read(res),
            .additionalCycle = 0,
        };
    }

    fn AM_Relative(self: *CPU) AMRes {
        const offset: i8 = @bitCast(self.bus.read(self.pc));
        self.pc += 1;
        const res = @as(i16, @bitCast(self.pc)) + offset;
        return AMRes{
            .addr = @bitCast(res),
            .res = self.bus.read(@bitCast(res)),
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
            .res = self.bus.read(abs_addr),
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
            .res = 0,
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
            .res = 0,
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
            .res = self.bus.read(final_addr),
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
            .res = self.bus.read(final_addr),
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
            .res = self.bus.read(final_addr),
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

    const g1_addr_mode = [8](*const fn (self: *CPU) AMRes){
        CPU.AM_IndexedIndirect, // indirect, x
        CPU.AM_ZeroPage,
        CPU.AM_Immediate,
        CPU.AM_Absolute,
        CPU.AM_IndirectIndexed, // indirect, y
        CPU.AM_ZeroPageX,
        CPU.AM_AbsoluteY,
        CPU.AM_AbsoluteX,
    };

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
        std.debug.print("{s} {s:16} res: {x:2} addr: {x:4}, c+: {}, A: {x:2} X: {x:2} Y: {x:2} SP: {x:2} F: {b:8}\n", .{
            instruction_name,
            @tagName(@as(enum_tag, (@enumFromInt(addr_mode)))),
            am_res.res,
            am_res.addr,
            am_res.additionalCycle,
            self.a,
            self.x,
            self.y,
            self.sp,
            @as(u8, @bitCast(self.status)),
        });
    }

    fn ORA(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        self.a |= am_res.res;
        const instruction_cycle = [8]u8{ 6, 3, 2, 4, 5, 4, 4, 4 };
        return instruction_cycle[addr_mode];
    }

    fn AND(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        self.a &= am_res.res;
        const instruction_cycle = [8]u8{ 6, 3, 2, 4, 5, 4, 4, 4 };
        return instruction_cycle[addr_mode];
    }

    fn EOR(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        self.a ^= am_res.res;
        const instruction_cycle = [8]u8{ 6, 3, 2, 4, 5, 4, 4, 4 };
        return instruction_cycle[addr_mode];
    }

    fn ADC(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        if (self.status.decimalMode == 1) {
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

    fn STA(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        self.bus.write(am_res.addr, self.a);
        const instruction_cycle = [8]u8{ 6, 3, 0, 4, 6, 4, 5, 5 };
        return instruction_cycle[addr_mode];
    }

    fn LDA(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        self.a = am_res.res;
        self.status.zero = if (am_res.res == 0) 1 else 0;
        self.status.negative = if (am_res.res & 0x80 != 0) 1 else 0;
        const instruction_cycle = [8]u8{ 6, 3, 2, 4, 5, 4, 4, 4 };
        return instruction_cycle[addr_mode];
    }

    fn CMP(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        const tmp = @as(i16, @intCast(self.a)) - am_res.res;
        self.status.zero = if (tmp == 0) 1 else 0;
        self.status.carry = if (self.a >= am_res.res) 1 else 0;
        self.status.negative = if (tmp >> 7 != 0) 1 else 0;
        const instruction_cycle = [8]u8{ 6, 3, 2, 4, 5, 4, 4, 4 };
        return instruction_cycle[addr_mode];
    }

    fn SBC(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        if (self.status.decimalMode == 1) {
            const first_a = self.a >> 4;
            const second_a = self.a & 0xFF;
            const first_res = am_res.res >> 4;
            const second_res = am_res.res & 0xFF;
            var res = second_a - second_res - 1 + self.status.carry;
            var carry: u8 = 0;
            if (res >= 10) {
                carry = 1;
                res -= 10;
            }
            var tmp = (first_a - first_res - 1 + carry);
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

    const g2_addr_mode = [8](*const fn (self: *CPU) AMRes){
        CPU.AM_Immediate,
        CPU.AM_ZeroPage,
        CPU.AM_Accumulator,
        CPU.AM_Absolute,
        CPU.AM_None,
        CPU.AM_ZeroPageX,
        CPU.AM_None,
        CPU.AM_AbsoluteX,
    };

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

    fn ASL(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
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

    fn ROL(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
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

    fn LSR(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
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

    fn ROR(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        var res = am_res.res / 2;
        const last = am_res.res & 1;
        res |= last << 7;
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

    fn STX(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        self.bus.write(am_res.addr, self.x);
        const instruction_cycle = [8]u8{ 0, 3, 0, 4, 0, 4, 0, 0 };
        return instruction_cycle[addr_mode];
    }

    fn LDX(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        self.x = am_res.res;
        self.status.zero = if (am_res.res == 0) 1 else 0;
        self.status.negative = if (am_res.res & 0x80 != 0) 1 else 0;
        const instruction_cycle = [8]u8{ 2, 3, 0, 4, 0, 4, 0, 4 };
        return instruction_cycle[addr_mode];
    }

    fn DEC(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        const res = am_res.res -% 1;
        self.status.zero = if (res == 0) 1 else 0;
        self.status.negative = if (res & 0x80 != 0) 1 else 0;
        self.bus.write(am_res.addr, res);
        const instruction_cycle = [8]u8{ 0, 5, 0, 6, 0, 6, 0, 7 };
        return instruction_cycle[addr_mode];
    }

    fn INC(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        const res = am_res.res +% 1;
        self.status.zero = if (res == 0) 1 else 0;
        self.status.negative = if (res & 0x80 != 0) 1 else 0;
        self.bus.write(am_res.addr, res);
        const instruction_cycle = [8]u8{ 0, 5, 0, 6, 0, 6, 0, 7 };
        return instruction_cycle[addr_mode];
    }

    const g3_addr_mode = [8](*const fn (self: *CPU) AMRes){
        CPU.AM_Immediate,
        CPU.AM_ZeroPage,
        CPU.AM_None,
        CPU.AM_Absolute,
        CPU.AM_Relative,
        CPU.AM_ZeroPageX,
        CPU.AM_None,
        CPU.AM_AbsoluteX,
    };
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

    fn LDY(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        self.y = am_res.res;
        self.status.zero = if (am_res.res == 0) 1 else 0;
        self.status.negative = if (am_res.res & 0x80 != 0) 1 else 0;
        const instruction_cycle = [8]u8{ 2, 3, 0, 4, 0, 4, 0, 4 };
        return instruction_cycle[addr_mode];
    }

    fn CPY(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
        const tmp = @as(i16, @intCast(self.y)) - am_res.res;
        self.status.zero = if (tmp == 0) 1 else 0;
        self.status.carry = if (self.y >= am_res.res) 1 else 0;
        self.status.negative = if (tmp >> 7 != 0) 1 else 0;
        const instruction_cycle = [8]u8{ 2, 3, 0, 4, 0, 0, 0, 0 };
        return instruction_cycle[addr_mode];
    }

    fn CPX(self: *CPU, addr_mode: u8, am_res: AMRes) u8 {
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

    fn wait() void {}

    pub fn exec(self: *CPU, end_after_: u16) !void {
        var end_after = end_after_;
        var wait_cycle: u8 = 0;
        while (true) {
            defer wait();
            if (end_after != 0) {
                end_after -= 1;
                if (end_after == 0) {
                    break;
                }
            }
            if (wait_cycle != 0) {
                wait_cycle -= 1;
                continue;
            }
            if (self.pc == 0xFFFA) {
                break;
            }
            // std.debug.print("Next: {x} {x} {x} {x}\n", .{ self.bus.read(self.pc + 1), self.bus.read(self.pc + 2), self.bus.read(self.pc + 3), self.bus.read(self.pc + 4) });
            const instruction = self.bus.read(self.pc);
            std.debug.print("{x:4} {x:2} ", .{ self.pc, instruction });
            self.pc += 1;
            const group = instruction & 3;
            const op_code = (instruction & 0b11100000) >> 5;
            const addr_mode = (instruction & 0b11100) >> 2;
            switch (group) {
                // Group 1
                0b01 => {
                    const am_res = g1_addr_mode[addr_mode](self);
                    const g1_instruction = [8](*const fn (*CPU, u8, AMRes) u8){
                        CPU.ORA, CPU.AND, CPU.EOR, CPU.ADC, CPU.STA, CPU.LDA, CPU.CMP, CPU.SBC,
                    };
                    const g1_instruction_str = [_][]const u8{
                        "ORA", "AND", "EOR", "ADC", "STA", "LDA", "CMP", "SBC",
                    };
                    self.logDbg(g1_instruction_str[op_code], addr_mode, am_res, g1_addr_mode_tag);
                    wait_cycle = g1_instruction[op_code](self, addr_mode, am_res) + am_res.additionalCycle;
                },
                // Group 2
                0b10 => {
                    var am_res: AMRes = undefined;
                    if (op_code == 4 or op_code == 5) { // LDX and STX exception
                        if (addr_mode == 5) {
                            am_res = self.AM_ZeroPageY();
                        }
                        if (addr_mode == 7) {
                            am_res = self.AM_AbsoluteY();
                        }
                        am_res = g2_addr_mode[addr_mode](self);
                    } else {
                        am_res = g2_addr_mode[addr_mode](self);
                    }
                    const g2_instruction = [8](*const fn (*CPU, u8, AMRes) u8){
                        CPU.ASL, CPU.ROL, CPU.LSR, CPU.ROR, CPU.STX, CPU.LDX, CPU.DEC, CPU.INC,
                    };
                    const g2_instruction_str = [_][]const u8{
                        "ASL", "ROL", "LSR", "ROR", "STX", "LDX", "DEC", "INC",
                    };
                    switch (instruction) {
                        0x8A => { // TXA
                            self.logDbg("TXA", addr_mode, am_res, g2_addr_mode_tag);
                            self.a = self.x;
                            self.status.zero = if (self.a == 0) 1 else 0;
                            self.status.negative = if (self.a >> 7 != 0) 1 else 0;
                            wait_cycle = 2;
                        },
                        0x9A => { // TXS
                            self.logDbg("TXS", addr_mode, am_res, g2_addr_mode_tag);
                            self.sp = self.x;
                            wait_cycle = 2;
                        },
                        0xAA => { // TAX
                            self.logDbg("TAX", addr_mode, am_res, g2_addr_mode_tag);
                            self.x = self.a;
                            self.status.zero = if (self.a == 0) 1 else 0;
                            self.status.negative = if (self.a >> 7 != 0) 1 else 0;
                            wait_cycle = 2;
                        },
                        0xBA => { // TSX
                            self.logDbg("TSX", addr_mode, am_res, g2_addr_mode_tag);
                            self.x = self.sp;
                            self.status.zero = if (self.x == 0) 1 else 0;
                            self.status.negative = if (self.x >> 7 != 0) 1 else 0;
                            wait_cycle = 2;
                        },
                        0xCA => { // DEX
                            self.logDbg("DEX", addr_mode, am_res, g2_addr_mode_tag);
                            self.DEStuff(&self.x);
                            wait_cycle = 2;
                        },
                        0xEA => { // NOP
                            self.logDbg("NOP", addr_mode, am_res, g2_addr_mode_tag);
                            wait_cycle = 2;
                        },
                        else => {
                            self.logDbg(g2_instruction_str[op_code], addr_mode, am_res, g2_addr_mode_tag);
                            wait_cycle = g2_instruction[op_code](self, addr_mode, am_res) + am_res.additionalCycle;
                        },
                    }
                },
                // Group 3
                0b00 => {
                    switch (instruction) {
                        0x00 => { // BRK is a 2-byte opcode
                            self.logDbg("BRK", 2, AMRes{}, g3_addr_mode_tag);
                            const padding = self.bus.read(self.pc);
                            _ = padding;
                            self.pc += 1;
                            self.bus.write(self.getStackAddr(0), @bitCast(self.status));
                            const hi: u8 = @truncate(self.pc >> 8);
                            self.bus.write(self.getStackAddr(-1), hi);
                            const lo: u8 = @truncate(self.pc);
                            self.bus.write(self.getStackAddr(-2), lo);
                            self.sp -%= 3;
                            self.pc = @as(u16, @intCast(self.bus.read(0xFFFF))) << 8 | self.bus.read(0xFFFE);
                            self.status.breakCommand = 1;
                            wait_cycle = 7;
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
                            wait_cycle = 6;
                        },
                        0x40 => { // RTI
                            self.logDbg("RTI", 2, AMRes{}, g3_addr_mode_tag);
                            self.sp +%= 1;
                            self.status = @bitCast(self.bus.read(self.getStackAddr(0)));
                            const pc_lo = self.bus.read(self.getStackAddr(1));
                            const pc_hi: u16 = self.bus.read(self.getStackAddr(2));
                            self.sp +%= 2;
                            self.pc = pc_hi << 8 | pc_lo;
                            wait_cycle = 6;
                        },
                        0x60 => { // RTS
                            self.logDbg("RTS", 2, AMRes{}, g3_addr_mode_tag);
                            self.sp +%= 1;
                            const pc_lo = self.bus.read(self.getStackAddr(0));
                            const pc_hi: u16 = self.bus.read(self.getStackAddr(1));
                            self.sp +%= 1;
                            self.pc = (pc_hi << 8 | pc_lo) + 1;
                            wait_cycle = 6;
                        },
                        0x08 => { // PHP not the language
                            self.logDbg("PHP", 2, AMRes{}, g3_addr_mode_tag);
                            self.bus.write(self.getStackAddr(0), @bitCast(self.status));
                            self.sp -%= 1;
                            wait_cycle = 3;
                        },
                        0x18 => { // CLC
                            self.logDbg("CLC", 2, AMRes{}, g3_addr_mode_tag);
                            self.status.carry = 0;
                            wait_cycle = 2;
                        },
                        0x28 => { // PLP
                            self.logDbg("PLP", 2, AMRes{}, g3_addr_mode_tag);
                            self.sp +%= 1;
                            self.status = @bitCast(self.bus.read(self.getStackAddr(0)));
                            wait_cycle = 4;
                        },
                        0x38 => { // SEC
                            self.logDbg("SEC", 2, AMRes{}, g3_addr_mode_tag);
                            self.status.carry = 1;
                            wait_cycle = 2;
                        },
                        0x48 => { // PHA
                            self.logDbg("PHA", 2, AMRes{}, g3_addr_mode_tag);
                            self.bus.write(self.getStackAddr(0), self.a);
                            self.sp -%= 1;
                            wait_cycle = 3;
                        },
                        0x58 => { // CLI
                            self.logDbg("CLI", 2, AMRes{}, g3_addr_mode_tag);
                            self.status.interruptDisable = 0;
                            wait_cycle = 2;
                        },
                        0x68 => { // PLA
                            self.logDbg("PLA", 2, AMRes{}, g3_addr_mode_tag);
                            self.sp +%= 1;
                            self.a = self.bus.read(self.getStackAddr(0));
                            self.status.zero = if (self.a == 0) 1 else 0;
                            self.status.negative = if (self.a >> 7 != 0) 1 else 0;
                            wait_cycle = 4;
                        },
                        0x78 => { // SEI
                            self.logDbg("SEI", 2, AMRes{}, g3_addr_mode_tag);
                            self.status.interruptDisable = 1;
                            wait_cycle = 2;
                        },
                        0x88 => { // DEY
                            self.logDbg("DEY", 2, AMRes{}, g3_addr_mode_tag);
                            self.DEStuff(&self.y);
                            wait_cycle = 2;
                        },
                        0x98 => { // TYA
                            self.logDbg("TYA", 2, AMRes{}, g3_addr_mode_tag);
                            self.a = self.y;
                            self.status.zero = if (self.y == 0) 1 else 0;
                            self.status.negative = if (self.y >> 7 != 0) 1 else 0;
                            wait_cycle = 2;
                        },
                        0xA8 => { // TAY
                            self.logDbg("TAY", 2, AMRes{}, g3_addr_mode_tag);
                            self.y = self.a;
                            self.status.zero = if (self.y == 0) 1 else 0;
                            self.status.negative = if (self.y >> 7 != 0) 1 else 0;
                            wait_cycle = 2;
                        },
                        0xB8 => { // CLV
                            self.logDbg("CLV", 2, AMRes{}, g3_addr_mode_tag);
                            self.status.overflow = 0;
                            wait_cycle = 2;
                        },
                        0xC8 => { // INY
                            self.logDbg("INY", 2, AMRes{}, g3_addr_mode_tag);
                            self.INStuff(&self.y);
                            wait_cycle = 2;
                        },
                        0xD8 => { // CLD
                            self.logDbg("CLD", 2, AMRes{}, g3_addr_mode_tag);
                            self.status.decimalMode = 0;
                            wait_cycle = 2;
                        },
                        0xE8 => { // INX
                            self.logDbg("INX", 2, AMRes{}, g3_addr_mode_tag);
                            self.INStuff(&self.x);
                            wait_cycle = 2;
                        },
                        0xF8 => { // SED
                            self.logDbg("SED", 2, AMRes{}, g3_addr_mode_tag);
                            self.status.decimalMode = 1;
                            wait_cycle = 2;
                        },
                        else => {
                            const am_res = if (instruction == 0x6C) self.AM_Indirect() else g3_addr_mode[addr_mode](self);
                            const g3_instruction = [8](*const fn (*CPU, u8, AMRes) u8){
                                CPU.NOP, CPU.BIT, CPU.JMP, CPU.JMP, CPU.STY, CPU.LDY, CPU.CPY, CPU.CPX,
                            };
                            const g3_instruction_str = [_][]const u8{
                                "NOP", "BIT", "JMP", "JMP", "STY", "LDX", "CPY", "CPX",
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
                                    wait_cycle = 3 + am_res.additionalCycle;
                                } else {
                                    wait_cycle = 2;
                                }
                            } else {
                                self.logDbg(g3_instruction_str[op_code], if (instruction == 0x6C) 6 else addr_mode, am_res, g3_addr_mode_tag);
                                wait_cycle = g3_instruction[op_code](self, addr_mode, am_res) + am_res.additionalCycle;
                            }
                        },
                    }
                },
                else => {},
            }
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

test "Simple test" {
    const Ram = @import("ram.zig").RAM;
    var bus = Bus.init(std.testing.allocator);
    defer bus.deinit();
    var ram = Ram{};
    try bus.register(&ram);
    var test_prog = simple_prog{ .data = &[_]u8{ 0xA9, 0x05, 0x69, 0x05 } };
    try bus.register(&test_prog);
    var cpu = CPU{ .bus = bus, .pc = 0xC000, .sp = 0xFF };
    try cpu.exec(5);
    try std.testing.expect(cpu.a == 10);
}

test "CPU operation test" {
    // Read test rom
    const iNes = @import("ines.zig").ROM;
    const Ram = @import("ram.zig").RAM;
    const testRomFile = try std.fs.cwd().openFile("test-rom/nestest.nes", .{});
    defer testRomFile.close();
    var test_rom = try iNes.readFromFile(testRomFile, std.testing.allocator);
    defer test_rom.deinit();
    var bus = Bus.init(std.testing.allocator);
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
    try std.testing.expect(bus.read(0x02) == 0);
}
