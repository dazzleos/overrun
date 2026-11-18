//! The battlefield: a grid of corners each at its own height, each square
//! between four of them two triangles, so the ground has hills, ridges and
//! valleys (with water in the lowest); and its triangles to draw, lit and
//! coloured by height and slope, in chunks (those out of view are not
//! drawn).

const std = @import("std");
const math = @import("math.zig");
const mesh = @import("mesh.zig");

const V3 = math.V3;
const Vertex = mesh.Vertex;

/// Squares across and down (the map is `size` blocks square).
pub const size = 96;
/// The water's height: ground below it is under water (units on the
/// ground cannot go there).
pub const water_level: f32 = 0.6;
/// Squares across a chunk (drawn, or not, together).
pub const chunk = 16;
pub const chunks = size / chunk;

/// Where each player's base is (the corners of the map, in from them).
pub const bases = [4][2]f32{ .{ 16, 16 }, .{ size - 16, size - 16 }, .{ size - 16, 16 }, .{ 16, size - 16 } };
/// How far round a base the ground is level.
const base_radius: f32 = 9;

pub const Map = struct {
    /// Each corner's height, (size + 1) by (size + 1).
    heights: [(size + 1) * (size + 1)]f32,

    pub fn generate(m: *Map, seed: u32) void {
        for (0..size + 1) |z| for (0..size + 1) |x| {
            const fx: f32 = @floatFromInt(x);
            const fz: f32 = @floatFromInt(z);
            var h = 3.2 * fbm(seed, fx / 22, fz / 22, 4) - 0.6;
            // Ridges here and there.
            const r = 1 - @abs(noise(seed +% 7, fx / 14, fz / 14) * 2 - 1);
            h += 2.2 * r * r * fbm(seed +% 11, fx / 30, fz / 30, 2);
            // Level ground round each base.
            for (bases) |b| {
                const d = @sqrt((fx - b[0]) * (fx - b[0]) + (fz - b[1]) * (fz - b[1]));
                const k = smoothstep(base_radius + 6, base_radius, d);
                h = h * (1 - k) + 1.5 * k;
            }
            m.heights[z * (size + 1) + x] = h;
        };
    }

    pub fn corner(m: *const Map, x: usize, z: usize) f32 {
        return m.heights[@as(usize, @min(z, size)) * (size + 1) + @as(usize, @min(x, size))];
    }

    /// The ground's height at (x, z), on its triangle.
    pub fn heightAt(m: *const Map, x: f32, z: f32) f32 {
        const cx = std.math.clamp(x, 0, size - 0.001);
        const cz = std.math.clamp(z, 0, size - 0.001);
        const ix: usize = @intFromFloat(@floor(cx));
        const iz: usize = @intFromFloat(@floor(cz));
        const fx = cx - @as(f32, @floatFromInt(ix));
        const fz = cz - @as(f32, @floatFromInt(iz));
        const h00 = m.corner(ix, iz);
        const h10 = m.corner(ix + 1, iz);
        const h01 = m.corner(ix, iz + 1);
        const h11 = m.corner(ix + 1, iz + 1);
        // Split from (0, 0) to (1, 1): the triangle below the diagonal, or
        // above it.
        return if (fx >= fz) h00 + (h10 - h00) * fx + (h11 - h10) * fz else h00 + (h01 - h00) * fz + (h11 - h01) * fx;
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

    /// The triangles of chunk (cx, cz), and its water, into `out`;
    /// returns how many vertices.
    pub fn chunkMesh(m: *const Map, cx: usize, cz: usize, out: []Vertex) usize {
        var b: mesh.Builder = .{ .out = out };
        for (cz * chunk..(cz + 1) * chunk) |z| for (cx * chunk..(cx + 1) * chunk) |x| {
            const p = [4]V3{
                m.point(x, z),
                m.point(x + 1, z),
                m.point(x + 1, z + 1),
                m.point(x, z + 1),
            };
            // The square's two triangles, from (0, 0) to (1, 1), each
            // facing up (counter-clockwise from above).
            for ([2][3]usize{ .{ 0, 2, 1 }, .{ 0, 3, 2 } }) |t| {
                const q = [3]V3{ p[t[0]], p[t[1]], p[t[2]] };
                const n = math.cross(q[1] - q[0], q[2] - q[0]);
                const lowest = @min(q[0][1], @min(q[1][1], q[2][1]));
                const mid = (q[0][1] + q[1][1] + q[2][1]) / 3;
                const steep = 1 - math.normalize(n)[1];
                b.triangle(q, groundColour(mid, steep, @intCast(x * 31 + z * 17)));
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

    fn point(m: *const Map, x: usize, z: usize) V3 {
        return .{ @floatFromInt(x), m.corner(x, z), @floatFromInt(z) };
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
    // At a corner, the corner's height.
    try testing.expectEqual(m.corner(10, 20), m.heightAt(10, 20));
    // A ray straight down onto a base meets it there.
    const hit = m.raycast(.{ bases[0][0], 30, bases[0][1] }, .{ 0, -1, 0 }).?;
    try testing.expectApproxEqAbs(@as(f32, 1.5), hit[1], 0.05);
    // A chunk's triangles face up.
    var verts: [chunk * chunk * 12]Vertex = undefined;
    const n = m.chunkMesh(0, 0, &verts);
    try testing.expect(n >= chunk * chunk * 6);
    var i: usize = 0;
    while (i < n) : (i += 3) {
        const p: [3]V3 = .{ verts[i].pos, verts[i + 1].pos, verts[i + 2].pos };
        try testing.expect(math.cross(p[1] - p[0], p[2] - p[0])[1] > 0);
    }
}
