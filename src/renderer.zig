//! Draws the battlefield: the ground, in chunks, and the units and
//! buildings (made anew each frame, all in one buffer, one draw), all with
//! one program (shaders/flat.zig).
//!
//! The ground's chunks are on the GPU only while they are in view or near
//! it: each made from the map's heights (kept in ordinary memory) as it
//! comes into view, and let go of once it is well out of it, so the GPU's
//! memory holds only what can be seen (about 2 MB), however large the
//! map is.

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
    /// Chunks on the GPU, and the memory they take.
    kept: u32 = 0,
    kept_bytes: usize = 0,
};

/// A chunk of ground: its triangles on the GPU (if it is in view, or was
/// lately), and how high it goes (for knowing if it is in view).
const Chunk = struct {
    bo: ?vc4.Bo = null,
    count: u32 = 0,
    lo: f32,
    hi: f32,
};

/// How many chunks are made in a frame (the rest in the frames after:
/// they come into view a few at a time as the view moves).
const made_per_frame = 6;
/// How far out of view (in blocks) a chunk is kept before it is let go of
/// (so one at the edge is not made and let go of again and again).
const keep_past: f32 = 12;

/// `Device`: vc4.Device, or a fake for tests.
pub fn Renderer(comptime Device: type) type {
    return struct {
        const Self = @This();

        gpa: std.mem.Allocator,
        dev: Device,
        flat: shader.Pipeline,
        map: *const Map,
        chunks: [map_mod.chunks_x * map_mod.chunks_z]Chunk,
        /// Where a chunk's triangles are made, before they go to the GPU.
        scratch: []Vertex,
        /// Every chunk in view made, however many (the first frame, and
        /// after the view jumps).
        all_now: bool = true,
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
            // How high each chunk goes (its triangles are made when it is
            // in view).
            var chunks: [map_mod.chunks_x * map_mod.chunks_z]Chunk = undefined;
            for (0..map_mod.chunks_z) |cz| for (0..map_mod.chunks_x) |cx| {
                const range = m.chunkHeights(cx, cz);
                chunks[cz * map_mod.chunks_x + cx] = .{ .lo = @min(range[0], map_mod.water_level), .hi = range[1] };
            };
            const scratch = try gpa.alloc(Vertex, Map.chunk_vertices);
            errdefer gpa.free(scratch);
            const d0 = try dev.createBo(max_dynamic * @sizeOf(Vertex));
            errdefer dev.destroyBo(d0);
            const d1 = try dev.createBo(max_dynamic * @sizeOf(Vertex));
            r.* = .{ .gpa = gpa, .dev = dev, .flat = flat, .map = m, .chunks = chunks, .scratch = scratch, .dynamic = .{ d0, d1 } };
            return r;
        }

        pub fn deinit(r: *Self) void {
            r.flat.deinit(r.dev);
            for (&r.chunks) |*c| r.letGo(c);
            r.gpa.free(r.scratch);
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
            var made: u32 = 0;
            for (&r.chunks, 0..) |*c, i| {
                const cx = i % map_mod.chunks_x;
                const cz = i / map_mod.chunks_x;
                const b = Map.chunkBounds(cx, cz);
                const lo = V3{ b[0][0], c.lo, b[0][1] };
                const hi = V3{ b[1][0], c.hi, b[1][1] };
                if (!inView(vp, lo, hi)) {
                    // Well out of view: let go of.
                    const k = math.splat(keep_past);
                    if (c.bo != null and !inView(vp, lo - k, hi + k)) r.letGo(c);
                    continue;
                }
                if (c.bo == null) {
                    // Come into view: made (a few a frame).
                    if (!r.all_now and made >= made_per_frame) continue;
                    r.make(c, cx, cz) catch continue;
                    made += 1;
                }
                r.stats.chunks += 1;
                if (c.count > 0) try r.drawRange(sink, c.bo.?.handle, 0, c.count, viewport, scissor);
            }
            r.all_now = false;
            for (r.chunks) |c| if (c.bo) |bo| {
                r.stats.kept += 1;
                r.stats.kept_bytes += bo.map.len;
            };
            try r.drawRange(sink, r.dynamic[r.which].handle, 0, @intCast(dynamic), viewport, scissor);
        }

        /// Makes chunk (cx, cz)'s triangles, and puts them on the GPU.
        fn make(r: *Self, c: *Chunk, cx: usize, cz: usize) !void {
            const n = r.map.chunkMesh(cx, cz, r.scratch);
            const bo = try r.dev.createBo(@intCast(@max(n, 3) * @sizeOf(Vertex)));
            @memcpy(bo.map[0 .. n * @sizeOf(Vertex)], std.mem.sliceAsBytes(r.scratch[0..n]));
            c.bo = bo;
            c.count = @intCast(n);
        }

        /// Takes a chunk off the GPU (one still being drawn is kept by the
        /// kernel until it has been).
        fn letGo(r: *Self, c: *Chunk) void {
            if (c.bo) |bo| r.dev.destroyBo(bo);
            c.bo = null;
            c.count = 0;
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
