//! The minimap: the map's hexagon, small, its ground made from the map's
//! seed (not from its heights, which are made only where they are wanted,
//! so it does not make them all), as a picture to draw.

const std = @import("std");
const kete = @import("kete");
const math = @import("math.zig");
const mesh = @import("mesh.zig");
const map_mod = @import("map.zig");

/// Its size, in pixels: the hexagon's square.
pub const width = 200;
pub const height: u32 = @intFromFloat(@ceil(@as(f32, map_mod.size) * map_mod.row_gap * scale));
/// Pixels a block.
const scale: f32 = @as(f32, width) / map_mod.size;
/// Where its top left is, on the map.
const origin = [2]f32{ map_mod.centre[0] - map_mod.radius, map_mod.centre[1] - map_mod.radius * map_mod.row_gap };

pub const Minimap = struct {
    pixels: [width * height]u32,
    image: kete.gfx.Image,

    /// Makes the map's (made from `seed`).
    pub fn create(gpa: std.mem.Allocator, seed: u32) !*Minimap {
        const mm = try gpa.create(Minimap);
        errdefer gpa.destroy(mm);
        // The ground's height at each pixel, and a pixel round it.
        const heights = try gpa.alloc(f32, (width + 2) * (height + 2));
        defer gpa.free(heights);
        for (0..height + 2) |y| for (0..width + 2) |x| {
            const p = fromPixel(.{ @as(f32, @floatFromInt(x)) - 0.5, @as(f32, @floatFromInt(y)) - 0.5 });
            heights[y * (width + 2) + x] = map_mod.heightOf(seed, p[0], p[1]);
        };
        for (0..height) |y| for (0..width) |x| {
            const p = fromPixel(.{ @as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5 });
            // Soft at the hexagon's edge; nothing past it.
            const alpha = std.math.clamp(map_mod.inside(p[0], p[1]) * scale + 0.5, 0, 1);
            const i = (y + 1) * (width + 2) + x + 1;
            const h = heights[i];
            // Its slope, a block across.
            const dx = (heights[i + 1] - heights[i - 1]) * scale / 2;
            const dz = (heights[i + width + 2] - heights[i - width - 2]) * scale / 2;
            const n = math.V3{ -dx, 1, -dz };
            const steep = 1 - math.normalize(n)[1];
            var c = if (h < map_mod.water_level) map_mod.waterColour(h) else mesh.lit(map_mod.colourOf(h, steep, @intCast(x * 31 + y * 17)), n);
            // Forests, darker.
            if (map_mod.treeHeight(h)) {
                const k = map_mod.forestOf(seed, p[0], p[1]) * 0.75;
                const tree = mesh.rgb(0x24502a);
                c = .{ c[0] + (tree[0] - c[0]) * k, c[1] + (tree[1] - c[1]) * k, c[2] + (tree[2] - c[2]) * k };
            }
            mm.pixels[y * width + x] = argb(c, alpha);
        };
        mm.image = .init(&mm.pixels, width, height);
        return mm;
    }

    pub fn destroy(mm: *Minimap, gpa: std.mem.Allocator) void {
        gpa.destroy(mm);
    }
};

/// Where on the minimap (in its pixels) a point of the map (x, z) is.
pub fn toPixel(p: [2]f32) [2]f32 {
    return .{ (p[0] - origin[0]) * scale, (p[1] - origin[1]) * scale };
}

/// Where on the map (x, z) a point of the minimap (in its pixels) is.
pub fn fromPixel(p: [2]f32) [2]f32 {
    return .{ p[0] / scale + origin[0], p[1] / scale + origin[1] };
}

/// The hexagon's corners, on the minimap.
pub fn hexagon() [6][2]f32 {
    const r = map_mod.radius;
    const h = r * map_mod.row_gap;
    const c = map_mod.centre;
    var out: [6][2]f32 = undefined;
    for (&out, [6][2]f32{ .{ -r, 0 }, .{ -r / 2, -h }, .{ r / 2, -h }, .{ r, 0 }, .{ r / 2, h }, .{ -r / 2, h } }) |*o, k| o.* = toPixel(.{ c[0] + k[0], c[1] + k[1] });
    return out;
}

fn argb(c: mesh.Rgb, alpha: f32) u32 {
    var out: u32 = @as(u32, @intFromFloat(@round(alpha * 255))) << 24;
    for (c, 0..) |v, k| out |= @as(u32, @intFromFloat(@round(std.math.clamp(v, 0, 1) * 255))) << @intCast(16 - 8 * k);
    return out;
}

const testing = std.testing;

test "the minimap: the hexagon filled, nothing past it; to it and back" {
    const mm = try Minimap.create(testing.allocator, 1);
    defer mm.destroy(testing.allocator);
    // Its middle solid; its corners (past the hexagon) clear.
    try testing.expectEqual(@as(u32, 0xff), mm.pixels[(height / 2) * width + width / 2] >> 24);
    try testing.expectEqual(@as(u32, 0), mm.pixels[0] >> 24);
    try testing.expectEqual(@as(u32, 0), mm.pixels[height * width - 1] >> 24);
    // The hexagon fills it across and down.
    const hex = hexagon();
    try testing.expectApproxEqAbs(@as(f32, 0), hex[0][0], 1e-3);
    try testing.expectApproxEqAbs(@as(f32, width), hex[3][0], 1e-3);
    try testing.expect(hex[4][1] <= @as(f32, @floatFromInt(height)) and hex[4][1] > @as(f32, @floatFromInt(height)) - 1);
    const p = fromPixel(toPixel(map_mod.bases[2]));
    try testing.expectApproxEqAbs(map_mod.bases[2][0], p[0], 1e-3);
    try testing.expectApproxEqAbs(map_mod.bases[2][1], p[1], 1e-3);
}
