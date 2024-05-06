const APU = @This();
const std = @import("std");
const sdl = @import("zsdl");

audio_spec: sdl.AudioSpec = sdl.AudioSpec{
    .channels = 1,
    .format = sdl.AUDIO_S16SYS,
    .freq = 44100,
    .samples = 1024,
    .callback = audio_callback,
},
audio_dev_id: sdl.AudioDeviceId,
allocator: std.mem.Allocator,
buffer: [2][]u8,

pub fn write(self: *APU, addr: u16, data: u8) void {
    _ = self;
    _ = addr;
    _ = data;
}

pub fn init(
    allocator: std.mem.Allocator,
    audio_dev_id: sdl.AudioDeviceId,
    audio_spec: sdl.AudioSpec,
) !APU {
    const buffer_size: usize = //
        @as(usize, audio_spec.channels) * @as(usize, @intCast(audio_spec.freq));
    var buffer: [2][]u8 = undefined;
    buffer[0] = try allocator.alloc(u8, buffer_size);
    @memset(buffer[0], 0);
    errdefer allocator.free(buffer[0]);
    buffer[1] = try allocator.alloc(u8, buffer_size);
    @memset(buffer[1], 0);
    errdefer allocator.free(buffer[1]);

    return APU{
        .allocator = allocator,
        .audio_spec = audio_spec,
        .audio_dev_id = audio_dev_id,
        .buffer = buffer,
    };
}

pub fn deinit(self: *APU) void {
    sdl.pauseAudioDevice(self.audio_dev_id, true);
    self.allocator.free(self.buffer[0]);
    self.allocator.free(self.buffer[1]);
}

pub fn audio_callback(
    userdata: ?*anyopaque,
    stream: [*c]u8,
    len: c_int,
) callconv(.C) void {
    _ = userdata;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        stream[i] = 0;
    }
}
