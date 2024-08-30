const std = @import("std");

pub fn Callable(comptime callsite_fn_type: type) type {
    const callsite_fn_type_info = @typeInfo(callsite_fn_type);
    comptime {
        if (callsite_fn_type_info != .Fn) {
            @compileError("Expected a function type, not " ++ @typeName(callsite_fn_type));
        }
    }

    const callsite_fn_info = callsite_fn_type_info.Fn;

    return struct {
        const Self = @This();
        function: *const anyopaque,
        original_function_type: type,
        closure: ?*anyopaque = null,
        closure_type: type,
        allocator: ?std.mem.Allocator,

        pub fn init(
            comptime function: anytype,
            comptime Closure: type,
            closure: *Closure,
            allocator_maybe: ?std.mem.Allocator,
        ) !Self {
            comptime {
                const fn_type = @TypeOf(function);
                const fn_type_info = @typeInfo(fn_type);
                if (fn_type_info != .Pointer or @typeInfo(fn_type_info.Pointer.child) != .Fn) {
                    @compileError("Expect a pointer to const function for function, not " ++ @typeName(function));
                }
                const in_fn_params = @typeInfo(fn_type_info.Pointer.child).Fn.params;
                var index: usize = 0;
                if (Closure != void) {
                    if (in_fn_params[0].type != *Closure) {
                        @compileError("Expect a function with first parameter's type is " //
                        ++ @typeName(*Closure) ++ ", not " ++ @typeName(in_fn_params[0].type.?));
                    }
                    index = 1;
                }
                for (callsite_fn_info.params, index..) |param, i| {
                    if (in_fn_params[i].type != param.type) {
                        @compileError("Expect a function with " //
                        ++ std.fmt.comptimePrint("{d}", .{i}) ++ " parameter's type is " //
                        ++ @typeName(param.type) ++ ", not " ++ @typeName(in_fn_params[i].type.?));
                    }
                }
            }

            return Self{
                .allocator = allocator_maybe,
                .function = @ptrCast(function),
                .original_function_type = @TypeOf(function),
                .closure = @ptrCast(closure),
                .closure_type = *Closure,
            };
        }

        pub fn call(
            self: Self,
            param: ParamOf(callsite_fn_type),
        ) callconv(callsite_fn_info.calling_convention) callsite_fn_info.return_type.? {
            return @call(
                .auto,
                @as(self.original_function_type, @ptrCast(self.function)),
                if (self.closure) |_| .{@as(self.closure_type, @ptrCast(self.closure))} ++ param else param,
                // param,
            );
        }

        pub fn deinit(self: Self) void {
            if (self.allocator) |allocator| {
                if (self.closure) |ptr| {
                    allocator.destroy(@as(self.closure_type, @ptrCast(ptr)));
                }
            }
        }
    };
}

fn add(a: u64, b: u64) u64 {
    return a +% b;
}

test "Test Callable No Context" {
    const lambda = try Callable(@TypeOf(add)).init(
        &add,
        void,
        @ptrFromInt(10),
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
    const lambda = try Callable(@TypeOf(add)).init(
        &addContext,
        u64,
        &base,
        null,
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
