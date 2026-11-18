//! The battlefield: corners on a hexagonal lattice (rows of them a block
//! apart, each row half a block along from the one before, the rows
//! √3/2 apart), each at its own height, and between each three of them a
//! triangle (equilateral, seen from above: six round each corner, a
//! hexagon), so the ground has hills, ridges and valleys (with water in
//! the lowest) and no grid's diagonals; and its triangles to draw, lit and
//! coloured by height and slope, in chunks (those out of view are not
//! drawn).

const std = @import("std");
const math = @import("math.zig");
const mesh = @import("mesh.zig");

const V3 = math.V3;
const Vertex = mesh.Vertex;

/// Blocks across and down (the map is `size` blocks square).
pub const size = 96;
/// How far apart the rows of corners are.
pub const row_gap: f32 = 0.8660254;
/// Corners in a row (the last of the odd rows half a block past the
/// map), and rows (enough to reach `size` down).
pub const cols = size + 1;
pub const rows = 112 + 1;
/// The water's height: ground below it is under water (units on the
/// ground cannot go there).
pub const water_level: f32 = 0.6;
/// Corners across and rows down a chunk (drawn, or not, together).
pub const chunk = 16;
pub const chunks_x = size / chunk;
pub const chunks_z = (rows - 1) / chunk;

/// Where each player's base is (the corners of the map, in from them).
pub const bases = [4][2]f32{ .{ 16, 16 }, .{ size - 16, size - 16 }, .{ size - 16, 16 }, .{ 16, size - 16 } };
/// How far round a base the ground is level.
const base_radius: f32 = 9;

pub const Map = struct {
    /// Each corner's height, row by row.
    heights: [rows * cols]f32,

    /// Where corner (c, r) is, across and down.
    pub fn at(c: usize, r: usize) [2]f32 {
        return .{ @as(f32, @floatFromInt(c)) + (if (r % 2 == 1) @as(f32, 0.5) else 0), @as(f32, @floatFromInt(r)) * row_gap };
    }

    pub fn generate(m: *Map, seed: u32) void {
        for (0..rows) |r| for (0..cols) |c| {
            const p = at(c, r);
            const fx = p[0];
            const fz = p[1];
            var h = 3.2 * fbm(seed, fx / 22, fz / 22, 4) - 0.6;
            // Ridges here and there.
            const rr = 1 - @abs(noise(seed +% 7, fx / 14, fz / 14) * 2 - 1);
            h += 2.2 * rr * rr * fbm(seed +% 11, fx / 30, fz / 30, 2);
            // Level ground round each base.
            for (bases) |b| {
                const d = @sqrt((fx - b[0]) * (fx - b[0]) + (fz - b[1]) * (fz - b[1]));
                const k = smoothstep(base_radius + 6, base_radius, d);
                h = h * (1 - k) + 1.5 * k;
            }
            m.heights[r * cols + c] = h;
        };
    }

    pub fn corner(m: *const Map, c: usize, r: usize) f32 {
        return m.heights[@as(usize, @min(r, rows - 1)) * cols + @as(usize, @min(c, cols - 1))];
    }

    fn point(m: *const Map, c: usize, r: usize) V3 {
        const p = at(c, r);
        return .{ p[0], m.corner(c, r), p[1] };
    }

    /// The two triangles between rows `r` and `r + 1` at column `c`: the
    /// one pointing down from row `r`, and the one pointing up from row
    /// `r + 1`, as corners (column, row).
    fn trianglesAt(c: usize, r: usize) [2][3][2]usize {
        // Even rows: the next row is half a block on; odd rows, half back.
        return if (r % 2 == 0)
            .{ .{ .{ c, r }, .{ c + 1, r }, .{ c, r + 1 } }, .{ .{ c + 1, r }, .{ c, r + 1 }, .{ c + 1, r + 1 } } }
        else
            .{ .{ .{ c, r }, .{ c + 1, r }, .{ c + 1, r + 1 } }, .{ .{ c, r }, .{ c, r + 1 }, .{ c + 1, r + 1 } } };
    }

    /// The ground's height at (x, z), on its triangle.
    pub fn heightAt(m: *const Map, x: f32, z: f32) f32 {
        const r: usize = @intFromFloat(std.math.clamp(@floor(z / row_gap), 0, rows - 2));
        // The columns the point may be between (each row is offset).
        const c0: usize = @intFromFloat(std.math.clamp(@floor(x - 0.5), 0, cols - 2));
        var best: f32 = 0;
        var best_out: f32 = std.math.inf(f32);
        var c = c0;
        while (c <= @min(c0 + 1, cols - 2)) : (c += 1) {
            for (trianglesAt(c, r)) |t| {
                const a = m.point(t[0][0], t[0][1]);
                const b = m.point(t[1][0], t[1][1]);
                const d = m.point(t[2][0], t[2][1]);
                // Barycentric weights, across and down.
                const den = (b[2] - d[2]) * (a[0] - d[0]) + (d[0] - b[0]) * (a[2] - d[2]);
                const wa = ((b[2] - d[2]) * (x - d[0]) + (d[0] - b[0]) * (z - d[2])) / den;
                const wb = ((d[2] - a[2]) * (x - d[0]) + (a[0] - d[0]) * (z - d[2])) / den;
                const wc = 1 - wa - wb;
                // Inside it, or (at the map's edges) the nearest.
                const out = @max(0, -wa) + @max(0, -wb) + @max(0, -wc);
                if (out < best_out) {
                    best_out = out;
                    best = wa * a[1] + wb * b[1] + wc * d[1];
                }
                if (out == 0) return best;
            }
        }
        return best;
    }

    /// The ground's height, or the water's over it.
    pub fn surfaceAt(m: *const Map, x: f32, z: f32) f32 {
        return @max(m.heightAt(x, z), water_level);
    }

    /// Whether a unit on the ground can be at (x, z): on the map, out of
    /// the water, and not too steep.
    pub fn passable(m: *const Map, x: f32, z: f32) bool {
        if (x < 0.5 or z < 0.5 or x > size - 0.5 or z > size - 0.5) return false;
        const h = m.heightAt(x, z);
        if (h < water_level + 0.05) return false;
        const dx = m.heightAt(x + 0.3, z) - m.heightAt(x - 0.3, z);
        const dz = m.heightAt(x, z + 0.3) - m.heightAt(x, z - 0.3);
        return @sqrt(dx * dx + dz * dz) / 0.6 < 1.4;
    }

    /// Where a ray (from `origin`, along `dir`) meets the ground or the
    /// water first, if it does on the map.
    pub fn raycast(m: *const Map, origin: V3, dir: V3) ?V3 {
        // From where it comes down to the highest the ground can be.
        if (dir[1] >= 0) return null;
        var t = @max(0, (12 - origin[1]) / dir[1]);
        var last = origin + dir * math.splat(t);
        const step: f32 = 0.2;
        var i: u32 = 0;
        while (i < 4000) : (i += 1) {
            t += step;
            const p = origin + dir * math.splat(t);
            if (p[1] < -2) return null;
            if (p[1] <= m.surfaceAt(p[0], p[2])) {
                // Between the last step and this: halve it a few times.
                var lo = last;
                var hi = p;
                for (0..8) |_| {
                    const mid = (lo + hi) / math.splat(2);
                    if (mid[1] <= m.surfaceAt(mid[0], mid[2])) hi = mid else lo = mid;
                }
                if (hi[0] < 0 or hi[2] < 0 or hi[0] > size or hi[2] > size) return null;
                return hi;
            }
            last = p;
        }
        return null;
    }

    /// The most vertices a chunk is (its triangles, and water over each).
    pub const chunk_vertices = chunk * chunk * 2 * 3 * 2;

    /// Where chunk (cx, cz) is, across and down: from, and to.
    pub fn chunkBounds(cx: usize, cz: usize) [2][2]f32 {
        return .{ .{ @floatFromInt(cx * chunk), @as(f32, @floatFromInt(cz * chunk)) * row_gap }, .{ @as(f32, @floatFromInt((cx + 1) * chunk)) + 0.5, @as(f32, @floatFromInt((cz + 1) * chunk)) * row_gap } };
    }

    /// The triangles of chunk (cx, cz), and its water, into `out`;
    /// returns how many vertices.
    pub fn chunkMesh(m: *const Map, cx: usize, cz: usize, out: []Vertex) usize {
        var b: mesh.Builder = .{ .out = out };
        for (cz * chunk..(cz + 1) * chunk) |r| for (cx * chunk..(cx + 1) * chunk) |c| {
            for (trianglesAt(c, r)) |t| {
                var q = [3]V3{ m.point(t[0][0], t[0][1]), m.point(t[1][0], t[1][1]), m.point(t[2][0], t[2][1]) };
                // Facing up (counter-clockwise from above).
                if (math.cross(q[1] - q[0], q[2] - q[0])[1] < 0) std.mem.swap(V3, &q[1], &q[2]);
                const n = math.cross(q[1] - q[0], q[2] - q[0]);
                const lowest = @min(q[0][1], @min(q[1][1], q[2][1]));
                const mid = (q[0][1] + q[1][1] + q[2][1]) / 3;
                const steep = 1 - math.normalize(n)[1];
                b.triangle(q, groundColour(mid, steep, @intCast(c * 31 + r * 17)));
                // Water over what is under it.
                if (lowest < water_level) {
                    const w = [3]V3{ .{ q[0][0], water_level, q[0][2] }, .{ q[1][0], water_level, q[1][2] }, .{ q[2][0], water_level, q[2][2] } };
                    const deep = std.math.clamp((water_level - mid) / 1.5, 0, 1);
                    b.shaded(w, mixRgb(mesh.rgb(0x3f8fb0), mesh.rgb(0x1d4f7a), deep));
                }
            }
        };
        return b.n;
    }
};

/// The ground's colour: sand by the water, grass, then rock up high and
/// on steep slopes; each triangle a little different (so they show).
fn groundColour(h: f32, steep: f32, salt: u32) mesh.Rgb {
    const sand = mesh.rgb(0xc8b27a);
    const grass = mesh.rgb(0x5f8a3e);
    const dry = mesh.rgb(0x8a8a4a);
    const rock = mesh.rgb(0x7d7468);
    var c = if (h < water_level + 0.35) sand else mixRgb(grass, dry, smoothstep(1.8, 3.4, h));
    c = mixRgb(c, rock, @max(smoothstep(0.18, 0.4, steep), smoothstep(3.6, 4.6, h)));
    const k = 0.94 + 0.1 * hash(salt);
    return .{ c[0] * k, c[1] * k, c[2] * k };
}

fn mixRgb(a: mesh.Rgb, b: mesh.Rgb, t: f32) mesh.Rgb {
    return .{ a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t };
}

fn smoothstep(lo: f32, hi: f32, x: f32) f32 {
    const t = std.math.clamp((x - lo) / (hi - lo), 0, 1);
    return t * t * (3 - 2 * t);
}

fn hash(v: u32) f32 {
    var h = v *% 0x9e3779b9;
    h ^= h >> 16;
    h *%= 0x7feb352d;
    h ^= h >> 15;
    return @as(f32, @floatFromInt(h & 0xffffff)) / 16777216.0;
}

fn lattice(seed: u32, x: i32, z: i32) f32 {
    return hash(seed ^ @as(u32, @bitCast(x)) *% 0x27d4eb2d ^ @as(u32, @bitCast(z)) *% 0x165667b1);
}

/// Smooth noise, from 0 to 1.
fn noise(seed: u32, x: f32, z: f32) f32 {
    const ix: i32 = @intFromFloat(@floor(x));
    const iz: i32 = @intFromFloat(@floor(z));
    const fx = x - @floor(x);
    const fz = z - @floor(z);
    const u = fx * fx * (3 - 2 * fx);
    const v = fz * fz * (3 - 2 * fz);
    const a = lattice(seed, ix, iz);
    const b = lattice(seed, ix + 1, iz);
    const c = lattice(seed, ix, iz + 1);
    const d = lattice(seed, ix + 1, iz + 1);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

fn fbm(seed: u32, x: f32, z: f32, octaves: u32) f32 {
    var sum: f32 = 0;
    var amp: f32 = 0.5;
    var f: f32 = 1;
    var total: f32 = 0;
    for (0..octaves) |o| {
        sum += amp * noise(seed +% @as(u32, @intCast(o)) *% 101, x * f, z * f);
        total += amp;
        amp *= 0.5;
        f *= 2;
    }
    return sum / total;
}

const testing = std.testing;

test "the ground: level round the bases, its height on its triangles, rays meeting it" {
    const m = try testing.allocator.create(Map);
    defer testing.allocator.destroy(m);
    m.generate(1);
    for (bases) |b| {
        try testing.expectApproxEqAbs(@as(f32, 1.5), m.heightAt(b[0], b[1]), 0.01);
        try testing.expect(m.passable(b[0], b[1]));
    }
    // At a corner (on an even row, and an odd), the corner's height.
    for ([_][2]usize{ .{ 10, 20 }, .{ 33, 41 } }) |cr| {
        const p = Map.at(cr[0], cr[1]);
        try testing.expectApproxEqAbs(m.corner(cr[0], cr[1]), m.heightAt(p[0], p[1]), 1e-4);
    }
    // A ray straight down onto a base meets it there.
    const hit = m.raycast(.{ bases[0][0], 30, bases[0][1] }, .{ 0, -1, 0 }).?;
    try testing.expectApproxEqAbs(@as(f32, 1.5), hit[1], 0.05);
}

test "the triangles: equilateral from above, facing up, six round each corner" {
    const m = try testing.allocator.create(Map);
    defer testing.allocator.destroy(m);
    m.generate(1);
    var verts: [Map.chunk_vertices]Vertex = undefined;
    const n = m.chunkMesh(1, 1, &verts);
    try testing.expect(n >= chunk * chunk * 6);
    var round: usize = 0;
    const centre = Map.at(24, 24);
    var i: usize = 0;
    while (i < n) : (i += 3) {
        const p: [3]V3 = .{ verts[i].pos, verts[i + 1].pos, verts[i + 2].pos };
        try testing.expect(math.cross(p[1] - p[0], p[2] - p[0])[1] > 0);
        // Water is over the ground's triangle: only the ground's counted.
        if (verts[i].pos[1] == water_level and verts[i + 1].pos[1] == water_level) continue;
        for (0..3) |k| {
            const a = p[k];
            const b = p[(k + 1) % 3];
            try testing.expectApproxEqAbs(@as(f32, 1), @sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[2] - b[2]) * (a[2] - b[2])), 1e-4);
        }
        for (p) |q| if (@abs(q[0] - centre[0]) < 1e-4 and @abs(q[2] - centre[1]) < 1e-4) {
            round += 1;
        };
    }
    try testing.expectEqual(@as(usize, 6), round);
}
