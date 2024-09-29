const std = @import("std");
const zglfw = @import("zglfw");

// https://blog.bearcats.nl/accurate-sleep-function/
const PreciseSleepState = struct {
    estimate: f64 = 5e-3,
    mean: f64 = 5e-3,
    m2: f64 = 0,
    count: u64 = 1,

    pub fn sleep(self: *PreciseSleepState, time_second: f64) void {
        var time_s = time_second;

        while (time_s > self.estimate) {
            const start = zglfw.getTime();
            std.time.sleep(1 * std.time.ns_per_s);
            const end = zglfw.getTime();

            const observed = end - start;
            time_s -= observed;

            self.count += 1;
            const delta = observed - self.mean;
            self.mean += delta / @as(f64, @floatFromInt(self.count));
            self.m2 += delta * (observed - self.mean);
            const stddev = std.math.sqrt(
                self.m2 / @as(f64, @floatFromInt(self.count)),
            );
            self.estimate = self.mean + stddev;
        }

        const start = zglfw.getTime();
        while (zglfw.getTime() - start < time_s) {}
    }
};

test "PreciseSleep" {
    var tmp = PreciseSleepState{};
    tmp.sleep(10);
}
