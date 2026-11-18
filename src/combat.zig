//! Fighting: each unit's and building's weapons, what they shoot at, and
//! what they do to it. Machine guns (walkers, drones, and tanks' second
//! gun; AA tanks' four, at what flies; fighters', the way they fly) hit
//! at once, each shot a tracer streaking from gun to target; big guns
//! (tanks', against vehicles and buildings; towers', two each) fire shells
//! that fly to where the target is going, and burst there. Bombers' bombs
//! (dropped as they fly over, see flight.zig) fall, and burst wide.

const std = @import("std");
const math = @import("math.zig");
const units = @import("units.zig");

const V3 = math.V3;
const Kind = units.Kind;
const Thing = units.Thing;
const World = units.World;

/// What a thing is to a weapon: small and quick, a vehicle, a building,
/// or an aircraft.
pub const Armour = enum { light, vehicle, building, air };

pub fn armourOf(k: Kind) Armour {
    return switch (k) {
        .walker, .drone => .light,
        .tank, .builder, .flak => .vehicle,
        .air_builder, .bomber, .fighter => .air,
        else => .building,
    };
}

/// How much a thing can take.
pub fn maxHealth(k: Kind) f32 {
    return switch (k) {
        .walker => 60,
        .drone => 45,
        .tank => 220,
        .builder => 140,
        .air_builder => 110,
        .bomber => 160,
        .fighter => 90,
        .flak => 180,
        .tower => 450,
        .factory => 1200,
        .power, .mine => 350,
    };
}

/// What a weapon is aimed at: anything; what is on the ground; only
/// vehicles and buildings (the big guns: not what is small, or flies); or
/// only what flies.
pub const Aims = enum { any, ground, heavy, air };

pub const Weapon = struct {
    /// How far it reaches, and how long between shots (seconds).
    range: f32,
    reload: f32,
    /// What a shot does to each kind of armour.
    damage: [4]f32,
    /// A bullet (hitting at once), a shell (flying, bursting), or a bomb
    /// (dropped by a bomber flying over: see flight.zig).
    shot: enum { bullet, shell, bomb },
    aims: Aims = .any,
    /// How far off it looks for what to aim at (as far as it reaches, if
    /// not set).
    seek: f32 = 0,
    /// Fires only the way it is going (a fighter's: it has to line up).
    forward: bool = false,

    pub fn canHit(wp: Weapon, k: Kind) bool {
        return switch (wp.aims) {
            .any => true,
            .ground => !k.flies(),
            .heavy => !k.flies() and armourOf(k) != .light,
            .air => k.flies(),
        };
    }

    fn seekRange(wp: Weapon) f32 {
        return if (wp.seek > 0) wp.seek else wp.range;
    }
};

/// Machine guns: good against walkers and drones, little against the rest.
const machine_gun: Weapon = .{ .range = 9, .reload = 0.2, .damage = .{ 7, 1.2, 0.8, 2.5 }, .shot = .bullet };
const drone_gun: Weapon = .{ .range = 8, .reload = 0.17, .damage = .{ 6, 1.0, 0.7, 2 }, .shot = .bullet };
/// A tank's big gun, and a tower's two.
const cannon: Weapon = .{ .range = 12, .reload = 2.5, .damage = .{ 20, 45, 45, 0 }, .shot = .shell, .aims = .heavy };
const tower_cannon: Weapon = .{ .range = 15, .reload = 0.9, .damage = .{ 20, 45, 45, 0 }, .shot = .shell, .aims = .ground };
/// An AA tank's four guns (in turn), at what flies.
const flak_guns: Weapon = .{ .range = 13, .reload = 0.08, .damage = .{ 6, 0, 0, 6 }, .shot = .bullet, .aims = .air };
/// A fighter's gun: firing the way it flies.
const fighter_gun: Weapon = .{ .range = 10, .reload = 0.1, .damage = .{ 6, 1, 0.5, 9 }, .shot = .bullet, .aims = .air, .seek = 24, .forward = true };
/// A bomber's bombs: good against everything on the ground.
pub const bombs: Weapon = .{ .range = 0, .reload = 0, .damage = .{ 70, 90, 90, 0 }, .shot = .bomb, .aims = .ground, .seek = 22 };

/// A thing's weapons: [0] its gun, [1] its big gun (towers': both
/// barrels, in turn).
pub fn weaponsOf(k: Kind) [2]?Weapon {
    return switch (k) {
        .walker => .{ machine_gun, null },
        .drone => .{ drone_gun, null },
        .tank => .{ machine_gun, cannon },
        .tower => .{ null, tower_cannon },
        .flak => .{ flak_guns, null },
        .fighter => .{ fighter_gun, null },
        .bomber => .{ bombs, null },
        else => .{ null, null },
    };
}

/// How fast a tracer and a shell go, how fast a bomb falls, and how far a
/// shell's (and a bomb's) burst reaches.
const tracer_speed: f32 = 70;
const shell_speed: f32 = 32;
const gravity: f32 = 9.8;
const burst_radius: f32 = 1.6;
const bomb_radius: f32 = 2.8;

/// Something in flight: a tracer (just to be seen) or a shell (bursting
/// where it lands).
pub const Shot = struct {
    from: V3,
    to: V3,
    /// How far along it is (0 to 1), and how much it goes on each second.
    at: f32 = 0,
    rate: f32,
    shell: bool,
    team: u2,
    damage: [4]f32 = .{ 0, 0, 0, 0 },
    /// A bomb's: how long it falls (it drops, faster and faster), and how
    /// far its burst reaches.
    fall: f32 = 0,
    radius: f32 = burst_radius,

    /// Where its head is now.
    pub fn head(s: Shot) V3 {
        var p = s.from + (s.to - s.from) * math.splat(s.at);
        if (s.fall > 0) {
            const t = s.at * s.fall;
            p[1] = s.from[1] - 0.5 * gravity * t * t;
        }
        return p;
    }
};

/// How long something dropped from `height` takes to fall.
pub fn fallTime(height: f32) f32 {
    return @sqrt(2 * @max(0.1, height) / gravity);
}

/// A bomb dropped by `t` (going at `vel`), falling for `fall` seconds.
pub fn dropBomb(w: *World, t: Thing, vel: V3, fall: f32) void {
    const from = t.pos - V3{ 0, 0.3, 0 };
    var to = from + vel * math.splat(fall);
    to[1] = from[1] - 0.5 * gravity * fall * fall;
    w.addShot(.{ .from = from, .to = to, .rate = 1 / fall, .shell = true, .team = t.team, .damage = bombs.damage, .fall = fall, .radius = bomb_radius });
}

/// A burst: a shell landing, or something destroyed; how big, and how
/// long ago (seconds).
pub const Blast = struct {
    at: V3,
    size: f32,
    age: f32 = 0,
};

pub const blast_seconds: f32 = 0.7;
pub const max_shots = 512;
pub const max_blasts = 96;

/// How often each looks again for what to shoot at.
const look_every: f32 = 0.25;

/// Where a thing's middle is (aimed at).
fn middle(t: Thing) V3 {
    return t.pos + V3{ 0, t.kind.height() * 0.5, 0 };
}

fn flat2(a: V3, b: V3) f32 {
    const dx = a[0] - b[0];
    const dz = a[2] - b[2];
    return dx * dx + dz * dz;
}

/// On by `dt` seconds: everything armed looks for what to shoot at, turns
/// to it and fires; shots fly and land; bursts fade.
pub fn step(w: *World, dt: f32) void {
    for (w.things[0..w.count], 0..) |*t, i| {
        if (t.built < 1) continue;
        const weapons = weaponsOf(t.kind);
        if (weapons[0] == null and weapons[1] == null) continue;
        t.look -= dt;
        if (t.look <= 0) {
            t.look = look_every + @as(f32, @floatFromInt(i % 7)) * 0.01;
            for (weapons, 0..) |maybe, slot| {
                const wp = maybe orelse continue;
                t.targets[slot] = choose(w, t.*, wp);
            }
        }
        aim(w, t, dt);
        for (weapons, 0..) |maybe, slot| {
            const wp = maybe orelse continue;
            t.cool[slot] = @max(0, t.cool[slot] - dt);
            const target = t.targets[slot] orelse continue;
            if (t.cool[slot] > 0) continue;
            if (wp.shot == .bomb) continue;
            const o = w.things[target];
            if (flat2(o.pos, t.pos) > wp.range * wp.range) continue;
            // Big guns (and AA guns) fire only when aimed; a fighter's
            // only when lined up.
            if (wp.shot == .shell and @abs(units.angleDiff(headingTo(t.*, o), t.aim)) > 0.12) continue;
            if (t.kind == .flak and @abs(units.angleDiff(headingTo(t.*, o), t.aim)) > 0.3) continue;
            if (wp.forward and @abs(units.angleDiff(headingTo(t.*, o), t.yaw)) > 0.14) continue;
            fire(w, t, slot, wp, target);
            t.cool[slot] = wp.reload;
        }
    }
    // Shots on their way.
    var k: usize = 0;
    while (k < w.shot_count) {
        const s = &w.shots[k];
        s.at += s.rate * dt;
        if (s.at < 1) {
            k += 1;
            continue;
        }
        if (s.shell) burst(w, s.*);
        w.shot_count -= 1;
        w.shots[k] = w.shots[w.shot_count];
    }
    k = 0;
    while (k < w.blast_count) {
        w.blasts[k].age += dt;
        if (w.blasts[k].age < blast_seconds) {
            k += 1;
            continue;
        }
        w.blast_count -= 1;
        w.blasts[k] = w.blasts[w.blast_count];
    }
}

/// What `t`'s weapon `wp` is to aim at: what it was told to attack (if
/// it can), or the nearest of another player's it can, in reach. (Winged
/// things sent somewhere look for nothing on the way.)
fn choose(w: *const World, t: Thing, wp: Weapon) ?u16 {
    if (t.attack) |j| if (wp.canHit(w.things[j].kind) and w.things[j].team != t.team) return j;
    if (t.kind.winged() and t.goal != null) return null;
    return nearest(w, t, wp);
}

/// The nearest of another player's that `wp` can hit, in reach.
fn nearest(w: *const World, t: Thing, wp: Weapon) ?u16 {
    var best: ?u16 = null;
    const r = wp.seekRange();
    var best_d = r * r;
    for (w.things[0..w.count], 0..) |o, j| {
        if (o.team == t.team or !wp.canHit(o.kind)) continue;
        const d = flat2(o.pos, t.pos);
        if (d < best_d) {
            best_d = d;
            best = @intCast(j);
        }
    }
    return best;
}

/// Which way (right of north) `o` is from `t`.
fn headingTo(t: Thing, o: Thing) f32 {
    return std.math.atan2(o.pos[0] - t.pos[0], -(o.pos[2] - t.pos[2]));
}

/// Turns what aims (a tank's turret, a tower's guns) to its target (the
/// big gun's first); with none, a tank's turret back to the front, and a
/// tower's guns kept still. A walker standing still turns to face its.
fn aim(w: *World, t: *Thing, dt: f32) void {
    const target = t.targets[1] orelse t.targets[0];
    switch (t.kind) {
        .tank, .tower, .flak => {
            const want = if (target) |j| headingTo(t.*, w.things[j]) else if (t.kind != .tower) t.yaw else return;
            const rate: f32 = if (t.kind == .tower) 2 else 2.5;
            const diff = units.angleDiff(want, t.aim);
            t.aim = units.wrap(t.aim + std.math.clamp(diff, -rate * dt, rate * dt));
        },
        .walker => if (target) |j| if (t.goal == null) {
            const diff = units.angleDiff(headingTo(t.*, w.things[j]), t.yaw);
            t.yaw = units.wrap(t.yaw + std.math.clamp(diff, -6 * dt, 6 * dt));
        },
        else => {},
    }
}

/// Where `t`'s weapon `slot` fires from.
fn muzzle(t: Thing, slot: usize) V3 {
    const s = t.kind.scale();
    const fwd = V3{ @sin(t.aim), 0, -@cos(t.aim) };
    const side = V3{ @cos(t.aim), 0, @sin(t.aim) };
    return switch (t.kind) {
        .tank => if (slot == 1)
            t.pos + V3{ 0, 0.52 * s, 0 } + fwd * math.splat(0.8 * s)
        else
            t.pos + V3{ 0, 0.62 * s, 0 } + fwd * math.splat(0.2 * s) + side * math.splat(0.15 * s),
        .tower => t.pos + V3{ 0, 1.85, 0 } + fwd * math.splat(0.9) + side * math.splat(if (t.barrel) @as(f32, 0.12) else -0.12),
        // Its four barrels, in turn.
        .flak => blk: {
            const k: f32 = @floatFromInt(t.gun % 4);
            const across = (if (@mod(k, 2) == 0) @as(f32, -0.1) else 0.1) * s;
            const up = (if (k < 2) @as(f32, 0.95) else 1.1) * s;
            break :blk t.pos + V3{ 0, up, 0 } + fwd * math.splat(0.45 * s) + side * math.splat(across);
        },
        .fighter => t.pos + V3{ @sin(t.yaw), 0, -@cos(t.yaw) } * math.splat(0.7),
        .walker => blk: {
            const f = V3{ @sin(t.yaw), 0, -@cos(t.yaw) };
            const r = V3{ @cos(t.yaw), 0, @sin(t.yaw) };
            break :blk t.pos + V3{ 0, 0.72, 0 } + r * math.splat(0.3) + f * math.splat(0.3);
        },
        else => t.pos,
    };
}

/// `t` fires its weapon `slot` at thing `j`.
fn fire(w: *World, t: *Thing, slot: usize, wp: Weapon, j: usize) void {
    const o = w.things[j];
    const from = muzzle(t.*, slot);
    if (t.kind == .tower) t.barrel = !t.barrel;
    t.gun +%= 1;
    if (wp.shot == .shell) {
        // At where it will be when the shell gets there.
        const there = middle(o);
        const time = math.length(there - from) / shell_speed;
        const vel = V3{ @sin(o.yaw) * o.moving, 0, -@cos(o.yaw) * o.moving };
        const to = there + vel * math.splat(time);
        w.addShot(.{ .from = from, .to = to, .rate = shell_speed / @max(0.1, math.length(to - from)), .shell = true, .team = t.team, .damage = wp.damage });
        return;
    }
    // A bullet: it hits (most of the time) at once; its tracer is just to
    // be seen.
    const salt = @as(u32, @intFromFloat(@abs(w.time) * 1000)) ^ @as(u32, @intFromFloat(@abs(t.pos[0]) * 7));
    const hits = hash(salt) < 0.85;
    var to = middle(o);
    if (hits) {
        w.things[j].health -= wp.damage[@intFromEnum(armourOf(o.kind))];
    } else {
        to += V3{ hash(salt +% 1) - 0.5, hash(salt +% 2) * 0.6, hash(salt +% 3) - 0.5 };
    }
    w.addShot(.{ .from = from, .to = to, .rate = tracer_speed / @max(0.1, math.length(to - from)), .shell = false, .team = t.team });
}

/// A shell (or bomb) bursting: what is near (of other players', on the
/// ground) is hurt, less further off.
fn burst(w: *World, s: Shot) void {
    w.addBlast(.{ .at = s.to, .size = if (s.fall > 0) @as(f32, 1.7) else 1 });
    for (w.things[0..w.count]) |*t| {
        if (t.team == s.team or t.kind.flies()) continue;
        const reach = s.radius + t.kind.radius();
        const d = @sqrt(flat2(t.pos, s.to));
        if (d > reach) continue;
        const k = 1 - 0.6 * d / reach;
        t.health -= s.damage[@intFromEnum(armourOf(t.kind))] * k;
    }
}

fn hash(v: u32) f32 {
    var h = v *% 0x9e3779b9;
    h ^= h >> 16;
    h *%= 0x7feb352d;
    h ^= h >> 15;
    return @as(f32, @floatFromInt(h & 0xffffff)) / 16777216.0;
}

const testing = std.testing;
const map_mod = @import("map.zig");

fn testWorld() !*World {
    const m = try map_mod.Map.create(testing.allocator, 1);
    const w = try testing.allocator.create(World);
    w.* = .{ .map = m };
    return w;
}

fn freeWorld(w: *World) void {
    @constCast(w.map).destroy(testing.allocator);
    testing.allocator.destroy(w);
}

/// Places a `k` of `team` near base 0 (level ground), `dx` along.
fn put(w: *World, k: Kind, team: u2, dx: f32) usize {
    const b = map_mod.bases[0];
    return w.add(.{ .kind = k, .team = team, .pos = .{ b[0] + dx, 0, b[1] } }).?;
}

fn run(w: *World, seconds: f32) void {
    var t: f32 = 0;
    while (t < seconds) : (t += 1.0 / 30.0) w.step(1.0 / 30.0);
}

test "walkers: shooting walkers down, hardly hurting a tank" {
    const w = try testWorld();
    defer freeWorld(w);
    _ = put(w, .walker, 0, 0);
    const theirs = put(w, .walker, 1, 6);
    run(w, 0.5);
    // Tracers flying, its health going.
    try testing.expect(w.shot_count > 0);
    try testing.expect(w.things[theirs].health < maxHealth(.walker));
    run(w, 6);
    // One of them is gone (they shoot each other: the first to fire wins).
    try testing.expect(w.count < 2);
    try testing.expect(w.blast_count > 0 or w.count < 2);

    const v = try testWorld();
    defer freeWorld(v);
    _ = put(v, .walker, 0, 0);
    const tank = put(v, .builder, 1, 6);
    run(v, 3);
    const left = v.things[tank].health / maxHealth(.builder);
    try testing.expect(left < 1 and left > 0.85);
}

test "tanks: the big gun at vehicles and buildings, not at walkers or drones" {
    const w = try testWorld();
    defer freeWorld(w);
    const mine = put(w, .tank, 0, 0);
    _ = put(w, .drone, 1, 5);
    _ = put(w, .walker, 1, -5);
    run(w, 1);
    try testing.expect(w.things[mine].targets[1] == null);
    try testing.expect(w.things[mine].targets[0] != null);
    for (w.shots[0..w.shot_count]) |s| try testing.expect(!s.shell);

    const v = try testWorld();
    defer freeWorld(v);
    const a = put(v, .tank, 0, 0);
    const b = put(v, .tank, 1, 9);
    var shells: usize = 0;
    var t: f32 = 0;
    while (t < 4) : (t += 1.0 / 30.0) {
        v.step(1.0 / 30.0);
        for (v.shots[0..v.shot_count]) |s| if (s.shell and s.at < 0.2) {
            shells += 1;
        };
    }
    try testing.expect(shells > 0);
    try testing.expect(v.things[b].targets[1] != null and v.things[a].targets[1] != null);
    // Shells burst, hurting.
    try testing.expect(v.things[b].health < maxHealth(.tank) - 30);
}

test "a tower: still until something comes; then its two guns, in turn" {
    const w = try testWorld();
    defer freeWorld(w);
    const tower = put(w, .tower, 0, 0);
    const was = w.things[tower].aim;
    run(w, 2);
    try testing.expectEqual(was, w.things[tower].aim);
    const theirs = put(w, .tank, 1, 10);
    var barrels: [2]bool = .{ false, false };
    var t: f32 = 0;
    while (t < 4) : (t += 1.0 / 30.0) {
        w.step(1.0 / 30.0);
        for (w.shots[0..w.shot_count]) |s| if (s.shell and s.at < 0.15) {
            // Which barrel: left or right of the tower's aim.
            const side = V3{ @cos(w.things[tower].aim), 0, @sin(w.things[tower].aim) };
            barrels[@intFromBool(math.dot(s.from - w.things[tower].pos, side) > 0)] = true;
        };
    }
    try testing.expect(barrels[0] and barrels[1]);
    try testing.expect(w.things[tower].aim != was);
    _ = theirs;
}

test "destroyed: taken out, the rest kept in order, a building's ground freed" {
    const w = try testWorld();
    defer freeWorld(w);
    const b = map_mod.bases[0];
    const a = put(w, .walker, 0, -8);
    const power = w.add(.{ .kind = .power, .team = 1, .pos = .{ b[0], 0, b[1] + 8 } }).?;
    const c = put(w, .walker, 0, 8);
    try testing.expect(!w.map.nav.openAt(.foot, b[0], b[1] + 8));
    w.things[power].health = 0;
    w.step(0.01);
    try testing.expect(w.removed_any);
    try testing.expectEqual(@as(usize, 2), w.count);
    try testing.expectEqual(@as(?u16, @intCast(a)), w.moved_to[a]);
    try testing.expectEqual(@as(?u16, null), w.moved_to[power]);
    try testing.expectEqual(@as(?u16, 1), w.moved_to[c]);
    try testing.expect(w.map.nav.openAt(.foot, b[0], b[1] + 8));
    try testing.expect(w.blast_count > 0);
}
