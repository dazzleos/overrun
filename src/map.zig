//! The battlefield: corners on a hexagonal lattice (rows of them a block
//! apart, each row half a block along from the one before, the rows
//! √3/2 apart), each at its own height, and between each three of them a
//! triangle (equilateral, seen from above: six round each corner, a
//! hexagon), so the ground has hills, ridges and valleys (with water in
//! the lowest) and no grid's diagonals. The map that can be played on is a
//! hexagon of them (its edges along the rows, and the lattice's other two
//! ways), nearly round; the ground goes on past it (to the edge of the
//! view, however it looks), dimmed, and nothing can go there. And its
//! triangles to draw, lit and
//! coloured by height and slope, in chunks (those out of view are not
//! drawn).

const std = @import("std");
const math = @import("math.zig");
const mesh = @import("mesh.zig");

const V3 = math.V3;
const Vertex = mesh.Vertex;

/// Blocks across the hexagon that can be played on, east to west.
pub const size = 512;
/// How far apart the rows of corners are.
pub const row_gap: f32 = 0.8660254;
/// Corners, and rows of them, past the hexagon's square each way: the
/// ground seen past its edge, in the view's corners (the view stops where
/// the map's edge reaches the screen's: see game.zig's `viewFits`), up to
/// 29 blocks past it at the most. Each a whole number of chunks
/// across, with the middle on an even row.
pub const margin_cols = 32;
pub const margin_rows = 32;
/// Rows from the middle to the top (or bottom) of the hexagon's square: a
/// little more than the hexagon reaches (`radius`·√3/2 blocks), a multiple
/// of 8 (so the rows are a whole number of chunks).
pub const hex_rows_half = size / 2 + 8;
/// Corners in a row, and rows: the hexagon's square (`size` across,
/// 2·`hex_rows_half` rows down), and the margins.
pub const cols = size + 2 * margin_cols + 1;
pub const rows = 2 * hex_rows_half + 2 * margin_rows + 1;
/// The water's height: ground below it is under water (units on the
/// ground cannot go there).
pub const water_level: f32 = 0.6;
/// Corners across and rows down a chunk (drawn, or not, together).
pub const chunk = 16;
pub const chunks_x = (cols - 1) / chunk;
pub const chunks_z = (rows - 1) / chunk;

/// The map's middle (a corner of the lattice, on an even row: its column
/// and row, and where it is), and how far its hexagon reaches from it to
/// its corners (east and west; its top and bottom edges are √3/2 of that
/// from it).
pub const centre_col = margin_cols + size / 2;
pub const centre_row = margin_rows + hex_rows_half;
pub const centre = [2]f32{ size / 2, hex_rows_half * row_gap };
pub const radius: f32 = size / 2;

/// Where each player's base is: towards four of the hexagon's corners,
/// each across the middle from the next (the first two face each other).
pub const bases = blk: {
    var out: [4][2]f32 = undefined;
    const angles = [4]f32{ 240, 60, 300, 120 };
    for (&out, angles) |*b, deg| {
        const a = deg * std.math.pi / 180.0;
        b.* = .{ centre[0] + @cos(a) * radius * 0.68, centre[1] + @sin(a) * radius * 0.68 };
    }
    break :blk out;
};

/// How far (x, z) is inside the map's hexagon, in blocks (below 0:
/// outside it).
pub fn inside(x: f32, z: f32) f32 {
    const dx = @abs(x - centre[0]);
    const dz = @abs(z - centre[1]);
    const half_height = radius * row_gap;
    // Its top and bottom edges, and its four slanted ones.
    return @min(half_height - dz, (radius - dx) * row_gap - dz / 2);
}

/// How much darker the ground past the hexagon is.
const outside_light: f32 = 0.42;
/// How far round a base the ground is level.
const base_radius: f32 = 9;

/// The lowest and highest the ground can be (see `heightOf`).
pub const lowest: f32 = -0.6;
pub const highest: f32 = 4.8;

/// The ground's height at (x, z), made from the map's seed: noise, ridges
/// here and there, and level round each base.
pub fn heightOf(seed: u32, x: f32, z: f32) f32 {
    // (Each term from 0 to 1: from `lowest` to `highest` in all.)
    var h = 3.2 * fbm(seed, x / 22, z / 22, 4) - 0.6;
    const rr = 1 - @abs(noise(seed +% 7, x / 14, z / 14) * 2 - 1);
    h += 2.2 * rr * rr * fbm(seed +% 11, x / 30, z / 30, 2);
    for (bases) |b| {
        const d = @sqrt((x - b[0]) * (x - b[0]) + (z - b[1]) * (z - b[1]));
        const k = smoothstep(base_radius + 6, base_radius, d);
        h = h * (1 - k) + 1.5 * k;
    }
    return h;
}

/// The ground's colour at a height, and how steep it is there (from 0,
/// level).
pub fn colourOf(h: f32, steep: f32, salt: u32) mesh.Rgb {
    return groundColour(h, steep, salt);
}

/// What a height is kept as: 1/1024ths of a block.
const height_scale: f32 = 1024;

pub const Map = struct {
    seed: u32,
    /// Each corner's height, row by row: made a chunk at a time, when it
    /// is first wanted (a corner of a chunk's, or a point on it), so a
    /// game starts at once, however large the map.
    heights: []i16,
    /// Which chunks' heights are made.
    made: []bool,

    pub fn create(gpa: std.mem.Allocator, seed: u32) !*Map {
        const m = try gpa.create(Map);
        errdefer gpa.destroy(m);
        const heights = try gpa.alloc(i16, rows * cols);
        errdefer gpa.free(heights);
        const made = try gpa.alloc(bool, chunks_x * chunks_z);
        @memset(made, false);
        m.* = .{ .seed = seed, .heights = heights, .made = made };
        return m;
    }

    pub fn destroy(m: *Map, gpa: std.mem.Allocator) void {
        gpa.free(m.heights);
        gpa.free(m.made);
        gpa.destroy(m);
    }

    /// Where corner (c, r) is, across and down (the hexagon's square from
    /// (0, 0)).
    pub fn at(c: usize, r: usize) [2]f32 {
        return .{
            @as(f32, @floatFromInt(c)) + (if (r % 2 == 1) @as(f32, 0.5) else 0) - margin_cols,
            (@as(f32, @floatFromInt(r)) - margin_rows) * row_gap,
        };
    }

    /// Makes chunk (cx, cz)'s heights: its corners, and (the last in a
    /// row or column) the map's last ones.
    fn makeHeights(m: *const Map, cx: usize, cz: usize) void {
        const r_end = if (cz == chunks_z - 1) rows else (cz + 1) * chunk;
        const c_end = if (cx == chunks_x - 1) cols else (cx + 1) * chunk;
        for (cz * chunk..r_end) |r| for (cx * chunk..c_end) |c| {
            const p = at(c, r);
            m.heights[r * cols + c] = @intFromFloat(@round(heightOf(m.seed, p[0], p[1]) * height_scale));
        };
        m.made[cz * chunks_x + cx] = true;
    }

    pub fn corner(m: *const Map, c_: usize, r_: usize) f32 {
        const c = @as(usize, @min(c_, cols - 1));
        const r = @as(usize, @min(r_, rows - 1));
        const cx = @as(usize, @min(c / chunk, chunks_x - 1));
        const cz = @as(usize, @min(r / chunk, chunks_z - 1));
        if (!m.made[cz * chunks_x + cx]) m.makeHeights(cx, cz);
        return @as(f32, @floatFromInt(m.heights[r * cols + c])) / height_scale;
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
        const r: usize = @intFromFloat(std.math.clamp(@floor(z / row_gap) + margin_rows, 0, rows - 2));
        // The columns the point may be between (each row is offset).
        const c0: usize = @intFromFloat(std.math.clamp(@floor(x - 0.5) + margin_cols, 0, cols - 2));
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
        if (inside(x, z) < 0.5) return false;
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
                if (inside(hi[0], hi[2]) < 0) return null;
                return hi;
            }
            last = p;
        }
        return null;
    }

    /// How low and how high chunk (cx, cz)'s corners are.
    pub fn chunkHeights(m: *const Map, cx: usize, cz: usize) [2]f32 {
        var lo: f32 = std.math.inf(f32);
        var hi: f32 = -std.math.inf(f32);
        for (cz * chunk..(cz + 1) * chunk + 1) |r| for (cx * chunk..(cx + 1) * chunk + 1) |c| {
            lo = @min(lo, m.corner(c, r));
            hi = @max(hi, m.corner(c, r));
        };
        return .{ lo, hi };
    }

    /// The most vertices a chunk is (its triangles, and water over each).
    pub const chunk_vertices = chunk * chunk * 2 * 3 * 2;

    /// Where chunk (cx, cz) is, across and down: from, and to.
    pub fn chunkBounds(cx: usize, cz: usize) [2][2]f32 {
        const lo = at(cx * chunk, cz * chunk);
        const hi = at((cx + 1) * chunk, (cz + 1) * chunk);
        return .{ lo, .{ hi[0] + 0.5, hi[1] } };
    }

    /// The triangles of chunk (cx, cz), and its water, into `out`;
    /// returns how many vertices.
    pub fn chunkMesh(m: *const Map, cx: usize, cz: usize, out: []Vertex) usize {
        var b: mesh.Builder = .{ .out = out };
        for (cz * chunk..(cz + 1) * chunk) |r| for (cx * chunk..(cx + 1) * chunk) |c| {
            for (trianglesAt(c, r)) |t| {
                var q = [3]V3{ m.point(t[0][0], t[0][1]), m.point(t[1][0], t[1][1]), m.point(t[2][0], t[2][1]) };
                // Those past the hexagon, dimmed.
                const past = @min(inside(q[0][0], q[0][2]), @min(inside(q[1][0], q[1][2]), inside(q[2][0], q[2][2]))) < -1e-3;
                const light: f32 = if (past) outside_light else 1;
                // Facing up (counter-clockwise from above).
                if (math.cross(q[1] - q[0], q[2] - q[0])[1] < 0) std.mem.swap(V3, &q[1], &q[2]);
                const n = math.cross(q[1] - q[0], q[2] - q[0]);
                const bottom = @min(q[0][1], @min(q[1][1], q[2][1]));
                const mid = (q[0][1] + q[1][1] + q[2][1]) / 3;
                const steep = 1 - math.normalize(n)[1];
                const ground = groundColour(mid, steep, @intCast(c * 31 + r * 17));
                b.shaded(q, dim(mesh.lit(ground, n), light));
                // Water over what is under it.
                if (bottom < water_level) {
                    const w = [3]V3{ .{ q[0][0], water_level, q[0][2] }, .{ q[1][0], water_level, q[1][2] }, .{ q[2][0], water_level, q[2][2] } };
                    b.shaded(w, dim(waterColour(mid), light));
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

/// The water's colour over ground `h` high: darker where it is deeper.
pub fn waterColour(h: f32) mesh.Rgb {
    const deep = std.math.clamp((water_level - h) / 1.5, 0, 1);
    return mixRgb(mesh.rgb(0x3f8fb0), mesh.rgb(0x1d4f7a), deep);
}

fn dim(c: mesh.Rgb, k: f32) mesh.Rgb {
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
    const m = try Map.create(testing.allocator, 1);
    defer m.destroy(testing.allocator);
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

test "the map is a hexagon: its corners on the lattice; past it, the ground dimmed, where nothing goes" {
    const m = try Map.create(testing.allocator, 1);
    defer m.destroy(testing.allocator);
    // Its six corners on corners of the lattice.
    try testing.expectApproxEqAbs(@as(f32, 0), inside(centre[0] - radius, centre[1]), 1e-3);
    try testing.expectApproxEqAbs(@as(f32, 0), inside(centre[0] + radius / 2, centre[1] - radius * row_gap), 1e-3);
    const top = Map.at(centre_col - size / 4, centre_row - size / 2);
    try testing.expectApproxEqAbs(@as(f32, 0), inside(top[0], top[1]), 1e-3);
    try testing.expectEqual(centre, Map.at(centre_col, centre_row));
    // The square's corners are outside; the bases well in.
    try testing.expect(inside(1, 1) < 0 and inside(size - 1, 1) < 0);
    for (bases) |b| try testing.expect(inside(b[0], b[1]) > 10);
    // The ground goes on far past it, darker; nothing goes there.
    var verts: [Map.chunk_vertices]Vertex = undefined;
    var farthest: f32 = 0;
    var brightest_out: f32 = 0;
    var brightest_in: f32 = 0;
    for (0..chunks_z) |cz| for (0..chunks_x) |cx| {
        const n = m.chunkMesh(cx, cz, &verts);
        for (verts[0..n]) |v| {
            const d = inside(v.pos[0], v.pos[2]);
            farthest = @min(farthest, d);
            const light = v.color[0] + v.color[1] + v.color[2];
            if (d < -2) brightest_out = @max(brightest_out, light) else if (d > 2) brightest_in = @max(brightest_in, light);
        }
    };
    try testing.expect(farthest < -24);
    // The chunks cover all of it.
    try testing.expectEqual(@as(usize, cols - 1), chunks_x * chunk);
    try testing.expectEqual(@as(usize, rows - 1), chunks_z * chunk);
    try testing.expect(brightest_out < brightest_in * 0.6);
    try testing.expect(!m.passable(centre[0] - radius - 1, centre[1]));
    try testing.expect(m.raycast(.{ centre[0] - radius - 10, 30, centre[1] }, .{ 0, -1, 0 }) == null);
}

test "the triangles: equilateral from above, facing up, six round each corner" {
    const m = try Map.create(testing.allocator, 1);
    defer m.destroy(testing.allocator);
    var verts: [Map.chunk_vertices]Vertex = undefined;
    const n = m.chunkMesh(1, 1, &verts);
    try testing.expect(n >= chunk * chunk * 6);
    var round: usize = 0;
    const at = Map.at(24, 24);
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
        for (p) |q| if (@abs(q[0] - at[0]) < 1e-4 and @abs(q[2] - at[1]) < 1e-4) {
            round += 1;
        };
    }
    try testing.expectEqual(@as(usize, 6), round);
}
