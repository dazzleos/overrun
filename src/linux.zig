//! Overrun on Linux (built with -Dplatform=linux): its window is kete's
//! own, on Wayland, and kete draws it (with Vulkan, where it can). The
//! game is the same as on Dazzle.
//!
//! The battlefield is drawn with Vulkan (see vulkan.zig), on the GPU kete
//! draws the window with, straight into its frames (nothing copied).

const std = @import("std");
const sys = @import("sys");
const kete = @import("kete");
const main = @import("main.zig");
const game_mod = @import("game.zig");
const view = @import("view.zig");
const gpu = @import("gpu.zig");
const vulkan = @import("vulkan.zig");
const renderer_mod = @import("renderer.zig");

const print = sys.print;

/// The window's root: the battlefield and what is over it.
const Root = struct {
    game: *game_mod.Game,
    scene: *Scene,

    pub fn build(r: *const Root, cx: *kete.BuildContext) kete.Widget {
        return cx.make(view.Overrun{ .game = r.game, .draw = .{ .ctx = r.scene, .f = Scene.draw } });
    }
};

/// What drawing the battlefield needs: the renderer, made on kete's
/// Vulkan device once the window has one.
const Scene = struct {
    gpa: std.mem.Allocator,
    app: *kete.App,
    game: *game_mod.Game,
    dev: ?gpu.Device = null,
    renderer: ?*main.Renderer = null,
    /// Vulkan could not be had (or the renderer made): not tried again.
    failed: bool = false,
    /// Frames drawn (for the frame rate the menu shows).
    frames: u32 = 0,

    fn deinit(s: *Scene) void {
        if (s.renderer) |r| r.deinit();
        if (s.dev) |d| d.deinit();
    }

    /// The renderer, if there is one (made the first time).
    fn ready(s: *Scene) ?*main.Renderer {
        if (s.renderer) |r| return r;
        if (s.failed) return null;
        const shared = s.app.gpuDevice() orelse return null;
        if (shared != .vulkan) {
            print("overrun: the window is not drawn with Vulkan: the battlefield cannot be shown\n", .{});
            s.failed = true;
            return null;
        }
        const dev = vulkan.State.init(s.gpa, shared.vulkan) catch |err| {
            print("overrun: no Vulkan ({s})\n", .{@errorName(err)});
            s.failed = true;
            return null;
        };
        s.renderer = main.Renderer.init(s.gpa, dev, s.game.map) catch |err| {
            print("overrun: cannot draw the battlefield ({s})\n", .{@errorName(err)});
            dev.deinit();
            s.failed = true;
            return null;
        };
        s.dev = dev;
        return s.renderer;
    }

    fn draw(ctx: *anyopaque, frame: *view.Draw.Frame, area: kete.gfx.GpuArea) anyerror!void {
        const s: *Scene = @ptrCast(@alignCast(ctx));
        const r = s.ready() orelse return;
        const dev = s.dev.?;
        const box = area.viewport;
        if (box.width == 0 or box.height == 0) return;
        s.frames += 1;
        // Straight into the window's frame, where the view is (the
        // renderer's viewport and scissor are within the view: at 0, 0).
        const vp: gpu.Viewport = .{ .x = 0, .y = 0, .width = box.width, .height = box.height };
        const scissor: ?gpu.Viewport = if (area.scissor) |sc| .{ .x = sc.x - box.x, .y = sc.y - box.y, .width = sc.width, .height = sc.height } else null;
        const within = area.scissor orelse box;
        try dev.begin(frame, .{ .x = box.x, .y = box.y, .width = box.width, .height = box.height }, .{ .x = within.x, .y = within.y, .width = within.width, .height = within.height }, 1);
        defer dev.end();
        try main.drawBattlefield(s.game, r, renderer_mod.FrameSink{ .frame = dev }, vp, scissor);
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

pub fn run(init: std.process.Init) !void {
    const gpa = std.heap.page_allocator;
    const app = try kete.App.init(gpa, init.io, init.minimal.environ, .{
        .on_quit_request = .quit,
        .on_last_window_closed = .quit,
    });
    defer app.deinit();

    var game = try game_mod.Game.init(gpa, @truncate(sys.nowNs()));
    defer game.deinit();
    var scene: Scene = .{ .gpa = gpa, .app = app, .game = &game };
    defer scene.deinit();
    const root: Root = .{ .game = &game, .scene = &scene };
    var input: Input = .{ .game = &game };
    const window = try app.openWindow(.{
        .title = "Overrun",
        .root = .of(&root),
        .size = view.open_size,
        .min_size = view.min_size,
        .on_close_request = .close,
        .on_input = .of(&input, Input.filter),
    });
    window.setFullscreen(true);

    var last = sys.nowNs();
    var fps_since = last;
    while (try app.step(std.time.ns_per_s / 60)) {
        const now = sys.nowNs();
        const dt: f32 = @floatCast(@as(f64, @floatFromInt(now - last)) / std.time.ns_per_s);
        last = now;
        game.tick(@min(dt, 0.1));
        if (now - fps_since >= std.time.ns_per_s) {
            game.noteFps(@as(f32, @floatFromInt(scene.frames)) / (@as(f32, @floatFromInt(now - fps_since)) / std.time.ns_per_s));
            scene.frames = 0;
            fps_since = now;
        }
        if (game.quit_asked or window.isClosed()) break;
    }
}
