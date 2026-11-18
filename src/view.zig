//! The window, as widgets: the battlefield filling it (drawn straight into
//! the frame by the renderer), and over it the resources, the box being
//! dragged, what is chosen (a factory's panel to queue units), and the
//! menu (Esc), which the game starts in.

const std = @import("std");
const kete = @import("kete");
const gfx = kete.gfx;
const vc4 = @import("vc4");
const game_mod = @import("game.zig");
const units = @import("units.zig");
const minimap = @import("minimap.zig");
const sky = @import("sky.zig");
const fog_mod = @import("fog.zig");
const font = kete.font;

const Game = game_mod.Game;
const math = @import("math.zig");
const Kind = units.Kind;

pub const min_size = [2]u32{ 640, 400 };
pub const open_size = [2]u32{ 1280, 720 };

const panel_bg = gfx.Color.argb(0xd8182232);
const button_size = 40;

/// Draws the battlefield into the frame.
pub const Draw = struct {
    ctx: *anyopaque,
    f: *const fn (ctx: *anyopaque, frame: *vc4.render.Frame, area: kete.gfx.GpuArea) anyerror!void,
};

pub const Overrun = struct {
    game: *Game,
    /// How to draw the battlefield (none in tests).
    draw: ?Draw = null,

    pub fn build(self: *const Overrun, cx: *kete.BuildContext) kete.Widget {
        const g = self.game;
        const a = cx.arena;
        var layers: std.ArrayList(kete.Widget) = .empty;
        layers.append(a, cx.make(Battlefield{ .game = g, .draw = self.draw })) catch {};
        if (g.dragBox() != null) layers.append(a, cx.make(DragBox{ .game = g })) catch {};
        layers.append(a, cx.make(kete.Align{ .alignment = .top_left, .child = cx.make(kete.Padding{ .padding = .all(12), .child = resources(cx, g) }) })) catch {};
        if (!g.menu_open) layers.append(a, cx.make(kete.Align{ .alignment = .top_right, .child = cx.make(kete.Padding{ .padding = .all(12), .child = cx.make(Minimap{ .game = g }) }) })) catch {};
        if (!g.menu_open and g.following) layers.append(a, cx.make(kete.Align{ .alignment = .top_center, .child = cx.make(kete.Padding{ .padding = .all(12), .child = cx.make(kete.RoundedBox{ .color = panel_bg, .radius = .all(10), .child = cx.make(kete.Padding{ .padding = .{ .left = 14, .top = 6, .right = 14, .bottom = 6 }, .child = label(cx, "Following (F to stop)", 15) }) }) }) })) catch {};
        if (!g.menu_open) if (chosenPanel(cx, g)) |p| layers.append(a, cx.make(kete.Align{ .alignment = .bottom_center, .child = cx.make(kete.Padding{ .padding = .all(14), .child = p }) })) catch {};
        if (g.menu_open) {
            layers.append(a, cx.make(kete.Align{ .alignment = .center, .child = menu(cx, g) })) catch {};
            layers.append(a, cx.make(kete.Align{
                .alignment = .top_right,
                .child = cx.make(kete.Padding{ .padding = .{ .top = 12, .right = 12 }, .child = windowButtons(cx, g) }),
            })) catch {};
        }
        return cx.make(kete.Overlay{ .children = layers.items });
    }
};

fn label(cx: *kete.BuildContext, text: []const u8, size: f32) kete.Widget {
    return cx.make(kete.Text{ .text = text, .style = .{ .size = size, .color = gfx.Color.argb(0xffffffff) }, .wrap = false });
}

/// The weather, and whether it is day or night, as an icon.
fn weatherIcon(g: *const Game) @FieldType(kete.Icon, "icon") {
    const t = g.world.time;
    return switch (sky.kindAt(g.map.seed, t)) {
        .clear => if (sky.isNight(t)) .nights_stay else .wb_sunny,
        .cloudy => .cloud,
        .rain => .water_drop,
        .storm => .thunderstorm,
    };
}

/// This player's metal and energy, and the weather, top left.
fn resources(cx: *kete.BuildContext, g: *Game) kete.Widget {
    const r = g.world.resources[game_mod.me];
    return cx.make(kete.RoundedBox{ .color = panel_bg, .radius = .all(10), .child = cx.make(kete.Padding{ .padding = .{ .left = 12, .top = 6, .right = 12, .bottom = 6 }, .child = cx.make(kete.Row{
        .fill = false,
        .spacing = 18,
        .cross_axis_alignment = .center,
        .children = cx.arena.dupe(kete.Widget, &.{
            cx.make(kete.Icon{ .icon = .construction, .size = 20, .color = gfx.Color.argb(0xffc8ccd2) }),
            counter(cx, r.metal),
            cx.make(kete.Icon{ .icon = .bolt, .size = 20, .color = gfx.Color.argb(0xffffd25a) }),
            counter(cx, r.energy),
            cx.make(kete.Icon{ .icon = weatherIcon(g), .size = 20, .color = gfx.Color.argb(if (sky.isNight(g.world.time)) 0xff9fb4ff else 0xffe8eef6) }),
        }) catch &.{},
    }) }) });
}

/// A resource's amount, in a box as wide as five figures (so what is
/// after it stays put as it changes), to its right.
fn counter(cx: *kete.BuildContext, amount: f32) kete.Widget {
    return cx.make(kete.SizedBox{ .width = counter_width, .height = 24, .child = cx.make(kete.Align{
        .alignment = .center_right,
        .child = label(cx, cx.fmt("{d:.0}", .{@min(amount, 99999)}), 18),
    }) });
}

/// Wide enough for "99999".
const counter_width = 56;

/// What is chosen, at the bottom: a factory's panel (what it makes), the
/// builders' (what they build), or how many units.
fn chosenPanel(cx: *kete.BuildContext, g: *Game) ?kete.Widget {
    const a = cx.arena;
    if (g.chosenFactory()) |fi| {
        const f = g.world.things[fi];
        var cells: std.ArrayList(kete.Widget) = .empty;
        for (units.buildable) |k| {
            const q = a.create(Queue) catch continue;
            q.* = .{ .game = g, .kind = k };
            const n = f.queuedOf(k);
            const making = f.making() == k;
            const note = if (n == 0) "" else if (making) cx.fmt("{d} queued, {d:.0}%", .{ n, f.progress * 100 }) else cx.fmt("{d} queued", .{n});
            cells.append(a, kindCell(cx, k, n > 0, making, note, .of(q, Queue.add))) catch {};
        }
        return panel(cx, "Factory: click to queue, right-click to take one out", cells.items);
    }
    if (g.chosenSilo()) |si| {
        const s = g.world.things[si];
        const q = a.create(SiloButton) catch return null;
        q.* = .{ .game = g };
        const note = if (g.targeting != null) "Aiming" else if (s.armed) "Ready: click to aim" else if (s.queued > 0) cx.fmt("Building, {d:.0}%", .{s.progress * 100}) else "Click to build";
        const cells = a.dupe(kete.Widget, &.{kindCell(cx, .missile, s.armed or s.queued > 0, g.targeting != null, note, .of(q, SiloButton.press))}) catch return null;
        return panel(cx, if (g.targeting != null) "Click where to send it (here, or on the minimap); right-click to stop" else "Missile silo: one missile at a time", cells);
    }
    if (g.buildersChosen()) {
        var cells: std.ArrayList(kete.Widget) = .empty;
        for (units.constructible) |k| {
            const q = a.create(Place) catch continue;
            q.* = .{ .game = g, .kind = k };
            const placing = g.placing == k;
            cells.append(a, kindCell(cx, k, placing, placing, if (placing) "Click where" else "", .of(q, Place.start))) catch {};
        }
        return panel(cx, if (g.placing != null) "Click where to build (Shift for more), right-click to stop" else "Builder: choose what to build", cells.items);
    }
    if (g.chosen.items.len == 0) return null;
    const t = g.world.things[g.chosen.items[0]];
    const text = if (g.chosen.items.len == 1) t.kind.name() else cx.fmt("{d} chosen", .{g.chosen.items.len});
    return cx.make(kete.RoundedBox{ .color = panel_bg, .radius = .all(10), .child = cx.make(kete.Padding{ .padding = .{ .left = 14, .top = 8, .right = 14, .bottom = 8 }, .child = label(cx, text, 16) }) });
}

/// A panel of cells, under a title: four to a row.
fn panel(cx: *kete.BuildContext, title: []const u8, cells: []const kete.Widget) kete.Widget {
    const a = cx.arena;
    var rows: std.ArrayList(kete.Widget) = .empty;
    rows.append(a, label(cx, title, 14)) catch {};
    var i: usize = 0;
    while (i < cells.len) : (i += 4) {
        rows.append(a, cx.make(kete.Row{ .fill = false, .spacing = 8, .children = cells[i..@min(i + 4, cells.len)] })) catch {};
    }
    return cx.make(kete.RoundedBox{ .color = panel_bg, .radius = .all(12), .child = cx.make(kete.Padding{ .padding = .all(10), .child = cx.make(kete.Column{ .fill = false, .spacing = 8, .children = rows.items }) }) });
}

/// A kind to make or build: its icon, name and cost, and a note; `on`
/// (queued, or being placed) lighter, `active` (being made) outlined.
fn kindCell(cx: *kete.BuildContext, k: Kind, on: bool, active: bool, note: []const u8, press: kete.Callback) kete.Widget {
    const a = cx.arena;
    const c = k.cost();
    return cx.make(kete.Pressable{ .on_press = press, .child = cx.make(kete.RoundedBox{
        .color = gfx.Color.argb(if (on) 0xcc303848 else 0x99000000),
        .border_width = if (active) 2 else 1,
        .border_color = gfx.Color.argb(if (active) 0xffffd25a else 0x66ffffff),
        .radius = .all(8),
        .child = cx.make(kete.SizedBox{ .width = 104, .child = cx.make(kete.Padding{ .padding = .all(7), .child = cx.make(kete.Column{ .fill = false, .spacing = 2, .cross_axis_alignment = .start, .children = a.dupe(kete.Widget, &.{
            cx.make(kete.Row{ .fill = false, .spacing = 4, .children = a.dupe(kete.Widget, &.{
                cx.make(kete.Icon{ .icon = iconOf(k), .size = 18, .color = gfx.Color.argb(0xffffffff) }),
                label(cx, k.shortName(), 13),
            }) catch &.{} }),
            cx.make(kete.Row{ .fill = false, .spacing = 3, .cross_axis_alignment = .center, .children = a.dupe(kete.Widget, &.{
                cx.make(kete.Icon{ .icon = .construction, .size = 12, .color = gfx.Color.argb(0xffc8ccd2) }),
                label(cx, cx.fmt("{d:.0}", .{c.metal}), 12),
                cx.make(kete.Icon{ .icon = .bolt, .size = 12, .color = gfx.Color.argb(0xffffd25a) }),
                label(cx, cx.fmt("{d:.0}", .{c.energy}), 12),
            }) catch &.{} }),
            label(cx, note, 12),
        }) catch &.{} }) }) }),
    }) });
}

// The icons chosen at run time (`iconOf`, and the window buttons').
comptime {
    _ = &[_]kete.IconName{ .rocket, .rocket_launch, .my_location, .local_airport, .airplanemode_active, .radar, .front_loader, .flight_takeoff, .bolt, .diamond, .security, .factory, .wb_sunny, .nights_stay, .cloud, .water_drop, .thunderstorm, .smart_toy, .local_shipping, .flight, .construction, .fullscreen, .fullscreen_exit, .close };
}

fn iconOf(k: Kind) @FieldType(kete.Icon, "icon") {
    return switch (k) {
        .walker => .smart_toy,
        .tank => .local_shipping,
        .drone => .flight,
        .builder => .front_loader,
        .air_builder => .flight_takeoff,
        .bomber => .local_airport,
        .fighter => .airplanemode_active,
        .flak => .radar,
        .missile => .rocket,
        .silo => .rocket_launch,
        .power => .bolt,
        .mine => .diamond,
        .tower => .security,
        .factory => .factory,
    };
}

/// A factory's button: clicked, one more queued; right-clicked, one fewer.
const Queue = struct {
    game: *Game,
    kind: Kind,

    fn add(q: *Queue) void {
        q.game.enqueue(q.kind);
    }
};

/// A silo's button: its missile built, or aimed.
const SiloButton = struct {
    game: *Game,

    fn press(q: *SiloButton) void {
        q.game.siloPressed();
    }
};

/// A builders' button: clicked, that building is placed next.
const Place = struct {
    game: *Game,
    kind: Kind,

    fn start(q: *Place) void {
        q.game.startPlacing(q.kind);
    }
};

/// The box being dragged, over the battlefield.
const DragBox = struct {
    game: *Game,

    pub fn layout(_: *const DragBox, _: *kete.WidgetNode, c: kete.Constraints) kete.Size {
        return c.biggest();
    }

    pub fn paint(self: *const DragBox, _: *kete.WidgetNode, p: *kete.Painter) void {
        const box = self.game.dragBox() orelse return;
        const r: kete.Rect = .{ .x = box[0][0], .y = box[0][1], .w = box[1][0] - box[0][0], .h = box[1][1] - box[0][1] };
        var c = p.canvas();
        c.fillRect(r, gfx.Color.argb(0x2238c26a));
        c.strokeRoundedRect(r, .all(0), 1.5, gfx.Color.argb(0xcc5ef08a));
    }
};

/// The minimap: the map's hexagon, the units and buildings on it, and the
/// view's outline; pressed (or dragged on), the view goes there. It is
/// turned as the view is (the view's up, up it), so what the view shows
/// is upright on it.
const Minimap = struct {
    game: *Game,

    /// Room round the hexagon (for its border, and the view's outline
    /// past its edge).
    const pad = 8;
    /// Across and down: the hexagon, turned any way, fits.
    const side: f32 = minimap.width + 2 * pad;

    pub fn layout(_: *const Minimap, _: *kete.WidgetNode, c: kete.Constraints) kete.Size {
        return c.constrain(.{ .w = side, .h = side });
    }

    /// The minimap's picture's pixel `p`, turned: where it is on the
    /// widget.
    fn turned(self: *const Minimap, p: [2]f32) kete.Point {
        const yaw = self.game.camera.yaw;
        const mid = minimap.toPixel(map_centre);
        const v = [2]f32{ p[0] - mid[0], p[1] - mid[1] };
        return .{ side / 2 + v[0] * @cos(yaw) + v[1] * @sin(yaw), side / 2 - v[0] * @sin(yaw) + v[1] * @cos(yaw) };
    }

    /// Where on the map (x, z) a point of the widget is.
    fn mapAt(self: *const Minimap, w: kete.Point) [2]f32 {
        const yaw = self.game.camera.yaw;
        const mid = minimap.toPixel(map_centre);
        const v = [2]f32{ w[0] - side / 2, w[1] - side / 2 };
        return minimap.fromPixel(.{ mid[0] + v[0] * @cos(yaw) - v[1] * @sin(yaw), mid[1] + v[0] * @sin(yaw) + v[1] * @cos(yaw) });
    }

    fn at(self: *const Minimap, p: [2]f32) kete.Point {
        return self.turned(minimap.toPixel(p));
    }

    pub fn paint(self: *const Minimap, _: *kete.WidgetNode, p: *kete.Painter) void {
        const g = self.game;
        var c = p.canvas();
        // A border round the hexagon.
        var hex: [6]kete.Point = undefined;
        for (&hex, minimap.hexagon()) |*h, k| {
            const q = self.turned(k);
            const out = [2]f32{ q[0] - side / 2, q[1] - side / 2 };
            const len = @sqrt(out[0] * out[0] + out[1] * out[1]);
            h.* = .{ q[0] + out[0] / len * 4, q[1] + out[1] / len * 4 };
        }
        c.fillPolygon(&hex, panel_bg);
        // The picture, turned: two triangles.
        const w: f32 = minimap.width;
        const h: f32 = @floatFromInt(minimap.height);
        var quad: [4][4]f32 = undefined;
        for (&quad, [4][2]f32{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 } }) |*q, uv| {
            const at_ = self.turned(.{ uv[0] * w, uv[1] * h });
            q.* = .{ at_[0], at_[1], uv[0], uv[1] };
        }
        c.drawImageTriangles(&g.minimap.image, &.{ quad[0], quad[1], quad[2], quad[0], quad[2], quad[3] }, 1);
        // The fog of war over it.
        g.minimap.setFog(g.fog);
        var fog: [4][4]f32 = undefined;
        for (&fog, [4][2]f32{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 } }) |*q, uv| {
            const at_ = self.at(.{ fog_mod.origin + uv[0] * fog_mod.span, fog_mod.origin + uv[1] * fog_mod.span });
            q.* = .{ at_[0], at_[1], uv[0], uv[1] };
        }
        c.drawImageTriangles(&g.minimap.fog_image, &.{ fog[0], fog[1], fog[2], fog[0], fog[2], fog[3] }, 1);
        // The units (small) and buildings (larger), in their teams' colours:
        // others' only where they can be seen.
        for (g.world.all()) |t| {
            if (!g.canSee(t)) continue;
            const q = self.at(.{ t.pos[0], t.pos[2] });
            const s: f32 = if (t.kind.isBuilding()) 4 else 2.5;
            c.fillRect(.{ .x = q[0] - s / 2, .y = q[1] - s / 2, .w = s, .h = s }, gfx.Color.rgb(units.team_colours[t.team]));
        }
        // What the view shows (upright).
        var view: [4]kete.Point = undefined;
        for (&view, g.viewCorners()) |*v, k| v.* = self.at(k);
        c.strokePolyline(&view, true, 1.5, gfx.Color.argb(0xeeffffff));
    }

    pub fn event(self: *const Minimap, _: *kete.WidgetNode, e: kete.Event) bool {
        const g = self.game;
        switch (e) {
            .press => |pr| if (pr.button == .left) {
                // Aiming a missile: sent there.
                if (g.targeting != null) {
                    g.launchAt(self.mapAt(pr.pos));
                    return true;
                }
                g.minimap_held = true;
                g.lookAt(self.mapAt(pr.pos));
                return true;
            },
            .motion => |pos| if (g.minimap_held) {
                g.lookAt(self.mapAt(pos));
                return true;
            },
            .release => |r| if (r.button == .left) {
                g.minimap_held = false;
                return true;
            },
            else => {},
        }
        return false;
    }
};

const map_centre = @import("map.zig").centre;

/// The battlefield, drawn by the renderer; the mouse's presses on it are
/// the game's.
const Battlefield = struct {
    game: *Game,
    draw: ?Draw,

    pub fn layout(self: *const Battlefield, _: *kete.WidgetNode, c: kete.Constraints) kete.Size {
        const size = c.biggest();
        self.game.view_size = .{ size.w, size.h };
        return size;
    }

    pub fn paint(self: *const Battlefield, _: *kete.WidgetNode, p: *kete.Painter) void {
        if (self.draw != null) p.gpu(self, drawWorld);
    }

    fn drawWorld(self: *const Battlefield, frame: *vc4.render.Frame, area: kete.gfx.GpuArea) anyerror!void {
        const d = self.draw.?;
        try d.f(d.ctx, frame, area);
    }

    pub fn event(self: *const Battlefield, _: *kete.WidgetNode, e: kete.Event) bool {
        const g = self.game;
        if (g.menu_open) return false;
        switch (e) {
            .press => |pr| switch (pr.button) {
                .left => {
                    // A double click on a unit: all of its kind on the
                    // screen.
                    if (pr.clicks >= 2 and g.chooseAllLike(pr.pos)) return true;
                    g.pointerDown(pr.pos);
                    return true;
                },
                .right => {
                    // Dragging moves the view; a click is seen on release.
                    g.panDown(pr.pos);
                    return true;
                },
                else => return false,
            },
            .motion => |pos| {
                g.pointerMoved(pos);
                g.panMoved(pos);
            },
            .release => |r| switch (r.button) {
                .left => {
                    g.pointerUp(r.pos);
                    return true;
                },
                .right => {
                    // A right-click (not a drag): placing a building
                    // stopped, a factory's last queued taken out, or what
                    // is chosen let go of.
                    if (!g.panUp()) return true;
                    if (g.placing != null or g.targeting != null) {
                        g.placing = null;
                        g.targeting = null;
                        return true;
                    }
                    if (g.chosenFactory()) |f| {
                        if (g.world.things[f].queued > 0) {
                            g.dequeue(g.world.things[f].queue[g.world.things[f].queued - 1]);
                            return true;
                        }
                    }
                    g.letGo();
                    return true;
                },
                else => {},
            },
            .scroll => |s| {
                g.zoom(if (s.dy > 0) 1.12 else 1.0 / 1.12);
                return true;
            },
            // (Not taken as a context menu's: the right button's press
            // comes next, which moves the view.)
            else => {},
        }
        return false;
    }
};

/// Fullscreen and quit, top right (with the menu).
fn windowButtons(cx: *kete.BuildContext, g: *Game) kete.Widget {
    const a = cx.arena;
    const window = cx.window();
    const full = if (window) |w| w.isFullscreen() else false;
    const round = struct {
        fn f(c: *kete.BuildContext, icon: @FieldType(kete.IconButton, "icon"), on: ?kete.Callback) kete.Widget {
            return c.make(kete.RoundedBox{ .color = panel_bg, .radius = .all(@as(f32, button_size) / 2), .child = c.make(kete.IconButton{ .size = button_size, .icon = icon, .on_press = on }) });
        }
    }.f;
    return cx.make(kete.Row{ .fill = false, .spacing = 8, .children = a.dupe(kete.Widget, &.{
        round(cx, if (full) .fullscreen_exit else .fullscreen, if (window) |w| kete.Callback.of(w, toggleFullscreen) else null),
        round(cx, .close, .of(g, Game.quit)),
    }) catch &.{} });
}

fn toggleFullscreen(w: *kete.App.Window) void {
    w.setFullscreen(!w.isFullscreen());
}

const menu_tabs = [_]kete.Tab{ .{ .label = "Game" }, .{ .label = "Play together" }, .{ .label = "Settings" } };
const menu_width = 520;

/// The menu, over the battlefield: tabs for the game, playing together and
/// the settings, and a close button (as Esc).
fn menu(cx: *kete.BuildContext, g: *Game) kete.Widget {
    const t = cx.theme();
    const a = cx.arena;
    const content = switch (g.menu_tab) {
        .game => gameTab(cx, g),
        .play => cx.make(kete.Text{ .text = "Up to four players on the same network: coming soon.", .style = .{ .size = t.body_size, .color = t.on_surface_variant } }),
        .settings => settingsTab(cx, g),
    };
    return cx.make(kete.RoundedBox{ .color = gfx.Color.argb(0xe0202024), .radius = .all(16), .child = cx.make(kete.Padding{ .padding = .{ .left = 20, .top = 12, .right = 12, .bottom = 20 }, .child = cx.make(kete.Column{
        .fill = false,
        .spacing = 12,
        .children = a.dupe(kete.Widget, &.{
            cx.make(kete.SizedBox{ .width = menu_width + 8, .child = cx.make(kete.Row{ .children = a.dupe(kete.Widget, &.{
                cx.make(kete.Text{ .text = "Overrun", .style = .{ .size = 22, .color = t.primary }, .wrap = false }),
                cx.make(kete.Expanded{ .child = cx.make(kete.SizedBox.empty) }),
                cx.make(kete.IconButton{ .icon = .close, .size = 36, .on_press = .of(g, Game.closeMenu) }),
            }) catch &.{} }) }),
            cx.make(kete.SizedBox{ .width = menu_width, .child = cx.make(kete.TabBar{ .tabs = &menu_tabs, .selected = @intFromEnum(g.menu_tab), .on_select = .of(g, Game.showMenuTab) }) }),
            cx.make(kete.SizedBox{ .width = menu_width, .height = 160, .child = content }),
        }) catch &.{},
    }) }) });
}

fn gameTab(cx: *kete.BuildContext, g: *Game) kete.Widget {
    const t = cx.theme();
    const a = cx.arena;
    return cx.make(kete.Column{ .fill = false, .spacing = 12, .cross_axis_alignment = .start, .children = a.dupe(kete.Widget, &.{
        cx.make(kete.Text{ .text = "Build an army at your factory and send it across the battlefield. Drag to choose units; click to send them.", .style = .{ .size = t.body_size, .color = t.on_surface_variant } }),
        cx.make(kete.Row{ .fill = false, .spacing = 8, .children = a.dupe(kete.Widget, &.{
            cx.make(kete.FilledButton{ .label = if (g.started) "Go on" else "Play", .on_press = .of(g, Game.closeMenu) }),
            cx.make(kete.OutlinedButton{ .label = "New game", .on_press = .of(g, Game.startNew) }),
        }) catch &.{} }),
    }) catch &.{} });
}

fn settingsTab(cx: *kete.BuildContext, g: *Game) kete.Widget {
    const t = cx.theme();
    const n = g.fps_count;
    const now: f32 = if (n > 0) g.fps_history[game_mod.fps_seconds - 1] else 0;
    return cx.make(kete.Column{ .fill = false, .spacing = 8, .cross_axis_alignment = .stretch, .children = cx.arena.dupe(kete.Widget, &.{
        cx.make(kete.Text{ .text = if (n > 0) cx.fmt("{d:.0} frames a second", .{now}) else "Frames a second", .style = .{ .size = t.body_size - 1, .color = t.on_surface_variant }, .wrap = false }),
        cx.make(FpsGraph{ .history = g.fps_history[game_mod.fps_seconds - n ..] }),
    }) catch &.{} });
}

/// The frame rate over the last seconds, a bar a second (the newest on the
/// right): green where it was good, yellow all right, red slow.
const FpsGraph = struct {
    history: []const f32,

    pub fn layout(_: *const FpsGraph, _: *kete.WidgetNode, c: kete.Constraints) kete.Size {
        return c.constrain(.{ .w = if (std.math.isFinite(c.max_w)) c.max_w else 300, .h = 56 });
    }

    pub fn paint(self: *const FpsGraph, n: *kete.WidgetNode, p: *kete.Painter) void {
        const c = p.canvas();
        const w = n.size.w;
        const h = n.size.h;
        c.fillRoundedRect(.{ .x = 0, .y = 0, .w = w, .h = h }, .all(6), gfx.Color.argb(0x22ffffff));
        const slot = w / game_mod.fps_seconds;
        for (self.history, 0..) |fps, i| {
            const bh = @max(2, @min(fps / 60, 1) * (h - 4));
            const x = w - @as(f32, @floatFromInt(self.history.len - i)) * slot;
            c.fillRect(.{ .x = x + 1, .y = h - 2 - bh, .w = slot - 2, .h = bh }, gfx.Color.argb(if (fps >= 50) 0xff4caf50 else if (fps >= 30) 0xffffc107 else 0xfff44336));
        }
    }
};

const testing = std.testing;

test "the view fits, menu or not, from the smallest window up" {
    const f = try font.Font.init(@embedFile("FiraSans-Regular.ttf"));
    const u = try kete.ui.WindowUi.create(testing.allocator, testing.io, &f);
    defer u.destroy();
    var g = try Game.init(testing.allocator, 1);
    defer g.deinit();
    const view: Overrun = .{ .game = &g };
    for ([_]bool{ true, false }) |menu_open| {
        g.menu_open = menu_open;
        // With the factory chosen, and with a builder (their panels the
        // widest things).
        for ([_]Kind{ .factory, .builder }) |k| {
            g.chosen.clearRetainingCapacity();
            if (k == .builder) _ = g.world.add(.{ .kind = .builder, .team = game_mod.me, .pos = .{ 100, 0, 100 } });
            for (g.world.all(), 0..) |t, i| if (t.kind == k) g.chosen.append(testing.allocator, i) catch {};
            for ([_][2]u32{ min_size, open_size }) |size| {
                u.frame(size[0], size[1], 0, view);
                try testing.expect(!overflows(u.root.?));
            }
        }
    }
}

test "dragging with the right button moves the view" {
    const f = try font.Font.init(@embedFile("FiraSans-Regular.ttf"));
    const u = try kete.ui.WindowUi.create(testing.allocator, testing.io, &f);
    defer u.destroy();
    var g = try Game.init(testing.allocator, 1);
    defer g.deinit();
    g.closeMenu();
    const view: Overrun = .{ .game = &g };
    u.frame(1280, 720, 0, view);
    const before = g.camera.target;
    u.pointerMotion(.{ 640, 360 });
    u.pointerButton(.{ 640, 360 }, .right, true);
    for (1..10) |i| u.pointerMotion(.{ 640 + @as(f32, @floatFromInt(i)) * 20, 360 });
    u.pointerButton(.{ 820, 360 }, .right, false);
    try testing.expect(math.length(g.camera.target - before) > 1);
}

test "pressing the minimap moves the view there" {
    const f = try font.Font.init(@embedFile("FiraSans-Regular.ttf"));
    const u = try kete.ui.WindowUi.create(testing.allocator, testing.io, &f);
    defer u.destroy();
    var g = try Game.init(testing.allocator, 1);
    defer g.deinit();
    g.closeMenu();
    const view: Overrun = .{ .game = &g };
    u.frame(1280, 720, 0, view);
    // The minimap's middle (top right): the map's.
    const mid: kete.Point = .{ 1280 - 12 - Minimap.side / 2, 12 + Minimap.side / 2 };
    u.pointerMotion(mid);
    u.pointerButton(mid, .left, true);
    u.pointerButton(mid, .left, false);
    const centre = @import("map.zig").centre;
    try testing.expectApproxEqAbs(centre[0], g.camera.target[0], 2);
    try testing.expectApproxEqAbs(centre[1], g.camera.target[2], 2);
    // Nothing chosen by it (the battlefield did not have the press).
    try testing.expect(g.dragBox() == null);
}

test "the minimap turned as the view is: the view upright on it" {
    var g = try Game.init(testing.allocator, 1);
    defer g.deinit();
    g.view_size = .{ 1280, 720 };
    const m: Minimap = .{ .game = &g };
    const k = g.viewCorners();
    const tl = m.at(k[0]);
    const tr = m.at(k[1]);
    const br = m.at(k[2]);
    // Its top edge level, its right edge upright, as wide as the view is.
    try testing.expectApproxEqAbs(tl[1], tr[1], 0.01);
    try testing.expectApproxEqAbs(tr[0], br[0], 0.01);
    try testing.expect(tr[0] > tl[0] and br[1] > tr[1]);
    try testing.expectApproxEqAbs(@as(f32, 1280.0 / 720.0), (tr[0] - tl[0]) / (br[1] - tr[1]) / @sin(g.camera.pitch), 0.05);
    // And back.
    const back = m.mapAt(m.at(.{ 200, 150 }));
    try testing.expectApproxEqAbs(@as(f32, 200), back[0], 1e-2);
    try testing.expectApproxEqAbs(@as(f32, 150), back[1], 1e-2);
}

test "the resources' counters: what is after them stays put as they change" {
    const f = try font.Font.init(@embedFile("FiraSans-Regular.ttf"));
    const u = try kete.ui.WindowUi.create(testing.allocator, testing.io, &f);
    defer u.destroy();
    var g = try Game.init(testing.allocator, 1);
    defer g.deinit();
    g.closeMenu();
    const view: Overrun = .{ .game = &g };
    var widths: [3]f32 = undefined;
    for ([_]f32{ 7, 1234, 99999 }, 0..) |amount, k| {
        g.world.resources[game_mod.me] = .{ .metal = amount, .energy = amount };
        u.frame(1280, 720, 0, view);
        try testing.expect(!overflows(u.root.?));
        widths[k] = panelWidth(u.root.?).?;
    }
    try testing.expectEqual(widths[0], widths[1]);
    try testing.expectEqual(widths[0], widths[2]);
}

/// The resources' panel's width (the first rounded box, top left).
fn panelWidth(node: *kete.WidgetNode) ?f32 {
    for (node.children.items) |ch| {
        if (ch.size.h > 20 and ch.size.h < 60 and ch.size.w > 150 and ch.size.w < 400) return ch.size.w;
        if (panelWidth(ch)) |w| return w;
    }
    return null;
}

fn overflows(node: *kete.WidgetNode) bool {
    if (node.overflow.any()) return true;
    for (node.children.items) |ch| if (overflows(ch)) return true;
    return false;
}
