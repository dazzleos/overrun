//! Playing: the world, the camera, what is chosen, and what the mouse and
//! keys do.
//!
//! - Clicking a unit or building chooses it (with Shift, adds it, or
//!   takes it out); dragging a box chooses the units in it.
//! - With units chosen, clicking the ground sends them there.
//! - A factory chosen, its panel queues units to make.
//! - Dragging with the right button moves the view (the ground follows the
//!   pointer); so do the arrow keys (or W, A, S, D). The wheel zooms it.
//! - Esc opens the menu (the game starts in it); right-clicking (without
//!   dragging) lets go of what is chosen.

const std = @import("std");
const kete = @import("kete");
const minimap_mod = @import("minimap.zig");
const math = @import("math.zig");
const map_mod = @import("map.zig");
const units = @import("units.zig");

const V3 = math.V3;
const Map = map_mod.Map;
const World = units.World;
const Kind = units.Kind;

/// How far in and out the view zooms (blocks from its middle to its top).
const min_zoom: f32 = 6;
const max_zoom: f32 = 24;
/// The height the view's middle is at (it does not follow the ground,
/// which would move the view up and down as it went over hills).
pub const view_height: f32 = 1.5;

/// How far the mouse moves with a button down before it is a drag.
const drag_threshold: f32 = 6;

pub const MenuTab = enum(u2) { game, play, settings };

/// How many seconds the menu's frame rate graph shows.
pub const fps_seconds = 30;

/// This computer's player.
pub const me: u2 = 0;

pub const Game = struct {
    gpa: std.mem.Allocator,
    map: *Map,
    world: *World,
    minimap: *minimap_mod.Minimap,
    /// The left button held on the minimap (the view follows it).
    minimap_held: bool = false,
    /// The view follows what is chosen (F).
    following: bool = false,
    /// The view jumped (from the minimap): all the ground in view is to be
    /// made at once, not a few chunks a frame.
    view_jumped: bool = false,
    camera: math.Camera,
    /// What is chosen: indices into the world's things.
    chosen: std.ArrayList(usize) = .empty,
    /// The view's size, in its pixels (for picking).
    view_size: [2]f32 = .{ 1, 1 },
    /// A button down at (where, and whether it has become a drag).
    press: ?struct { at: kete.Point, now: kete.Point, dragging: bool } = null,
    /// The right button down: where the pointer was last, and whether it
    /// has moved the view (not a click).
    pan: ?struct { last: kete.Point, moved: bool } = null,
    shift: bool = false,
    keys: std.EnumSet(kete.KeyboardKey) = .empty,
    /// Where units were last sent, and when (a mark shows there a while).
    sent: ?struct { at: V3, time: f32 } = null,
    menu_open: bool = true,
    menu_tab: MenuTab = .game,
    /// Asked to quit.
    quit_asked: bool = false,
    /// Frames a second, each second, the oldest first.
    fps_history: [fps_seconds]f32 = @splat(0),
    fps_count: u8 = 0,
    /// Started (the menu's button says to play, not go on).
    started: bool = false,

    pub fn init(gpa: std.mem.Allocator, seed: u32) !Game {
        const m = try Map.create(gpa, seed);
        errdefer m.destroy(gpa);
        const mm = try minimap_mod.Minimap.create(gpa, seed);
        errdefer mm.destroy(gpa);
        const w = try gpa.create(World);
        w.* = .{ .map = m };
        var g: Game = .{ .gpa = gpa, .map = m, .world = w, .minimap = mm, .camera = .{ .target = .{ 0, 0, 0 } } };
        g.newGame();
        return g;
    }

    pub fn deinit(g: *Game) void {
        g.chosen.deinit(g.gpa);
        g.gpa.destroy(g.world);
        g.minimap.destroy(g.gpa);
        g.map.destroy(g.gpa);
    }

    /// A new game: this player's base, the view on it.
    pub fn newGame(g: *Game) void {
        g.world.* = .{ .map = g.map };
        g.world.addBase(me);
        g.chosen.clearRetainingCapacity();
        const b = map_mod.bases[me];
        g.camera.target = .{ b[0] + 4, view_height, b[1] + 4 };
        g.sent = null;
        g.keepViewOnMap();
    }

    pub fn startNew(g: *Game) void {
        g.newGame();
        g.started = true;
        g.menu_open = false;
    }

    pub fn closeMenu(g: *Game) void {
        g.menu_open = false;
        g.started = true;
    }

    pub fn openMenu(g: *Game) void {
        g.menu_open = true;
        g.press = null;
    }

    pub fn quit(g: *Game) void {
        g.quit_asked = true;
    }

    pub fn showMenuTab(g: *Game, i: usize) void {
        if (i < std.enums.values(MenuTab).len) g.menu_tab = @enumFromInt(i);
    }

    pub fn noteFps(g: *Game, fps: f32) void {
        std.mem.copyForwards(f32, g.fps_history[0 .. fps_seconds - 1], g.fps_history[1..]);
        g.fps_history[fps_seconds - 1] = fps;
        g.fps_count = @min(g.fps_count + 1, fps_seconds);
    }

    pub fn aspect(g: *const Game) f32 {
        return g.view_size[0] / @max(g.view_size[1], 1);
    }

    /// On by `dt` seconds: the world (but not behind the menu), and the
    /// view moved by the keys held.
    pub fn tick(g: *Game, dt: f32) void {
        if (g.menu_open) return;
        g.world.step(dt);
        var dx: f32 = 0;
        var dz: f32 = 0;
        if (g.keys.contains(.left) or g.keys.contains(.a)) dx -= 1;
        if (g.keys.contains(.right) or g.keys.contains(.d)) dx += 1;
        if (g.keys.contains(.up) or g.keys.contains(.w)) dz += 1;
        if (g.keys.contains(.down) or g.keys.contains(.s)) dz -= 1;
        if (dx != 0 or dz != 0) {
            const speed = g.camera.zoom * 1.4 * dt;
            g.following = false;
            g.moveView(.{ dx * speed, dz * speed });
        }
        if (g.following) g.follow(dt);
    }

    /// F: the view follows what is chosen (or stops following it).
    pub fn toggleFollowing(g: *Game) void {
        g.following = !g.following and g.chosenMiddle() != null;
    }

    /// The middle of what is chosen (across the ground), if anything is.
    pub fn chosenMiddle(g: *const Game) ?[2]f32 {
        if (g.chosen.items.len == 0) return null;
        var sum: [2]f32 = .{ 0, 0 };
        for (g.chosen.items) |i| {
            sum[0] += g.world.things[i].pos[0];
            sum[1] += g.world.things[i].pos[2];
        }
        const n: f32 = @floatFromInt(g.chosen.items.len);
        return .{ sum[0] / n, sum[1] / n };
    }

    /// The view moved `dt` seconds' worth towards what is chosen (gliding
    /// there, then keeping up with it), as far as it keeps to the map.
    fn follow(g: *Game, dt: f32) void {
        const to = g.chosenMiddle() orelse {
            g.following = false;
            return;
        };
        const k = 1 - @exp(-6 * dt);
        g.camera.target[0] += (to[0] - g.camera.target[0]) * k;
        g.camera.target[2] += (to[1] - g.camera.target[2]) * k;
        g.keepViewOnMap();
    }

    pub fn key(g: *Game, k: kete.KeyboardKey, pressed: bool) void {
        if (pressed) g.keys.insert(k) else g.keys.remove(k);
        if (k == .left_shift or k == .right_shift) g.shift = pressed;
        if (!pressed) return;
        if (k == .escape) {
            if (g.menu_open) g.closeMenu() else g.openMenu();
        }
        if (k == .f and !g.menu_open) g.toggleFollowing();
    }

    /// Where on the ground (at the view's middle's height) a point of the
    /// view (x and y from -1 to 1, y up) is, with the camera at `target`
    /// and `zoom`.
    fn groundOfView(g: *const Game, target: V3, zoom_: f32, x: f32, y: f32) [2]f32 {
        var c = g.camera;
        c.target = target;
        c.zoom = zoom_;
        const r = c.ray(g.aspect(), x, y);
        const t = (target[1] - r.origin[1]) / r.dir[1];
        const p = r.origin + r.dir * math.splat(t);
        return .{ p[0], p[2] };
    }

    /// Whether the view (its middle at `target`, at `zoom`) keeps to the
    /// map: the middle of each of the screen's edges over it (the map's
    /// edge can reach the screen's, not come in from it).
    pub fn viewFits(g: *const Game, target: V3, zoom_: f32) bool {
        for ([_][2]f32{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } }) |n| {
            const p = g.groundOfView(target, zoom_, n[0], n[1]);
            if (map_mod.inside(p[0], p[1]) < 0) return false;
        }
        return true;
    }

    /// The view put back on the map: zoomed in until it fits at the map's
    /// middle, and moved towards the middle until it fits where it is (as
    /// little as it need be, however far off the map it was).
    pub fn keepViewOnMap(g: *Game) void {
        const mid = V3{ map_mod.centre[0], view_height, map_mod.centre[1] };
        while (!g.viewFits(mid, g.camera.zoom) and g.camera.zoom > min_zoom) g.camera.zoom = @max(min_zoom, g.camera.zoom * 0.95);
        g.camera.target[1] = view_height;
        if (g.viewFits(g.camera.target, g.camera.zoom)) return;
        // Halfway, and halfway again, along the way to the middle: the
        // furthest from it that fits.
        const away = g.camera.target - mid;
        var fits: f32 = 0;
        var not: f32 = 1;
        for (0..24) |_| {
            const t = (fits + not) / 2;
            if (g.viewFits(mid + away * math.splat(t), g.camera.zoom)) fits = t else not = t;
        }
        g.camera.target = mid + away * math.splat(fits);
    }

    /// Moves the view's middle `by` blocks across the screen (right) and
    /// up it, on the ground; as far as the map's edge reaching the
    /// screen's (see `viewFits`), sliding along the edge rather than
    /// stopping at it.
    pub fn moveView(g: *Game, by: [2]f32) void {
        const r = g.camera.right();
        const f = math.normalize(.{ g.camera.forward()[0], 0, g.camera.forward()[2] });
        const step = r * math.splat(by[0]) + f * math.splat(by[1]);
        for ([_]V3{ step, r * math.splat(by[0]), f * math.splat(by[1]) }) |s| {
            var moved = g.camera.target + s;
            moved[1] = view_height;
            if (!g.viewFits(moved, g.camera.zoom)) continue;
            g.camera.target = moved;
            return;
        }
    }

    /// Moves the view's middle to (x, z), or as near as it keeps to the
    /// map.
    pub fn lookAt(g: *Game, p: [2]f32) void {
        g.following = false;
        g.camera.target = .{ p[0], view_height, p[1] };
        g.keepViewOnMap();
        g.view_jumped = true;
    }

    /// The ground at the view's corners (top left, top right, bottom
    /// right, bottom left): what is seen of it.
    pub fn viewCorners(g: *const Game) [4][2]f32 {
        var out: [4][2]f32 = undefined;
        for (&out, [4][2]f32{ .{ -1, 1 }, .{ 1, 1 }, .{ 1, -1 }, .{ -1, -1 } }) |*o, k| o.* = g.groundOfView(g.camera.target, g.camera.zoom, k[0], k[1]);
        return out;
    }

    pub fn panDown(g: *Game, p: kete.Point) void {
        g.pan = .{ .last = p, .moved = false };
    }

    /// The right button held and the pointer moved: the ground follows it.
    pub fn panMoved(g: *Game, p: kete.Point) void {
        const pan = &(g.pan orelse return);
        const dx = p[0] - pan.last[0];
        const dy = p[1] - pan.last[1];
        if (!pan.moved and @abs(dx) + @abs(dy) < drag_threshold) return;
        pan.moved = true;
        pan.last = p;
        g.following = false;
        // A pixel, in blocks across the screen; up it, the ground slants
        // away (seen from the camera's angle), so it is further.
        const per_pixel = 2 * g.camera.zoom / g.view_size[1];
        g.moveView(.{ -dx * per_pixel, dy * per_pixel / @sin(g.camera.pitch) });
    }

    /// The right button let go: true if it was a click (it did not move the
    /// view).
    pub fn panUp(g: *Game) bool {
        const pan = g.pan orelse return false;
        g.pan = null;
        return !pan.moved;
    }

    /// Zooms in (or out), as far out as the view still keeps to the map
    /// (moved towards its middle, near its edge, to keep to it).
    pub fn zoom(g: *Game, by: f32) void {
        g.camera.zoom = std.math.clamp(g.camera.zoom * by, min_zoom, max_zoom);
        g.keepViewOnMap();
    }

    // --- The mouse ----------------------------------------------------------------------

    /// Where (x and y from -1 to 1, y up) a point of the view is.
    fn ndc(g: *const Game, p: kete.Point) [2]f32 {
        return .{ p[0] / g.view_size[0] * 2 - 1, 1 - p[1] / g.view_size[1] * 2 };
    }

    /// Where on the view `p` (in the world) is, in its pixels.
    pub fn onView(g: *const Game, p: V3) kete.Point {
        const c = math.transform(g.camera.viewProjection(g.aspect()), p);
        return .{ (c[0] / c[3] + 1) / 2 * g.view_size[0], (1 - c[1] / c[3]) / 2 * g.view_size[1] };
    }

    /// The ground (or water) under a point of the view.
    pub fn groundAt(g: *const Game, p: kete.Point) ?V3 {
        const n = g.ndc(p);
        const r = g.camera.ray(g.aspect(), n[0], n[1]);
        return g.map.raycast(r.origin, r.dir);
    }

    /// The unit or building under a point of the view, if any: the nearest
    /// whose shape on the screen (a box round it, as tall as it is) has it.
    pub fn thingAt(g: *const Game, p: kete.Point) ?usize {
        var best: ?usize = null;
        var best_d: f32 = std.math.inf(f32);
        const per_block = g.view_size[1] / (2 * g.camera.zoom);
        for (g.world.things[0..g.world.count], 0..) |t, i| {
            const foot = g.onView(t.pos);
            const top = g.onView(t.pos + V3{ 0, t.kind.height(), 0 });
            const r = @max(t.kind.radius() * per_block, 10);
            if (p[0] < foot[0] - r or p[0] > foot[0] + r or p[1] > foot[1] + r * 0.6 or p[1] < top[1] - r * 0.3) continue;
            const mid = (foot[1] + top[1]) / 2;
            const d = @abs(p[0] - foot[0]) + @abs(p[1] - mid);
            if (d < best_d) {
                best_d = d;
                best = i;
            }
        }
        return best;
    }

    pub fn isChosen(g: *const Game, i: usize) bool {
        return std.mem.indexOfScalar(usize, g.chosen.items, i) != null;
    }

    /// The factory chosen, if one is (and nothing else is).
    pub fn chosenFactory(g: *const Game) ?usize {
        if (g.chosen.items.len != 1) return null;
        const i = g.chosen.items[0];
        return if (g.world.things[i].kind == .factory) i else null;
    }

    pub fn pointerDown(g: *Game, p: kete.Point) void {
        g.press = .{ .at = p, .now = p, .dragging = false };
    }

    /// A double click at `p`: if on one of this player's, all of its kind
    /// on the screen chosen (added to what is chosen, with Shift). False
    /// if not on one (then it is a click as any other).
    pub fn chooseAllLike(g: *Game, p: kete.Point) bool {
        const i = g.thingAt(p) orelse return false;
        const kind = g.world.things[i].kind;
        if (g.world.things[i].team != me) return false;
        if (!g.shift) g.chosen.clearRetainingCapacity();
        for (g.world.things[0..g.world.count], 0..) |t, k| {
            if (t.team != me or t.kind != kind or g.isChosen(k)) continue;
            const at = g.onView(t.pos);
            if (at[0] < 0 or at[1] < 0 or at[0] > g.view_size[0] or at[1] > g.view_size[1]) continue;
            g.chosen.append(g.gpa, k) catch {};
        }
        // (Its release is not a click.)
        g.press = null;
        return true;
    }

    pub fn pointerMoved(g: *Game, p: kete.Point) void {
        if (g.press) |*pr| {
            pr.now = p;
            if (@abs(p[0] - pr.at[0]) + @abs(p[1] - pr.at[1]) > drag_threshold) pr.dragging = true;
        }
    }

    pub fn pointerUp(g: *Game, p: kete.Point) void {
        const pr = g.press orelse return;
        g.press = null;
        if (pr.dragging) return g.chooseIn(pr.at, p);
        g.click(p);
    }

    /// The box being dragged, if one is: its corners on the view.
    pub fn dragBox(g: *const Game) ?[2]kete.Point {
        const pr = g.press orelse return null;
        if (!pr.dragging) return null;
        return .{ .{ @min(pr.at[0], pr.now[0]), @min(pr.at[1], pr.now[1]) }, .{ @max(pr.at[0], pr.now[0]), @max(pr.at[1], pr.now[1]) } };
    }

    pub fn click(g: *Game, p: kete.Point) void {
        if (g.thingAt(p)) |i| {
            const t = g.world.things[i];
            // Another player's: units chosen go to it.
            if (t.team != me) {
                if (g.hasUnitsChosen()) g.sendTo(t.pos);
                return;
            }
            if (g.shift) {
                if (std.mem.indexOfScalar(usize, g.chosen.items, i)) |at| {
                    _ = g.chosen.orderedRemove(at);
                } else g.chosen.append(g.gpa, i) catch {};
                return;
            }
            g.chosen.clearRetainingCapacity();
            g.chosen.append(g.gpa, i) catch {};
            return;
        }
        // The ground: units chosen go there; a factory chosen, its units
        // will.
        const at = g.groundAt(p) orelse return;
        if (g.hasUnitsChosen()) return g.sendTo(at);
        if (g.chosenFactory()) |f| {
            g.world.things[f].rally = .{ at[0], at[2] };
            g.sent = .{ .at = at, .time = g.world.time };
            return;
        }
        g.chosen.clearRetainingCapacity();
    }

    fn hasUnitsChosen(g: *const Game) bool {
        for (g.chosen.items) |i| if (!g.world.things[i].kind.isBuilding()) return true;
        return false;
    }

    fn sendTo(g: *Game, at: V3) void {
        g.world.moveTo(g.chosen.items, at[0], at[2]);
        g.sent = .{ .at = at, .time = g.world.time };
    }

    /// Chooses this player's units in the box from `a` to `b` (or, with
    /// Shift, adds them); a box with none chooses its buildings.
    fn chooseIn(g: *Game, a: kete.Point, b: kete.Point) void {
        const lo: kete.Point = .{ @min(a[0], b[0]), @min(a[1], b[1]) };
        const hi: kete.Point = .{ @max(a[0], b[0]), @max(a[1], b[1]) };
        if (!g.shift) g.chosen.clearRetainingCapacity();
        for ([2]bool{ false, true }) |buildings| {
            for (g.world.things[0..g.world.count], 0..) |t, i| {
                if (t.team != me or t.kind.isBuilding() != buildings) continue;
                const at = g.onView(t.pos + V3{ 0, t.kind.height() / 2, 0 });
                if (at[0] < lo[0] or at[0] > hi[0] or at[1] < lo[1] or at[1] > hi[1]) continue;
                if (!g.isChosen(i)) g.chosen.append(g.gpa, i) catch {};
            }
            if (g.chosen.items.len > 0) return;
        }
    }

    /// Lets go of what is chosen.
    pub fn letGo(g: *Game) void {
        g.chosen.clearRetainingCapacity();
    }

    // --- The factory's panel --------------------------------------------------------------

    pub fn enqueue(g: *Game, k: Kind) void {
        const f = g.chosenFactory() orelse return;
        _ = g.world.enqueue(f, k);
    }

    pub fn dequeue(g: *Game, k: Kind) void {
        const f = g.chosenFactory() orelse return;
        g.world.dequeue(f, k);
    }
};

const testing = std.testing;

fn testGame() !Game {
    var g = try Game.init(testing.allocator, 1);
    g.view_size = .{ 1280, 720 };
    g.closeMenu();
    return g;
}

test "clicking a unit chooses it, clicking the ground sends it there" {
    var g = try testGame();
    defer g.deinit();
    const walker = for (g.world.all(), 0..) |t, i| {
        if (t.kind == .walker) break i;
    } else unreachable;
    const at = g.onView(g.world.things[walker].pos + V3{ 0, 0.5, 0 });
    g.pointerDown(at);
    g.pointerUp(at);
    try testing.expectEqualSlices(usize, &.{walker}, g.chosen.items);
    // The ground a little way off, on the view.
    const there = g.world.things[walker].pos + V3{ 6, 0, -4 };
    const p = g.onView(.{ there[0], g.map.heightAt(there[0], there[2]), there[2] });
    g.pointerDown(p);
    g.pointerUp(p);
    const goal = g.world.things[walker].goal.?;
    try testing.expectApproxEqAbs(there[0], goal[0], 0.5);
    try testing.expectApproxEqAbs(there[2], goal[1], 0.5);
}

test "dragging a box chooses this player's units in it, not its buildings" {
    var g = try testGame();
    defer g.deinit();
    g.pointerDown(.{ 0, 0 });
    g.pointerMoved(.{ 1280, 720 });
    try testing.expect(g.dragBox() != null);
    g.pointerUp(.{ 1280, 720 });
    try testing.expect(g.chosen.items.len >= 4);
    for (g.chosen.items) |i| try testing.expect(!g.world.things[i].kind.isBuilding());
}

test "a factory chosen: its panel's buttons queue units" {
    var g = try testGame();
    defer g.deinit();
    const f = for (g.world.all(), 0..) |t, i| {
        if (t.kind == .factory) break i;
    } else unreachable;
    const at = g.onView(g.world.things[f].pos + V3{ 0, 1, 0 });
    g.pointerDown(at);
    g.pointerUp(at);
    try testing.expectEqual(@as(?usize, f), g.chosenFactory());
    g.enqueue(.drone);
    g.enqueue(.drone);
    try testing.expectEqual(@as(u32, 2), g.world.things[f].queuedOf(.drone));
    g.dequeue(.drone);
    try testing.expectEqual(@as(u32, 1), g.world.things[f].queuedOf(.drone));
}

test "dragging with the right button moves the view, the ground following the pointer" {
    var g = try testGame();
    defer g.deinit();
    // At the map's middle (room to move every way).
    g.camera.target = .{ map_mod.centre[0], view_height, map_mod.centre[1] };
    const before = g.camera.target;
    // A point of the ground, on the view, before.
    const ground = before + V3{ 3, 0, 2 };
    const was = g.onView(.{ ground[0], g.map.heightAt(ground[0], ground[2]), ground[2] });
    g.panDown(.{ 600, 400 });
    g.panMoved(.{ 700, 300 });
    g.panMoved(.{ 760, 330 });
    try testing.expect(!g.panUp());
    // The view moved; the same ground is as far along as the pointer.
    try testing.expect(math.length(g.camera.target - before) > 1);
    const now = g.onView(.{ ground[0], g.map.heightAt(ground[0], ground[2]), ground[2] });
    try testing.expectApproxEqAbs(was[0] + 160, now[0], 2);
    try testing.expectApproxEqAbs(was[1] - 70, now[1], 8);
    // A right-click without moving: a click.
    g.panDown(.{ 600, 400 });
    g.panMoved(.{ 602, 401 });
    try testing.expect(g.panUp());
}

test "a double click on a unit chooses all of its kind on the screen" {
    var g = try testGame();
    defer g.deinit();
    g.view_size = .{ 1280, 720 };
    g.closeMenu();
    // Two more walkers by the base, and one far off the screen.
    const b = map_mod.bases[me];
    _ = g.world.add(.{ .kind = .walker, .team = me, .pos = .{ b[0] + 2, 0, b[1] - 3 } }).?;
    const far = g.world.add(.{ .kind = .walker, .team = me, .pos = .{ b[0] + 120, 0, b[1] } }).?;
    var walker: ?usize = null;
    for (g.world.all(), 0..) |t, i| if (t.kind == .walker and i != far) {
        walker = i;
        break;
    };
    const at = g.onView(g.world.things[walker.?].pos + V3{ 0, 0.5, 0 });
    try testing.expect(g.chooseAllLike(at));
    var walkers: usize = 0;
    for (g.chosen.items) |i| {
        try testing.expectEqual(units.Kind.walker, g.world.things[i].kind);
        try testing.expect(i != far);
        walkers += 1;
    }
    try testing.expect(walkers >= 2);
    // The ground: not a double click on anything.
    try testing.expect(!g.chooseAllLike(.{ 5, 700 }));
}

test "F: the view follows what is chosen, until it is moved" {
    var g = try testGame();
    defer g.deinit();
    g.view_size = .{ 1280, 720 };
    g.closeMenu();
    // Nothing chosen: nothing to follow.
    g.key(.f, true);
    try testing.expect(!g.following);
    g.key(.f, false);
    for (g.world.all(), 0..) |t, i| if (!t.kind.isBuilding()) g.chosen.append(testing.allocator, i) catch {};
    g.key(.f, true);
    g.key(.f, false);
    try testing.expect(g.following);
    // Sent away: the view goes with them.
    g.sendTo(.{ map_mod.centre[0], 2, map_mod.centre[1] });
    for (0..60 * 20) |_| g.tick(1.0 / 60.0);
    const mid = g.chosenMiddle().?;
    try testing.expect(@abs(g.camera.target[0] - mid[0]) < 1 and @abs(g.camera.target[2] - mid[1]) < 1);
    // Moved by hand: no longer following.
    g.panDown(.{ 600, 400 });
    g.panMoved(.{ 700, 400 });
    _ = g.panUp();
    try testing.expect(!g.following);
    // F again, and again: on, then off.
    g.key(.f, true);
    g.key(.f, false);
    try testing.expect(g.following);
    g.key(.f, true);
    g.key(.f, false);
    try testing.expect(!g.following);
}

test "the view sent off the map (from the minimap's corner) is put back on it" {
    var g = try testGame();
    defer g.deinit();
    for ([_]f32{ 6, 14, max_zoom }) |z| {
        g.camera.zoom = z;
        for ([_][2]f32{ .{ -200, -200 }, .{ 700, 400 }, .{ 256, -150 }, .{ -40, 300 } }) |p| {
            g.lookAt(p);
            try testing.expect(g.viewFits(g.camera.target, g.camera.zoom));
            // As far towards it as it can go: the edge reaching the screen's.
            const towards = math.normalize(V3{ p[0], view_height, p[1] } - g.camera.target);
            try testing.expect(!g.viewFits(g.camera.target + towards * math.splat(1), g.camera.zoom));
        }
    }
}

test "the view keeps to the map: its edge can reach the screen's, not come in from it" {
    var g = try testGame();
    defer g.deinit();
    for ([_][2]f32{ .{ 1920, 1080 }, .{ 640, 400 }, .{ 1024, 768 } }) |size| {
        g.view_size = size;
        g.camera.zoom = max_zoom;
        g.keepViewOnMap();
        try testing.expect(g.viewFits(g.camera.target, g.camera.zoom));
        // Pushed hard each way: still on it, and as far as it goes.
        for ([_][2]f32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 }, .{ 0.7, 0.7 } }) |d| {
            for (0..400) |_| g.moveView(.{ d[0], d[1] });
            try testing.expect(g.viewFits(g.camera.target, g.camera.zoom));
            // The screen's corners on the ground (which reaches past the
            // map's edge: see map.zig's margins).
            const first = Map.at(0, 0);
            const last = Map.at(map_mod.cols - 1, map_mod.rows - 1);
            for ([_][2]f32{ .{ -1, -1 }, .{ 1, -1 }, .{ -1, 1 }, .{ 1, 1 } }) |c| {
                const p = g.groundOfView(g.camera.target, g.camera.zoom, c[0], c[1]);
                try testing.expect(p[0] > first[0] + 1 and p[0] < last[0] - 1);
                try testing.expect(p[1] > first[1] + 1 and p[1] < last[1] - 1);
            }
        }
    }
}
