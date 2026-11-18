//! Triangles as the GPU takes them (see shaders/flat.zig), and making them:
//! each lit by the sun as it is made, from which way it faces.

const std = @import("std");
const math = @import("math.zig");

const V3 = math.V3;

pub const Vertex = extern struct {
    pos: [3]f32,
    color: [3]f32,
};

pub const Rgb = [3]f32;

pub fn rgb(hex: u24) Rgb {
    return .{
        @as(f32, @floatFromInt(hex >> 16)) / 255,
        @as(f32, @floatFromInt(hex >> 8 & 0xff)) / 255,
        @as(f32, @floatFromInt(hex & 0xff)) / 255,
    };
}

/// Where the sun is (from the ground), and how much light there is in the
/// shade.
const sun = math.normalize(.{ -0.45, 0.8, 0.35 });
const ambient: f32 = 0.45;

/// `c` lit as a face whose normal is `n` is.
pub fn lit(c: Rgb, n: V3) Rgb {
    const d = @max(0, math.dot(math.normalize(n), sun));
    const k = ambient + (1 - ambient) * d;
    return .{ c[0] * k, c[1] * k, c[2] * k };
}

/// A way of facing: right, up and back (`right × up = back`), turned `yaw`
/// from facing north (-z), and tipped `pitch` (nose up) and `roll`.
pub const Frame = struct {
    right: V3,
    up: V3,
    back: V3,

    /// The same, `s` times as big (all drawn with it is).
    pub fn scaled(f: Frame, s: f32) Frame {
        return .{ .right = f.right * math.splat(s), .up = f.up * math.splat(s), .back = f.back * math.splat(s) };
    }

    pub fn of(yaw: f32, pitch: f32, roll: f32) Frame {
        const cy = @cos(yaw);
        const sy = @sin(yaw);
        const fwd = V3{ sy * @cos(pitch), @sin(pitch), -cy * @cos(pitch) };
        const level_right = V3{ cy, 0, sy };
        const level_up = math.cross(level_right, fwd);
        const cr = @cos(roll);
        const sr = @sin(roll);
        return .{
            .right = level_right * math.splat(cr) + level_up * math.splat(sr),
            .up = level_up * math.splat(cr) - level_right * math.splat(sr),
            .back = -fwd,
        };
    }

    pub const level: Frame = .{ .right = .{ 1, 0, 0 }, .up = .{ 0, 1, 0 }, .back = .{ 0, 0, 1 } };

    /// Turned `a` about its up.
    pub fn turned(f: Frame, a: f32) Frame {
        const c = @cos(a);
        const s = @sin(a);
        return .{ .right = f.right * math.splat(c) + f.back * math.splat(s), .up = f.up, .back = f.back * math.splat(c) - f.right * math.splat(s) };
    }

    /// Tipped `a` about its right (its front up).
    pub fn tipped(f: Frame, a: f32) Frame {
        const c = @cos(a);
        const s = @sin(a);
        return .{ .right = f.right, .up = f.up * math.splat(c) + f.back * math.splat(s), .back = f.back * math.splat(c) - f.up * math.splat(s) };
    }

    /// Where `local` (right, up, back from `origin`) is.
    pub fn at(f: Frame, origin: V3, local: V3) V3 {
        return origin + f.right * math.splat(local[0]) + f.up * math.splat(local[1]) + f.back * math.splat(local[2]);
    }
};

/// Adds lit triangles to `out` (as many as fit).
pub const Builder = struct {
    out: []Vertex,
    n: usize = 0,

    pub fn triangle(b: *Builder, p: [3]V3, c: Rgb) void {
        b.shaded(p, lit(c, math.cross(p[1] - p[0], p[2] - p[0])));
    }

    /// As it is, not lit (glowing, or its light already worked out).
    pub fn shaded(b: *Builder, p: [3]V3, c: Rgb) void {
        if (b.n + 3 > b.out.len) return;
        for (p, 0..) |q, i| b.out[b.n + i] = .{ .pos = q, .color = c };
        b.n += 3;
    }

    /// A quad, its corners counter-clockwise seen from in front.
    pub fn quad(b: *Builder, p: [4]V3, c: Rgb) void {
        b.triangle(.{ p[0], p[1], p[2] }, c);
        b.triangle(.{ p[0], p[2], p[3] }, c);
    }

    /// A box `half` from `center` each way (in `f`'s right, up and back),
    /// narrowed to `top` (across and back) at its top; without its
    /// bottom (on the ground, or seen from above: never seen).
    pub fn box(b: *Builder, f: Frame, center: V3, half: V3, top: [2]f32, c: Rgb) void {
        var p: [2][2][2]V3 = undefined;
        for (0..2) |ix| for (0..2) |iy| for (0..2) |iz| {
            const sx: f32 = if (ix == 0) -1 else 1;
            const sy: f32 = if (iy == 0) -1 else 1;
            const sz: f32 = if (iz == 0) -1 else 1;
            const k: [2]f32 = if (iy == 1) top else .{ 1, 1 };
            p[ix][iy][iz] = f.at(center, .{ sx * half[0] * k[0], sy * half[1], sz * half[2] * k[1] });
        };
        // Top, then the four sides: right, left, back, front.
        b.quad(.{ p[0][1][1], p[1][1][1], p[1][1][0], p[0][1][0] }, c);
        b.quad(.{ p[1][0][1], p[1][0][0], p[1][1][0], p[1][1][1] }, c);
        b.quad(.{ p[0][0][0], p[0][0][1], p[0][1][1], p[0][1][0] }, c);
        b.quad(.{ p[0][0][1], p[1][0][1], p[1][1][1], p[0][1][1] }, c);
        b.quad(.{ p[1][0][0], p[0][0][0], p[0][1][0], p[1][1][0] }, c);
    }

    /// A prism of `sides` sides about `f`'s up, `radius` round and `half`
    /// high from `center`, narrowed to `top` (of its radius) at its top;
    /// with its top, without its bottom.
    pub fn prism(b: *Builder, f: Frame, center: V3, radius: f32, half: f32, sides: u32, top: f32, c: Rgb) void {
        var k: u32 = 0;
        while (k < sides) : (k += 1) {
            const a0 = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(sides)) * 2 * std.math.pi;
            const a1 = @as(f32, @floatFromInt(k + 1)) / @as(f32, @floatFromInt(sides)) * 2 * std.math.pi;
            const lo0 = f.at(center, .{ @cos(a0) * radius, -half, @sin(a0) * radius });
            const lo1 = f.at(center, .{ @cos(a1) * radius, -half, @sin(a1) * radius });
            const hi0 = f.at(center, .{ @cos(a0) * radius * top, half, @sin(a0) * radius * top });
            const hi1 = f.at(center, .{ @cos(a1) * radius * top, half, @sin(a1) * radius * top });
            b.quad(.{ lo1, lo0, hi0, hi1 }, c);
            if (top > 0) b.triangle(.{ f.at(center, .{ 0, half, 0 }), hi1, hi0 }, c);
        }
    }
};

const testing = std.testing;

test "boxes and prisms face out (counter-clockwise from outside)" {
    var verts: [256]Vertex = undefined;
    var b: Builder = .{ .out = &verts };
    const f = Frame.of(0.7, 0.2, 0.1);
    const center = V3{ 3, 4, 5 };
    b.box(f, center, .{ 1, 0.5, 2 }, .{ 0.8, 0.9 }, rgb(0xffffff));
    b.prism(f, center, 1, 1, 6, 0.5, rgb(0xffffff));
    var i: usize = 0;
    while (i < b.n) : (i += 3) {
        const p: [3]V3 = .{ verts[i].pos, verts[i + 1].pos, verts[i + 2].pos };
        const n = math.cross(p[1] - p[0], p[2] - p[0]);
        const mid = (p[0] + p[1] + p[2]) / math.splat(3);
        try testing.expect(math.dot(n, mid - center) > 0);
    }
}
