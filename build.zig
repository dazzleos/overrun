//! Overrun, a real-time strategy game of robot armies for Dazzle: built
//! with Dazzle's modules and tools (see Dazzle's build.zig, `addApp`).
//!
//!     zig build                 the program, and its archive and catalogue (zig-out/apps)
//!     zig build test            its tests, on this computer
//!     zig build -Dplatform=linux  for Linux (Wayland and Vulkan): see src/linux.zig
//!
//! With a Dazzle (or kete) checkout of your own beside it:
//! `zig build --fork=../dazzle`.

const std = @import("std");
const dazzle = @import("dazzle");

pub fn build(b: *std.Build) void {
    const app = dazzle.addApp(b, .{
        .name = "overrun",
        .icon = .sports_esports,
        .title = "Overrun",
        .description = "Command robot armies",
        .about = "Build a base and command an army of robots, on foot, on tracks and in the air, across a battlefield of hills and valleys.",
        .shaders = &.{
            // Everything: flat-shaded, coloured triangles (lit as they are
            // made, on the CPU).
            .{ .source = "src/shaders/flat.zig", .args = &.{"--depth-test"} },
        },
    });

    // Each shader's render state, for the Vulkan backend (on Dazzle, the
    // shader compiler builds it into the program):
    // `@import("shader_state").<name>`.
    var state: std.Io.Writer.Allocating = .init(b.allocator);
    for (app.shaders) |sh| {
        var depth_test = false;
        var blend = false;
        for (sh.args) |a| {
            if (std.mem.eql(u8, a, "--depth-test")) depth_test = true;
            if (std.mem.eql(u8, a, "--blend=source-over")) blend = true;
        }
        state.writer.print("pub const {s} = .{{ .depth_test = {}, .blend = {} }};\n", .{ sh.name, depth_test, blend }) catch @panic("OOM");
    }
    const state_file = b.addWriteFiles().add("shader_state.zig", state.written());
    app.module.addAnonymousImport("shader_state", .{ .root_source_file = state_file });
}
