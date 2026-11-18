//! The armies: what each kind of unit and building is, and how they move,
//! build and are made. Everything is in one list (`World.things`), each a
//! `Thing` of a `Kind`, belonging to a player.

const std = @import("std");
const math = @import("math.zig");
const map_mod = @import("map.zig");

const V3 = math.V3;
const Map = map_mod.Map;

pub const Kind = enum(u8) {
    /// On two legs: quick and cheap.
    walker,
    /// On tracks: slow, tough.
    tank,
    /// Flying on four rotors: hovers, over water and hills alike.
    drone,
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
        return k == .drone;
    }

    pub fn name(k: Kind) []const u8 {
        return switch (k) {
            .walker => "Walker",
            .tank => "Tank",
            .drone => "Drone",
            .tower => "Tower",
            .factory => "Factory",
            .power => "Power plant",
            .mine => "Mine",
        };
    }

    /// Blocks a second, at its best.
    pub fn speed(k: Kind) f32 {
        return switch (k) {
            .walker => 3.2,
            .tank => 2.0,
            .drone => 4.5,
            else => 0,
        };
    }

    /// How far round it is (for picking it, and keeping apart).
    pub fn radius(k: Kind) f32 {
        return switch (k) {
            .walker => 0.45,
            .tank => 0.6,
            .drone => 0.5,
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
            .tank => 0.7,
            .drone => 0.5,
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
            else => .{ .metal = 0, .energy = 0, .seconds = 0 },
        };
    }
};

pub const Cost = struct { metal: f32, energy: f32, seconds: f32 };

/// What a factory makes.
pub const buildable = [_]Kind{ .walker, .tank, .drone };

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
    /// Where it is going, if anywhere.
    goal: ?[2]f32 = null,
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
        var n: usize = 0;
        for (which) |i| {
            if (w.things[i].kind.isBuilding()) continue;
            n += 1;
        }
        if (n == 0) return;
        const across: usize = @intFromFloat(@ceil(@sqrt(@as(f32, @floatFromInt(n)))));
        const gap: f32 = 1.4;
        var k: usize = 0;
        for (which) |i| {
            const t = &w.things[i];
            if (t.kind.isBuilding()) continue;
            const col: f32 = @floatFromInt(k % across);
            const row: f32 = @floatFromInt(k / across);
            const half = @as(f32, @floatFromInt(across - 1)) / 2;
            t.goal = .{ x + (col - half) * gap, z + (row - half) * gap };
            k += 1;
        }
    }

    /// On by `dt` seconds.
    pub fn step(w: *World, dt: f32) void {
        w.time += dt;
        for (w.all(), 0..) |*t, i| {
            switch (t.kind) {
                .walker, .tank, .drone => w.moveUnit(t, i, dt),
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
        if (t.goal) |g| {
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
            .tank => 2.2,
            .walker => 6,
            else => 5,
        };
        t.yaw = wrap(t.yaw + std.math.clamp(diff, -turn_rate * dt, turn_rate * dt));
        if (k == .tank and @abs(diff) > 0.6) want = 0;
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
        // Flying, anywhere over the map; on the ground, where it can go.
        if (if (k.flies()) map_mod.inside(nx, nz) > 0.5 else w.map.passable(nx, nz)) {
            t.pos[0] = nx;
            t.pos[2] = nz;
        } else {
            // Blocked (water, a cliff): it stops.
            t.moving = 0;
            t.goal = null;
        }
        // Up or down to the ground; flying, a little bob.
        const ground = w.groundFor(k, t.pos[0], t.pos[2]);
        t.pos[1] += (ground - t.pos[1]) * @min(1, (if (k.flies()) @as(f32, 3) else 20) * dt);
        t.phase += dt * switch (k) {
            .walker => t.moving * 3.2,
            .tank => t.moving * 2,
            else => 30,
        };
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
            w.things[i].goal = f.rally;
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
