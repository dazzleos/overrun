//! Draws the battlefield: the ground, in chunks, and the units and
//! buildings (made anew each frame, all in one buffer, one draw), all with
//! one program (shaders/flat.zig).
//!
//! The ground's chunks are on the GPU only while they are in view or near
//! it: each made from the map's heights (kept in ordinary memory) as it
//! comes into view, and let go of once it is well out of it, so the GPU's
//! memory holds only what can be seen (about 2 MB), however large the
//! map is. Only the chunks under the view are looked at (and those kept),
//! so a frame takes no longer on a larger map.

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
    /// As low and high as it can be, until its heights are made.
    lo: f32 = @min(map_mod.lowest, map_mod.water_level),
    hi: f32 = map_mod.highest,
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
        /// The chunks on the GPU.
        kept: std.ArrayList(u16) = .empty,
        /// Where a chunk's triangles are made, before they go to the GPU.
        scratch: []Vertex,
        /// Every chunk in view made, however many (the first frame, and
        /// after the view jumps: see `makeAllNow`).
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
            const chunks: [map_mod.chunks_x * map_mod.chunks_z]Chunk = @splat(.{});
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
            for (r.kept.items) |i| r.letGo(&r.chunks[i]);
            r.kept.deinit(r.gpa);
            r.gpa.free(r.scratch);
            for (r.dynamic) |bo| r.dev.destroyBo(bo);
            r.gpa.destroy(r);
        }

        /// The view has jumped: the next frame makes all the ground in view
        /// (rather than showing it a few chunks at a time).
        pub fn makeAllNow(r: *Self) void {
            r.all_now = true;
        }

        /// The next frame's buffer for units and buildings, to make them in.
        pub fn dynamicVertices(r: *Self) []Vertex {
            r.which +%= 1;
            const bo = r.dynamic[r.which];
            return std.mem.bytesAsSlice(Vertex, bo.map[0 .. max_dynamic * @sizeOf(Vertex)]);
        }

        /// Draws the ground in view, and `dynamic` vertices of the buffer
        /// `dynamicVertices` gave, with `vp` (world to clip space); `ground`
        /// is what of the ground can be in view (from `Camera.groundBox`).
        pub fn draw(r: *Self, sink: anytype, viewport: vc4.render.Viewport, scissor: ?vc4.render.Viewport, vp: math.Mat4, ground: [2][2]f32, dynamic: usize) !void {
            r.stats = .{};
            const u: Uniforms = .{ .mvp = vp };
            r.flat.setUniforms(std.mem.asBytes(&u));
            // Those well out of view let go of.
            const keep = chunksIn(ground, keep_past);
            var k: usize = 0;
            while (k < r.kept.items.len) {
                const i = r.kept.items[k];
                const cx = i % map_mod.chunks_x;
                const cz = i / map_mod.chunks_x;
                if (cx < keep[0][0] or cx > keep[1][0] or cz < keep[0][1] or cz > keep[1][1]) {
                    r.letGo(&r.chunks[i]);
                    _ = r.kept.swapRemove(k);
                } else k += 1;
            }
            // Those in view drawn (made first, a few a frame, if need be).
            const range = chunksIn(ground, 0);
            var made: u32 = 0;
            for (range[0][1]..range[1][1] + 1) |cz| for (range[0][0]..range[1][0] + 1) |cx| {
                const i = cz * map_mod.chunks_x + cx;
                const c = &r.chunks[i];
                const b = Map.chunkBounds(cx, cz);
                if (!inView(vp, .{ b[0][0], c.lo, b[0][1] }, .{ b[1][0], c.hi, b[1][1] })) continue;
                if (c.bo == null) {
                    if (!r.all_now and made >= made_per_frame) continue;
                    r.make(c, cx, cz) catch continue;
                    r.kept.append(r.gpa, @intCast(i)) catch {
                        r.letGo(c);
                        continue;
                    };
                    made += 1;
                }
                r.stats.chunks += 1;
                if (c.count > 0) try r.drawRange(sink, c.bo.?.handle, 0, c.count, viewport, scissor);
            };
            r.all_now = false;
            for (r.kept.items) |i| {
                r.stats.kept += 1;
                r.stats.kept_bytes += r.chunks[i].bo.?.map.len;
            }
            try r.drawRange(sink, r.dynamic[r.which].handle, 0, @intCast(dynamic), viewport, scissor);
        }

        /// Makes chunk (cx, cz)'s triangles, and puts them on the GPU.
        fn make(r: *Self, c: *Chunk, cx: usize, cz: usize) !void {
            const n = r.map.chunkMesh(cx, cz, r.scratch);
            const bo = try r.dev.createBo(@intCast(@max(n, 3) * @sizeOf(Vertex)));
            @memcpy(bo.map[0 .. n * @sizeOf(Vertex)], std.mem.sliceAsBytes(r.scratch[0..n]));
            c.bo = bo;
            c.count = @intCast(n);
            // How high it goes, now its heights are made.
            const range = r.map.chunkHeights(cx, cz);
            c.lo = @min(range[0], map_mod.water_level);
            c.hi = range[1];
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

/// The chunks (from, to: across and down) under `ground` (from (x, z), to
/// (x, z)), `past` blocks further each way, on the map.
fn chunksIn(ground: [2][2]f32, past: f32) [2][2]usize {
    const per_row = map_mod.row_gap * map_mod.chunk;
    const x0 = (ground[0][0] - past - 0.5 + map_mod.margin_cols) / map_mod.chunk;
    const x1 = (ground[1][0] + past + map_mod.margin_cols) / map_mod.chunk;
    const z0 = ground[0][1] / per_row - past / per_row + map_mod.margin_rows / @as(f32, map_mod.chunk);
    const z1 = ground[1][1] / per_row + past / per_row + map_mod.margin_rows / @as(f32, map_mod.chunk);
    return .{ .{ clampChunk(x0, map_mod.chunks_x), clampChunk(z0, map_mod.chunks_z) }, .{ clampChunk(x1, map_mod.chunks_x), clampChunk(z1, map_mod.chunks_z) } };
}

fn clampChunk(f: f32, n: usize) usize {
    return @intFromFloat(std.math.clamp(@floor(f), 0, @as(f32, @floatFromInt(n - 1))));
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

test "the chunks under the view: all the ground seen, and not much more" {
    const c: math.Camera = .{ .target = .{ 120, 1, 90 }, .zoom = 24 };
    const aspect: f32 = 16.0 / 9.0;
    const range = chunksIn(c.groundBox(aspect, map_mod.lowest, map_mod.highest), 0);
    // Ground across the view, from as low as it goes to as high: in a
    // chunk in the range.
    for (0..9) |i| for (0..9) |j| for ([_]f32{ map_mod.lowest, map_mod.highest }) |y| {
        const r = c.ray(aspect, @as(f32, @floatFromInt(i)) / 4 - 1, @as(f32, @floatFromInt(j)) / 4 - 1);
        const p = r.origin + r.dir * math.splat((y - r.origin[1]) / r.dir[1]);
        const at = chunksIn(.{ .{ p[0], p[2] }, .{ p[0], p[2] } }, 0);
        try testing.expect(at[0][0] >= range[0][0] and at[1][0] <= range[1][0] and at[0][1] >= range[0][1] and at[1][1] <= range[1][1]);
    };
    // Far fewer than all of the map's.
    try testing.expect((range[1][0] - range[0][0] + 1) * (range[1][1] - range[0][1] + 1) < 120);
}

test "a box in view, or not" {
    const c: math.Camera = .{ .target = .{ 50, 1, 50 } };
    const vp = c.viewProjection(16.0 / 9.0);
    try testing.expect(inView(vp, .{ 48, 0, 48 }, .{ 52, 2, 52 }));
    try testing.expect(!inView(vp, .{ 0, 0, 0 }, .{ 4, 2, 4 }));
}
