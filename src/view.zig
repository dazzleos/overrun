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
const font = kete.font;

const Game = game_mod.Game;
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

/// This player's metal and energy, top left.
fn resources(cx: *kete.BuildContext, g: *Game) kete.Widget {
    const r = g.world.resources[game_mod.me];
    return cx.make(kete.RoundedBox{ .color = panel_bg, .radius = .all(10), .child = cx.make(kete.Padding{ .padding = .{ .left = 12, .top = 6, .right = 12, .bottom = 6 }, .child = cx.make(kete.Row{
        .fill = false,
        .spacing = 18,
        .cross_axis_alignment = .center,
        .children = cx.arena.dupe(kete.Widget, &.{
            cx.make(kete.Icon{ .icon = .construction, .size = 20, .color = gfx.Color.argb(0xffc8ccd2) }),
            label(cx, cx.fmt("{d:.0}", .{r.metal}), 18),
            cx.make(kete.Icon{ .icon = .bolt, .size = 20, .color = gfx.Color.argb(0xffffd25a) }),
            label(cx, cx.fmt("{d:.0}", .{r.energy}), 18),
        }) catch &.{},
    }) }) });
}

/// What is chosen, at the bottom: a factory's panel, or how many units.
fn chosenPanel(cx: *kete.BuildContext, g: *Game) ?kete.Widget {
    const a = cx.arena;
    if (g.chosenFactory()) |fi| {
        const f = g.world.things[fi];
        var cells: std.ArrayList(kete.Widget) = .empty;
        for (units.buildable) |k| {
            const q = a.create(Queue) catch continue;
            q.* = .{ .game = g, .kind = k };
            const n = f.queuedOf(k);
            const c = k.cost();
            const making = f.making() == k;
            cells.append(a, cx.make(kete.Pressable{ .on_press = .of(q, Queue.add), .child = cx.make(kete.RoundedBox{
                .color = gfx.Color.argb(if (n > 0) 0xcc303848 else 0x99000000),
                .border_width = if (making) 2 else 1,
                .border_color = gfx.Color.argb(if (making) 0xffffd25a else 0x66ffffff),
                .radius = .all(8),
                .child = cx.make(kete.SizedBox{ .width = 120, .child = cx.make(kete.Padding{ .padding = .all(8), .child = cx.make(kete.Column{ .fill = false, .spacing = 2, .cross_axis_alignment = .start, .children = a.dupe(kete.Widget, &.{
                    cx.make(kete.Row{ .fill = false, .spacing = 6, .children = a.dupe(kete.Widget, &.{
                        cx.make(kete.Icon{ .icon = iconOf(k), .size = 22, .color = gfx.Color.argb(0xffffffff) }),
                        label(cx, k.name(), 16),
                    }) catch &.{} }),
                    label(cx, cx.fmt("{d:.0} metal, {d:.0} energy", .{ c.metal, c.energy }), 11),
                    label(cx, if (n == 0) "" else if (making) cx.fmt("{d} queued, {d:.0}%", .{ n, f.progress * 100 }) else cx.fmt("{d} queued", .{n}), 13),
                }) catch &.{} }) }) }),
            }) })) catch {};
        }
        return cx.make(kete.RoundedBox{ .color = panel_bg, .radius = .all(12), .child = cx.make(kete.Padding{ .padding = .all(10), .child = cx.make(kete.Column{ .fill = false, .spacing = 8, .children = a.dupe(kete.Widget, &.{
            label(cx, "Factory: click to queue, right-click to take one out", 14),
            cx.make(kete.Row{ .fill = false, .spacing = 8, .children = cells.items }),
        }) catch &.{} }) }) });
    }
    if (g.chosen.items.len == 0) return null;
    const t = g.world.things[g.chosen.items[0]];
    const text = if (g.chosen.items.len == 1) t.kind.name() else cx.fmt("{d} chosen", .{g.chosen.items.len});
    return cx.make(kete.RoundedBox{ .color = panel_bg, .radius = .all(10), .child = cx.make(kete.Padding{ .padding = .{ .left = 14, .top = 8, .right = 14, .bottom = 8 }, .child = label(cx, text, 16) }) });
}

// The icons chosen at run time (`iconOf`, and the window buttons').
comptime {
    _ = &[_]kete.IconName{ .smart_toy, .local_shipping, .flight, .construction, .fullscreen, .fullscreen_exit, .close };
}

fn iconOf(k: Kind) @FieldType(kete.Icon, "icon") {
    return switch (k) {
        .walker => .smart_toy,
        .tank => .local_shipping,
        .drone => .flight,
        else => .construction,
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
                    g.pointerDown(pr.pos);
                    return true;
                },
                .right => {
                    // A factory's last queued taken out, or what is chosen
                    // let go of.
                    if (g.chosenFactory()) |f| {
                        if (g.world.things[f].queued > 0) {
                            g.dequeue(g.world.things[f].queue[g.world.things[f].queued - 1]);
                            return true;
                        }
                    }
                    g.letGo();
                    return true;
                },
                else => return false,
            },
            .motion => |pos| g.pointerMoved(pos),
            .release => |r| if (r.button == .left) {
                g.pointerUp(r.pos);
                return true;
            },
            .scroll => |s| {
                g.zoom(if (s.dy > 0) 1.12 else 1.0 / 1.12);
                return true;
            },
            .context => return true,
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
        // With the factory chosen (its panel the widest thing).
        g.chosen.clearRetainingCapacity();
        for (g.world.all(), 0..) |t, i| if (t.kind == .factory) g.chosen.append(testing.allocator, i) catch {};
        for ([_][2]u32{ min_size, open_size }) |size| {
            u.frame(size[0], size[1], 0, view);
            try testing.expect(!overflows(u.root.?));
        }
    }
}

fn overflows(node: *kete.WidgetNode) bool {
    if (node.overflow.any()) return true;
    for (node.children.items) |ch| if (overflows(ch)) return true;
    return false;
}
