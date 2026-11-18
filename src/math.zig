//! Vectors and matrices (column-major, as the GPU takes them), and the
//! isometric camera.

const std = @import("std");

pub const V3 = @Vector(3, f32);
pub const Mat4 = [16]f32;

pub fn splat(x: f32) V3 {
    return @splat(x);
}

pub fn dot(a: V3, b: V3) f32 {
    return @reduce(.Add, a * b);
}

pub fn cross(a: V3, b: V3) V3 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

pub fn length(a: V3) f32 {
    return @sqrt(dot(a, a));
}

pub fn normalize(a: V3) V3 {
    const l = length(a);
    return if (l > 0) a / splat(l) else a;
}

pub const identity: Mat4 = .{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 };

pub fn mul(a: Mat4, b: Mat4) Mat4 {
    var out: Mat4 = undefined;
    for (0..4) |col| for (0..4) |row| {
        var sum: f32 = 0;
        for (0..4) |k| sum += a[k * 4 + row] * b[col * 4 + k];
        out[col * 4 + row] = sum;
    };
    return out;
}

/// Where a point goes (x, y, z, w).
pub fn transform(m: Mat4, p: V3) [4]f32 {
    var out: [4]f32 = undefined;
    for (0..4) |r| out[r] = m[r] * p[0] + m[4 + r] * p[1] + m[8 + r] * p[2] + m[12 + r];
    return out;
}

/// The isometric camera: looking down at `target` (on the ground) from the
/// south-east-ish, at the angle of an isometric picture, with no
/// perspective; `zoom` blocks from the middle of the view to its top.
pub const Camera = struct {
    target: V3,
    zoom: f32 = 14,
    /// Turned this far right of looking north (-z), and down.
    yaw: f32 = std.math.pi / 4.0,
    pitch: f32 = 0.6154797, // atan(1 / √2): an isometric picture's
    /// How far back from the target the eye is (only for the depth range).
    distance: f32 = 120,

    pub fn forward(c: Camera) V3 {
        return .{ @sin(c.yaw) * @cos(c.pitch), -@sin(c.pitch), -@cos(c.yaw) * @cos(c.pitch) };
    }

    pub fn right(c: Camera) V3 {
        return .{ @cos(c.yaw), 0, @sin(c.yaw) };
    }

    pub fn up(c: Camera) V3 {
        return cross(c.right(), c.forward());
    }

    pub fn eye(c: Camera) V3 {
        return c.target - c.forward() * splat(c.distance);
    }

    /// World to clip space, for a view `aspect` wide (to its height).
    pub fn viewProjection(c: Camera, aspect: f32) Mat4 {
        const r = c.right();
        const u = c.up();
        const f = c.forward();
        const e = c.eye();
        // The view: the eye at the origin, looking down -z.
        const view: Mat4 = .{
            r[0],        u[0],        -f[0],      0,
            r[1],        u[1],        -f[1],      0,
            r[2],        u[2],        -f[2],      0,
            -dot(r, e), -dot(u, e), dot(f, e), 1,
        };
        const near: f32 = 1;
        const far: f32 = 2 * c.distance;
        const hw = c.zoom * aspect;
        const hh = c.zoom;
        const proj: Mat4 = .{
            1 / hw, 0,      0,                          0,
            0,      1 / hh, 0,                          0,
            0,      0,      -2 / (far - near),          0,
            0,      0,      -(far + near) / (far - near), 1,
        };
        return mul(proj, view);
    }

    /// The ray through a point of the view (x and y from -1 to 1, y up):
    /// where it starts, near the eye, and its way (the camera's).
    pub fn ray(c: Camera, aspect: f32, x: f32, y: f32) struct { origin: V3, dir: V3 } {
        return .{ .origin = c.eye() + c.right() * splat(x * c.zoom * aspect) + c.up() * splat(y * c.zoom), .dir = c.forward() };
    }
};

const testing = std.testing;

test "the camera: its target in the middle of the view, rays back to it" {
    const c: Camera = .{ .target = .{ 10, 2, 20 } };
    const m = c.viewProjection(16.0 / 9.0);
    const t = transform(m, c.target);
    try testing.expectApproxEqAbs(@as(f32, 0), t[0] / t[3], 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 0), t[1] / t[3], 1e-4);
    // In front of the eye, in the depth range.
    try testing.expect(t[2] / t[3] > -1 and t[2] / t[3] < 1);
    // The middle's ray goes through the target.
    const r = c.ray(16.0 / 9.0, 0, 0);
    const to = c.target - r.origin;
    try testing.expectApproxEqAbs(@as(f32, 0), length(to - r.dir * splat(dot(to, r.dir))), 1e-3);
    // A point up the view, up the screen.
    const above = transform(m, c.target + c.up());
    try testing.expect(above[1] > 0);
}
