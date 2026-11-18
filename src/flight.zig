//! How winged things (bombers and fighters) fly: upright, hovering, on
//! their rotors; to go far, tilting forward (slowly), speeding up as they
//! do, flying fast and turning in wide, banked arcs; near where they are
//! going, slowing, tilting back, and hovering in. Going after something:
//! a bomber flies over it, dropping three bombs as it passes, goes on a
//! while, then turns back for another run; a fighter turns to line up
//! its gun (which fires the way it flies), and breaks away when close.

const std = @import("std");
const math = @import("math.zig");
const map_mod = @import("map.zig");
const units = @import("units.zig");
const combat = @import("combat.zig");

const V3 = math.V3;
const Thing = units.Thing;
const World = units.World;

/// How fast it tilts forward (slowly) and back, a second.
const tilt_forward: f32 = 0.45;
const tilt_back: f32 = 0.9;
/// How fast it goes hovering (upright, sliding).
const hover_speed: f32 = 2.2;
/// How long a bomber goes on after its run before turning back, and the
/// time between its bombs.
const overshoot_seconds: f32 = 2.6;
const bomb_gap: f32 = 0.18;
/// How long a fighter breaks away after passing close.
const break_seconds: f32 = 1.3;

fn turnRate(k: units.Kind) f32 {
    return if (k == .fighter) 1.9 else 1.05;
}

fn accel(k: units.Kind) f32 {
    return if (k == .fighter) 5 else 3;
}

fn heading(yaw: f32) V3 {
    return .{ @sin(yaw), 0, -@cos(yaw) };
}

fn flatDist(a: V3, b: [2]f32) f32 {
    const dx = a[0] - b[0];
    const dz = a[2] - b[1];
    return @sqrt(dx * dx + dz * dz);
}

/// On by `dt` seconds.
pub fn step(w: *World, t: *Thing, dt: f32) void {
    const k = t.kind;
    const top = k.speed();
    const dir = heading(t.yaw);
    var aim: ?[2]f32 = null;
    var fast = false;
    if (t.targets[0]) |j| {
        const o = w.things[j];
        fast = true;
        aim = if (k == .bomber) bombing(w, t, o, dt) else chasing(t, o, dt);
    } else if (t.goal) |g| {
        const d = flatDist(t.pos, g);
        // Far: flying; near (as near as it takes to slow down): hovering in.
        const stopping = t.moving * t.moving / (2 * accel(k)) + 3;
        fast = d > stopping and (d > 10 or t.tilt > 0.3);
        if (!fast and d < 0.2 and t.moving < 0.3) {
            t.goal = null;
        } else aim = g;
    }
    // Kept over the map: turning back to its middle near the edge.
    if (map_mod.inside(t.pos[0], t.pos[2]) < 6 and fast) aim = map_mod.centre;

    // Tilting forward (slowly) to fly; back to hover.
    if (fast) t.tilt = @min(1, t.tilt + tilt_forward * dt) else t.tilt = @max(0, t.tilt - tilt_back * dt);

    var turned: f32 = 0;
    var want: f32 = 0;
    if (aim) |a| {
        const to = std.math.atan2(a[0] - t.pos[0], -(a[1] - t.pos[2]));
        const diff = units.angleDiff(to, t.yaw);
        // Upright, it turns on the spot; flying, in an arc.
        const rate = if (t.tilt < 0.3) @as(f32, 2.2) else turnRate(k);
        turned = std.math.clamp(diff, -rate * dt, rate * dt);
        t.yaw = units.wrap(t.yaw + turned);
        if (fast) {
            want = hover_speed + (top - hover_speed) * t.tilt;
            // Sent with others: no faster than the slowest of them.
            if (t.cap > 0 and t.targets[0] == null) want = @min(want, @max(t.cap, hover_speed));
        } else {
            // Hovering in: slower as it gets there, and not until facing.
            const d = flatDist(t.pos, a);
            want = @min(hover_speed, d * 1.2) * @max(0, @cos(diff));
        }
    }
    const a_ = accel(k);
    t.moving += std.math.clamp(want - t.moving, -a_ * dt, a_ * dt);
    // Banked as it turns.
    const bank_want = std.math.clamp(turned / @max(dt, 1e-4) / turnRate(k), -1, 1) * t.tilt;
    t.bank += (bank_want - t.bank) * @min(1, 3 * dt);

    const next = t.pos + dir * math.splat(t.moving * dt);
    if (map_mod.inside(next[0], next[2]) > 0.5) {
        t.pos[0] = next[0];
        t.pos[2] = next[2];
    } else t.moving = 0;
    const ground = w.groundFor(k, t.pos[0], t.pos[2]);
    t.pos[1] += (ground - t.pos[1]) * @min(1, 1.5 * dt);
    t.phase += dt * 30;
}

/// A bomber's run over `o`: where to fly to (`o`, then on past it), and
/// its bombs dropped as it passes (where they would land near `o`).
fn bombing(w: *World, t: *Thing, o: Thing, dt: f32) [2]f32 {
    const dir = heading(t.yaw);
    t.run_time -= dt;
    if (t.bombs == 0) {
        // On past it a while, then round for another run.
        if (t.run_time <= 0) t.bombs = 3;
        const on = t.pos + dir * math.splat(20);
        return .{ on[0], on[2] };
    }
    // Where a bomb dropped now would land.
    const fall = combat.fallTime(t.pos[1] - w.map.surfaceAt(o.pos[0], o.pos[2]));
    const lands = t.pos + dir * math.splat(t.moving * fall);
    const near = flatDist(lands, .{ o.pos[0], o.pos[2] }) < 2.8;
    const started = t.bombs < 3;
    if (t.tilt > 0.75 and (near or started) and t.run_time <= 0) {
        combat.dropBomb(w, t.*, dir * math.splat(t.moving), fall);
        t.bombs -= 1;
        t.run_time = if (t.bombs == 0) overshoot_seconds else bomb_gap;
    }
    return .{ o.pos[0], o.pos[2] };
}

/// A fighter after `o`: flying at where it is going; close, breaking away
/// (on, straight) a while, to come round again.
fn chasing(t: *Thing, o: Thing, dt: f32) [2]f32 {
    const dir = heading(t.yaw);
    if (t.run_time > 0) {
        t.run_time -= dt;
        const on = t.pos + dir * math.splat(20);
        return .{ on[0], on[2] };
    }
    const d = flatDist(t.pos, .{ o.pos[0], o.pos[2] });
    if (d < 2.5) t.run_time = break_seconds;
    const vel = heading(o.yaw) * math.splat(o.moving);
    const lead = o.pos + vel * math.splat(d / 40);
    return .{ lead[0], lead[2] };
}

const testing = std.testing;

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

test "flying: hovering; tilting slowly to go far, fast; hovering in where it is sent" {
    const w = try testWorld();
    defer freeWorld(w);
    const c = map_mod.centre;
    const i = w.add(.{ .kind = .bomber, .team = 0, .pos = .{ c[0], 0, c[1] } }).?;
    w.step(1);
    try testing.expectEqual(@as(f32, 0), w.things[i].tilt);
    w.moveTo(&.{i}, c[0] + 80, c[1]);
    for (0..30) |_| w.step(1.0 / 30.0);
    // A second on: tilting, not yet fast.
    const t1 = w.things[i];
    try testing.expect(t1.tilt > 0.2 and t1.tilt < 0.6 and t1.moving < 6);
    var fastest: f32 = 0;
    var tf: f32 = 0;
    while (tf < 40 and w.things[i].goal != null) : (tf += 1.0 / 30.0) {
        w.step(1.0 / 30.0);
        fastest = @max(fastest, w.things[i].moving);
    }
    const t2 = w.things[i];
    try testing.expect(fastest > 7);
    try testing.expect(@abs(t2.pos[0] - (c[0] + 80)) < 1 and @abs(t2.pos[2] - c[1]) < 1);
    // Upright again (or nearly), hovering.
    for (0..60) |_| w.step(1.0 / 30.0);
    try testing.expect(w.things[i].tilt < 0.05 and w.things[i].moving < 0.1);
}

test "a bomber: runs over a tank, three bombs a run, round again until it is gone" {
    const w = try testWorld();
    defer freeWorld(w);
    const c = map_mod.centre;
    const i = w.add(.{ .kind = .bomber, .team = 0, .pos = .{ c[0] - 20, 0, c[1] } }).?;
    const tank = w.add(.{ .kind = .tank, .team = 1, .pos = .{ c[0] + 10, 0, c[1] } }).?;
    w.orderAttack(&.{i}, tank);
    var dropped: usize = 0;
    var runs: usize = 0;
    var was: u8 = 3;
    var t: f32 = 0;
    while (t < 60 and w.count == 2) : (t += 1.0 / 30.0) {
        const before = w.shot_count;
        w.step(1.0 / 30.0);
        if (w.shot_count > before) dropped += w.shot_count - before;
        if (w.count < 2) break;
        const b = w.things[i].bombs;
        if (was == 0 and b == 3) runs += 1;
        was = b;
    }
    // Bombs dropped, more than one run, and the tank destroyed.
    try testing.expect(dropped >= 3);
    try testing.expect(w.count == 1 or runs >= 1);
    try testing.expectEqual(@as(usize, 1), w.count);
    try testing.expectEqual(units.Kind.bomber, w.things[0].kind);
}

test "a fighter: fires only lined up; brings a bomber down" {
    const w = try testWorld();
    defer freeWorld(w);
    const c = map_mod.centre;
    const f = w.add(.{ .kind = .fighter, .team = 0, .pos = .{ c[0] - 6, 0, c[1] + 8 }, .yaw = 0 }).?;
    _ = w.add(.{ .kind = .bomber, .team = 1, .pos = .{ c[0] + 10, 0, c[1] } }).?;
    var fired: usize = 0;
    var t: f32 = 0;
    while (t < 60 and w.count == 2) : (t += 1.0 / 30.0) {
        const before = w.shot_count;
        w.step(1.0 / 30.0);
        if (w.count < 2) break;
        if (w.shot_count > before) {
            fired += 1;
            const s = w.shots[w.shot_count - 1];
            const fi = w.things[f];
            const way = std.math.atan2(s.to[0] - s.from[0], -(s.to[2] - s.from[2]));
            try testing.expect(@abs(units.angleDiff(way, fi.yaw)) < 0.3);
        }
    }
    try testing.expect(fired > 5);
    try testing.expectEqual(@as(usize, 1), w.count);
    try testing.expectEqual(units.Kind.fighter, w.things[0].kind);
}

test "an AA tank: at what flies, not at what is on the ground" {
    const w = try testWorld();
    defer freeWorld(w);
    const c = map_mod.centre;
    const aa = w.add(.{ .kind = .flak, .team = 0, .pos = .{ c[0], 0, c[1] } }).?;
    const walker = w.add(.{ .kind = .walker, .team = 1, .pos = .{ c[0] + 5, 0, c[1] } }).?;
    for (0..60) |_| w.step(1.0 / 30.0);
    try testing.expectEqual(combat.maxHealth(.walker), w.things[walker].health);
    _ = w.add(.{ .kind = .drone, .team = 1, .pos = .{ c[0] - 6, 0, c[1] } }).?;
    var t: f32 = 0;
    while (t < 10 and w.count == 3) : (t += 1.0 / 30.0) w.step(1.0 / 30.0);
    try testing.expectEqual(@as(usize, 2), w.count);
    try testing.expectEqual(units.Kind.flak, w.things[aa].kind);
}
