//! Overrun, a real-time strategy game of robot armies for Dazzle: built
//! with Dazzle's modules and tools (see Dazzle's build.zig, `addApp`).
//!
//!     zig build                 the program, and its archive and catalogue (zig-out/apps)
//!     zig build test            its tests, on this computer
//!
//! With a Dazzle (or kete) checkout of your own beside it:
//! `zig build --fork=../dazzle`.

const std = @import("std");
const dazzle = @import("dazzle");

pub fn build(b: *std.Build) void {
    _ = dazzle.addApp(b, .{
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
}
