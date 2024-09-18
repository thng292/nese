const std = @import("std");

pub fn Callable(comptime Callsite_fn: type) type {
    const callsite_fn_type_info = @typeInfo(Callsite_fn);
    comptime {
        if (callsite_fn_type_info != .Fn) {
            @compileError("Expected a function type, not " ++ @typeName(Callsite_fn));
        }
    }

    const callsite_fn_info = callsite_fn_type_info.Fn;
    const Passsite_fn = blk: {
        var passsite_fn_param: [callsite_fn_info.params.len + 1]std.builtin.Type.Fn.Param = undefined;
        passsite_fn_param[0] = .{
            .is_generic = false,
            .is_noalias = false,
            .type = *anyopaque,
        };
        for (callsite_fn_info.params, 1..) |param, i| {
            passsite_fn_param[i] = param;
        }

        var tmp = callsite_fn_info;
        tmp.params = passsite_fn_param[0..];

        const Type = @Type(.{ .Fn = tmp });
        break :blk *const Type;
    };

    return struct {
        const Self = @This();
        function: *const anyopaque,
        context: ?*anyopaque = null,
        deinit_fn: ?*const fn (*anyopaque) void,

        pub fn init(
            function: *const anyopaque,
            context: ?*anyopaque,
        ) Self {
            return Self{
                .function = function,
                .context = context,
                .deinit_fn = null,
            };
        }

        pub fn initWithDeinitFn(
            function: *const anyopaque,
            context: ?*anyopaque,
            deinit_fn: ?*const fn (*anyopaque) void,
        ) Self {
            return Self{
                .function = function,
                .context = context,
                .deinit_fn = deinit_fn,
            };
        }

        pub fn initNoContext(
            function: *const Callsite_fn,
        ) Self {
            return Self.init(@ptrCast(function), null);
        }

        pub fn call(
            self: Self,
            param: ParamOf(Callsite_fn),
        ) callconv(callsite_fn_info.calling_convention) callsite_fn_info.return_type.? {
            if (self.context) |closure| {
                return @call(
                    .auto,
                    @as(Passsite_fn, @ptrCast(self.function)),
                    .{closure} ++ param,
                );
            } else {
                return @call(
                    .auto,
                    @as(*const Callsite_fn, @ptrCast(self.function)),
                    param,
                );
            }
        }

        pub fn deinit(self: Self) void {
            if (self.deinit_fn) |deinit_fn| {
                if (self.context) |context| {
                    deinit_fn(context);
                }
            }
        }
    };
}

fn add(a: u64, b: u64) u64 {
    return a +% b;
}

test "Test Callable No Context" {
    const lambda = Callable(@TypeOf(add)).initNoContext(
        &add,
        null,
    );
    defer lambda.deinit();
    const result = lambda.call(.{ 1, 2 });
    try std.testing.expect(result == 3);
}

fn addContext(base: *u64, a: u64, b: u64) u64 {
    return base.* +% a +% b;
}

test "Test Callable With Context" {
    var base: u64 = 10;
    const lambda = Callable(@TypeOf(add)).init(
        &addContext,
        @ptrCast(&base),
        null,
    );
    defer lambda.deinit();
    const result = lambda.call(.{ 1, 2 });
    try std.testing.expect(result == 13);
}

test "Test Callable With Context Alloc" {
    const Context = struct {
        base: u64,
        allocator: std.mem.Allocator,
    };
    var context = try std.testing.allocator.create(Context);
    context.base = 10;
    context.allocator = std.testing.allocator;
    const lambda = Callable(@TypeOf(add)).init(
        &addContext,
        @ptrCast(context),
        struct {
            pub fn call(context_: *anyopaque) void {
                const ctx = @as(*Context, @ptrCast(@alignCast(context_)));
                const allocator = ctx.allocator;
                allocator.destroy(ctx);
            }
        }.call,
    );
    defer lambda.deinit();
    const result = lambda.call(.{ 1, 2 });
    try std.testing.expect(result == 13);
}

pub fn ParamOf(comptime function_type: type) type {
    const fn_type_info = @typeInfo(function_type);
    comptime {
        if (fn_type_info != .Fn) {
            @compileError("Expected function type, not " ++ @typeName(function_type));
        }
    }

    const fn_info = fn_type_info.Fn;
    var params: [fn_info.params.len]std.builtin.Type.StructField = undefined;

    for (fn_info.params, 0..) |param, i| {
        params[i] = std.builtin.Type.StructField{
            .alignment = @alignOf(param.type orelse void),
            .default_value = null,
            .is_comptime = param.is_generic,
            .name = std.fmt.comptimePrint("{}", .{i}),
            .type = param.type.?,
        };
    }

    return @Type(.{ .Struct = .{
        .layout = .auto,
        .fields = params[0..],
        .decls = &[_]std.builtin.Type.Declaration{},
        .is_tuple = true,
    } });
}

test "Test ParamOf" {
    // const expect = std.testing.expect;
    const tmp = @typeInfo(ParamOf(fn (u64, u64) void));
    const a: u64 = 0;
    const b: u64 = 1;
    const tup = .{ a, b };
    const tup_type = @typeInfo(@TypeOf(tup));
    try std.testing.expectEqual(
        tup_type.Struct.fields[0].type,
        tmp.Struct.fields[0].type,
    );

    const val: ParamOf(fn (u64, u64) void) = .{ a, b };
    _ = val;
}
