//! Overrun: a real-time strategy game of robot armies (see game.zig for
//! how it is played, units.zig for the armies, map.zig for the
//! battlefield, renderer.zig for how it is drawn).
//!
//!     overrun

const std = @import("std");
const sys = @import("sys");
const locale = @import("locale");
const vc4 = @import("vc4");
const app = @import("app");
const kete = @import("kete");
const kete_vc4 = @import("kete_vc4");
const math = @import("math.zig");
const mesh = @import("mesh.zig");
const map_mod = @import("map.zig");
const models = @import("models.zig");
const game_mod = @import("game.zig");
const renderer_mod = @import("renderer.zig");
const view = @import("view.zig");
const units = @import("units.zig");
const sky = @import("sky.zig");
const combat = @import("combat.zig");

const print = sys.print;
const Renderer = renderer_mod.Renderer(vc4.Device);
const V3 = math.V3;

pub fn main(init: std.process.Init) u8 {
    sys.logToKmsgIfStderr();
    run(init) catch |err| {
        print(sys.log_error ++ "overrun: error: {s}\n", .{@errorName(err)});
        return 1;
    };
    return 0;
}

/// What drawing the battlefield needs (the view's widget calls `draw`).
const Scene = struct {
    game: *game_mod.Game,
    renderer: *Renderer,
    /// The window's renderer: how much smaller than the window its buffer
    /// is.
    window_renderer: *const kete_vc4.Renderer,

    fn draw(ctx: *anyopaque, f: *vc4.render.Frame, area: kete.gfx.GpuArea) anyerror!void {
        const s: *Scene = @ptrCast(@alignCast(ctx));
        const g = s.game;
        const vp = s.window_renderer.scaled(area.viewport);
        const scissor = if (area.scissor) |sc| s.window_renderer.scaled(sc) else null;
        const aspect = @as(f32, @floatFromInt(vp.width)) / @as(f32, @floatFromInt(@max(vp.height, 1)));
        const m = g.camera.viewProjection(aspect);
        if (g.view_jumped) {
            s.renderer.makeAllNow();
            g.view_jumped = false;
        }
        // The units and buildings in view, and the marks on the ground.
        const hovered = g.hovered();
        var b: mesh.Builder = .{ .out = s.renderer.dynamicVertices() };
        for (g.world.things[0..g.world.count], 0..) |*t, i| {
            const r = t.kind.radius() + 0.3;
            const top = t.pos + V3{ 0, t.kind.height(), 0 };
            if (!renderer_mod.inView(m, t.pos - V3{ r, 0, r }, top + V3{ r, 0, r })) continue;
            if (!g.canSee(t.*)) continue;
            if (t.built < 1) {
                // Being built: rising out of the ground.
                var rising = t.*;
                rising.pos[1] -= (1 - t.built) * t.kind.height();
                models.thing(&b, &rising);
                models.ring(&b, t.pos + V3{ 0, 0.06, 0 }, t.kind.radius() + 0.25, mesh.rgb(0xffd25a));
            } else models.thing(&b, t);
            // Under the pointer (not already chosen): a faint ring, white
            // for this player's, red for another's.
            if (hovered == i and !g.isChosen(i)) {
                const ground = if (t.kind.flies()) g.map.surfaceAt(t.pos[0], t.pos[2]) else t.pos[1];
                models.ring(&b, .{ t.pos[0], ground + 0.06, t.pos[2] }, t.kind.radius() + 0.2, mesh.rgb(if (t.team == game_mod.me) 0xd8e4f0 else 0xf05e5e));
            }
            // Where a builder is going to build.
            if (t.order) |o| if (t.site == null and t.team == game_mod.me) {
                models.ring(&b, .{ o.at[0], g.map.surfaceAt(o.at[0], o.at[1]) + 0.06, o.at[1] }, o.kind.radius() + 0.25, mesh.rgb(0xffd25a));
            };
            if (g.isChosen(i)) {
                const ground = if (t.kind.flies()) g.map.surfaceAt(t.pos[0], t.pos[2]) else t.pos[1];
                models.ring(&b, .{ t.pos[0], ground + 0.06, t.pos[2] }, t.kind.radius() + 0.2, mesh.rgb(0x5ef08a));
            }
        }
        // The fighting: health bars over what is damaged (and seen),
        // tracers and shells in flight, and bursts.
        const per_pixel = 2 * g.camera.zoom / @as(f32, @floatFromInt(@max(vp.height, 1)));
        const fwd = g.camera.forward();
        for (g.world.things[0..g.world.count]) |t| {
            const most = combat.maxHealth(t.kind);
            if (t.health >= most or !g.canSee(t)) continue;
            const over = t.pos + V3{ 0, t.kind.height() + 0.35, 0 };
            models.healthBar(&b, over, std.math.clamp(t.health / most, 0, 1), @max(0.8, t.kind.radius() * 1.6), g.camera.right(), g.camera.up());
        }
        for (g.world.shots[0..g.world.shot_count]) |shot| {
            const head = shot.head();
            const way = shot.to - shot.from;
            const len = math.length(way);
            const tail_len = @min(if (shot.shell) @as(f32, 0.9) else 2.4, len * shot.at);
            const tail = head - way * math.splat(tail_len / @max(len, 0.01));
            if (shot.fall > 0) {
                // A bomb: short, dark, along its fall.
                var before = shot;
                before.at = @max(0, shot.at - 0.06);
                models.streak(&b, before.head(), head, per_pixel * 5, fwd, .{ 0.16, 0.16, 0.18 });
            } else if (shot.shell) {
                models.streak(&b, tail, head, per_pixel * 4, fwd, .{ 2.4, 1.9, 1.2 });
            } else {
                models.streak(&b, tail, head, per_pixel * 2, fwd, .{ 2.0, 1.7, 0.8 });
            }
        }
        for (g.world.blasts[0..g.world.blast_count]) |bl| models.blast(&b, bl.at, bl.size, bl.age, combat.blast_seconds);
        // The building being placed, under the pointer: green where it can
        // go, red where not.
        if (g.ghost()) |gh| {
            const yaw = std.math.atan2(map_mod.centre[0] - gh.at[0], -(map_mod.centre[1] - gh.at[2]));
            const t: units.Thing = .{ .kind = gh.kind, .team = game_mod.me, .pos = gh.at, .yaw = yaw };
            models.thing(&b, &t);
            models.ring(&b, gh.at + V3{ 0, 0.06, 0 }, gh.kind.radius() + 0.3, mesh.rgb(if (gh.ok) 0x5ef08a else 0xf05e5e));
        }
        if (g.sent) |sent| {
            const age = g.world.time - sent.time;
            if (age < 0.8) models.ring(&b, sent.at + V3{ 0, 0.06, 0 }, 0.3 + age, mesh.rgb(0xffd25a));
        }
        s.renderer.setFog(g.fog);
        // The weather: rain, and the light.
        const time = g.world.time;
        const weather = sky.weatherAt(g.map.seed, time);
        sky.rain(&b, g.camera, aspect, 2 * g.camera.zoom / @as(f32, @floatFromInt(@max(vp.height, 1))), time, weather.rain);
        try s.renderer.draw(renderer_mod.FrameSink{ .frame = f }, vp, scissor, .{
            .vp = m,
            .ground = g.camera.groundBox(aspect, map_mod.lowest, map_mod.highest + map_mod.tallest_tree),
            .tint = sky.tintAt(g.map.seed, time, weather),
        }, b.n);
    }
};

/// The window's root: the battlefield and what is over it.
const Root = struct {
    game: *game_mod.Game,
    scene: *Scene,

    pub fn build(r: *const Root, cx: *kete.BuildContext) kete.Widget {
        return cx.make(view.Overrun{ .game = r.game, .draw = .{ .ctx = r.scene, .f = Scene.draw } });
    }
};

/// The keys are the game's before the widgets see them.
const Input = struct {
    game: *game_mod.Game,

    fn filter(in: *Input, e: kete.window.InputEvent) bool {
        switch (e) {
            .key => |k| {
                in.game.key(k.key, k.pressed);
                return true;
            },
            else => return false,
        }
    }
};

/// Whether `err` means the connection to the shell is gone.
fn lostShell(err: anyerror) bool {
    return err == error.Closed or err == error.ProtocolError or err == error.ServerError or err == error.SystemError or err == error.Canceled;
}

fn run(init: std.process.Init) !void {
    locale.current = locale.load().language;
    const gpa = std.heap.page_allocator;
    var host: kete_vc4.Host = undefined;
    // A frame in flight: the next is recorded while the GPU renders this
    // one.
    try host.init(gpa, init.io, init.minimal.environ, .{ .app_id = "overrun", .pipelined = true });
    defer host.deinit();

    var game = try game_mod.Game.init(gpa, @truncate(sys.nowNs()));
    defer game.deinit();
    const renderer = try Renderer.init(gpa, host.dev, game.map);
    defer renderer.deinit();
    var scene: Scene = .{ .game = &game, .renderer = renderer, .window_renderer = &host.renderer };

    const root: Root = .{ .game = &game, .scene = &scene };
    var input: Input = .{ .game = &game };
    const window = try host.app.openWindow(.{
        .title = "Overrun",
        .root = .of(&root),
        .size = view.open_size,
        .min_size = view.min_size,
        .clear_color = 0xff000000,
        .on_close_request = .close,
        .on_input = .of(&input, Input.filter),
    });
    // Fullscreen to start with (the menu's button leaves it).
    host.display.window.?.setFullscreen(true);

    var last = sys.nowNs();
    var frames: u32 = 0;
    var fps_since = last;
    var log_since = last;
    while (true) {
        if (!window.suspended) host.redraw();
        const going = host.step(std.time.ns_per_s) catch |err| blk: {
            if (lostShell(err)) return err;
            // Anything else (the GPU slow, or out of memory for a frame):
            // the frame is drawn again, after a moment.
            print(sys.log_warning ++ "overrun: a frame: {s}\n", .{@errorName(err)});
            sys.sleepMs(50);
            break :blk true;
        };
        if (!going or game.quit_asked) return;
        const now = sys.nowNs();
        const dt: f32 = @floatCast(@as(f64, @floatFromInt(now - last)) / std.time.ns_per_s);
        last = now;
        game.tick(@min(dt, 0.1));
        frames += 1;
        if (now - fps_since >= std.time.ns_per_s) {
            const fps = @as(f32, @floatFromInt(frames)) / (@as(f32, @floatFromInt(now - fps_since)) / std.time.ns_per_s);
            game.noteFps(fps);
            frames = 0;
            fps_since = now;
        }
        if (now - log_since >= 10 * std.time.ns_per_s) {
            const st = renderer.stats;
            const fps = game.fps_history[game_mod.fps_seconds - 1];
            print("overrun: {d:.1} fps; {d} units and buildings, {d} chunks, {d} draws, {d} triangles; {d} chunks on the GPU ({d} KB)\n", .{ fps, game.world.count, st.chunks, st.draws, st.triangles, st.kept, st.kept_bytes / 1024 });
            log_since = now;
        }
    }
}

test {
    _ = @import("math.zig");
    _ = @import("mesh.zig");
    _ = @import("map.zig");
    _ = @import("minimap.zig");
    _ = @import("sky.zig");
    _ = @import("fog.zig");
    _ = @import("nav.zig");
    _ = @import("combat.zig");
    _ = @import("flight.zig");
    _ = @import("units.zig");
    _ = @import("models.zig");
    _ = @import("renderer.zig");
    _ = @import("game.zig");
    _ = @import("view.zig");
}
