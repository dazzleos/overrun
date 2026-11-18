//! The fog of war: what a player sees now (near their units and
//! buildings), what they have seen (darker: the ground as it was), and what
//! they never have (near black). Kept as an 8-bit picture over the map, a
//! texel every few blocks, which the GPU samples for each pixel (see
//! shaders/flat.zig) and the minimap draws over itself.

const std = @import("std");
const map_mod = @import("map.zig");
const units = @import("units.zig");

/// Texels across and down.
pub const size = 256;
/// The square it covers: from (`origin`, `origin`), `span` blocks across
/// and down (all of the map, and its margins).
pub const origin: f32 = -@as(f32, map_mod.margin_cols);
pub const span: f32 = @floatFromInt(map_mod.cols - 1);
const per_texel = span / size;

/// How light each is (the ground's colour is multiplied by it, of 255).
pub const seeing: u8 = 255;
pub const seen: u8 = 120;
pub const unseen: u8 = 26;

/// How often it is worked out again, in seconds of the game.
pub const every: f32 = 0.2;

/// How far each kind sees, in blocks.
pub fn sight(k: units.Kind) f32 {
    return switch (k) {
        .walker => 10,
        .tank => 9,
        .drone => 14,
        .builder => 9,
        .air_builder => 12,
        .tower => 13,
        .factory => 9,
        .power, .mine => 7,
    };
}

pub const Fog = struct {
    /// How light each texel is, row by row (north first).
    light: [size * size]u8 = @splat(unseen),
    /// Which have been seen.
    explored: [size * size]bool = @splat(false),
    /// Changed each time it is worked out (for the GPU's copy).
    version: u32 = 0,

    /// Worked out again for `team`, from its units and buildings.
    pub fn update(f: *Fog, w: *const units.World, team: u2) void {
        for (&f.light, f.explored) |*l, e| l.* = if (e) seen else unseen;
        for (w.things[0..w.count]) |t| {
            if (t.team != team) continue;
            f.stamp(t.pos[0], t.pos[2], sight(t.kind));
        }
        f.version +%= 1;
    }

    /// What is within `r` blocks of (x, z) seen now: soft at its edge.
    fn stamp(f: *Fog, x: f32, z: f32, r: f32) void {
        const cx = (x - origin) / per_texel;
        const cz = (z - origin) / per_texel;
        const rt = r / per_texel;
        const x0: usize = @intFromFloat(std.math.clamp(@floor(cx - rt - 1), 0, size - 1));
        const x1: usize = @intFromFloat(std.math.clamp(@ceil(cx + rt + 1), 0, size - 1));
        const z0: usize = @intFromFloat(std.math.clamp(@floor(cz - rt - 1), 0, size - 1));
        const z1: usize = @intFromFloat(std.math.clamp(@ceil(cz + rt + 1), 0, size - 1));
        for (z0..z1 + 1) |tz| for (x0..x1 + 1) |tx| {
            const dx = @as(f32, @floatFromInt(tx)) + 0.5 - cx;
            const dz = @as(f32, @floatFromInt(tz)) + 0.5 - cz;
            const k = std.math.clamp(rt - @sqrt(dx * dx + dz * dz), 0, 1);
            if (k <= 0) continue;
            const i = tz * size + tx;
            f.explored[i] = true;
            const base: f32 = @floatFromInt(seen);
            const l: u8 = @intFromFloat(base + (255 - base) * k);
            f.light[i] = @max(f.light[i], l);
        };
    }

    /// Whether (x, z) is seen now.
    pub fn sees(f: *const Fog, x: f32, z: f32) bool {
        const tx = (x - origin) / per_texel;
        const tz = (z - origin) / per_texel;
        if (tx < 0 or tz < 0 or tx >= size or tz >= size) return false;
        return f.light[@as(usize, @intFromFloat(tz)) * size + @as(usize, @intFromFloat(tx))] > seen;
    }
};

/// Where (x, z) is on the fog's picture, from 0 to 1 across and down.
pub fn uvOf(x: f32, z: f32) [2]f32 {
    return .{ (x - origin) / span, (z - origin) / span };
}

const testing = std.testing;

test "the fog: seen round this player's, not round another's; what was seen stays darker" {
    const m = try map_mod.Map.create(testing.allocator, 1);
    defer m.destroy(testing.allocator);
    const w = try testing.allocator.create(units.World);
    defer testing.allocator.destroy(w);
    w.* = .{ .map = m };
    const a = w.add(.{ .kind = .walker, .team = 0, .pos = .{ 100, 0, 100 } }).?;
    _ = w.add(.{ .kind = .walker, .team = 1, .pos = .{ 300, 0, 300 } }).?;
    const f = try testing.allocator.create(Fog);
    defer testing.allocator.destroy(f);
    f.* = .{};
    f.update(w, 0);
    try testing.expect(f.sees(100, 100) and f.sees(108, 100));
    try testing.expect(!f.sees(113, 100));
    try testing.expect(!f.sees(300, 300));
    // Moved away: where it was, seen before, darker; never seen, darker still.
    w.things[a].pos = .{ 200, 0, 100 };
    f.update(w, 0);
    try testing.expect(!f.sees(100, 100) and f.sees(200, 100));
    const at = uvOf(100, 100);
    const i = @as(usize, @intFromFloat(at[1] * size)) * size + @as(usize, @intFromFloat(at[0] * size));
    try testing.expectEqual(seen, f.light[i]);
    try testing.expectEqual(unseen, f.light[0]);
    // It covers the map, margins and all.
    try testing.expectEqual(@as(f32, 0), uvOf(origin, origin)[0]);
    const last = map_mod.Map.at(map_mod.cols - 1, map_mod.rows - 1);
    try testing.expect(uvOf(last[0], last[1])[0] <= 1 and uvOf(last[0], last[1])[1] <= 1);
}
