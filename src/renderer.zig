//! Draws the battlefield: the ground (made once, in chunks, those out of
//! view left out) and the units and buildings (made anew each frame, all
//! in one buffer, one draw), all with one program (shaders/flat.zig).

const std = @import("std");
const vc4 = @import("vc4");
const shader = @import("shader");
const math = @import("math.zig");
const mesh = @import("mesh.zig");
const map_mod = @import("map.zig");

const Vertex = mesh.Vertex;
const V3 = math.V3;
const Map = map_mod.Map;

/// The most vertices a frame's units and buildings can be.
pub const max_dynamic = 3 * 60000;
/// The most vertices in one draw.
const max_per_draw = 3 * 20000;

const Uniforms = extern struct {
    mvp: math.Mat4,
};

pub const Stats = struct {
    chunks: u32 = 0,
    draws: u32 = 0,
    triangles: u32 = 0,
};

/// A chunk of ground: where its vertices are in the ground's buffer, and
/// how high it goes (for knowing if it is in view).
const Chunk = struct {
    first: u32,
    count: u32,
    lo: f32,
    hi: f32,
};

/// `Device`: vc4.Device, or a fake for tests.
pub fn Renderer(comptime Device: type) type {
    return struct {
        const Self = @This();

        gpa: std.mem.Allocator,
        dev: Device,
        flat: shader.Pipeline,
        ground: vc4.Bo,
        chunks: [map_mod.chunks * map_mod.chunks]Chunk,
        /// The units' and buildings' vertices, two buffers in turn (one may
        /// still be being drawn while the next is made).
        dynamic: [2]vc4.Bo,
        which: u1 = 0,
        stats: Stats = .{},

        pub fn init(gpa: std.mem.Allocator, dev: Device, m: *const Map) !*Self {
            const r = try gpa.create(Self);
            errdefer gpa.destroy(r);
            var flat = try shader.Pipeline.init(gpa, dev, shader.Program.decode(@embedFile("flat.shader")) catch unreachable, .{
                .vertex_stride = @sizeOf(Vertex),
                .attributes = &.{ .{ .location = 0, .offset = 0 }, .{ .location = 1, .offset = 12 } },
                .cull = .back,
                .early_z = true,
            });
            errdefer flat.deinit(dev);
            // The ground, chunk by chunk.
            const per_chunk = map_mod.chunk * map_mod.chunk * 12;
            const verts = try gpa.alloc(Vertex, per_chunk * map_mod.chunks * map_mod.chunks);
            defer gpa.free(verts);
            var chunks: [map_mod.chunks * map_mod.chunks]Chunk = undefined;
            var at: usize = 0;
            for (0..map_mod.chunks) |cz| for (0..map_mod.chunks) |cx| {
                const n = m.chunkMesh(cx, cz, verts[at..][0..per_chunk]);
                var lo: f32 = std.math.inf(f32);
                var hi: f32 = -std.math.inf(f32);
                for (verts[at..][0..n]) |v| {
                    lo = @min(lo, v.pos[1]);
                    hi = @max(hi, v.pos[1]);
                }
                chunks[cz * map_mod.chunks + cx] = .{ .first = @intCast(at), .count = @intCast(n), .lo = lo, .hi = hi };
                at += n;
            };
            const ground = try dev.createBo(@intCast(at * @sizeOf(Vertex)));
            errdefer dev.destroyBo(ground);
            @memcpy(ground.map[0 .. at * @sizeOf(Vertex)], std.mem.sliceAsBytes(verts[0..at]));
            const d0 = try dev.createBo(max_dynamic * @sizeOf(Vertex));
            errdefer dev.destroyBo(d0);
            const d1 = try dev.createBo(max_dynamic * @sizeOf(Vertex));
            r.* = .{ .gpa = gpa, .dev = dev, .flat = flat, .ground = ground, .chunks = chunks, .dynamic = .{ d0, d1 } };
            return r;
        }

        pub fn deinit(r: *Self) void {
            r.flat.deinit(r.dev);
            r.dev.destroyBo(r.ground);
            for (r.dynamic) |bo| r.dev.destroyBo(bo);
            r.gpa.destroy(r);
        }

        /// The next frame's buffer for units and buildings, to make them in.
        pub fn dynamicVertices(r: *Self) []Vertex {
            r.which +%= 1;
            const bo = r.dynamic[r.which];
            return std.mem.bytesAsSlice(Vertex, bo.map[0 .. max_dynamic * @sizeOf(Vertex)]);
        }

        /// Draws the ground in view, and `dynamic` vertices of the buffer
        /// `dynamicVertices` gave, with `vp` (world to clip space).
        pub fn draw(r: *Self, sink: anytype, viewport: vc4.render.Viewport, scissor: ?vc4.render.Viewport, vp: math.Mat4, dynamic: usize) !void {
            r.stats = .{};
            const u: Uniforms = .{ .mvp = vp };
            r.flat.setUniforms(std.mem.asBytes(&u));
            for (r.chunks, 0..) |c, i| {
                if (c.count == 0) continue;
                const cx: f32 = @floatFromInt(i % map_mod.chunks * map_mod.chunk);
                const cz: f32 = @floatFromInt(i / map_mod.chunks * map_mod.chunk);
                if (!inView(vp, .{ cx, @min(c.lo, map_mod.water_level), cz }, .{ cx + map_mod.chunk, c.hi, cz + map_mod.chunk })) continue;
                r.stats.chunks += 1;
                try r.drawRange(sink, r.ground.handle, c.first, c.count, viewport, scissor);
            }
            try r.drawRange(sink, r.dynamic[r.which].handle, 0, @intCast(dynamic), viewport, scissor);
        }

        fn drawRange(r: *Self, sink: anytype, handle: u32, first: u32, count: u32, viewport: vc4.render.Viewport, scissor: ?vc4.render.Viewport) !void {
            var done: u32 = 0;
            while (done < count) {
                const n = @min(count - done, max_per_draw);
                // A frame that is full gets no more.
                if (!sink.hasRoom(64)) return;
                try sink.draw(&r.flat, .{
                    .vertices = handle,
                    .vertex_offset = (first + done) * @sizeOf(Vertex),
                    .count = n,
                    .viewport = viewport,
                    .scissor = scissor,
                });
                r.stats.draws += 1;
                r.stats.triangles += n / 3;
                done += n;
            }
        }
    };
}

/// Whether any of a box (from `lo` to `hi`) may be in view: not all of its
/// corners off one side of the view.
pub fn inView(vp: math.Mat4, lo: V3, hi: V3) bool {
    var outside: [4]u8 = .{ 0, 0, 0, 0 };
    for (0..8) |k| {
        const p = V3{ if (k & 1 != 0) hi[0] else lo[0], if (k & 2 != 0) hi[1] else lo[1], if (k & 4 != 0) hi[2] else lo[2] };
        const c = math.transform(vp, p);
        if (c[0] < -c[3]) outside[0] += 1;
        if (c[0] > c[3]) outside[1] += 1;
        if (c[1] < -c[3]) outside[2] += 1;
        if (c[1] > c[3]) outside[3] += 1;
    }
    for (outside) |o| if (o == 8) return false;
    return true;
}

/// Where draws go: into a frame.
pub const FrameSink = struct {
    frame: *vc4.render.Frame,

    pub fn hasRoom(s: FrameSink, uniform_words: usize) bool {
        return s.frame.hasRoom(uniform_words);
    }

    pub fn draw(s: FrameSink, p: *shader.Pipeline, d: shader.Pipeline.Draw) !void {
        try p.draw(s.frame, d);
    }
};

const testing = std.testing;

test "a box in view, or not" {
    const c: math.Camera = .{ .target = .{ 50, 1, 50 } };
    const vp = c.viewProjection(16.0 / 9.0);
    try testing.expect(inView(vp, .{ 48, 0, 48 }, .{ 52, 2, 52 }));
    try testing.expect(!inView(vp, .{ 0, 0, 0 }, .{ 4, 2, 4 }));
}
