//! How each kind of unit and building looks: boxes and prisms, in its
//! player's colour where it is marked, its moving parts (legs, rotors,
//! drills, guns) placed as they are now. Made anew each frame, all into
//! one buffer (one draw for them all).

const std = @import("std");
const math = @import("math.zig");
const mesh = @import("mesh.zig");
const units = @import("units.zig");

const V3 = math.V3;
const Frame = mesh.Frame;
const Builder = mesh.Builder;
const Thing = units.Thing;
const rgb = mesh.rgb;

const metal = rgb(0x9aa3ad);
const dark = rgb(0x4a5058);
const black = rgb(0x24272b);
const glass = rgb(0x8fd8ff);
const glow = rgb(0xffd25a);

/// The most triangles a thing is (for room in the buffer).
pub const max_triangles = 180;

/// Adds `t`'s triangles to `b`.
pub fn thing(b: *Builder, t: *const Thing) void {
    const team = rgb(units.team_colours[t.team]);
    const f = Frame.of(t.yaw, 0, 0).scaled(t.kind.scale());
    const p = t.pos;
    switch (t.kind) {
        .walker => walker(b, f, p, t, team),
        .tank => tank(b, f, p, t, team),
        .drone => drone(b, f, p, t, team),
        .builder => builder(b, f, p, t, team),
        .air_builder => airBuilder(b, f, p, t, team),
        .bomber => aircraft(b, f, p, t, team, .bomber),
        .fighter => aircraft(b, f, p, t, team, .fighter),
        .flak => flak(b, f, p, t, team),
        .tower => tower(b, f, p, t, team),
        .factory => factory(b, f, p, t, team),
        .power => power(b, f, p, t, team),
        .mine => mine(b, f, p, t, team),
    }
}

fn walker(b: *Builder, f: Frame, p: V3, t: *const Thing, team: mesh.Rgb) void {
    // Legs, swinging as it walks, and its body bobbing with them.
    const swing = @sin(t.phase) * @min(1, t.moving) * 0.6;
    const bob = @abs(@sin(t.phase)) * 0.05 * @min(1, t.moving);
    for ([2]f32{ -1, 1 }) |side| {
        const leg = f.tipped(swing * side);
        const hip = f.at(p, .{ side * 0.16, 0.55, 0 });
        b.box(leg, leg.at(hip, .{ 0, -0.27, 0 }), .{ 0.08, 0.27, 0.1 }, .{ 1, 1 }, dark);
        b.box(leg, leg.at(hip, .{ 0, -0.52, -0.05 }), .{ 0.1, 0.03, 0.16 }, .{ 1, 1 }, black);
    }
    const body = f.at(p, .{ 0, 0.72 + bob, 0 });
    b.box(f, body, .{ 0.24, 0.18, 0.16 }, .{ 0.85, 0.85 }, metal);
    b.box(f, f.at(body, .{ 0, 0.06, 0.17 }), .{ 0.16, 0.1, 0.03 }, .{ 1, 1 }, team);
    // Its head, eye forward, and a gun on its arm.
    b.box(f, f.at(body, .{ 0, 0.27, -0.02 }), .{ 0.12, 0.09, 0.11 }, .{ 0.9, 0.9 }, team);
    b.box(f, f.at(body, .{ 0, 0.28, -0.13 }), .{ 0.08, 0.025, 0.02 }, .{ 1, 1 }, glass);
    b.box(f, f.at(body, .{ 0.3, 0, -0.12 }), .{ 0.05, 0.05, 0.22 }, .{ 1, 1 }, dark);
}

fn tank(b: *Builder, f: Frame, p: V3, t: *const Thing, team: mesh.Rgb) void {
    for ([2]f32{ -1, 1 }) |side| b.box(f, f.at(p, .{ side * 0.42, 0.16, 0 }), .{ 0.14, 0.16, 0.55 }, .{ 1, 0.9 }, black);
    b.box(f, f.at(p, .{ 0, 0.3, 0 }), .{ 0.32, 0.12, 0.5 }, .{ 0.85, 0.85 }, metal);
    // The turret, turned to aim: its big gun, and a machine gun on top.
    const turret = Frame.of(t.aim, 0, 0).scaled(t.kind.scale());
    const top = f.at(p, .{ 0, 0.5, 0.05 });
    b.prism(turret, top, 0.26, 0.09, 6, 0.75, team);
    b.box(turret, turret.at(top, .{ 0, 0.02, -0.45 }), .{ 0.05, 0.05, 0.32 }, .{ 1, 1 }, dark);
    b.box(turret, turret.at(top, .{ 0.11, 0.12, -0.12 }), .{ 0.025, 0.025, 0.12 }, .{ 1, 1 }, black);
}

fn builder(b: *Builder, f: Frame, p: V3, t: *const Thing, team: mesh.Rgb) void {
    // Six wheels, three a side, turning as it goes: each a five-sided
    // prism on its side, its cap outwards.
    for ([2]f32{ -1, 1 }) |side| {
        const axle: Frame = if (side > 0) .{ .right = -f.up, .up = f.right, .back = f.back } else .{ .right = f.up, .up = -f.right, .back = f.back };
        const spin = axle.turned(t.phase * side);
        for ([3]f32{ -0.38, 0, 0.38 }) |along| {
            b.prism(spin, f.at(p, .{ side * 0.4, 0.15, along }), 0.15, 0.07, 5, 1, black);
        }
    }
    // The body, the cab in front, and its player's colour on top.
    b.box(f, f.at(p, .{ 0, 0.3, 0.05 }), .{ 0.32, 0.12, 0.52 }, .{ 0.95, 0.95 }, rgb(0xd9a62e));
    b.box(f, f.at(p, .{ 0, 0.53, -0.3 }), .{ 0.26, 0.11, 0.16 }, .{ 0.85, 0.8 }, metal);
    b.box(f, f.at(p, .{ 0, 0.53, -0.47 }), .{ 0.2, 0.06, 0.01 }, .{ 1, 1 }, glass);
    b.box(f, f.at(p, .{ 0, 0.43, 0.3 }), .{ 0.22, 0.02, 0.18 }, .{ 1, 1 }, team);
    // Its crane, swinging while it builds.
    const working: f32 = if (t.site != null) 1 else 0;
    const arm = f.turned(@sin(t.phase * 0.7) * 0.5 * working);
    const base = f.at(p, .{ 0, 0.5, 0.3 });
    b.box(arm, arm.at(base, .{ 0, 0.06, 0 }), .{ 0.07, 0.06, 0.07 }, .{ 1, 1 }, dark);
    const boom = arm.tipped(0.5 + 0.2 * working);
    b.box(boom, boom.at(base, .{ 0, 0.1, -0.35 }), .{ 0.04, 0.04, 0.35 }, .{ 1, 1 }, glow);
}

fn airBuilder(b: *Builder, f_in: Frame, p: V3, t: *const Thing, team: mesh.Rgb) void {
    const f = f_in.tipped(-0.15 * @min(1, t.moving / 3));
    const at = p + V3{ 0, @sin(t.phase * 0.05) * 0.06, 0 };
    // A long body, its player's colour along its back, a window in front.
    b.box(f, at, .{ 0.3, 0.13, 0.5 }, .{ 0.8, 0.85 }, rgb(0xd9a62e));
    b.box(f, f.at(at, .{ 0, 0.14, 0.05 }), .{ 0.12, 0.02, 0.32 }, .{ 1, 1 }, team);
    b.box(f, f.at(at, .{ 0, 0, -0.51 }), .{ 0.16, 0.06, 0.02 }, .{ 1, 1 }, glass);
    // Six rotors, on arms out to each side.
    for ([3]f32{ -0.4, 0, 0.4 }, 0..) |along, i| {
        b.box(f, f.at(at, .{ 0, 0.05, along }), .{ 0.56, 0.025, 0.025 }, .{ 1, 1 }, dark);
        for ([2]f32{ -1, 1 }) |side| {
            const spin = f.turned(t.phase + @as(f32, @floatFromInt(i)) * 1.3 + side);
            b.box(spin, f.at(at, .{ side * 0.58, 0.1, along }), .{ 0.22, 0.01, 0.03 }, .{ 1, 1 }, metal);
        }
    }
    // Its clamp, hanging below, lowered while it builds.
    const drop: f32 = if (t.site != null) 0.35 + 0.1 * @sin(t.phase) else 0.1;
    b.box(f, f.at(at, .{ 0, -0.13 - drop / 2, 0 }), .{ 0.02, drop / 2, 0.02 }, .{ 1, 1 }, dark);
    b.box(f, f.at(at, .{ 0, -0.17 - drop, 0 }), .{ 0.12, 0.04, 0.08 }, .{ 1, 1 }, glow);
    shadow(b, .{ p[0], p[1] - 3 + 0.04, p[2] }, 0.6 * t.kind.scale());
}

/// A bomber or a fighter: a body, wings, and a propeller at each
/// wingtip facing forward, as a plane's. Hovering, it stands on its tail,
/// nose up (its propellers lifting it); flying, it tilts forward until
/// level; banking as it turns.
fn aircraft(b: *Builder, f_in: Frame, p: V3, t: *const Thing, team: mesh.Rgb, k: units.Kind) void {
    const big = k == .bomber;
    const f = f_in.rolled(t.bank * 0.7).tipped((1 - t.tilt) * std.math.pi / 2 * 0.95);
    const len: f32 = if (big) 0.75 else 0.55;
    const span: f32 = if (big) 1.25 else 0.85;
    b.box(f, p, .{ 0.2, 0.14, len }, .{ 0.8, 0.85 }, if (big) rgb(0x5d6670) else metal);
    b.box(f, f.at(p, .{ 0, 0.15, 0.1 }), .{ 0.1, 0.02, len * 0.6 }, .{ 1, 1 }, team);
    b.box(f, f.at(p, .{ 0, 0.08, -len + 0.12 }), .{ 0.12, 0.07, 0.1 }, .{ 0.8, 0.8 }, glass);
    // Wings (swept back, a fighter's), and its tail fin.
    b.box(f, f.at(p, .{ 0, 0.02, if (big) @as(f32, 0) else 0.1 }), .{ span, 0.035, if (big) @as(f32, 0.28) else 0.2 }, .{ if (big) @as(f32, 1) else 0.8, 1 }, if (big) rgb(0x4a525b) else dark);
    b.box(f, f.at(p, .{ 0, 0.28, len - 0.12 }), .{ 0.03, 0.16, 0.12 }, .{ 1, 0.7 }, team);
    if (big) {
        b.box(f, f.at(p, .{ 0, -0.18, 0.05 }), .{ 0.12, 0.05, 0.35 }, .{ 1, 1 }, black);
    } else {
        b.box(f, f.at(p, .{ 0, -0.02, -len - 0.15 }), .{ 0.025, 0.025, 0.15 }, .{ 1, 1 }, black);
    }
    // A propeller at each wingtip, facing forward.
    const rotor = f.tipped(-std.math.pi / 2.0);
    for ([2]f32{ -1, 1 }) |side| {
        const tip = f.at(p, .{ side * span, 0.02, 0 });
        b.box(rotor, rotor.at(tip, .{ 0, 0.06, 0 }), .{ 0.07, 0.12, 0.07 }, .{ 1, 1 }, dark);
        const spin = rotor.turned(t.phase * side);
        const hub = rotor.at(tip, .{ 0, 0.2, 0 });
        const blade: f32 = if (big) 0.55 else 0.4;
        b.box(spin, hub, .{ blade, 0.01, 0.035 }, .{ 1, 1 }, metal);
        b.box(spin, hub, .{ 0.035, 0.01, blade }, .{ 1, 1 }, metal);
    }
    shadow(b, .{ p[0], p[1] - k.altitude() + 0.04, p[2] }, if (big) @as(f32, 0.9) else 0.6);
}

fn flak(b: *Builder, f: Frame, p: V3, t: *const Thing, team: mesh.Rgb) void {
    for ([2]f32{ -1, 1 }) |side| b.box(f, f.at(p, .{ side * 0.42, 0.16, 0 }), .{ 0.14, 0.16, 0.55 }, .{ 1, 0.9 }, black);
    b.box(f, f.at(p, .{ 0, 0.3, 0 }), .{ 0.32, 0.12, 0.5 }, .{ 0.85, 0.85 }, metal);
    // Its turret, turned to aim, and four guns pointing up.
    const turret = Frame.of(t.aim, 0, 0).scaled(t.kind.scale());
    const top = f.at(p, .{ 0, 0.52, 0.05 });
    b.box(turret, top, .{ 0.24, 0.1, 0.24 }, .{ 0.8, 0.8 }, team);
    const up = turret.tipped(0.75);
    for ([2]f32{ -1, 1 }) |across| for ([2]f32{ 0, 1 }) |row| {
        b.box(up, up.at(turret.at(top, .{ across * 0.1, 0.1 + row * 0.12, -0.05 }), .{ 0, 0, -0.28 }), .{ 0.025, 0.025, 0.28 }, .{ 1, 1 }, dark);
    };
}

fn drone(b: *Builder, f_in: Frame, p: V3, t: *const Thing, team: mesh.Rgb) void {
    // Leaning into where it is going; hovering up and down a little.
    const f = f_in.tipped(-0.25 * @min(1, t.moving / 3));
    const at = p + V3{ 0, @sin(t.phase * 0.08) * 0.08, 0 };
    b.box(f, at, .{ 0.2, 0.1, 0.28 }, .{ 0.8, 0.8 }, team);
    b.box(f, f.at(at, .{ 0, -0.02, -0.29 }), .{ 0.1, 0.05, 0.02 }, .{ 1, 1 }, glass);
    // Four arms, a rotor spinning at each end.
    for ([4][2]f32{ .{ -1, -1 }, .{ 1, -1 }, .{ -1, 1 }, .{ 1, 1 } }, 0..) |c, i| {
        const arm = f.turned(std.math.atan2(c[0], c[1]));
        b.box(arm, arm.at(at, .{ 0, 0.04, 0.25 }), .{ 0.03, 0.03, 0.22 }, .{ 1, 1 }, dark);
        const hub = f.at(at, .{ c[0] * 0.33, 0.1, c[1] * 0.33 });
        const spin = f.turned(t.phase + @as(f32, @floatFromInt(i)));
        b.box(spin, hub, .{ 0.2, 0.01, 0.03 }, .{ 1, 1 }, metal);
    }
    // Its shadow, on what is under it.
    shadow(b, .{ p[0], p[1] - 3 + 0.04, p[2] }, 0.45);
}

fn tower(b: *Builder, f: Frame, p: V3, t: *const Thing, team: mesh.Rgb) void {
    b.prism(f, f.at(p, .{ 0, 0.25, 0 }), 0.75, 0.25, 8, 0.85, dark);
    b.prism(f, f.at(p, .{ 0, 1.0, 0 }), 0.35, 0.55, 6, 0.85, metal);
    b.prism(f, f.at(p, .{ 0, 1.6, 0 }), 0.2, 0.06, 6, 1, team);
    // The gun, turned to aim.
    const gun = Frame.of(t.aim, 0, 0);
    const head = gun.at(p, .{ 0, 1.85, 0 });
    b.box(gun, head, .{ 0.3, 0.2, 0.35 }, .{ 0.85, 0.8 }, metal);
    for ([2]f32{ -1, 1 }) |side| b.box(gun, gun.at(head, .{ side * 0.12, 0, -0.6 }), .{ 0.05, 0.05, 0.3 }, .{ 1, 1 }, dark);
}

fn factory(b: *Builder, f: Frame, p: V3, t: *const Thing, team: mesh.Rgb) void {
    b.box(f, f.at(p, .{ 0, 0.8, 0 }), .{ 1.8, 0.8, 1.8 }, .{ 0.95, 0.95 }, metal);
    // Its door, in front, glowing while it makes something.
    const lit: f32 = if (t.queued > 0) 0.6 + 0.4 * @abs(@sin(t.phase * 3)) else 0;
    b.box(f, f.at(p, .{ 0, 0.55, -1.8 }), .{ 0.9, 0.55, 0.06 }, .{ 1, 1 }, mixRgb(black, glow, lit));
    // Roof stripes in its player's colour, and a crane.
    b.box(f, f.at(p, .{ 0, 1.62, 0.6 }), .{ 1.5, 0.04, 0.3 }, .{ 1, 1 }, team);
    b.box(f, f.at(p, .{ 0, 1.62, -0.4 }), .{ 1.5, 0.04, 0.3 }, .{ 1, 1 }, team);
    const crane = f.turned(@sin(t.phase * 0.5) * 0.8);
    const mast = f.at(p, .{ 1.2, 1.6, 1.2 });
    b.box(f, f.at(mast, .{ 0, 0.4, 0 }), .{ 0.1, 0.4, 0.1 }, .{ 1, 1 }, dark);
    b.box(crane, crane.at(mast, .{ 0, 0.85, -0.6 }), .{ 0.07, 0.06, 0.8 }, .{ 1, 1 }, glow);
}

fn power(b: *Builder, f: Frame, p: V3, t: *const Thing, team: mesh.Rgb) void {
    b.box(f, f.at(p, .{ 0, 0.3, 0 }), .{ 1.2, 0.3, 1.2 }, .{ 0.9, 0.9 }, dark);
    // A cooling tower, and a core pulsing with what it makes.
    b.prism(f, f.at(p, .{ -0.4, 1.1, 0.2 }), 0.65, 0.5, 8, 0.7, metal);
    const pulse = 0.5 + 0.5 * @sin(t.phase * 2);
    b.prism(f, f.at(p, .{ 0.6, 0.9, -0.5 }), 0.3, 0.3, 6, 0.6, mixRgb(team, glow, pulse));
    b.box(f, f.at(p, .{ 0, 0.62, 1.15 }), .{ 0.8, 0.04, 0.06 }, .{ 1, 1 }, team);
}

fn mine(b: *Builder, f: Frame, p: V3, t: *const Thing, team: mesh.Rgb) void {
    b.box(f, f.at(p, .{ 0, 0.25, 0 }), .{ 1.2, 0.25, 1.2 }, .{ 0.9, 0.9 }, dark);
    // A frame over the shaft, and the drill turning in it.
    for ([4][2]f32{ .{ -1, -1 }, .{ 1, -1 }, .{ -1, 1 }, .{ 1, 1 } }) |c| {
        b.box(f, f.at(p, .{ c[0] * 0.7, 1.4, c[1] * 0.7 }), .{ 0.07, 0.95, 0.07 }, .{ 1, 1 }, metal);
    }
    b.box(f, f.at(p, .{ 0, 2.4, 0 }), .{ 0.8, 0.08, 0.8 }, .{ 1, 1 }, team);
    const drill = f.turned(t.phase * 3);
    b.prism(drill, f.at(p, .{ 0, 1.3, 0 }), 0.25, 0.8, 4, 0.4, glow);
}

/// A dark patch on the ground under something.
fn shadow(b: *Builder, at: V3, r: f32) void {
    const c = rgb(0x1e2418);
    const sides = 8;
    for (0..sides) |k| {
        const a0 = @as(f32, @floatFromInt(k)) / sides * 2 * std.math.pi;
        const a1 = @as(f32, @floatFromInt(k + 1)) / sides * 2 * std.math.pi;
        b.shaded(.{ at, at + V3{ @cos(a1) * r, 0, @sin(a1) * r }, at + V3{ @cos(a0) * r, 0, @sin(a0) * r } }, c);
    }
}

/// A ring on the ground round something chosen, `r` round, at height `y`.
pub fn ring(b: *Builder, at: V3, r: f32, c: mesh.Rgb) void {
    const sides = 12;
    const w: f32 = 0.08;
    for (0..sides) |k| {
        const a0 = @as(f32, @floatFromInt(k)) / sides * 2 * std.math.pi;
        const a1 = @as(f32, @floatFromInt(k + 1)) / sides * 2 * std.math.pi;
        const in0 = at + V3{ @cos(a0) * r, 0, @sin(a0) * r };
        const in1 = at + V3{ @cos(a1) * r, 0, @sin(a1) * r };
        const out0 = at + V3{ @cos(a0) * (r + w), 0, @sin(a0) * (r + w) };
        const out1 = at + V3{ @cos(a1) * (r + w), 0, @sin(a1) * (r + w) };
        b.shaded(.{ in0, in1, out1 }, c);
        b.shaded(.{ in0, out1, out0 }, c);
    }
}

/// A streak from `tail` to `head`, `width` across, facing the camera
/// (looking along `forward`), glowing (brighter than lit things, so it
/// shows at night).
pub fn streak(b: *Builder, tail: V3, head: V3, width: f32, forward: V3, c: mesh.Rgb) void {
    const along = head - tail;
    const side = math.normalize(math.cross(along, forward)) * math.splat(width / 2);
    var q = [4]V3{ tail - side, tail + side, head + side * math.splat(0.6), head - side * math.splat(0.6) };
    // Facing the camera (counter-clockwise seen from it).
    if (math.dot(math.cross(q[1] - q[0], q[2] - q[0]), forward) > 0) std.mem.swap(V3, &q[1], &q[3]);
    b.shaded(.{ q[0], q[1], q[2] }, c);
    b.shaded(.{ q[0], q[2], q[3] }, c);
}

/// A burst, `age` of `life` seconds old, `size` across: a fireball
/// swelling, white to orange, then dark smoke rising.
pub fn blast(b: *Builder, at: V3, size: f32, age: f32, life: f32) void {
    const k = age / life;
    const r = size * (0.35 + 0.65 * @sqrt(k));
    const hot = mixRgb(.{ 2.4, 2.2, 1.6 }, .{ 1.8, 0.7, 0.15 }, @min(1, k * 2.2));
    const c = mixRgb(hot, .{ 0.22, 0.2, 0.19 }, smooth(0.45, 1, k));
    const f = Frame.of(age * 2 + size, 0, 0);
    const mid = at + V3{ 0, r * 0.4 + k * size * 0.6, 0 };
    b.prism(f, mid, r, r * 0.5, 6, 0.45, c);
    // Its underside (seen from above, the lower half's sides).
    b.prism(f.tipped(std.math.pi), mid, r, r * 0.35, 6, 0.6, mixRgb(c, .{ 0.1, 0.1, 0.1 }, 0.3));
}

/// A bar over a damaged thing: how much it has left, green to red.
pub fn healthBar(b: *Builder, over: V3, left: f32, width: f32, right: V3, up: V3) void {
    const h: f32 = 0.09;
    const r = right * math.splat(width / 2);
    const u = up * math.splat(h / 2);
    const start = over - r;
    const split = start + r * math.splat(2 * left);
    b.shaded(.{ start - u, split - u, split + u }, .{ 1.6 - 1.4 * left, 0.25 + 1.2 * left, 0.2 });
    b.shaded(.{ start - u, split + u, start + u }, .{ 1.6 - 1.4 * left, 0.25 + 1.2 * left, 0.2 });
    b.shaded(.{ split - u, over + r - u, over + r + u }, .{ 0.12, 0.12, 0.12 });
    b.shaded(.{ split - u, over + r + u, split + u }, .{ 0.12, 0.12, 0.12 });
}

fn smooth(lo: f32, hi: f32, x: f32) f32 {
    const t = std.math.clamp((x - lo) / (hi - lo), 0, 1);
    return t * t * (3 - 2 * t);
}

fn mixRgb(a: mesh.Rgb, b2: mesh.Rgb, t: f32) mesh.Rgb {
    return .{ a[0] + (b2[0] - a[0]) * t, a[1] + (b2[1] - a[1]) * t, a[2] + (b2[2] - a[2]) * t };
}

const testing = std.testing;

test "every kind: within its room, facing out" {
    var verts: [max_triangles * 3]mesh.Vertex = undefined;
    for (std.enums.values(units.Kind)) |k| {
        var b: Builder = .{ .out = &verts };
        const t: Thing = .{ .kind = k, .team = 1, .pos = .{ 5, 3 + (if (k.flies()) @as(f32, 3) else 0), 5 }, .yaw = 0.5, .moving = 1, .phase = 1.3 };
        thing(&b, &t);
        try testing.expect(b.n > 0);
        // Not cut short: room to spare.
        try testing.expect(b.n < verts.len);
    }
}
