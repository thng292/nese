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
allocator: std.mem.Allocator,
buffer: [2][]u8,

pub fn write(self: *APU, addr: u16, data: u8) void {
    _ = self;
    _ = addr;
    _ = data;
}

pub fn init(allocator: std.mem.Allocator) !APU {
    const audio_spec: sdl.AudioSpec = sdl.AudioSpec{
        .channels = 1,
        .format = sdl.AUDIO_U8,
        .freq = 44100,
        .samples = 1024,
        .callback = audio_callback,
    };
    var out_audio_spec: sdl.AudioSpec = undefined;

    const audio_dev_id = sdl.openAudioDevice(null, false, &audio_spec, &out_audio_spec, 0);
    sdl.pauseAudioDevice(audio_dev_id, false);

    // std.debug.print("audio_dev_id: {}, out_audio_spec: {}\n", .{ audio_dev_id, out_audio_spec });
    if (audio_dev_id == 0) {
        std.debug.print("Failed to init audio: {?s}\n", .{SDL_GetError()});
    }

    const buffer_size: usize = audio_spec.channels * audio_spec.freq;
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
        .buffer = buffer,
    };
}

pub fn deinit(self: *APU) void {
    self.allocator.free(self.buffer[0]);
    self.allocator.free(self.buffer[1]);
}

fn audio_callback(
    userdata: ?*anyopaque,
    stream: [*c]u8,
    len: c_int,
) callconv(.C) void {
    _ = userdata;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        stream[i] = @truncate(i % 255);
    }
}

extern fn SDL_GetError() ?[*:0]const u8;
