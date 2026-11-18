//! Everything Overrun draws: triangles each corner of which has its
//! colour, lit as it was made (on the CPU), so the GPU only moves corners
//! and fills: the least work a pixel can be, for many units on a Pi Zero.
//! The light of the time of day and the weather is a tint each corner's
//! colour is multiplied by.

const gpu = @import("gpu");
const Vec3 = gpu.Vec3;
const Vec4 = gpu.Vec4;

const Uniforms = extern struct {
    mvp: [4]Vec4,
    /// What every colour is multiplied by: the time of day's light, and
    /// the weather's.
    tint: Vec4,
};
const u = gpu.uniforms(Uniforms);

const in_pos = gpu.vertexInput(Vec3, 0);
const in_color = gpu.vertexInput(Vec3, 1);

const v_color = gpu.vertexOutput(Vec3, 0);

export fn vertex() callconv(.spirv_vertex) void {
    const p = in_pos.*;
    const m = u.mvp;
    gpu.position.* = m[0] * gpu.splat4(p[0]) + m[1] * gpu.splat4(p[1]) + m[2] * gpu.splat4(p[2]) + m[3];
    const c = in_color.*;
    const t = u.tint;
    v_color.* = .{ c[0] * t[0], c[1] * t[1], c[2] * t[2] };
}

const f_color = gpu.fragmentInput(Vec3, 0);

export fn fragment() callconv(.{ .spirv_fragment = .{} }) void {
    const c = f_color.*;
    gpu.color.* = .{ c[0], c[1], c[2], 1 };
}
