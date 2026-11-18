//! The armies: what each kind of unit and building is, and how they move,
//! build and are made. Everything is in one list (`World.things`), each a
//! `Thing` of a `Kind`, belonging to a player.

const std = @import("std");
const math = @import("math.zig");
const map_mod = @import("map.zig");
const nav = @import("nav.zig");

const V3 = math.V3;
const Map = map_mod.Map;

pub const Kind = enum(u8) {
    /// On two legs: quick and cheap.
    walker,
    /// On tracks: slow, tough; too big to go between trees.
    tank,
    /// Flying on four rotors: hovers, over water and hills alike.
    drone,
    /// On six wheels: builds buildings (see `Thing.order`); too wide to
    /// go between trees.
    builder,
    /// A large drone that builds buildings, flying to them over trees and
    /// water.
    air_builder,
    /// Guards the base: a gun on a column.
    tower,
    /// Makes units (see `Thing.queue`).
    factory,
    /// Makes energy.
    power,
    /// Digs metal.
    mine,

    pub fn isBuilding(k: Kind) bool {
        return @intFromEnum(k) >= @intFromEnum(Kind.tower);
    }

    pub fn flies(k: Kind) bool {
        return k == .drone or k == .air_builder;
    }

    /// Whether trees are in its way (those on tracks and wheels are too
    /// big to go between them; walkers and fliers are not).
    pub fn blockedByTrees(k: Kind) bool {
        return k == .tank or k == .builder;
    }

    /// How much bigger than its model is drawn (see models.zig).
    pub fn scale(k: Kind) f32 {
        return switch (k) {
            .tank, .builder => 1.4,
            .air_builder => 1.3,
            else => 1,
        };
    }

    /// How it finds its way (none: it flies straight).
    pub fn navClass(k: Kind) ?nav.Class {
        return switch (k) {
            .walker => .foot,
            .tank, .builder => .wheels,
            else => null,
        };
    }

    /// Whether it builds buildings.
    pub fn builds(k: Kind) bool {
        return k == .builder or k == .air_builder;
    }

    pub fn name(k: Kind) []const u8 {
        return switch (k) {
            .walker => "Walker",
            .tank => "Tank",
            .drone => "Drone",
            .builder => "Builder",
            .air_builder => "Air builder",
            .tower => "Tower",
            .factory => "Factory",
            .power => "Power plant",
            .mine => "Mine",
        };
    }

    /// Its name, short (for buttons).
    pub fn shortName(k: Kind) []const u8 {
        return switch (k) {
            .power => "Power",
            else => k.name(),
        };
    }

    /// Blocks a second, at its best.
    pub fn speed(k: Kind) f32 {
        return switch (k) {
            .walker => 3.2,
            .tank => 2.0,
            .drone => 4.5,
            .builder => 1.8,
            .air_builder => 3.0,
            else => 0,
        };
    }

    /// How far round it is (for picking it, and keeping apart).
    pub fn radius(k: Kind) f32 {
        return switch (k) {
            .walker => 0.45,
            .tank => 0.84,
            .drone => 0.5,
            .builder => 0.84,
            .air_builder => 0.85,
            .tower => 0.8,
            .factory => 2.2,
            .power => 1.4,
            .mine => 1.4,
        };
    }

    /// How tall it is (for picking it on the screen).
    pub fn height(k: Kind) f32 {
        return switch (k) {
            .walker => 1.1,
            .tank => 1.0,
            .drone => 0.5,
            .builder => 1.1,
            .air_builder => 0.8,
            .tower => 2.4,
            .factory => 2.2,
            .power => 2.0,
            .mine => 2.6,
        };
    }

    /// What making one costs, and how long it takes (seconds).
    pub fn cost(k: Kind) Cost {
        return switch (k) {
            .walker => .{ .metal = 40, .energy = 20, .seconds = 4 },
            .tank => .{ .metal = 90, .energy = 40, .seconds = 7 },
            .drone => .{ .metal = 60, .energy = 70, .seconds = 6 },
            .builder => .{ .metal = 110, .energy = 60, .seconds = 8 },
            .air_builder => .{ .metal = 150, .energy = 150, .seconds = 11 },
            .tower => .{ .metal = 120, .energy = 60, .seconds = 12 },
            .factory => .{ .metal = 320, .energy = 160, .seconds = 25 },
            .power => .{ .metal = 70, .energy = 20, .seconds = 8 },
            .mine => .{ .metal = 60, .energy = 50, .seconds = 10 },
        };
    }
};

pub const Cost = struct { metal: f32, energy: f32, seconds: f32 };

/// What a factory makes.
pub const buildable = [_]Kind{ .walker, .tank, .drone, .builder, .air_builder };
/// What a builder builds.
pub const constructible = [_]Kind{ .power, .mine, .tower, .factory };

/// A builder's order: to build a `kind` at `at`, facing `yaw`.
pub const Order = struct {
    kind: Kind,
    at: [2]f32,
    yaw: f32 = 0,
};

/// Players' colours (their units' and buildings' marks).
pub const team_colours = [4]u24{ 0x3b82f6, 0xe64535, 0x38c26a, 0xeab72c };

pub const max_things = 512;
/// Units a factory can have waiting to be made.
pub const max_queue = 20;

pub const Thing = struct {
    kind: Kind,
    team: u2,
    /// Its middle, on the ground (or, flying, its height over it).
    pos: V3,
    /// Which way it faces, right of north.
    yaw: f32 = 0,
    /// Where it is going, if anywhere: by way of `path`'s points from
    /// `path_next` on (round what is in the way).
    goal: ?[2]f32 = null,
    path: nav.Path = .{},
    path_next: u8 = 0,
    /// How many times it has looked for a way again (stuck), since sent.
    replans: u8 = 0,
    /// How fast it is going now (it speeds up and slows down).
    moving: f32 = 0,
    /// Its legs', rotors' or drill's turn, for drawing them.
    phase: f32 = 0,
    /// A tower's gun's way.
    aim: f32 = 0,
    /// A factory's: what it is to make, in turn, and how far through the
    /// first it is (0 to 1).
    queue: [max_queue]Kind = undefined,
    queued: u8 = 0,
    progress: f32 = 0,
    /// Where a factory's units go once made.
    rally: [2]f32 = .{ 0, 0 },
    /// A building's: how far built it is (0 to 1; until 1, it does
    /// nothing).
    built: f32 = 1,
    /// A builder's: what it is to build, and (once it has started) the
    /// building.
    order: ?Order = null,
    site: ?usize = null,

    /// Its first in line, if it has one.
    pub fn making(t: *const Thing) ?Kind {
        return if (t.queued > 0) t.queue[0] else null;
    }

    /// How many of `k` are waiting to be made.
    pub fn queuedOf(t: *const Thing, k: Kind) u32 {
        var n: u32 = 0;
        for (t.queue[0..t.queued]) |q| if (q == k) {
            n += 1;
        };
        return n;
    }
};

pub const Resources = struct {
    metal: f32 = 300,
    energy: f32 = 300,
};

/// What a building makes each second.
pub fn income(k: Kind) Resources {
    return switch (k) {
        .power => .{ .metal = 0, .energy = 6 },
        .mine => .{ .metal = 4, .energy = 0 },
        .factory => .{ .metal = 1, .energy = 1 },
        else => .{ .metal = 0, .energy = 0 },
    };
}

pub const World = struct {
    map: *const Map,
    things: [max_things]Thing = undefined,
    count: usize = 0,
    resources: [4]Resources = @splat(.{}),
    /// The game's time, in seconds.
    time: f32 = 0,

    pub fn add(w: *World, t: Thing) ?usize {
        if (w.count == max_things) return null;
        var with = t;
        with.pos[1] = w.groundFor(t.kind, t.pos[0], t.pos[2]);
        if (t.kind.isBuilding()) w.map.nav.building(t.pos[0], t.pos[2], t.kind.radius(), true);
        w.things[w.count] = with;
        w.count += 1;
        return w.count - 1;
    }

    pub fn all(w: *World) []Thing {
        return w.things[0..w.count];
    }

    /// Where `k` is (up and down) at (x, z): on the ground, or flying.
    pub fn groundFor(w: *const World, k: Kind, x: f32, z: f32) f32 {
        return if (k.flies()) w.map.surfaceAt(x, z) + 3 else w.map.heightAt(x, z);
    }

    /// Player `team`'s base: a factory, a power plant, a mine and a tower,
    /// and a few units to start with.
    pub fn addBase(w: *World, team: u2) void {
        const b = map_mod.bases[team];
        // Towards the middle of the map.
        const out = math.normalize(.{ map_mod.centre[0] - b[0], 0, map_mod.centre[1] - b[1] });
        const side = V3{ -out[2], 0, out[0] };
        const at = struct {
            fn f(base: [2]f32, o: V3, s: V3, fwd: f32, across: f32) V3 {
                return .{ base[0] + o[0] * fwd + s[0] * across, 0, base[1] + o[2] * fwd + s[2] * across };
            }
        }.f;
        const facing = std.math.atan2(out[0], -out[2]);
        if (w.add(.{ .kind = .factory, .team = team, .pos = at(b, out, side, 0, 0), .yaw = facing })) |i| {
            const r = at(b, out, side, 5, 0);
            w.things[i].rally = .{ r[0], r[2] };
        }
        _ = w.add(.{ .kind = .power, .team = team, .pos = at(b, out, side, -2, -5), .yaw = facing });
        _ = w.add(.{ .kind = .mine, .team = team, .pos = at(b, out, side, -2, 5), .yaw = facing });
        _ = w.add(.{ .kind = .tower, .team = team, .pos = at(b, out, side, 6, -4), .yaw = facing });
        _ = w.add(.{ .kind = .tower, .team = team, .pos = at(b, out, side, 6, 4), .yaw = facing });
        for ([_]Kind{ .walker, .walker, .tank, .drone }, 0..) |k, i| {
            _ = w.add(.{ .kind = k, .team = team, .pos = at(b, out, side, 4, @as(f32, @floatFromInt(i)) * 1.5 - 2.25), .yaw = facing });
        }
    }

    /// Asks factory `i` to make a `k`, if it has room in its line.
    pub fn enqueue(w: *World, i: usize, k: Kind) bool {
        const f = &w.things[i];
        if (f.kind != .factory or f.queued == max_queue) return false;
        f.queue[f.queued] = k;
        f.queued += 1;
        return true;
    }

    /// Takes the last of `k` out of factory `i`'s line.
    pub fn dequeue(w: *World, i: usize, k: Kind) void {
        const f = &w.things[i];
        var j: usize = f.queued;
        while (j > 0) {
            j -= 1;
            if (f.queue[j] != k) continue;
            std.mem.copyForwards(Kind, f.queue[j .. f.queued - 1], f.queue[j + 1 .. f.queued]);
            f.queued -= 1;
            if (j == 0) f.progress = 0;
            return;
        }
    }

    /// Sends the units `which` to (x, z): spread out round it, so they do
    /// not all try to stand in one place.
    pub fn moveTo(w: *World, which: []const usize, x: f32, z: f32) void {
        // Builders sent elsewhere stop building (what they had started
        // stays, to be gone on with).
        for (which) |i| {
            w.things[i].order = null;
            w.things[i].site = null;
        }
        var n: usize = 0;
        for (which) |i| {
            if (w.things[i].kind.isBuilding()) continue;
            n += 1;
        }
        if (n == 0) return;
        const across: usize = @intFromFloat(@ceil(@sqrt(@as(f32, @floatFromInt(n)))));
        // Far enough apart for the biggest of them.
        var widest: f32 = 0;
        for (which) |i| if (!w.things[i].kind.isBuilding()) {
            widest = @max(widest, w.things[i].kind.radius());
        };
        const gap: f32 = @max(1.4, 2 * widest + 0.3);
        // One way for each class (from the middle of those of it), shared.
        var ways: [2]?nav.Path = .{ null, null };
        for (std.enums.values(nav.Class)) |class| {
            var mid: [2]f32 = .{ 0, 0 };
            var m: f32 = 0;
            for (which) |i| if (w.things[i].kind.navClass() == class) {
                mid[0] += w.things[i].pos[0];
                mid[1] += w.things[i].pos[2];
                m += 1;
            };
            if (m == 0) continue;
            var p: nav.Path = .{};
            if (w.map.nav.find(class, .{ mid[0] / m, mid[1] / m }, .{ x, z }, &p)) ways[@intFromEnum(class)] = p;
        }
        var k: usize = 0;
        for (which) |i| {
            const t = &w.things[i];
            if (t.kind.isBuilding()) continue;
            const col: f32 = @floatFromInt(k % across);
            const row: f32 = @floatFromInt(k / across);
            const half = @as(f32, @floatFromInt(across - 1)) / 2;
            const slot = [2]f32{ x + (col - half) * gap, z + (row - half) * gap };
            k += 1;
            t.goal = slot;
            t.replans = 0;
            t.path = .{};
            t.path_next = 0;
            const class = t.kind.navClass() orelse continue;
            const way = ways[@intFromEnum(class)] orelse continue;
            // The shared way, from its point nearest this one (of the
            // first few), to its own place at the end.
            var start: usize = 0;
            var best: f32 = std.math.inf(f32);
            for (way.points[0..@min(way.len, 4)], 0..) |p, j| {
                const d = (p[0] - t.pos[0]) * (p[0] - t.pos[0]) + (p[1] - t.pos[2]) * (p[1] - t.pos[2]);
                if (d < best) {
                    best = d;
                    start = j;
                }
            }
            for (way.points[start .. way.len - 1]) |p| {
                t.path.points[t.path.len] = p;
                t.path.len += 1;
            }
        }
    }

    /// Sends unit `i` to `to`, finding its way.
    pub fn send(w: *World, i: usize, to: [2]f32) void {
        const t = &w.things[i];
        t.goal = to;
        t.replans = 0;
        w.route(t);
    }

    /// Finds `t`'s way to its goal (none, flying: it goes straight).
    fn route(w: *World, t: *Thing) void {
        t.path = .{};
        t.path_next = 0;
        const goal = t.goal orelse return;
        const class = t.kind.navClass() orelse return;
        var p: nav.Path = .{};
        if (!w.map.nav.find(class, .{ t.pos[0], t.pos[2] }, goal, &p)) return;
        // (Its last point is the goal.)
        if (p.len > 0) p.len -= 1;
        t.path = p;
    }

    /// On by `dt` seconds.
    pub fn step(w: *World, dt: f32) void {
        w.time += dt;
        for (w.all(), 0..) |*t, i| {
            if (t.built < 1) continue;
            switch (t.kind) {
                .walker, .tank, .drone => w.moveUnit(t, i, dt),
                .builder, .air_builder => {
                    w.construct(t, dt);
                    w.moveUnit(t, i, dt);
                },
                .tower => w.aimTower(t, dt),
                .factory => w.make(t, dt),
                .mine, .power => t.phase += dt * 2,
            }
            const inc = income(t.kind);
            w.resources[t.team].metal += inc.metal * dt;
            w.resources[t.team].energy += inc.energy * dt;
        }
    }

    fn moveUnit(w: *World, t: *Thing, i: usize, dt: f32) void {
        const k = t.kind;
        var want: f32 = 0;
        var heading = t.yaw;
        // On its way: to the next point of its way, on (not slowing) when
        // near it; then to its goal.
        while (t.path_next < t.path.len) {
            const p = t.path.points[t.path_next];
            const dx = p[0] - t.pos[0];
            const dz = p[1] - t.pos[2];
            if (dx * dx + dz * dz > 0.8 * 0.8) break;
            t.path_next += 1;
        }
        if (t.path_next < t.path.len and t.goal != null) {
            const p = t.path.points[t.path_next];
            heading = std.math.atan2(p[0] - t.pos[0], -(p[1] - t.pos[2]));
            want = k.speed();
        } else if (t.goal) |g| {
            const dx = g[0] - t.pos[0];
            const dz = g[1] - t.pos[2];
            const d = @sqrt(dx * dx + dz * dz);
            if (d < 0.15) {
                t.goal = null;
            } else {
                heading = std.math.atan2(dx, -dz);
                // Slowing as it gets there.
                want = k.speed() * @min(1, d / 1.2);
            }
        }
        // Turning towards where it is going: tanks turn on the spot, then
        // go; walkers and drones turn as they go.
        const diff = angleDiff(heading, t.yaw);
        const turn_rate: f32 = switch (k) {
            .tank, .builder => 2.2,
            .walker => 6,
            else => 5,
        };
        t.yaw = wrap(t.yaw + std.math.clamp(diff, -turn_rate * dt, turn_rate * dt));
        if ((k == .tank or k == .builder) and @abs(diff) > 0.6) want = 0;
        t.moving += (want - t.moving) * @min(1, 4 * dt);
        var nx = t.pos[0] + @sin(t.yaw) * t.moving * dt;
        var nz = t.pos[2] - @cos(t.yaw) * t.moving * dt;
        // Kept apart from the others (flying ones from flying ones, those
        // on the ground from those on the ground and from buildings).
        for (w.things[0..w.count], 0..) |o, j| {
            if (j == i or o.kind.flies() != k.flies()) continue;
            const dx = nx - o.pos[0];
            const dz = nz - o.pos[2];
            const want_d = k.radius() + o.kind.radius();
            const d2 = dx * dx + dz * dz;
            if (d2 >= want_d * want_d or d2 < 1e-6) continue;
            const d = @sqrt(d2);
            const push = (want_d - d) * (if (o.kind.isBuilding()) @as(f32, 1) else 0.5);
            nx += dx / d * push;
            nz += dz / d * push;
        }
        // Flying, anywhere over the map; on the ground, where it can go:
        // sliding along what is in the way, if it can; stopping if not.
        if (w.canBe(k, nx, nz)) {
            t.pos[0] = nx;
            t.pos[2] = nz;
        } else if (t.moving > 0.05 and w.canBe(k, nx, t.pos[2])) {
            t.pos[0] = nx;
        } else if (t.moving > 0.05 and w.canBe(k, t.pos[0], nz)) {
            t.pos[2] = nz;
        } else if (t.goal != null and t.replans < 3) {
            // Stuck (its way cut short, or a corner caught): a way from
            // here, looked for again.
            t.moving = 0;
            t.replans += 1;
            w.route(t);
        } else {
            t.moving = 0;
            t.goal = null;
        }
        // Up or down to the ground; flying, a little bob.
        const ground = w.groundFor(k, t.pos[0], t.pos[2]);
        t.pos[1] += (ground - t.pos[1]) * @min(1, (if (k.flies()) @as(f32, 3) else 20) * dt);
        t.phase += dt * switch (k) {
            .walker => t.moving * 3.2,
            .tank, .builder => t.moving * 2,
            else => 30,
        };
    }

    /// Whether a `k` can be at (x, z): flying, anywhere over the map; on
    /// the ground, out of the water, off cliffs (and, too big to go
    /// between trees, not among them).
    pub fn canBe(w: *const World, k: Kind, x: f32, z: f32) bool {
        if (k.flies()) return map_mod.inside(x, z) > 0.5;
        if (!w.map.passable(x, z)) return false;
        return !k.blockedByTrees() or !w.map.treeNear(x, z, k.radius());
    }

    /// Whether a `k` (a building) can be built at (x, z): on the map, on
    /// level enough dry ground, among no trees, and clear of other
    /// buildings.
    pub fn canPlace(w: *const World, k: Kind, x: f32, z: f32) bool {
        const r = k.radius();
        if (map_mod.inside(x, z) < r + 1) return false;
        const h = w.map.heightAt(x, z);
        for ([_][2]f32{ .{ 0, 0 }, .{ r, 0 }, .{ -r, 0 }, .{ 0, r }, .{ 0, -r } }) |d| {
            if (!w.map.passable(x + d[0], z + d[1])) return false;
            if (@abs(w.map.heightAt(x + d[0], z + d[1]) - h) > 0.6) return false;
        }
        if (w.map.treeNear(x, z, r)) return false;
        for (w.things[0..w.count]) |o| {
            if (!o.kind.isBuilding()) continue;
            const dx = o.pos[0] - x;
            const dz = o.pos[2] - z;
            const apart = o.kind.radius() + r + 0.4;
            if (dx * dx + dz * dz < apart * apart) return false;
        }
        // Nor where another builder means to build.
        for (w.things[0..w.count]) |o| {
            const ord = o.order orelse continue;
            if (o.site != null) continue;
            const dx = ord.at[0] - x;
            const dz = ord.at[1] - z;
            const apart = ord.kind.radius() + r + 0.4;
            if (dx * dx + dz * dz < apart * apart) return false;
        }
        return true;
    }

    /// Gives builder `i` an order (it goes there, and builds).
    pub fn orderBuild(w: *World, i: usize, o: Order) void {
        const t = &w.things[i];
        if (!t.kind.builds()) return;
        t.order = o;
        t.site = null;
        w.send(i, o.at);
    }

    /// Sends builder `i` to go on building `site` (one of its player's,
    /// not yet built).
    pub fn orderResume(w: *World, i: usize, site: usize) void {
        const t = &w.things[i];
        const b = w.things[site];
        if (!t.kind.builds() or b.built >= 1 or b.team != t.team) return;
        t.order = .{ .kind = b.kind, .at = .{ b.pos[0], b.pos[2] }, .yaw = b.yaw };
        t.site = site;
        w.send(i, t.order.?.at);
    }

    /// A builder's work: going to where it is to build; there, starting
    /// the building (where it was asked, if it still can be), then
    /// building it, paid for bit by bit as it goes.
    fn construct(w: *World, t: *Thing, dt: f32) void {
        const o = t.order orelse return;
        const dx = o.at[0] - t.pos[0];
        const dz = o.at[1] - t.pos[2];
        const reach = o.kind.radius() + t.kind.radius() + 1.0;
        const there = dx * dx + dz * dz <= reach * reach;
        if (!there) {
            // On its way (sent again, if it stopped).
            if (t.goal == null and t.replans < 3) {
                t.goal = o.at;
                t.replans += 1;
                w.route(t);
            }
            return;
        }
        t.goal = null;
        if (t.site) |s| {
            const b = &w.things[s];
            if (b.built >= 1) {
                t.order = null;
                t.site = null;
                return;
            }
            t.phase += dt * 4;
            const c = o.kind.cost();
            const part = dt / c.seconds;
            const r = &w.resources[t.team];
            if (r.metal < c.metal * part or r.energy < c.energy * part) return;
            r.metal -= c.metal * part;
            r.energy -= c.energy * part;
            b.built = @min(1, b.built + part);
            if (b.built >= 1) {
                t.order = null;
                t.site = null;
            }
            return;
        }
        // Started, if it still can be (or given up).
        t.order = null;
        if (!w.canPlace(o.kind, o.at[0], o.at[1])) return;
        t.order = o;
        const i = w.add(.{ .kind = o.kind, .team = t.team, .pos = .{ o.at[0], 0, o.at[1] }, .yaw = o.yaw, .built = 0 }) orelse {
            t.order = null;
            return;
        };
        const fwd = [2]f32{ @sin(o.yaw), -@cos(o.yaw) };
        const out = o.kind.radius() + 4;
        w.things[i].rally = .{ o.at[0] + fwd[0] * out, o.at[1] + fwd[1] * out };
        t.site = i;
        // Facing it.
        t.yaw = std.math.atan2(dx, -dz);
    }

    /// A tower's gun turns to the nearest unit of another player in reach,
    /// or slowly round, looking.
    fn aimTower(w: *World, t: *Thing, dt: f32) void {
        var best: ?V3 = null;
        var best_d: f32 = 14 * 14;
        for (w.things[0..w.count]) |o| {
            if (o.team == t.team or o.kind.isBuilding()) continue;
            const d = o.pos - t.pos;
            const d2 = d[0] * d[0] + d[2] * d[2];
            if (d2 < best_d) {
                best_d = d2;
                best = o.pos;
            }
        }
        const want = if (best) |p| std.math.atan2(p[0] - t.pos[0], -(p[2] - t.pos[2])) else t.aim + 0.4;
        const diff = angleDiff(want, t.aim);
        t.aim = wrap(t.aim + std.math.clamp(diff, -2 * dt, 2 * dt));
    }

    /// A factory makes its first in line, if its player can pay for it as
    /// it goes; done, it comes out of the door and goes to the rally point.
    fn make(w: *World, f: *Thing, dt: f32) void {
        f.phase += dt;
        const k = f.making() orelse return;
        const c = k.cost();
        const r = &w.resources[f.team];
        // Paid for bit by bit, as it is made.
        const part = dt / c.seconds;
        if (r.metal < c.metal * part or r.energy < c.energy * part) return;
        r.metal -= c.metal * part;
        r.energy -= c.energy * part;
        f.progress += part;
        if (f.progress < 1) return;
        f.progress = 0;
        std.mem.copyForwards(Kind, f.queue[0 .. f.queued - 1], f.queue[1..f.queued]);
        f.queued -= 1;
        const fwd = V3{ @sin(f.yaw), 0, -@cos(f.yaw) };
        const door = f.pos + fwd * math.splat(f.kind.radius() + 0.8);
        if (w.add(.{ .kind = k, .team = f.team, .pos = door, .yaw = f.yaw })) |i| {
            // (`f` may have moved: the list is not resized, so it has not.)
            w.send(i, f.rally);
        }
    }
};

pub fn wrap(a: f32) f32 {
    return std.math.atan2(@sin(a), @cos(a));
}

pub fn angleDiff(target: f32, current: f32) f32 {
    return wrap(target - current);
}

const testing = std.testing;

fn testWorld() !struct { map: *Map, world: *World } {
    const m = try Map.create(testing.allocator, 1);
    const w = try testing.allocator.create(World);
    w.* = .{ .map = m };
    return .{ .map = m, .world = w };
}

test "a base: its buildings, and units that go where they are sent" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    w.addBase(0);
    var units: [8]usize = undefined;
    var n: usize = 0;
    for (w.all(), 0..) |t, i| if (!t.kind.isBuilding()) {
        units[n] = i;
        n += 1;
    };
    try testing.expectEqual(@as(usize, 4), n);
    const b = map_mod.bases[0];
    w.moveTo(units[0..n], b[0] + 8, b[1] + 6);
    for (0..400) |_| w.step(0.05);
    for (units[0..n]) |i| {
        const t = w.things[i];
        try testing.expect(t.goal == null);
        const d = @sqrt((t.pos[0] - b[0] - 8) * (t.pos[0] - b[0] - 8) + (t.pos[2] - b[1] - 6) * (t.pos[2] - b[1] - 6));
        try testing.expect(d < 3);
        // On the ground, or flying over it.
        if (t.kind.flies()) try testing.expect(t.pos[1] > w.map.surfaceAt(t.pos[0], t.pos[2]) + 2) else try testing.expectApproxEqAbs(w.map.heightAt(t.pos[0], t.pos[2]), t.pos[1], 0.05);
    }
}

test "a factory makes what is queued, paying as it goes, and sends it out" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    w.addBase(0);
    const f = for (w.all(), 0..) |t, i| {
        if (t.kind == .factory) break i;
    } else unreachable;
    const before = w.count;
    try testing.expect(w.enqueue(f, .walker));
    try testing.expect(w.enqueue(f, .tank));
    try testing.expect(w.enqueue(f, .tank));
    try testing.expectEqual(@as(u32, 2), w.things[f].queuedOf(.tank));
    w.dequeue(f, .tank);
    try testing.expectEqual(@as(u32, 1), w.things[f].queuedOf(.tank));
    const metal = w.resources[0].metal;
    // The walker, then the tank (4 and 7 seconds).
    for (0..250) |_| w.step(0.05);
    try testing.expectEqual(before + 2, w.count);
    try testing.expectEqual(@as(u8, 0), w.things[f].queued);
    try testing.expectEqual(Kind.walker, w.things[before].kind);
    try testing.expectEqual(Kind.tank, w.things[before + 1].kind);
    // Paid for (less what the base made meanwhile).
    try testing.expect(w.resources[0].metal < metal + 12.5 * (4 + 1) - 100);
    // On their way to the rally point.
    try testing.expect(w.things[before].goal != null or @abs(w.things[before].pos[0] - w.things[f].rally[0]) < 2);
}

/// A tree on the map, on open enough ground to drive up to.
fn someTree(m: *const Map) map_mod.Tree {
    var r: usize = map_mod.margin_rows + 20;
    while (r < map_mod.rows - map_mod.margin_rows) : (r += 1) {
        for (map_mod.margin_cols + 20..map_mod.cols - map_mod.margin_cols) |c| {
            const t = m.treeAt(c, r) orelse continue;
            if (map_mod.inside(t.at[0], t.at[2]) > 20 and m.passable(t.at[0], t.at[2])) return t;
        }
    }
    unreachable;
}

test "trees: in the way of tanks and builders, not of walkers and fliers" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    const tree = someTree(w.map);
    for ([_]Kind{ .tank, .builder }) |k| try testing.expect(!w.canBe(k, tree.at[0], tree.at[2]));
    for ([_]Kind{ .walker, .drone, .air_builder }) |k| try testing.expect(w.canBe(k, tree.at[0], tree.at[2]));
    // Sent through it: those it is in the way of never get to it.
    for ([_]Kind{ .tank, .builder, .walker, .air_builder }) |k| {
        w.count = 0;
        const i = w.add(.{ .kind = k, .team = 0, .pos = .{ tree.at[0] - 6, 0, tree.at[2] } }).?;
        w.things[i].goal = .{ tree.at[0], tree.at[2] };
        var nearest: f32 = 100;
        for (0..60 * 10) |_| {
            w.step(1.0 / 60.0);
            const t = w.things[i];
            nearest = @min(nearest, @abs(t.pos[0] - tree.at[0]) + @abs(t.pos[2] - tree.at[2]));
        }
        if (k.blockedByTrees()) try testing.expect(nearest > 0.5) else try testing.expect(nearest < 0.3);
    }
}

test "builders: sent to build, they go there and build it, paying as they go; then it works" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    // (No base: nothing else earns metal.)
    const b = map_mod.bases[0];
    const at = [2]f32{ b[0] + 6, b[1] + 6 };
    for ([_]Kind{ .builder, .air_builder }, 0..) |k, n| {
        const site = [2]f32{ at[0] + @as(f32, @floatFromInt(n)) * 5, at[1] - @as(f32, @floatFromInt(n)) * 5 };
        try testing.expect(w.canPlace(.power, site[0], site[1]));
        const i = w.add(.{ .kind = k, .team = 0, .pos = .{ b[0] + 4, 0, b[1] - 4 } }).?;
        w.orderBuild(i, .{ .kind = .power, .at = site });
        // Where it is to go, nothing else is placed.
        try testing.expect(!w.canPlace(.power, site[0] + 0.5, site[1]));
        const before = w.resources[0];
        var site_i: ?usize = null;
        var t: f32 = 0;
        while (t < 40) : (t += 1.0 / 30.0) {
            w.step(1.0 / 30.0);
            if (w.things[i].site) |s| site_i = s;
            if (site_i != null and w.things[i].order == null) break;
        }
        const s = site_i.?;
        try testing.expectEqual(Kind.power, w.things[s].kind);
        try testing.expectEqual(@as(f32, 1), w.things[s].built);
        try testing.expect(w.things[i].order == null);
        // It cost what a power plant costs.
        try testing.expectApproxEqAbs(before.metal - Kind.power.cost().metal, w.resources[0].metal, 0.5);
    }
    // Not on a building, nor in the water, nor off the map.
    _ = w.add(.{ .kind = .factory, .team = 0, .pos = .{ b[0], 0, b[1] } }).?;
    try testing.expect(!w.canPlace(.tower, b[0] + 1, b[1]));
    try testing.expect(!w.canPlace(.tower, -10, -10));
}

test "a building half built: does nothing until it is finished" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    const b = map_mod.bases[0];
    _ = w.add(.{ .kind = .power, .team = 0, .pos = .{ b[0], 0, b[1] }, .built = 0.5 }).?;
    const before = w.resources[0].energy;
    w.step(1);
    try testing.expectEqual(before, w.resources[0].energy);
}

test "sent past a forest, a tank finds its way round it and gets there" {
    const tw = try testWorld();
    defer tw.map.destroy(testing.allocator);
    defer testing.allocator.destroy(tw.world);
    const w = tw.world;
    const n = w.map.nav;
    // A thick forest, with open ground either side.
    var from: [2]f32 = undefined;
    var to: [2]f32 = undefined;
    var found = false;
    var r: usize = map_mod.margin_rows + 60;
    search: while (r < map_mod.rows - map_mod.margin_rows - 60) : (r += 3) {
        for (map_mod.margin_cols + 60..map_mod.cols - map_mod.margin_cols - 60) |c| {
            const t = w.map.treeAt(c, r) orelse continue;
            if (map_mod.forestOf(1, t.at[0], t.at[2]) < 0.9) continue;
            from = .{ t.at[0] - 20, t.at[2] };
            to = .{ t.at[0] + 20, t.at[2] };
            if (!n.openAt(.wheels, from[0], from[1]) or !n.openAt(.wheels, to[0], to[1])) continue;
            found = true;
            break :search;
        }
    }
    try testing.expect(found);
    for ([_]Kind{ .tank, .walker }) |k| {
        w.count = 0;
        const i = w.add(.{ .kind = k, .team = 0, .pos = .{ from[0], 0, from[1] } }).?;
        w.moveTo(&.{i}, to[0], to[1]);
        var t: f32 = 0;
        while (t < 120 and w.things[i].goal != null) : (t += 1.0 / 30.0) w.step(1.0 / 30.0);
        const p = w.things[i].pos;
        try testing.expect(@abs(p[0] - to[0]) < 1 and @abs(p[2] - to[1]) < 1);
    }
}
