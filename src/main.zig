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
        var b: mesh.Builder = .{ .out = s.renderer.dynamicVertices() };
        for (g.world.things[0..g.world.count], 0..) |*t, i| {
            const r = t.kind.radius() + 0.3;
            const top = t.pos + V3{ 0, t.kind.height(), 0 };
            if (!renderer_mod.inView(m, t.pos - V3{ r, 0, r }, top + V3{ r, 0, r })) continue;
            models.thing(&b, t);
            if (g.isChosen(i)) {
                const ground = if (t.kind.flies()) g.map.surfaceAt(t.pos[0], t.pos[2]) else t.pos[1];
                models.ring(&b, .{ t.pos[0], ground + 0.06, t.pos[2] }, t.kind.radius() + 0.2, mesh.rgb(0x5ef08a));
            }
        }
        if (g.sent) |sent| {
            const age = g.world.time - sent.time;
            if (age < 0.8) models.ring(&b, sent.at + V3{ 0, 0.06, 0 }, 0.3 + age, mesh.rgb(0xffd25a));
        }
        try s.renderer.draw(renderer_mod.FrameSink{ .frame = f }, vp, scissor, m, g.camera.groundBox(aspect, map_mod.lowest, map_mod.highest), b.n);
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
    _ = @import("units.zig");
    _ = @import("models.zig");
    _ = @import("renderer.zig");
    _ = @import("game.zig");
    _ = @import("view.zig");
}
