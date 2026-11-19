//! Overrun's GPU on Linux (as Motu's, which this is a copy of): Vulkan, on
//! the device kete's window renderer uses
//! (kete shares it), drawing into the window's frames as they are made.
//!
//! The same kinds and calls as on Dazzle (see gpu.zig): buffers mapped for
//! the CPU to fill, named by a number in draws; pipelines made from a
//! shader (its SPIR-V, the same as Dazzle's compiler is given) and a
//! vertex layout; draws, each with its uniforms, up to three textures, and
//! a viewport and scissor. A frame's draws go straight into the window's
//! frame (kete's image, which the compositor is given), where the world's
//! view is, with a depth buffer of its own: nothing is copied.
//!
//! The shaders are Dazzle's: OpenGL's depth (from -1 to 1), which the
//! projection is moved into Vulkan's (0 to 1) for (`clip`), and drawn the
//! right way up with a viewport upside down.

const std = @import("std");
const vk = @import("vk.zig");
const kete = @import("kete");
const shader = @import("shader");
const render = @import("vc4").render;

const kv = kete.gfx.vulkan;

pub const Viewport = render.Viewport;
pub const Indices = render.Indices;
pub const pipeline = shader.pipeline;

/// The window's frame, as kete gives it to draw into.
pub const Frame = kv.DirectFrame;

/// A buffer on the GPU, its memory mapped for the CPU to fill.
pub const Buffer = struct {
    handle: u32,
    map: []align(16) u8,
};

/// A texture as a draw samples it (see `Device.createTexture`).
pub const Texture = struct {
    id: u32,
};

/// How a texture is sampled.
pub const Sampling = struct {
    mag_linear: bool = true,
    min_linear: bool = true,
    /// Between mipmap levels: blended, or the nearest.
    mip_linear: bool = true,
    repeat_s: bool = false,
    repeat_t: bool = false,
};

/// A shader: its SPIR-V (both its entry points, "vertex" and "fragment"),
/// and the render state it is for.
pub const Shader = struct {
    spirv: []align(4) const u8,
    depth_test: bool,
    blend: bool,
};

/// The window's frames (as kete makes them), and the depth Motu adds.
const color_format = vk.VK_FORMAT_B8G8R8A8_UNORM;
const depth_format = vk.VK_FORMAT_D32_SFLOAT;

/// The uniforms' ring: each draw's copied in, after the last's.
const ring_size = 8 << 20;
const uniform_align = 256;
/// The most a shader's uniforms can be.
const max_uniforms = 512;
/// How many frames after it was let go of something is destroyed (the
/// GPU may still be drawing frames that use it).
const keep_frames = 4;

const Procs = struct {
    CreateBuffer: *const fn (vk.VkDevice, *const vk.VkBufferCreateInfo, ?*const anyopaque, *vk.VkBuffer) callconv(.c) vk.VkResult,
    DestroyBuffer: *const fn (vk.VkDevice, vk.VkBuffer, ?*const anyopaque) callconv(.c) void,
    GetBufferMemoryRequirements: *const fn (vk.VkDevice, vk.VkBuffer, *vk.VkMemoryRequirements) callconv(.c) void,
    AllocateMemory: *const fn (vk.VkDevice, *const vk.VkMemoryAllocateInfo, ?*const anyopaque, *vk.VkDeviceMemory) callconv(.c) vk.VkResult,
    FreeMemory: *const fn (vk.VkDevice, vk.VkDeviceMemory, ?*const anyopaque) callconv(.c) void,
    BindBufferMemory: *const fn (vk.VkDevice, vk.VkBuffer, vk.VkDeviceMemory, vk.VkDeviceSize) callconv(.c) vk.VkResult,
    MapMemory: *const fn (vk.VkDevice, vk.VkDeviceMemory, vk.VkDeviceSize, vk.VkDeviceSize, vk.VkFlags, *?*anyopaque) callconv(.c) vk.VkResult,
    CreateImage: *const fn (vk.VkDevice, *const vk.VkImageCreateInfo, ?*const anyopaque, *vk.VkImage) callconv(.c) vk.VkResult,
    DestroyImage: *const fn (vk.VkDevice, vk.VkImage, ?*const anyopaque) callconv(.c) void,
    GetImageMemoryRequirements: *const fn (vk.VkDevice, vk.VkImage, *vk.VkMemoryRequirements) callconv(.c) void,
    BindImageMemory: *const fn (vk.VkDevice, vk.VkImage, vk.VkDeviceMemory, vk.VkDeviceSize) callconv(.c) vk.VkResult,
    CreateImageView: *const fn (vk.VkDevice, *const vk.VkImageViewCreateInfo, ?*const anyopaque, *vk.VkImageView) callconv(.c) vk.VkResult,
    DestroyImageView: *const fn (vk.VkDevice, vk.VkImageView, ?*const anyopaque) callconv(.c) void,
    CreateSampler: *const fn (vk.VkDevice, *const vk.VkSamplerCreateInfo, ?*const anyopaque, *vk.VkSampler) callconv(.c) vk.VkResult,
    DestroySampler: *const fn (vk.VkDevice, vk.VkSampler, ?*const anyopaque) callconv(.c) void,
    CreateRenderPass: *const fn (vk.VkDevice, *const vk.VkRenderPassCreateInfo, ?*const anyopaque, *vk.VkRenderPass) callconv(.c) vk.VkResult,
    DestroyRenderPass: *const fn (vk.VkDevice, vk.VkRenderPass, ?*const anyopaque) callconv(.c) void,
    CreateFramebuffer: *const fn (vk.VkDevice, *const vk.VkFramebufferCreateInfo, ?*const anyopaque, *vk.VkFramebuffer) callconv(.c) vk.VkResult,
    DestroyFramebuffer: *const fn (vk.VkDevice, vk.VkFramebuffer, ?*const anyopaque) callconv(.c) void,
    CreateShaderModule: *const fn (vk.VkDevice, *const vk.VkShaderModuleCreateInfo, ?*const anyopaque, *vk.VkShaderModule) callconv(.c) vk.VkResult,
    DestroyShaderModule: *const fn (vk.VkDevice, vk.VkShaderModule, ?*const anyopaque) callconv(.c) void,
    CreatePipelineLayout: *const fn (vk.VkDevice, *const vk.VkPipelineLayoutCreateInfo, ?*const anyopaque, *vk.VkPipelineLayout) callconv(.c) vk.VkResult,
    DestroyPipelineLayout: *const fn (vk.VkDevice, vk.VkPipelineLayout, ?*const anyopaque) callconv(.c) void,
    CreateGraphicsPipelines: *const fn (vk.VkDevice, vk.VkPipelineCache, u32, [*]const vk.VkGraphicsPipelineCreateInfo, ?*const anyopaque, [*]vk.VkPipeline) callconv(.c) vk.VkResult,
    DestroyPipeline: *const fn (vk.VkDevice, vk.VkPipeline, ?*const anyopaque) callconv(.c) void,
    CreateDescriptorSetLayout: *const fn (vk.VkDevice, *const vk.VkDescriptorSetLayoutCreateInfo, ?*const anyopaque, *vk.VkDescriptorSetLayout) callconv(.c) vk.VkResult,
    DestroyDescriptorSetLayout: *const fn (vk.VkDevice, vk.VkDescriptorSetLayout, ?*const anyopaque) callconv(.c) void,
    CreateDescriptorPool: *const fn (vk.VkDevice, *const vk.VkDescriptorPoolCreateInfo, ?*const anyopaque, *vk.VkDescriptorPool) callconv(.c) vk.VkResult,
    DestroyDescriptorPool: *const fn (vk.VkDevice, vk.VkDescriptorPool, ?*const anyopaque) callconv(.c) void,
    AllocateDescriptorSets: *const fn (vk.VkDevice, *const vk.VkDescriptorSetAllocateInfo, [*]vk.VkDescriptorSet) callconv(.c) vk.VkResult,
    UpdateDescriptorSets: *const fn (vk.VkDevice, u32, [*]const vk.VkWriteDescriptorSet, u32, ?*const anyopaque) callconv(.c) void,
    DeviceWaitIdle: *const fn (vk.VkDevice) callconv(.c) vk.VkResult,
    CmdBeginRenderPass: *const fn (vk.VkCommandBuffer, *const vk.VkRenderPassBeginInfo, u32) callconv(.c) void,
    CmdEndRenderPass: *const fn (vk.VkCommandBuffer) callconv(.c) void,
    CmdBindPipeline: *const fn (vk.VkCommandBuffer, u32, vk.VkPipeline) callconv(.c) void,
    CmdBindDescriptorSets: *const fn (vk.VkCommandBuffer, u32, vk.VkPipelineLayout, u32, u32, [*]const vk.VkDescriptorSet, u32, ?[*]const u32) callconv(.c) void,
    CmdBindVertexBuffers: *const fn (vk.VkCommandBuffer, u32, u32, [*]const vk.VkBuffer, [*]const vk.VkDeviceSize) callconv(.c) void,
    CmdBindIndexBuffer: *const fn (vk.VkCommandBuffer, vk.VkBuffer, vk.VkDeviceSize, u32) callconv(.c) void,
    CmdSetViewport: *const fn (vk.VkCommandBuffer, u32, u32, [*]const vk.VkViewport) callconv(.c) void,
    CmdSetScissor: *const fn (vk.VkCommandBuffer, u32, u32, [*]const vk.VkRect2D) callconv(.c) void,
    CmdDraw: *const fn (vk.VkCommandBuffer, u32, u32, u32, u32) callconv(.c) void,
    CmdDrawIndexed: *const fn (vk.VkCommandBuffer, u32, u32, u32, i32, u32) callconv(.c) void,
    CmdPipelineBarrier: *const fn (vk.VkCommandBuffer, vk.VkFlags, vk.VkFlags, vk.VkFlags, u32, ?*const anyopaque, u32, ?*const anyopaque, u32, [*]const vk.VkImageMemoryBarrier) callconv(.c) void,
    CmdCopyBufferToImage: *const fn (vk.VkCommandBuffer, vk.VkBuffer, vk.VkImage, u32, u32, [*]const vk.VkBufferImageCopy) callconv(.c) void,
    CmdBlitImage: *const fn (vk.VkCommandBuffer, vk.VkImage, u32, vk.VkImage, u32, u32, [*]const vk.VkImageBlit, u32) callconv(.c) void,
};

const GetInstanceProcAddr = *const fn (?vk.VkInstance, [*:0]const u8) callconv(.c) ?*const anyopaque;
const GetDeviceProcAddr = *const fn (vk.VkDevice, [*:0]const u8) callconv(.c) ?*const anyopaque;

const BufferRec = struct {
    buffer: vk.VkBuffer = vk.VK_NULL_HANDLE,
    memory: vk.VkDeviceMemory = vk.VK_NULL_HANDLE,
};

const TextureRec = struct {
    image: vk.VkImage = vk.VK_NULL_HANDLE,
    memory: vk.VkDeviceMemory = vk.VK_NULL_HANDLE,
    view: vk.VkImageView = vk.VK_NULL_HANDLE,
    sampler: vk.VkSampler = vk.VK_NULL_HANDLE,
};

/// Something let go of, destroyed once the frames that may use it are
/// drawn.
const Dead = struct {
    frame: u64,
    what: union(enum) {
        buffer: BufferRec,
        texture: TextureRec,
        target: Target,
        window: Window,
        small: Small,
    },
};

/// An image's pixels waiting to be copied in (at the start of the next
/// frame: from a buffer the CPU filled).
const Upload = struct {
    staging: BufferRec,
    image: vk.VkImage,
    width: u32,
    height: u32,
    levels: u32,
};

/// The depth the world is drawn with, as big as the window's frames.
const Target = struct {
    width: u32 = 0,
    height: u32 = 0,
    depth: TextureRec = .{},
};

/// Where the world is drawn smaller than the view (at a quality under
/// the full one), before it is stretched into the window's frame: its
/// image, and its depth.
const Small = struct {
    width: u32 = 0,
    height: u32 = 0,
    color: TextureRec = .{},
    depth: TextureRec = .{},
    framebuffer: vk.VkFramebuffer = vk.VK_NULL_HANDLE,
};

/// A frame of the window's, as it is drawn into: its image (kete's), and
/// the depth with it. Made for each frame (kete's images come and go).
const Window = struct {
    view: vk.VkImageView = vk.VK_NULL_HANDLE,
    framebuffer: vk.VkFramebuffer = vk.VK_NULL_HANDLE,
};

/// A set of the textures a draw samples (the uniforms' ring with them).
const Set = struct {
    textures: [3]u32,
    set: vk.VkDescriptorSet,
};

pub const Device = *State;

pub const State = struct {
    gpa: std.mem.Allocator,
    lib: std.DynLib,
    f: Procs,
    device: vk.VkDevice,
    mem_props: vk.VkPhysicalDeviceMemoryProperties,
    buffers: std.ArrayList(BufferRec) = .empty,
    free_buffers: std.ArrayList(u32) = .empty,
    textures: std.ArrayList(TextureRec) = .empty,
    dead: std.ArrayList(Dead) = .empty,
    uploads: std.ArrayList(Upload) = .empty,
    sets: std.ArrayList(Set) = .empty,
    set_layout: vk.VkDescriptorSetLayout = vk.VK_NULL_HANDLE,
    layout: vk.VkPipelineLayout = vk.VK_NULL_HANDLE,
    pool: vk.VkDescriptorPool = vk.VK_NULL_HANDLE,
    render_pass: vk.VkRenderPass = vk.VK_NULL_HANDLE,
    /// Into `small`, to stretch from.
    small_pass: vk.VkRenderPass = vk.VK_NULL_HANDLE,
    small: Small = .{},
    /// Drawing into `small`: where it is stretched to in the frame's
    /// image, from where in it.
    stretch: ?struct { image: vk.VkImage, src: [2][2]i32, dst: [2][2]i32 } = null,
    ring: BufferRec = .{},
    ring_map: []u8 = &.{},
    ring_at: u32 = 0,
    target: Target = .{},
    /// The frame being drawn: where the world's view is in its image, and
    /// the part of it that may be drawn on.
    offset: [2]i32 = .{ 0, 0 },
    area: Viewport = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    window: Window = .{},
    /// Frames drawn.
    frame_no: u64 = 0,
    /// The texture a draw with none samples (a white pixel).
    blank: Texture = .{ .id = 0 },
    /// The frame being drawn, while it is.
    cmd: ?vk.VkCommandBuffer = null,

    /// On the device kete's window renderer uses.
    pub fn init(gpa: std.mem.Allocator, shared: kv.SharedDevice) !Device {
        var lib = try std.DynLib.open("libvulkan.so.1");
        errdefer lib.close();
        const get_inst = lib.lookup(GetInstanceProcAddr, "vkGetInstanceProcAddr") orelse return error.NoVulkan;
        const get_dev: GetDeviceProcAddr = @ptrCast(@alignCast(get_inst(shared.instance, "vkGetDeviceProcAddr") orelse return error.NoVulkan));
        var f: Procs = undefined;
        inline for (@typeInfo(Procs).@"struct".field_names) |name| {
            const p = get_dev(shared.device, "vk" ++ name) orelse return error.NoVulkan;
            @field(f, name) = @ptrCast(@alignCast(p));
        }
        const s = try gpa.create(State);
        errdefer gpa.destroy(s);
        s.* = .{ .gpa = gpa, .lib = lib, .f = f, .device = shared.device, .mem_props = @as(*const vk.VkPhysicalDeviceMemoryProperties, @ptrCast(&shared.mem_props)).* };
        try s.makeShared();
        // Texture 0: a white pixel (what a draw without a texture binds).
        s.blank = try s.createTexture(&.{0xffffffff}, 1, 1, 0, .{});
        return s;
    }

    pub fn deinit(s: *State) void {
        _ = s.f.DeviceWaitIdle(s.device);
        for (s.dead.items) |d| s.destroyNow(d);
        s.dead.deinit(s.gpa);
        for (s.uploads.items) |u| s.destroyBufferRec(u.staging);
        s.uploads.deinit(s.gpa);
        for (s.buffers.items) |b| s.destroyBufferRec(b);
        s.buffers.deinit(s.gpa);
        s.free_buffers.deinit(s.gpa);
        for (s.textures.items) |t| s.destroyTextureRec(t);
        s.textures.deinit(s.gpa);
        s.destroyTarget(s.target);
        s.destroyWindow(s.window);
        s.destroySmall(s.small);
        s.f.DestroyRenderPass(s.device, s.small_pass, null);
        s.destroyBufferRec(s.ring);
        s.sets.deinit(s.gpa);
        s.f.DestroyDescriptorPool(s.device, s.pool, null);
        s.f.DestroyPipelineLayout(s.device, s.layout, null);
        s.f.DestroyDescriptorSetLayout(s.device, s.set_layout, null);
        s.f.DestroyRenderPass(s.device, s.render_pass, null);
        s.lib.close();
        s.gpa.destroy(s);
    }

    fn check(r: vk.VkResult) !void {
        if (r != .success) return error.VulkanFailed;
    }

    fn memoryType(s: *const State, bits: u32, want: vk.VkFlags) !u32 {
        for (0..s.mem_props.memoryTypeCount) |i| {
            if (bits & (@as(u32, 1) << @intCast(i)) != 0 and s.mem_props.memoryTypes[i].propertyFlags & want == want) return @intCast(i);
        }
        return error.NoMemoryType;
    }

    /// The layout every pipeline shares (the uniforms, then three
    /// textures), the render pass, and the uniforms' ring.
    fn makeShared(s: *State) !void {
        const frag = vk.VK_SHADER_STAGE_FRAGMENT_BIT;
        const bindings = [_]vk.VkDescriptorSetLayoutBinding{
            .{ .binding = 0, .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC, .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT | frag },
            .{ .binding = 1, .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .stageFlags = frag },
            .{ .binding = 2, .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .stageFlags = frag },
            .{ .binding = 3, .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .stageFlags = frag },
        };
        try check(s.f.CreateDescriptorSetLayout(s.device, &.{ .bindingCount = bindings.len, .pBindings = &bindings }, null, &s.set_layout));
        try check(s.f.CreatePipelineLayout(s.device, &.{ .setLayoutCount = 1, .pSetLayouts = @ptrCast(&s.set_layout) }, null, &s.layout));
        const sizes = [_]vk.VkDescriptorPoolSize{
            .{ .type = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC, .descriptorCount = 64 },
            .{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 64 * 3 },
        };
        try check(s.f.CreateDescriptorPool(s.device, &.{ .maxSets = 64, .poolSizeCount = sizes.len, .pPoolSizes = &sizes }, null, &s.pool));

        const attachments = [_]vk.VkAttachmentDescription{
            // The window's image (shared with the compositor: in GENERAL
            // layout), cleared where the world is.
            .{ .format = color_format, .samples = vk.VK_SAMPLE_COUNT_1_BIT, .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR, .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE, .initialLayout = vk.VK_IMAGE_LAYOUT_GENERAL, .finalLayout = vk.VK_IMAGE_LAYOUT_GENERAL },
            .{ .format = depth_format, .samples = vk.VK_SAMPLE_COUNT_1_BIT, .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR, .storeOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE, .finalLayout = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL },
        };
        const color_ref = [_]vk.VkAttachmentReference{.{ .attachment = 0, .layout = vk.VK_IMAGE_LAYOUT_GENERAL }};
        const depth_ref: vk.VkAttachmentReference = .{ .attachment = 1, .layout = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL };
        const subpass = [_]vk.VkSubpassDescription{.{ .pColorAttachments = &color_ref, .pDepthStencilAttachment = &depth_ref }};
        // After what kete drew under it (and the last frame's depth), and
        // before what it draws over it.
        const color_rw = vk.VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        const depth_rw = vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
        const deps = [_]vk.VkSubpassDependency{ .{
            .srcSubpass = vk.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | vk.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
            .dstStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .srcAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
            .dstAccessMask = color_rw | depth_rw,
        }, .{
            .srcSubpass = 0,
            .dstSubpass = vk.VK_SUBPASS_EXTERNAL,
            .srcStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .srcAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            .dstAccessMask = color_rw,
        } };
        try check(s.f.CreateRenderPass(s.device, &.{ .attachmentCount = attachments.len, .pAttachments = &attachments, .pSubpasses = &subpass, .dependencyCount = deps.len, .pDependencies = &deps }, null, &s.render_pass));

        // Drawing smaller: into an image of its own, left to be read
        // from (stretched into the frame); after the last frame's
        // stretching from it.
        const small_attachments = [_]vk.VkAttachmentDescription{
            .{ .format = color_format, .samples = vk.VK_SAMPLE_COUNT_1_BIT, .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR, .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE, .finalLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL },
            .{ .format = depth_format, .samples = vk.VK_SAMPLE_COUNT_1_BIT, .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR, .storeOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE, .finalLayout = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL },
        };
        const small_color_ref = [_]vk.VkAttachmentReference{.{ .attachment = 0, .layout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL }};
        const small_subpass = [_]vk.VkSubpassDescription{.{ .pColorAttachments = &small_color_ref, .pDepthStencilAttachment = &depth_ref }};
        const small_deps = [_]vk.VkSubpassDependency{.{
            .srcSubpass = vk.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = vk.VK_PIPELINE_STAGE_TRANSFER_BIT | vk.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
            .dstStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .srcAccessMask = vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
            .dstAccessMask = color_rw | depth_rw,
        }};
        try check(s.f.CreateRenderPass(s.device, &.{ .attachmentCount = small_attachments.len, .pAttachments = &small_attachments, .pSubpasses = &small_subpass, .dependencyCount = small_deps.len, .pDependencies = &small_deps }, null, &s.small_pass));

        s.ring = try s.makeBuffer(ring_size, vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
        var p: ?*anyopaque = null;
        try check(s.f.MapMemory(s.device, s.ring.memory, 0, ring_size, 0, &p));
        s.ring_map = @as([*]u8, @ptrCast(p.?))[0..ring_size];
    }

    fn makeBuffer(s: *State, size: u64, usage: vk.VkFlags) !BufferRec {
        var r: BufferRec = .{};
        try check(s.f.CreateBuffer(s.device, &.{ .size = size, .usage = usage }, null, &r.buffer));
        errdefer s.f.DestroyBuffer(s.device, r.buffer, null);
        var req: vk.VkMemoryRequirements = undefined;
        s.f.GetBufferMemoryRequirements(s.device, r.buffer, &req);
        const kind = try s.memoryType(req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
        try check(s.f.AllocateMemory(s.device, &.{ .allocationSize = req.size, .memoryTypeIndex = kind }, null, &r.memory));
        errdefer s.f.FreeMemory(s.device, r.memory, null);
        try check(s.f.BindBufferMemory(s.device, r.buffer, r.memory, 0));
        return r;
    }

    fn destroyBufferRec(s: *State, r: BufferRec) void {
        if (r.buffer != vk.VK_NULL_HANDLE) s.f.DestroyBuffer(s.device, r.buffer, null);
        if (r.memory != vk.VK_NULL_HANDLE) s.f.FreeMemory(s.device, r.memory, null);
    }

    fn destroyTextureRec(s: *State, t: TextureRec) void {
        if (t.sampler != vk.VK_NULL_HANDLE) s.f.DestroySampler(s.device, t.sampler, null);
        if (t.view != vk.VK_NULL_HANDLE) s.f.DestroyImageView(s.device, t.view, null);
        if (t.image != vk.VK_NULL_HANDLE) s.f.DestroyImage(s.device, t.image, null);
        if (t.memory != vk.VK_NULL_HANDLE) s.f.FreeMemory(s.device, t.memory, null);
    }

    fn destroyTarget(s: *State, t: Target) void {
        s.destroyTextureRec(t.depth);
    }

    fn destroySmall(s: *State, sm: Small) void {
        if (sm.framebuffer != vk.VK_NULL_HANDLE) s.f.DestroyFramebuffer(s.device, sm.framebuffer, null);
        s.destroyTextureRec(sm.color);
        s.destroyTextureRec(sm.depth);
    }

    fn destroyWindow(s: *State, w: Window) void {
        if (w.framebuffer != vk.VK_NULL_HANDLE) s.f.DestroyFramebuffer(s.device, w.framebuffer, null);
        if (w.view != vk.VK_NULL_HANDLE) s.f.DestroyImageView(s.device, w.view, null);
    }

    fn destroyNow(s: *State, d: Dead) void {
        switch (d.what) {
            .buffer => |b| s.destroyBufferRec(b),
            .texture => |t| s.destroyTextureRec(t),
            .target => |t| s.destroyTarget(t),
            .window => |w| s.destroyWindow(w),
            .small => |sm| s.destroySmall(sm),
        }
    }

    fn bury(s: *State, what: @FieldType(Dead, "what")) void {
        s.dead.append(s.gpa, .{ .frame = s.frame_no, .what = what }) catch s.destroyNow(.{ .frame = 0, .what = what });
    }

    // --- Buffers ---------------------------------------------------------------

    /// A buffer of `size` bytes, for vertices or indices, mapped.
    pub fn createBo(s: *State, size: u32) !Buffer {
        const r = try s.makeBuffer(@max(size, 16), vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
        errdefer s.destroyBufferRec(r);
        var p: ?*anyopaque = null;
        try check(s.f.MapMemory(s.device, r.memory, 0, @max(size, 16), 0, &p));
        const handle: u32 = if (s.free_buffers.pop()) |h| h else blk: {
            try s.buffers.append(s.gpa, .{});
            break :blk @intCast(s.buffers.items.len);
        };
        s.buffers.items[handle - 1] = r;
        return .{ .handle = handle, .map = @as([*]align(16) u8, @ptrCast(@alignCast(p.?)))[0..size] };
    }

    /// Let go of (destroyed once the frames drawing with it are drawn).
    pub fn destroyBo(s: *State, b: Buffer) void {
        const r = s.buffers.items[b.handle - 1];
        s.buffers.items[b.handle - 1] = .{};
        s.free_buffers.append(s.gpa, b.handle) catch {};
        s.bury(.{ .buffer = r });
    }

    fn bufferOf(s: *const State, handle: u32) vk.VkBuffer {
        return s.buffers.items[handle - 1].buffer;
    }

    // --- Textures --------------------------------------------------------------

    /// A texture of RGBA pixels (0xAABBGGRR, as bytes R, G, B, A), `width`
    /// by `height`, with `levels` mipmap levels after it (each half as big,
    /// following it in `pixels`). Its pixels are copied in at the start of
    /// the next frame.
    pub fn createTexture(s: *State, pixels: []const u32, width: u32, height: u32, levels: u32, sampling: Sampling) !Texture {
        var t: TextureRec = .{};
        errdefer s.destroyTextureRec(t);
        try check(s.f.CreateImage(s.device, &.{
            .format = vk.VK_FORMAT_R8G8B8A8_UNORM,
            .extent = .{ .width = width, .height = height, .depth = 1 },
            .mipLevels = levels + 1,
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .usage = vk.VK_IMAGE_USAGE_SAMPLED_BIT | vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        }, null, &t.image));
        var req: vk.VkMemoryRequirements = undefined;
        s.f.GetImageMemoryRequirements(s.device, t.image, &req);
        try check(s.f.AllocateMemory(s.device, &.{ .allocationSize = req.size, .memoryTypeIndex = try s.memoryType(req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) }, null, &t.memory));
        try check(s.f.BindImageMemory(s.device, t.image, t.memory, 0));
        try check(s.f.CreateImageView(s.device, &.{
            .image = t.image,
            .format = vk.VK_FORMAT_R8G8B8A8_UNORM,
            .subresourceRange = .{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .levelCount = levels + 1 },
        }, null, &t.view));
        try check(s.f.CreateSampler(s.device, &.{
            .magFilter = if (sampling.mag_linear) vk.VK_FILTER_LINEAR else vk.VK_FILTER_NEAREST,
            .minFilter = if (sampling.min_linear) vk.VK_FILTER_LINEAR else vk.VK_FILTER_NEAREST,
            .mipmapMode = if (sampling.mip_linear) vk.VK_SAMPLER_MIPMAP_MODE_LINEAR else vk.VK_SAMPLER_MIPMAP_MODE_NEAREST,
            .addressModeU = if (sampling.repeat_s) vk.VK_SAMPLER_ADDRESS_MODE_REPEAT else vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeV = if (sampling.repeat_t) vk.VK_SAMPLER_ADDRESS_MODE_REPEAT else vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .maxLod = @floatFromInt(levels),
        }, null, &t.sampler));
        try s.stage(t.image, pixels, width, height, levels + 1);
        try s.textures.append(s.gpa, t);
        return .{ .id = @intCast(s.textures.items.len - 1) };
    }

    /// New pixels for texture `t` (made `width` by `height`, without
    /// mipmaps), copied in at the start of the next frame.
    pub fn updateTexture(s: *State, t: Texture, pixels: []const u32, width: u32, height: u32) !void {
        try s.stage(s.textures.items[t.id].image, pixels, width, height, 1);
    }

    /// `pixels` (with `levels` levels), into a buffer to copy into `image`
    /// from at the start of the next frame.
    fn stage(s: *State, image: vk.VkImage, pixels: []const u32, width: u32, height: u32, levels: u32) !void {
        const bytes = std.mem.sliceAsBytes(pixels);
        const staging = try s.makeBuffer(bytes.len, vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
        errdefer s.destroyBufferRec(staging);
        var p: ?*anyopaque = null;
        try check(s.f.MapMemory(s.device, staging.memory, 0, bytes.len, 0, &p));
        @memcpy(@as([*]u8, @ptrCast(p.?))[0..bytes.len], bytes);
        try s.uploads.append(s.gpa, .{ .staging = staging, .image = image, .width = width, .height = height, .levels = levels });
    }

    pub fn destroyTexture(s: *State, t: Texture) void {
        const r = s.textures.items[t.id];
        s.textures.items[t.id] = .{};
        s.bury(.{ .texture = r });
    }

    /// The descriptor set with the uniforms' ring and these textures.
    fn setOf(s: *State, tex: [3]?Texture) !vk.VkDescriptorSet {
        var ids: [3]u32 = undefined;
        for (&ids, tex) |*id, t| id.* = if (t) |x| x.id else s.blank.id;
        for (s.sets.items) |x| if (std.mem.eql(u32, &x.textures, &ids)) return x.set;
        var set: vk.VkDescriptorSet = vk.VK_NULL_HANDLE;
        try check(s.f.AllocateDescriptorSets(s.device, &.{ .descriptorPool = s.pool, .pSetLayouts = @ptrCast(&s.set_layout) }, @ptrCast(&set)));
        const ubo: vk.VkDescriptorBufferInfo = .{ .buffer = s.ring.buffer, .offset = 0, .range = max_uniforms };
        var images: [3]vk.VkDescriptorImageInfo = undefined;
        for (&images, ids) |*im, id| {
            const t = s.textures.items[id];
            im.* = .{ .sampler = t.sampler, .imageView = t.view, .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL };
        }
        const writes = [_]vk.VkWriteDescriptorSet{
            .{ .dstSet = set, .dstBinding = 0, .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC, .pBufferInfo = &ubo },
            .{ .dstSet = set, .dstBinding = 1, .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &images[0] },
            .{ .dstSet = set, .dstBinding = 2, .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &images[1] },
            .{ .dstSet = set, .dstBinding = 3, .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &images[2] },
        };
        s.f.UpdateDescriptorSets(s.device, writes.len, &writes, 0, null);
        try s.sets.append(s.gpa, .{ .textures = ids, .set = set });
        return set;
    }

    // --- Frames ----------------------------------------------------------------

    /// Starts drawing the world into `frame` (kete's), in its command
    /// buffer: the textures made since the last copied in, and what was
    /// let go of then destroyed; then, where the world's view is (`view`,
    /// in the frame), within `within`, the frame cleared (and the depth).
    /// At a `quality` under 1, it is drawn that much smaller (across and
    /// down), into an image of its own, and stretched into the frame at
    /// `end`: draws are then as big as that (`smallSize`).
    pub fn begin(s: *State, frame: *const Frame, view: Viewport, within: Viewport, quality: f32) !void {
        const cmd = frame.cmd;
        s.frame_no += 1;
        var k: usize = 0;
        while (k < s.dead.items.len) {
            if (s.dead.items[k].frame + keep_frames <= s.frame_no) {
                s.destroyNow(s.dead.swapRemove(k));
            } else k += 1;
        }
        for (s.uploads.items) |u| s.recordUpload(cmd, u);
        for (s.uploads.items) |u| s.bury(.{ .buffer = u.staging });
        s.uploads.clearRetainingCapacity();

        // The frame in its image (inside the window's shadow, if it has
        // one), and what may be drawn on: within the frame.
        const fw = if (frame.width > 0) frame.width else @as(u32, @intCast(view.x)) + view.width;
        const fh = if (frame.height > 0) frame.height else @as(u32, @intCast(view.y)) + view.height;
        const x0 = @max(within.x, 0);
        const y0 = @max(within.y, 0);
        const x1 = @min(within.x + @as(i32, @intCast(within.width)), @as(i32, @intCast(fw)));
        const y1 = @min(within.y + @as(i32, @intCast(within.height)), @as(i32, @intCast(fh)));
        if (x1 <= x0 or y1 <= y0) return;
        const origin = frame.origin;
        if (quality < 0.999) return s.beginSmall(cmd, frame, view, .{ .{ x0, y0 }, .{ x1, y1 } }, quality);
        s.offset = .{ view.x + origin[0], view.y + origin[1] };
        s.area = .{ .x = x0 + origin[0], .y = y0 + origin[1], .width = @intCast(x1 - x0), .height = @intCast(y1 - y0) };
        // The depth (and the framebuffer) as big as the image is, up to
        // the frame's far corner.
        const width: u32 = @intCast(origin[0] + @as(i32, @intCast(fw)));
        const height: u32 = @intCast(origin[1] + @as(i32, @intCast(fh)));
        if (s.target.width != width or s.target.height != height) {
            if (s.target.depth.image != vk.VK_NULL_HANDLE) s.bury(.{ .target = s.target });
            s.target = .{};
            s.target = try s.makeTarget(width, height);
        }
        var w: Window = .{};
        errdefer s.destroyWindow(w);
        try check(s.f.CreateImageView(s.device, &.{
            .image = frame.image,
            .format = color_format,
            .subresourceRange = .{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT },
        }, null, &w.view));
        const views = [2]vk.VkImageView{ w.view, s.target.depth.view };
        try check(s.f.CreateFramebuffer(s.device, &.{ .renderPass = s.render_pass, .attachmentCount = 2, .pAttachments = &views, .width = width, .height = height }, null, &w.framebuffer));
        s.window = w;

        const clears = [2]vk.VkClearValue{
            .{ .color = .{ 0, 0, 0, 1 } },
            .{ .depth_stencil = .{ .depth = 1.0, .stencil = 0 } },
        };
        s.f.CmdBeginRenderPass(cmd, &.{
            .renderPass = s.render_pass,
            .framebuffer = w.framebuffer,
            .renderArea = .{ .offset = .{ .x = s.area.x, .y = s.area.y }, .extent = .{ .width = s.area.width, .height = s.area.height } },
            .clearValueCount = clears.len,
            .pClearValues = &clears,
        }, 0);
        s.cmd = cmd;
    }

    /// How big the world is drawn, `view` at `quality`.
    pub fn smallSize(view: Viewport, quality: f32) [2]u32 {
        return .{
            @max(1, @as(u32, @intFromFloat(@ceil(@as(f32, @floatFromInt(view.width)) * quality)))),
            @max(1, @as(u32, @intFromFloat(@ceil(@as(f32, @floatFromInt(view.height)) * quality)))),
        };
    }

    /// `begin`, smaller: into `small`, to be stretched into `frame`'s
    /// `view` within `shown` (in the frame: corners).
    fn beginSmall(s: *State, cmd: vk.VkCommandBuffer, frame: *const Frame, view: Viewport, shown: [2][2]i32, quality: f32) !void {
        const size = smallSize(view, quality);
        if (s.small.width != size[0] or s.small.height != size[1]) {
            if (s.small.framebuffer != vk.VK_NULL_HANDLE) s.bury(.{ .small = s.small });
            s.small = .{};
            s.small = try s.makeSmall(size[0], size[1]);
        }
        s.offset = .{ 0, 0 };
        s.area = .{ .x = 0, .y = 0, .width = size[0], .height = size[1] };
        // The part of the view shown (clipped), and where that is in the
        // small image.
        const kx = @as(f32, @floatFromInt(size[0])) / @as(f32, @floatFromInt(view.width));
        const ky = @as(f32, @floatFromInt(size[1])) / @as(f32, @floatFromInt(view.height));
        const o = frame.origin;
        var src: [2][2]i32 = undefined;
        var dst: [2][2]i32 = undefined;
        for (0..2) |c| {
            dst[c] = .{ shown[c][0] + o[0], shown[c][1] + o[1] };
            src[c] = .{
                @intFromFloat(@round(@as(f32, @floatFromInt(shown[c][0] - view.x)) * kx)),
                @intFromFloat(@round(@as(f32, @floatFromInt(shown[c][1] - view.y)) * ky)),
            };
        }
        s.stretch = .{ .image = frame.image, .src = src, .dst = dst };
        const clears = [2]vk.VkClearValue{
            .{ .color = .{ 0, 0, 0, 1 } },
            .{ .depth_stencil = .{ .depth = 1.0, .stencil = 0 } },
        };
        s.f.CmdBeginRenderPass(cmd, &.{
            .renderPass = s.small_pass,
            .framebuffer = s.small.framebuffer,
            .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = size[0], .height = size[1] } },
            .clearValueCount = clears.len,
            .pClearValues = &clears,
        }, 0);
        s.cmd = cmd;
    }

    /// Ends drawing the world into the frame (kete draws on, over it):
    /// drawn smaller, stretched into it (smoothly).
    pub fn end(s: *State) void {
        const cmd = s.cmd orelse return;
        s.f.CmdEndRenderPass(cmd);
        s.cmd = null;
        if (s.stretch) |st| {
            s.stretch = null;
            const color = vk.VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
            const range: vk.VkImageSubresourceRange = .{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT };
            const before = [1]vk.VkImageMemoryBarrier{.{ .srcAccessMask = color, .dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT, .oldLayout = vk.VK_IMAGE_LAYOUT_GENERAL, .newLayout = vk.VK_IMAGE_LAYOUT_GENERAL, .image = st.image, .subresourceRange = range }};
            s.f.CmdPipelineBarrier(cmd, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &before);
            const region = [1]vk.VkImageBlit{.{
                .srcOffsets = .{ .{ .x = st.src[0][0], .y = st.src[0][1], .z = 0 }, .{ .x = st.src[1][0], .y = st.src[1][1], .z = 1 } },
                .dstOffsets = .{ .{ .x = st.dst[0][0], .y = st.dst[0][1], .z = 0 }, .{ .x = st.dst[1][0], .y = st.dst[1][1], .z = 1 } },
            }};
            s.f.CmdBlitImage(cmd, s.small.color.image, vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, st.image, vk.VK_IMAGE_LAYOUT_GENERAL, 1, &region, vk.VK_FILTER_LINEAR);
            const after = [1]vk.VkImageMemoryBarrier{.{ .srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT, .dstAccessMask = color, .oldLayout = vk.VK_IMAGE_LAYOUT_GENERAL, .newLayout = vk.VK_IMAGE_LAYOUT_GENERAL, .image = st.image, .subresourceRange = range }};
            s.f.CmdPipelineBarrier(cmd, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, 0, 0, null, 0, null, 1, &after);
            return;
        }
        s.bury(.{ .window = s.window });
        s.window = .{};
    }

    fn makeSmall(s: *State, width: u32, height: u32) !Small {
        var t: Small = .{ .width = width, .height = height };
        errdefer s.destroySmall(t);
        for ([2]u32{ color_format, depth_format }, [2]*TextureRec{ &t.color, &t.depth }) |format, r| {
            const is_depth = format == depth_format;
            try check(s.f.CreateImage(s.device, &.{
                .format = format,
                .extent = .{ .width = width, .height = height, .depth = 1 },
                .samples = vk.VK_SAMPLE_COUNT_1_BIT,
                .usage = if (is_depth) vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT else vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
            }, null, &r.image));
            var req: vk.VkMemoryRequirements = undefined;
            s.f.GetImageMemoryRequirements(s.device, r.image, &req);
            try check(s.f.AllocateMemory(s.device, &.{ .allocationSize = req.size, .memoryTypeIndex = try s.memoryType(req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) }, null, &r.memory));
            try check(s.f.BindImageMemory(s.device, r.image, r.memory, 0));
            try check(s.f.CreateImageView(s.device, &.{
                .image = r.image,
                .format = format,
                .subresourceRange = .{ .aspectMask = if (is_depth) vk.VK_IMAGE_ASPECT_DEPTH_BIT else vk.VK_IMAGE_ASPECT_COLOR_BIT },
            }, null, &r.view));
        }
        const views = [2]vk.VkImageView{ t.color.view, t.depth.view };
        try check(s.f.CreateFramebuffer(s.device, &.{ .renderPass = s.small_pass, .attachmentCount = 2, .pAttachments = &views, .width = width, .height = height }, null, &t.framebuffer));
        return t;
    }

    fn makeTarget(s: *State, width: u32, height: u32) !Target {
        var t: Target = .{ .width = width, .height = height };
        errdefer s.destroyTarget(t);
        const r = &t.depth;
        try check(s.f.CreateImage(s.device, &.{
            .format = depth_format,
            .extent = .{ .width = width, .height = height, .depth = 1 },
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .usage = vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        }, null, &r.image));
        var req: vk.VkMemoryRequirements = undefined;
        s.f.GetImageMemoryRequirements(s.device, r.image, &req);
        try check(s.f.AllocateMemory(s.device, &.{ .allocationSize = req.size, .memoryTypeIndex = try s.memoryType(req.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) }, null, &r.memory));
        try check(s.f.BindImageMemory(s.device, r.image, r.memory, 0));
        try check(s.f.CreateImageView(s.device, &.{
            .image = r.image,
            .format = depth_format,
            .subresourceRange = .{ .aspectMask = vk.VK_IMAGE_ASPECT_DEPTH_BIT },
        }, null, &r.view));
        return t;
    }

    fn recordUpload(s: *State, cmd: vk.VkCommandBuffer, u: Upload) void {
        const range: vk.VkImageSubresourceRange = .{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .levelCount = u.levels };
        const to_dst = [1]vk.VkImageMemoryBarrier{.{ .srcAccessMask = 0, .dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT, .oldLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED, .newLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, .image = u.image, .subresourceRange = range }};
        // (After the last frame's sampling of it, if it is being changed.)
        s.f.CmdPipelineBarrier(cmd, vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &to_dst);
        var regions: [16]vk.VkBufferImageCopy = undefined;
        var offset: u64 = 0;
        var w = u.width;
        var h = u.height;
        for (regions[0..u.levels], 0..) |*r, level| {
            r.* = .{
                .bufferOffset = offset,
                .imageSubresource = .{ .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = @intCast(level) },
                .imageExtent = .{ .width = w, .height = h, .depth = 1 },
            };
            offset += @as(u64, w) * h * 4;
            w = @max(1, w / 2);
            h = @max(1, h / 2);
        }
        s.f.CmdCopyBufferToImage(cmd, u.staging.buffer, u.image, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, u.levels, &regions);
        const to_read = [1]vk.VkImageMemoryBarrier{.{ .srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT, .dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT, .oldLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, .newLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, .image = u.image, .subresourceRange = range }};
        s.f.CmdPipelineBarrier(cmd, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, &to_read);
    }

    /// `bytes`, copied into the uniforms' ring: where.
    fn uniforms(s: *State, bytes: []const u8) u32 {
        if (s.ring_at + max_uniforms > ring_size) s.ring_at = 0;
        const at = s.ring_at;
        @memcpy(s.ring_map[at..][0..bytes.len], bytes);
        s.ring_at += uniform_align * ((@as(u32, @intCast(bytes.len)) + uniform_align - 1) / uniform_align);
        return at;
    }
};

// --- Pipelines ------------------------------------------------------------------

pub const Pipeline = struct {
    pipe: vk.VkPipeline,
    uniform_bytes: [max_uniforms]u8 align(16) = undefined,
    uniform_len: usize = 0,

    pub const Draw = struct {
        vertices: u32,
        vertex_offset: u32 = 0,
        count: u32,
        first: u32 = 0,
        indices: ?Indices = null,
        texture: ?Texture = null,
        texture1: ?Texture = null,
        texture2: ?Texture = null,
        viewport: ?Viewport = null,
        scissor: ?Viewport = null,
    };

    pub fn init(gpa: std.mem.Allocator, dev: Device, sh: Shader, options: pipeline.Options) !Pipeline {
        _ = gpa;
        const s = dev;
        var module: vk.VkShaderModule = vk.VK_NULL_HANDLE;
        const words = std.mem.bytesAsSlice(u32, sh.spirv);
        try State.check(s.f.CreateShaderModule(s.device, &.{ .codeSize = sh.spirv.len, .pCode = words.ptr }, null, &module));
        defer s.f.DestroyShaderModule(s.device, module, null);
        const stages = [2]vk.VkPipelineShaderStageCreateInfo{
            .{ .stage = vk.VK_SHADER_STAGE_VERTEX_BIT, .module = module, .pName = "vertex" },
            .{ .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT, .module = module, .pName = "fragment" },
        };
        // Each input: floats, as many as fit before the next (or the
        // vertex's end).
        var attrs: [8]vk.VkVertexInputAttributeDescription = undefined;
        for (options.attributes, 0..) |a, i| {
            var end: u32 = options.vertex_stride;
            for (options.attributes) |b| if (b.offset > a.offset and b.offset < end) {
                end = b.offset;
            };
            const floats = @min(4, (end - a.offset) / 4);
            attrs[i] = .{ .location = a.location, .offset = a.offset, .format = switch (floats) {
                1 => vk.VK_FORMAT_R32_SFLOAT,
                2 => vk.VK_FORMAT_R32G32_SFLOAT,
                3 => vk.VK_FORMAT_R32G32B32_SFLOAT,
                else => vk.VK_FORMAT_R32G32B32A32_SFLOAT,
            } };
        }
        const binding = [1]vk.VkVertexInputBindingDescription{.{ .stride = options.vertex_stride }};
        const vertex_input: vk.VkPipelineVertexInputStateCreateInfo = .{
            .vertexBindingDescriptionCount = 1,
            .pVertexBindingDescriptions = &binding,
            .vertexAttributeDescriptionCount = @intCast(options.attributes.len),
            .pVertexAttributeDescriptions = &attrs,
        };
        const assembly: vk.VkPipelineInputAssemblyStateCreateInfo = .{ .topology = if (options.primitive == .lines) vk.VK_PRIMITIVE_TOPOLOGY_LINE_LIST else vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };
        const viewport_state: vk.VkPipelineViewportStateCreateInfo = .{};
        const raster: vk.VkPipelineRasterizationStateCreateInfo = .{ .cullMode = switch (options.cull) {
            .none => vk.VK_CULL_MODE_NONE,
            .back => vk.VK_CULL_MODE_BACK_BIT,
            .front => vk.VK_CULL_MODE_FRONT_BIT,
        } };
        const multisample: vk.VkPipelineMultisampleStateCreateInfo = .{ .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT };
        const depth: vk.VkPipelineDepthStencilStateCreateInfo = .{
            .depthTestEnable = @intFromBool(sh.depth_test),
            .depthWriteEnable = @intFromBool(sh.depth_test and options.depth_write),
            .depthCompareOp = vk.VK_COMPARE_OP_LESS,
        };
        // Dazzle's "source-over": the colour times its alpha, and what is
        // there times the rest.
        const blend = [1]vk.VkPipelineColorBlendAttachmentState{if (sh.blend) .{
            .blendEnable = vk.VK_TRUE,
            .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
            .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
            .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        } else .{}};
        const blend_state: vk.VkPipelineColorBlendStateCreateInfo = .{ .pAttachments = &blend };
        const dynamic = [2]u32{ vk.VK_DYNAMIC_STATE_VIEWPORT, vk.VK_DYNAMIC_STATE_SCISSOR };
        const dynamic_state: vk.VkPipelineDynamicStateCreateInfo = .{ .dynamicStateCount = 2, .pDynamicStates = &dynamic };
        const info = [1]vk.VkGraphicsPipelineCreateInfo{.{
            .pStages = &stages,
            .pVertexInputState = &vertex_input,
            .pInputAssemblyState = &assembly,
            .pViewportState = &viewport_state,
            .pRasterizationState = &raster,
            .pMultisampleState = &multisample,
            .pDepthStencilState = &depth,
            .pColorBlendState = &blend_state,
            .pDynamicState = &dynamic_state,
            .layout = s.layout,
            .renderPass = s.render_pass,
        }};
        var pipe: [1]vk.VkPipeline = .{vk.VK_NULL_HANDLE};
        try State.check(s.f.CreateGraphicsPipelines(s.device, vk.VK_NULL_HANDLE, 1, &info, null, &pipe));
        return .{ .pipe = pipe[0] };
    }

    pub fn deinit(p: *Pipeline, dev: Device) void {
        dev.f.DestroyPipeline(dev.device, p.pipe, null);
    }

    /// The uniforms for the draws after (copied, as each is recorded).
    pub fn setUniforms(p: *Pipeline, bytes: []const u8) void {
        p.uniform_len = @min(bytes.len, max_uniforms);
        @memcpy(p.uniform_bytes[0..p.uniform_len], bytes[0..p.uniform_len]);
    }

    /// Records a draw into the frame being drawn (`State.begin`).
    pub fn draw(p: *Pipeline, s: *State, d: Draw) !void {
        const cmd = s.cmd orelse return;
        const set = try s.setOf(.{ d.texture, d.texture1, d.texture2 });
        const at = s.uniforms(p.uniform_bytes[0..p.uniform_len]);
        s.f.CmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, p.pipe);
        s.f.CmdBindDescriptorSets(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, s.layout, 0, 1, @ptrCast(&set), 1, @ptrCast(&at));
        // In the frame's image: moved to where the world's view is, and cut
        // to what may be drawn on.
        var vp = d.viewport orelse Viewport{ .x = 0, .y = 0, .width = s.area.width, .height = s.area.height };
        vp.x += s.offset[0];
        vp.y += s.offset[1];
        // Upside down: Dazzle's (and OpenGL's) up, up.
        const vk_vp = [1]vk.VkViewport{.{ .x = @floatFromInt(vp.x), .y = @as(f32, @floatFromInt(vp.y)) + @as(f32, @floatFromInt(vp.height)), .width = @floatFromInt(vp.width), .height = -@as(f32, @floatFromInt(vp.height)), .minDepth = 0, .maxDepth = 1 }};
        s.f.CmdSetViewport(cmd, 0, 1, &vk_vp);
        var sc = d.scissor orelse vp;
        if (d.scissor != null) {
            sc.x += s.offset[0];
            sc.y += s.offset[1];
        }
        const a = s.area;
        const x0 = @max(sc.x, a.x);
        const y0 = @max(sc.y, a.y);
        const x1 = @min(sc.x + @as(i32, @intCast(sc.width)), a.x + @as(i32, @intCast(a.width)));
        const y1 = @min(sc.y + @as(i32, @intCast(sc.height)), a.y + @as(i32, @intCast(a.height)));
        if (x1 <= x0 or y1 <= y0) return;
        const vk_sc = [1]vk.VkRect2D{.{ .offset = .{ .x = x0, .y = y0 }, .extent = .{ .width = @intCast(x1 - x0), .height = @intCast(y1 - y0) } }};
        s.f.CmdSetScissor(cmd, 0, 1, &vk_sc);
        const buf = [1]vk.VkBuffer{s.bufferOf(d.vertices)};
        const off = [1]vk.VkDeviceSize{d.vertex_offset};
        s.f.CmdBindVertexBuffers(cmd, 0, 1, &buf, &off);
        if (d.indices) |ix| {
            s.f.CmdBindIndexBuffer(cmd, s.bufferOf(ix.handle), ix.offset, vk.VK_INDEX_TYPE_UINT16);
            s.f.CmdDrawIndexed(cmd, d.count, 1, d.first, 0, 0);
        } else {
            s.f.CmdDraw(cmd, d.count, 1, d.first, 0);
        }
    }
};

/// The projection (OpenGL's depth, from -1 to 1, as Dazzle's shaders
/// have it) into Vulkan's (from 0 to 1): z' = (z + w) / 2.
pub fn clip(m: [16]f32) [16]f32 {
    var out = m;
    for (0..4) |c| out[c * 4 + 2] = 0.5 * (m[c * 4 + 2] + m[c * 4 + 3]);
    return out;
}

test "the projection's depth into Vulkan's" {
    // A point at depth -1 (near) and 1 (far), with w 1: 0 and 1.
    var m: [16]f32 = @splat(0);
    m[0] = 1;
    m[5] = 1;
    m[10] = 1;
    m[15] = 1;
    const v = clip(m);
    try std.testing.expectEqual(@as(f32, 0.5), v[10]);
    try std.testing.expectEqual(@as(f32, 0.5), v[14]);
    // z' at z = -1: 0.5 * -1 + 0.5 = 0; at z = 1: 1.
    try std.testing.expectEqual(@as(f32, 0), v[10] * -1 + v[14]);
    try std.testing.expectEqual(@as(f32, 1), v[10] * 1 + v[14]);
}
