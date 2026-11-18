//! Playing: the world, the camera, what is chosen, and what the mouse and
//! keys do.
//!
//! - Clicking a unit or building chooses it (with Shift, adds it, or
//!   takes it out); dragging a box chooses the units in it.
//! - With units chosen, clicking the ground sends them there.
//! - A factory chosen, its panel queues units to make.
//! - The arrow keys (or W, A, S, D) move the view, the wheel zooms it.
//! - Esc opens the menu (the game starts in it); right-clicking lets go of
//!   what is chosen.

const std = @import("std");
const kete = @import("kete");
const math = @import("math.zig");
const map_mod = @import("map.zig");
const units = @import("units.zig");

const V3 = math.V3;
const Map = map_mod.Map;
const World = units.World;
const Kind = units.Kind;

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
    camera: math.Camera,
    /// What is chosen: indices into the world's things.
    chosen: std.ArrayList(usize) = .empty,
    /// The view's size, in its pixels (for picking).
    view_size: [2]f32 = .{ 1, 1 },
    /// A button down at (where, and whether it has become a drag).
    press: ?struct { at: kete.Point, now: kete.Point, dragging: bool } = null,
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
        const m = try gpa.create(Map);
        errdefer gpa.destroy(m);
        m.generate(seed);
        const w = try gpa.create(World);
        w.* = .{ .map = m };
        var g: Game = .{ .gpa = gpa, .map = m, .world = w, .camera = .{ .target = .{ 0, 0, 0 } } };
        g.newGame();
        return g;
    }

    pub fn deinit(g: *Game) void {
        g.chosen.deinit(g.gpa);
        g.gpa.destroy(g.world);
        g.gpa.destroy(g.map);
    }

    /// A new game: this player's base, the view on it.
    pub fn newGame(g: *Game) void {
        g.world.* = .{ .map = g.map };
        g.world.addBase(me);
        g.chosen.clearRetainingCapacity();
        const b = map_mod.bases[me];
        g.camera.target = .{ b[0] + 4, g.map.heightAt(b[0], b[1]), b[1] + 4 };
        g.sent = null;
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
            // Across the screen and up it, on the ground.
            const r = g.camera.right();
            const f = math.normalize(.{ g.camera.forward()[0], 0, g.camera.forward()[2] });
            const speed = g.camera.zoom * 1.4 * dt;
            const moved = g.camera.target + (r * math.splat(dx) + f * math.splat(dz)) * math.splat(speed);
            // Over the map (its hexagon), a little in from its edge (the
            // ground past it is there to the edge of the view).
            if (map_mod.inside(moved[0], moved[2]) > 6) g.camera.target = moved;
            g.camera.target[1] = g.map.surfaceAt(g.camera.target[0], g.camera.target[2]);
        }
    }

    pub fn key(g: *Game, k: kete.KeyboardKey, pressed: bool) void {
        if (pressed) g.keys.insert(k) else g.keys.remove(k);
        if (k == .left_shift or k == .right_shift) g.shift = pressed;
        if (!pressed) return;
        if (k == .escape) {
            if (g.menu_open) g.closeMenu() else g.openMenu();
        }
    }

    pub fn zoom(g: *Game, by: f32) void {
        // No further out than the ground past the map reaches.
        g.camera.zoom = std.math.clamp(g.camera.zoom * by, 6, 24);
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
