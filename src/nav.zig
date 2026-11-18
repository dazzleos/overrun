//! Finding a way across the map, round water, cliffs, buildings and (for
//! those too big to go between trees) forests: A* over a grid of cells a
//! block across, each cell's way known only once it is first asked about
//! (so the map's heights are not all made), then kept. The way found is
//! straightened (corner to corner, where nothing is in between) into a few
//! points to drive to in turn.

const std = @import("std");
const map_mod = @import("map.zig");

const Map = map_mod.Map;

/// Who can go where: on foot (walkers), or on tracks and wheels (tanks and
/// builders: too big to go between trees).
pub const Class = enum { foot, wheels };

/// The grid: a cell a block across, over the hexagon's square from (0, 0).
pub const width: usize = map_mod.size;
pub const height: usize = @intFromFloat(@ceil(@as(f32, map_mod.size) * map_mod.row_gap));
const cells = width * height;

/// How far from a tree's trunk tracks and wheels keep (the biggest of
/// their radii).
pub const wheels_radius: f32 = 0.85;
/// How far round a building (past its radius) is kept clear.
const building_clearance: f32 = 0.9;
/// The most cells a search looks at, before it settles for the nearest
/// it got.
const max_expanded = 150_000;

/// A way: the points to go to, in turn.
pub const max_points = 32;
pub const Path = struct {
    points: [max_points][2]f32 = undefined,
    len: u8 = 0,
};

const Node = struct { f: f32, i: u32 };

pub const Nav = struct {
    map: *const Map,
    /// Each cell's way: bit 0, known; bit 1, open on foot; bit 2, on
    /// wheels.
    ground: []u8,
    /// How many buildings are over each cell.
    buildings: []u8,
    // A search's: each cell's cost so far, where it came from, and which
    // search last reached it (and closed it); the cells to look at; and
    // the way back.
    cost: []f32,
    came: []u32,
    reached: []u16,
    closed: []u16,
    search: u16 = 0,
    open: []Node,
    open_len: usize = 0,
    trail: []u32,

    pub fn create(gpa: std.mem.Allocator, map: *const Map) !*Nav {
        const n = try gpa.create(Nav);
        errdefer gpa.destroy(n);
        n.* = .{
            .map = map,
            .ground = try gpa.alloc(u8, cells),
            .buildings = try gpa.alloc(u8, cells),
            .cost = try gpa.alloc(f32, cells),
            .came = try gpa.alloc(u32, cells),
            .reached = try gpa.alloc(u16, cells),
            .closed = try gpa.alloc(u16, cells),
            .open = try gpa.alloc(Node, cells),
            .trail = try gpa.alloc(u32, cells),
        };
        @memset(n.ground, 0);
        @memset(n.buildings, 0);
        @memset(n.reached, 0);
        @memset(n.closed, 0);
        return n;
    }

    pub fn destroy(n: *Nav, gpa: std.mem.Allocator) void {
        gpa.free(n.ground);
        gpa.free(n.buildings);
        gpa.free(n.cost);
        gpa.free(n.came);
        gpa.free(n.reached);
        gpa.free(n.closed);
        gpa.free(n.open);
        gpa.free(n.trail);
        gpa.destroy(n);
    }

    /// No buildings (a new game).
    pub fn clearBuildings(n: *Nav) void {
        @memset(n.buildings, 0);
    }

    /// A building `r` round at (x, z), put up (or taken down).
    pub fn building(n: *Nav, x: f32, z: f32, r: f32, up: bool) void {
        const reach = r + building_clearance;
        const x0 = cellIndex(x - reach, width);
        const x1 = cellIndex(x + reach, width);
        const z0 = cellIndex(z - reach, height);
        const z1 = cellIndex(z + reach, height);
        for (z0..z1 + 1) |cz| for (x0..x1 + 1) |cx| {
            const dx = @as(f32, @floatFromInt(cx)) + 0.5 - x;
            const dz = @as(f32, @floatFromInt(cz)) + 0.5 - z;
            if (dx * dx + dz * dz > reach * reach) continue;
            const b = &n.buildings[cz * width + cx];
            b.* = if (up) b.* +| 1 else b.* -| 1;
        };
    }

    /// Whether cell `i` is open to `class`.
    fn cellOpen(n: *Nav, class: Class, i: usize) bool {
        if (n.buildings[i] > 0) return false;
        var g = n.ground[i];
        if (g & 1 == 0) {
            const x = @as(f32, @floatFromInt(i % width)) + 0.5;
            const z = @as(f32, @floatFromInt(i / width)) + 0.5;
            const foot = n.map.passable(x, z);
            const wheels = foot and !n.map.treeNear(x, z, wheels_radius);
            g = 1 | (@as(u8, @intFromBool(foot)) << 1) | (@as(u8, @intFromBool(wheels)) << 2);
            n.ground[i] = g;
        }
        return g & (@as(u8, 2) << @intFromEnum(class)) != 0;
    }

    /// Whether (x, z) is open to `class`.
    pub fn openAt(n: *Nav, class: Class, x: f32, z: f32) bool {
        const i = cellOf(.{ x, z }) orelse return false;
        return n.cellOpen(class, i);
    }

    /// Whether nothing is in the way from `a` to `b`, for `class`.
    fn clear(n: *Nav, class: Class, a: [2]f32, b: [2]f32) bool {
        const dx = b[0] - a[0];
        const dz = b[1] - a[1];
        const len = @sqrt(dx * dx + dz * dz);
        const steps: usize = @intFromFloat(@ceil(len / 0.4));
        for (1..steps + 1) |s| {
            const t = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(steps));
            if (!n.openAt(class, a[0] + dx * t, a[1] + dz * t)) return false;
        }
        return true;
    }

    /// The open cell nearest `i` (within `within` cells), if any.
    fn nearestOpen(n: *Nav, class: Class, i: usize, within: usize) ?usize {
        const cx = i % width;
        const cz = i / width;
        var ring: usize = 1;
        while (ring <= within) : (ring += 1) {
            var best: ?usize = null;
            var best_d: usize = std.math.maxInt(usize);
            const x0 = cx -| ring;
            const z0 = cz -| ring;
            for (z0..@min(cz + ring, height - 1) + 1) |z| for (x0..@min(cx + ring, width - 1) + 1) |x| {
                const j = z * width + x;
                if (!n.cellOpen(class, j)) continue;
                const d = (x -| cx) + (cx -| x) + (z -| cz) + (cz -| z);
                if (d < best_d) {
                    best_d = d;
                    best = j;
                }
            };
            if (best != null) return best;
        }
        return null;
    }

    /// A way for `class` from `from` to `to` (or, if it cannot get there,
    /// as near as it can) into `out`; false if there is none at all.
    pub fn find(n: *Nav, class: Class, from: [2]f32, to: [2]f32, out: *Path) bool {
        out.len = 0;
        const start = cellOf(from) orelse return false;
        var goal = cellOf(to) orelse return false;
        const reaches = n.cellOpen(class, goal);
        if (!reaches) goal = n.nearestOpen(class, goal, 16) orelse return false;
        n.search +%= 1;
        if (n.search == 0) {
            @memset(n.reached, 0);
            @memset(n.closed, 0);
            n.search = 1;
        }
        const gx = goal % width;
        const gz = goal / width;
        n.open_len = 0;
        n.cost[start] = 0;
        n.came[start] = @intCast(start);
        n.reached[start] = n.search;
        n.push(.{ .f = guess(start, gx, gz), .i = @intCast(start) });
        var best = start;
        var best_h = guess(start, gx, gz);
        var expanded: usize = 0;
        while (n.open_len > 0) {
            const node = n.pop();
            const i: usize = node.i;
            if (n.closed[i] == n.search) continue;
            n.closed[i] = n.search;
            if (i == goal) {
                best = goal;
                break;
            }
            const h = guess(i, gx, gz);
            if (h < best_h) {
                best_h = h;
                best = i;
            }
            expanded += 1;
            if (expanded > max_expanded) break;
            const cx: isize = @intCast(i % width);
            const cz: isize = @intCast(i / width);
            for ([_][2]isize{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 }, .{ 1, 1 }, .{ 1, -1 }, .{ -1, 1 }, .{ -1, -1 } }) |d| {
                const nx = cx + d[0];
                const nz = cz + d[1];
                if (nx < 0 or nz < 0 or nx >= width or nz >= height) continue;
                const j: usize = @intCast(nz * @as(isize, width) + nx);
                if (n.closed[j] == n.search or !n.cellOpen(class, j)) continue;
                const diagonal = d[0] != 0 and d[1] != 0;
                // Not cutting a corner.
                if (diagonal and (!n.cellOpen(class, @intCast(cz * @as(isize, width) + nx)) or !n.cellOpen(class, @intCast(nz * @as(isize, width) + cx)))) continue;
                const c = n.cost[i] + @as(f32, if (diagonal) std.math.sqrt2 else 1);
                if (n.reached[j] == n.search and c >= n.cost[j]) continue;
                n.cost[j] = c;
                n.came[j] = @intCast(i);
                n.reached[j] = n.search;
                n.push(.{ .f = c + guess(j, gx, gz), .i = @intCast(j) });
            }
        }
        // The way back, then forwards.
        var len: usize = 0;
        var at = best;
        while (true) {
            n.trail[len] = @intCast(at);
            len += 1;
            if (at == start) break;
            at = n.came[at];
        }
        std.mem.reverse(u32, n.trail[0..len]);
        // Straightened: from each point, on to the furthest cell in a
        // straight line from it.
        const end: [2]f32 = if (best == goal and reaches) to else centreOf(best);
        var from_here = from;
        var k: usize = 0;
        while (out.len < max_points) {
            if (n.clear(class, from_here, end)) {
                out.points[out.len] = end;
                out.len += 1;
                break;
            }
            var j = k + 1;
            while (j + 1 < len and n.clear(class, from_here, centreOf(n.trail[j + 1]))) j += 1;
            if (j >= len) j = len - 1;
            const p = centreOf(n.trail[j]);
            out.points[out.len] = p;
            out.len += 1;
            if (j == len - 1) break;
            from_here = p;
            k = j;
        }
        return true;
    }

    fn push(n: *Nav, node: Node) void {
        if (n.open_len == n.open.len) return;
        var i = n.open_len;
        n.open_len += 1;
        while (i > 0) {
            const parent = (i - 1) / 2;
            if (n.open[parent].f <= node.f) break;
            n.open[i] = n.open[parent];
            i = parent;
        }
        n.open[i] = node;
    }

    fn pop(n: *Nav) Node {
        const top = n.open[0];
        n.open_len -= 1;
        const last = n.open[n.open_len];
        var i: usize = 0;
        while (true) {
            var child = 2 * i + 1;
            if (child >= n.open_len) break;
            if (child + 1 < n.open_len and n.open[child + 1].f < n.open[child].f) child += 1;
            if (n.open[child].f >= last.f) break;
            n.open[i] = n.open[child];
            i = child;
        }
        n.open[i] = last;
        return top;
    }
};

/// How far (at least) cell `i` is from (gx, gz), going straight and
/// diagonally.
fn guess(i: usize, gx: usize, gz: usize) f32 {
    const dx: f32 = @floatFromInt(@max(i % width, gx) - @min(i % width, gx));
    const dz: f32 = @floatFromInt(@max(i / width, gz) - @min(i / width, gz));
    return @max(dx, dz) + (std.math.sqrt2 - 1) * @min(dx, dz);
}

fn cellIndex(v: f32, n: usize) usize {
    return @intFromFloat(std.math.clamp(@floor(v), 0, @as(f32, @floatFromInt(n - 1))));
}

fn cellOf(p: [2]f32) ?usize {
    if (p[0] < 0 or p[1] < 0 or p[0] >= width or p[1] >= height) return null;
    return @as(usize, @intFromFloat(p[1])) * width + @as(usize, @intFromFloat(p[0]));
}

fn centreOf(i: usize) [2]f32 {
    return .{ @as(f32, @floatFromInt(i % width)) + 0.5, @as(f32, @floatFromInt(i / width)) + 0.5 };
}

const testing = std.testing;

test "a way round a forest: on wheels round it, on foot through it" {
    const m = try Map.create(testing.allocator, 1);
    defer m.destroy(testing.allocator);
    const n = m.nav;
    // A tree well inside, and points either side of it (open to wheels).
    var tree: ?map_mod.Tree = null;
    var r: usize = map_mod.margin_rows + 60;
    search: while (r < map_mod.rows - map_mod.margin_rows - 60) : (r += 3) {
        for (map_mod.margin_cols + 60..map_mod.cols - map_mod.margin_cols - 60) |c| {
            const t = m.treeAt(c, r) orelse continue;
            if (map_mod.forestOf(1, t.at[0], t.at[2]) < 0.9) continue;
            if (!n.openAt(.wheels, t.at[0] - 25, t.at[2]) or !n.openAt(.wheels, t.at[0] + 25, t.at[2])) continue;
            tree = t;
            break :search;
        }
    }
    const t = tree.?;
    const a = [2]f32{ t.at[0] - 25, t.at[2] };
    const b = [2]f32{ t.at[0] + 25, t.at[2] };
    var path: Path = .{};
    try testing.expect(n.find(.wheels, a, b, &path));
    try testing.expect(path.len >= 2);
    // It gets there; nothing in the way between its points.
    try testing.expectEqual(b, path.points[path.len - 1]);
    var from = a;
    for (path.points[0..path.len]) |p| {
        try testing.expect(n.clear(.wheels, from, p));
        from = p;
    }
    // On foot: straight through.
    var on_foot: Path = .{};
    try testing.expect(n.find(.foot, a, b, &on_foot));
    try testing.expect(on_foot.len <= path.len);
    // A building in the way: round it.
    const mid = [2]f32{ (a[0] + b[0]) / 2, a[1] };
    n.building(mid[0], mid[1], 2.2, true);
    try testing.expect(!n.openAt(.foot, mid[0], mid[1]));
    n.building(mid[0], mid[1], 2.2, false);
    try testing.expect(n.openAt(.foot, mid[0], mid[1]) or !m.passable(mid[0], mid[1]));
}
