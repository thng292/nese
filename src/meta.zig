const std = @import("std");

pub fn search(comptime haystack: anytype, needle: [:0]const u8) bool {
    for (haystack) |item| {
        if (std.mem.eql(u8, item, needle)) {
            return true;
        }
    }
    return false;
}

pub fn StructWithout(comptime original_struct: type, ignore_fields: anytype) type {
    const original_struct_fields = std.meta.fields(original_struct);
    var fields: [original_struct_fields.len - ignore_fields.len]std.builtin.Type.StructField = undefined;
    var counter: u64 = 0;
    inline for (original_struct_fields) |field| {
        if (search(ignore_fields, field.name)) {
            continue;
        }

        fields[counter] = field;

        counter += 1;
    }
    return @Type(.{ .Struct = .{
        .layout = .auto,
        .fields = fields[0..],
        .decls = &[_]std.builtin.Type.Declaration{},
        .is_tuple = false,
    } });
}

pub fn cloneStructWithout(
    original_struct: anytype,
    ignore_fields: anytype,
) StructWithout(
    @TypeOf(original_struct),
    ignore_fields,
) {
    const res_type = StructWithout(@TypeOf(original_struct), ignore_fields);
    var res: res_type = undefined;
    inline for (std.meta.fields(res_type)) |field| {
        @field(res, field.name) = @field(original_struct, field.name);
    }
    return res;
}

pub fn copyStructExhaust(source: anytype, destination: anytype) void {
    const assert = std.debug.assert;
    const destination_type = @TypeOf(destination);
    const source_type = @TypeOf(source);
    assert(@typeInfo(destination_type) == .Pointer); // Must be a pointer
    assert(@typeInfo(destination_type).Pointer.size == .One); // Must be a single-item pointer
    assert(@typeInfo(@typeInfo(destination_type).Pointer.child) == .Struct); // Must point to a struct

    inline for (std.meta.fields(@TypeOf(destination.*))) |field| {
        if (@hasField(source_type, field.name)) {
            @field(destination.*, field.name) = @field(source, field.name);
        }
    }
}

pub fn initStructFrom(comptime T: type, source: anytype) T {
    var res: T = undefined;
    copyStructExhaust(source, &res);
    return res;
}
