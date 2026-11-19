//! What Overrun draws with: the GPU, behind the kinds and calls Overrun
//! uses of it, so that it can be built for another (the renderer and the
//! window's drawing use only these).
//!
//! On Dazzle: the VideoCore IV, through Dazzle's vc4 and shader modules.
//! These names stand for theirs, with nothing in between, so drawing
//! costs no more than calling them.
//!
//! On Linux: Vulkan (vulkan.zig), the same calls made with it. Which is
//! chosen when Overrun is built, so Dazzle's has nothing of it.

const vc4 = @import("vc4");
const shader_mod = @import("shader");
const math = @import("math.zig");

/// Whether this is Linux's (Vulkan's).
pub const vulkan = @import("platform").platform == .linux;
const vk = if (vulkan) @import("vulkan.zig") else struct {};

/// The GPU (opened by the window's host).
pub const Device = if (vulkan) vk.Device else vc4.Device;
/// A buffer on the GPU, its memory mapped (`map`) for the CPU to fill.
pub const Buffer = if (vulkan) vk.Buffer else vc4.Bo;
/// Its pixel formats.
pub const Format = vc4.Format;

/// A frame being recorded (draws go into it), where in it a draw goes
/// (and what it is cut to), what is drawn into, and a texture as a draw
/// samples it.
pub const Frame = if (vulkan) vk.State else vc4.render.Frame;
pub const Viewport = vc4.render.Viewport;
pub const Target = vc4.render.Target;
pub const Texture = if (vulkan) vk.Texture else vc4.render.Texture;

/// Textures: their layouts (with mipmaps) and how they are sampled.
pub const texture = vc4.texture;

/// A shader program (as Dazzle's compiler made it), and a pipeline: the
/// program with the vertex layout and render state it is drawn with.
pub const Program = shader_mod.Program;
pub const Pipeline = if (vulkan) vk.Pipeline else shader_mod.Pipeline;
pub const pipeline = shader_mod.pipeline;

/// Shader `name` (one of build.zig's), as `Pipeline.init` takes it: on
/// Dazzle, the program its compiler made; with Vulkan, its SPIR-V and
/// render state.
pub inline fn shader(comptime name: []const u8) if (vulkan) vk.Shader else Program {
    if (vulkan) {
        const S = struct {
            const bytes = @embedFile(name ++ ".spv");
            const words: [bytes.len]u8 align(4) = bytes.*;
            const state = @field(@import("shader_state"), name);
        };
        return .{ .spirv = &S.words, .depth_test = S.state.depth_test, .blend = S.state.blend };
    }
    return Program.decode(@embedFile(name ++ ".shader")) catch unreachable;
}

/// A projection as the shaders are given it: on Dazzle, as it is (depth
/// from -1 to 1, as OpenGL's); with Vulkan, its depth moved to 0 to 1.
pub inline fn clip(m: math.Mat4) math.Mat4 {
    return if (vulkan) vk.clip(m) else m;
}
