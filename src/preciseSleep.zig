// https://blog.bearcats.nl/accurate-sleep-function/
pub fn preciseSleep(time_second: f64) void {
    var time_s = time_second;
    const StaticState = struct {
        var estimate: f64 = 5e-3;
        var mean: f64 = 5e-3;
        var m2: f64 = 0;
        var count: u64 = 1;
    };

    while (time_s > StaticState.estimate) {
        const start = zglfw.getTime();
        std.time.sleep(1 * std.time.ns_per_s);
        const end = zglfw.getTime();

        const observed = end - start;
        time_s -= observed;

        StaticState.count += 1;
        const delta = observed - StaticState.mean;
        StaticState.mean += delta / @as(f64, @floatFromInt(StaticState.count));
        StaticState.m2 += delta * (observed - StaticState.mean);
        const stddev = std.math.sqrt(
            StaticState.m2 / @as(f64, @floatFromInt(StaticState.count)),
        );
        StaticState.estimate = StaticState.mean + stddev;
    }

    const start = zglfw.getTime();
    while (zglfw.getTime() - start < time_s) {}
}
