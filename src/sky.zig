//! The time of day and the weather, from the game's time and the map's
//! seed (so every player has the same): the light, as a tint every colour
//! is multiplied by (in the shader, so it costs nothing to change), and
//! the rain, as thin triangles falling round the view.

const std = @import("std");
const math = @import("math.zig");
const mesh = @import("mesh.zig");

const V3 = math.V3;

/// How long a day (and its night) is, in seconds.
pub const day_seconds: f32 = 480;
/// Where in the day a game starts: mid-morning.
const start_of_day: f32 = 0.06;

/// How long the weather keeps to a kind, and how long it takes to change.
const spell_seconds: f32 = 75;
const change_seconds: f32 = 20;

pub const Kind = enum { clear, cloudy, rain, storm };

/// How cloudy, rainy and stormy it is, each from 0 to 1.
pub const Weather = struct {
    cloud: f32 = 0,
    rain: f32 = 0,
    storm: f32 = 0,

    fn of(k: Kind) Weather {
        return switch (k) {
            .clear => .{},
            .cloudy => .{ .cloud = 0.6 },
            .rain => .{ .cloud = 0.85, .rain = 0.7 },
            .storm => .{ .cloud = 1, .rain = 1, .storm = 1 },
        };
    }

    fn mix(a: Weather, b: Weather, t: f32) Weather {
        return .{ .cloud = a.cloud + (b.cloud - a.cloud) * t, .rain = a.rain + (b.rain - a.rain) * t, .storm = a.storm + (b.storm - a.storm) * t };
    }
};

/// The weather's kind in spell `i` (the first is always clear).
fn spellKind(seed: u32, i: u32) Kind {
    if (i == 0) return .clear;
    const h = hash(seed *% 0x85ebca6b ^ i *% 0xc2b2ae35);
    return if (h < 0.45) .clear else if (h < 0.7) .cloudy else if (h < 0.9) .rain else .storm;
}

/// The weather at `time` (seconds into the game).
pub fn weatherAt(seed: u32, time: f32) Weather {
    const i: u32 = @intFromFloat(@max(0, time) / spell_seconds);
    const into = time - @as(f32, @floatFromInt(i)) * spell_seconds;
    const now = Weather.of(spellKind(seed, i));
    if (i == 0 or into >= change_seconds) return now;
    return Weather.mix(.of(spellKind(seed, i - 1)), now, smoothstep(0, change_seconds, into));
}

/// The weather's kind at `time` (what it is changing to, half way).
pub fn kindAt(seed: u32, time: f32) Kind {
    const i: u32 = @intFromFloat(@max(0, time) / spell_seconds);
    const into = time - @as(f32, @floatFromInt(i)) * spell_seconds;
    return spellKind(seed, if (i > 0 and into < change_seconds / 2) i - 1 else i);
}

/// How high the sun is at `time`: 1 at noon, 0 at sunrise and sunset, -1
/// at midnight.
pub fn sunAt(time: f32) f32 {
    const phase = start_of_day + time / day_seconds;
    return @sin(2 * std.math.pi * (phase - @floor(phase)));
}

/// Whether it is night (for the weather's icon).
pub fn isNight(time: f32) bool {
    return sunAt(time) < -0.1;
}

/// The light at `time`, in `w`: what every colour is multiplied by. White
/// by day, warm at sunrise and sunset, a dim blue at night (dim enough to
/// see it is night, light enough to play); greyer and darker under cloud;
/// a flash now and then in a storm.
pub fn tintAt(seed: u32, time: f32, w: Weather) mesh.Rgb {
    const e = sunAt(time);
    const day = mesh.rgb(0xffffff);
    const dusk = mesh.Rgb{ 1.0, 0.74, 0.56 };
    const night = mesh.Rgb{ 0.32, 0.38, 0.6 };
    const warm = 1 - smoothstep(0, 0.35, @abs(e));
    const light = smoothstep(-0.3, 0.1, e);
    var c = mixRgb(night, mixRgb(day, dusk, warm), light);
    // Cloud: greyer, darker.
    const grey = (c[0] + c[1] + c[2]) / 3;
    c = mixRgb(c, .{ grey, grey, grey }, w.cloud * 0.4);
    const dark = 1 - 0.3 * w.cloud;
    c = .{ c[0] * dark, c[1] * dark, c[2] * dark };
    // Lightning.
    const flash = lightningAt(seed, time, w.storm);
    return .{ c[0] + flash, c[1] + flash, c[2] + flash * 1.1 };
}

/// How bright a flash of lightning is at `time` (0 most of the time).
pub fn lightningAt(seed: u32, time: f32, storm: f32) f32 {
    if (storm <= 0) return 0;
    const slot_seconds: f32 = 0.3;
    const slot = @floor(time / slot_seconds);
    const h = hash(seed +% 99 ^ @as(u32, @intFromFloat(@max(0, slot))) *% 0x27d4eb2d);
    if (h >= 0.02 * storm) return 0;
    const k = 1 - (time - slot * slot_seconds) / slot_seconds;
    return k * k * 0.9;
}

/// How high the rain falls from, and how fast.
const fall_height: f32 = 18;
const fall_speed: f32 = 16;
/// The rain is the same drops over each square this wide, across the map.
const tile: f32 = 128;
/// How many drops in a tile, in the heaviest rain.
const most_drops = 2600;

/// The rain's drops in the view (`cam`, `aspect` wide; `per_pixel` blocks
/// a pixel), `amount` heavy (0 to 1), at `time`: each a thin triangle,
/// a pixel or so wide, facing the camera.
pub fn rain(b: *mesh.Builder, cam: math.Camera, aspect: f32, per_pixel: f32, time: f32, amount: f32) void {
    if (amount <= 0) return;
    const box = cam.groundBox(aspect, -1, fall_height);
    const n: u32 = @intFromFloat(amount * most_drops);
    const right = cam.right();
    const half = right * math.splat(0.7 * per_pixel);
    const streak = V3{ 0.12, 0.9, 0.05 };
    const colour = mesh.Rgb{ 0.78, 0.84, 0.95 };
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const x = wrapInto(hash(i *% 3 +% 1) * tile, box[0][0]);
        if (x > box[1][0]) continue;
        const z = wrapInto(hash(i *% 3 +% 2) * tile, box[0][1]);
        if (z > box[1][1]) continue;
        const f = hash(i *% 3 +% 3) + time * fall_speed / fall_height;
        const y = fall_height * (1 - (f - @floor(f))) - 0.5;
        // Slanting a little with the wind as it falls.
        const p = V3{ x + 0.12 * y, y, z + 0.05 * y };
        b.shaded(.{ p - half, p + half, p + streak }, colour);
    }
}

/// `x` (in the tile from 0) moved by whole tiles to be at `from` or just
/// after it.
fn wrapInto(x: f32, from: f32) f32 {
    const d = x - from;
    return from + (d - @floor(d / tile) * tile);
}

fn hash(v: u32) f32 {
    var h = v *% 0x9e3779b9;
    h ^= h >> 16;
    h *%= 0x7feb352d;
    h ^= h >> 15;
    return @as(f32, @floatFromInt(h & 0xffffff)) / 16777216.0;
}

fn smoothstep(lo: f32, hi: f32, x: f32) f32 {
    const t = std.math.clamp((x - lo) / (hi - lo), 0, 1);
    return t * t * (3 - 2 * t);
}

fn mixRgb(a: mesh.Rgb, b: mesh.Rgb, t: f32) mesh.Rgb {
    return .{ a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t };
}

const testing = std.testing;

test "a day: light at noon, warm at sunset, dim and blue at night" {
    const noon = (0.25 - start_of_day) * day_seconds;
    const sunset = (0.5 - start_of_day) * day_seconds;
    const midnight = (0.75 - start_of_day) * day_seconds;
    try testing.expectApproxEqAbs(@as(f32, 1), sunAt(noon), 1e-3);
    try testing.expect(!isNight(0) and !isNight(noon) and isNight(midnight));
    const clear: Weather = .{};
    const day = tintAt(1, noon, clear);
    try testing.expectApproxEqAbs(@as(f32, 1), day[0], 1e-3);
    const dusk = tintAt(1, sunset, clear);
    try testing.expect(dusk[0] > dusk[2] + 0.2);
    const night = tintAt(1, midnight, clear);
    try testing.expect(night[2] > night[0] and night[0] < 0.4 and night[2] > 0.5);
    // Cloud: darker.
    try testing.expect(tintAt(1, noon, .{ .cloud = 1 })[1] < 0.75);
}

test "the weather: clear at first, then changing, smoothly; every kind comes" {
    try testing.expectEqual(Kind.clear, kindAt(1, 10));
    var seen: [4]bool = @splat(false);
    var last = weatherAt(1, 0);
    var t: f32 = 0;
    while (t < 200 * spell_seconds) : (t += 1) {
        seen[@intFromEnum(kindAt(1, t))] = true;
        const w = weatherAt(1, t);
        try testing.expect(@abs(w.rain - last.rain) < 0.1 and @abs(w.cloud - last.cloud) < 0.1);
        last = w;
    }
    for (seen) |s| try testing.expect(s);
}

test "rain: drops in view, a triangle each, facing the camera" {
    var verts: [3 * most_drops]mesh.Vertex = undefined;
    var b: mesh.Builder = .{ .out = &verts };
    const cam: math.Camera = .{ .target = .{ 300, 1.5, 300 }, .zoom = 14 };
    rain(&b, cam, 16.0 / 9.0, 0.03, 12.5, 1);
    try testing.expect(b.n > 300 and b.n % 3 == 0);
    const box = cam.groundBox(16.0 / 9.0, -1, fall_height);
    var i: usize = 0;
    while (i < b.n) : (i += 3) {
        const p: [3]V3 = .{ verts[i].pos, verts[i + 1].pos, verts[i + 2].pos };
        try testing.expect(p[0][0] >= box[0][0] - 3 and p[0][0] <= box[1][0] + 3);
        try testing.expect(p[0][1] >= -1 and p[0][1] <= fall_height);
        try testing.expect(math.dot(math.cross(p[1] - p[0], p[2] - p[0]), cam.forward()) < 0);
    }
}
