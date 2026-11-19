//! Vulkan's types and constants that Overrun's Vulkan backend (vulkan.zig,
//! as Motu's) uses: declared here (no SDK headers or link libraries needed), as
//! kete's own (src/gfx/vulkan.zig) are, from which these come. Its handles
//! are kete's (it shares its device: see vulkan.zig).

const kv = @import("kete").gfx.vulkan;

pub const VkFlags = u32;

pub const VkBool32 = u32;

pub const VkDeviceSize = u64;

pub const VK_TRUE: VkBool32 = 1;

pub const VK_FALSE: VkBool32 = 0;

pub const VkResult = enum(i32) {
    success = 0,
    _,
};

pub const VkInstance = kv.VkInstance;

pub const VkPhysicalDevice = kv.VkPhysicalDevice;

pub const VkDevice = kv.VkDevice;

pub const VkQueue = kv.VkQueue;

pub const VkCommandBuffer = kv.VkCommandBuffer;

pub const VkCommandPool = u64;

pub const VkRenderPass = u64;

pub const VkFramebuffer = u64;

pub const VkImage = u64;

pub const VkImageView = u64;

pub const VkPipeline = u64;

pub const VkPipelineCache = u64;

pub const VkPipelineLayout = u64;

pub const VkShaderModule = u64;

pub const VkBuffer = u64;

pub const VkDeviceMemory = u64;

pub const VkDescriptorSetLayout = u64;

pub const VkDescriptorPool = u64;

pub const VkDescriptorSet = u64;

pub const VkSampler = u64;

pub const VkFence = u64;

pub const VkSemaphore = u64;

pub const VK_NULL_HANDLE: u64 = 0;

pub const VkStructureType = enum(u32) {
    application_info = 0,
    instance_create_info = 1,
    device_queue_create_info = 2,
    device_create_info = 3,
    submit_info = 4,
    memory_allocate_info = 5,
    buffer_create_info = 12,
    image_create_info = 14,
    image_view_create_info = 15,
    shader_module_create_info = 16,
    pipeline_shader_stage_create_info = 18,
    pipeline_vertex_input_state_create_info = 19,
    pipeline_input_assembly_state_create_info = 20,
    pipeline_viewport_state_create_info = 22,
    pipeline_rasterization_state_create_info = 23,
    pipeline_multisample_state_create_info = 24,
    pipeline_depth_stencil_state_create_info = 25,
    pipeline_color_blend_state_create_info = 26,
    pipeline_dynamic_state_create_info = 27,
    graphics_pipeline_create_info = 28,
    pipeline_layout_create_info = 30,
    sampler_create_info = 31,
    descriptor_set_layout_create_info = 32,
    descriptor_pool_create_info = 33,
    descriptor_set_allocate_info = 34,
    write_descriptor_set = 35,
    framebuffer_create_info = 37,
    render_pass_create_info = 38,
    command_pool_create_info = 39,
    command_buffer_allocate_info = 40,
    command_buffer_begin_info = 42,
    render_pass_begin_info = 43,
    image_memory_barrier = 45,
    fence_create_info = 8,
    semaphore_create_info = 9,
    import_semaphore_fd_info_khr = 1000079000,
    physical_device_timeline_semaphore_features = 1000207000,
    semaphore_type_create_info = 1000207002,
    timeline_semaphore_submit_info = 1000207003,
    semaphore_wait_info = 1000207004,
    semaphore_signal_info = 1000207005,
    physical_device_properties_2 = 1000059001,
    physical_device_drm_properties_ext = 1000353000,
    external_memory_image_create_info = 1000072001,
    import_memory_fd_info_khr = 1000074000,
    memory_fd_properties_khr = 1000074001,
    memory_dedicated_allocate_info = 1000127001,
    image_drm_format_modifier_explicit_create_info_ext = 1000158004,
    _,
};

pub const VkBufferUsageFlags = VkFlags;

pub const VK_BUFFER_USAGE_TRANSFER_SRC_BIT: VkBufferUsageFlags = 0x00000001;

pub const VK_BUFFER_USAGE_TRANSFER_DST_BIT: VkBufferUsageFlags = 0x00000002;

pub const VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT: VkBufferUsageFlags = 0x00000010;

pub const VK_BUFFER_USAGE_INDEX_BUFFER_BIT: VkBufferUsageFlags = 0x00000040;

pub const VK_BUFFER_USAGE_VERTEX_BUFFER_BIT: VkBufferUsageFlags = 0x00000080;

pub const VkShaderModuleCreateInfo = extern struct {
    sType: VkStructureType = .shader_module_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    codeSize: usize,
    pCode: [*]const u32,
};

pub const VkBufferCreateInfo = extern struct {
    sType: VkStructureType = .buffer_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    size: VkDeviceSize,
    usage: VkBufferUsageFlags,
    sharingMode: u32 = 0,
    queueFamilyIndexCount: u32 = 0,
    pQueueFamilyIndices: ?[*]const u32 = null,
};

pub const VkMemoryRequirements = extern struct {
    size: VkDeviceSize,
    alignment: VkDeviceSize,
    memoryTypeBits: u32,
};

pub const VkMemoryAllocateInfo = extern struct {
    sType: VkStructureType = .memory_allocate_info,
    pNext: ?*const anyopaque = null,
    allocationSize: VkDeviceSize,
    memoryTypeIndex: u32,
};

pub const VkViewport = extern struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    minDepth: f32 = 0.0,
    maxDepth: f32 = 1.0,
};

pub const VkOffset2D = extern struct {
    x: i32,
    y: i32,
};

pub const VkExtent2D = extern struct {
    width: u32,
    height: u32,
};

pub const VkRect2D = extern struct {
    offset: VkOffset2D,
    extent: VkExtent2D,
};

pub const VK_PIPELINE_BIND_POINT_GRAPHICS: u32 = 0;

pub const VK_FORMAT_R8_UNORM: u32 = 9;

pub const VK_FORMAT_R8G8B8A8_UNORM: u32 = 37;

pub const VK_FORMAT_B8G8R8A8_UNORM: u32 = 44;

pub const VK_FORMAT_R32_SFLOAT: u32 = 100;

pub const VK_FORMAT_R32G32_SFLOAT: u32 = 103;

pub const VK_FORMAT_R32G32B32_SFLOAT: u32 = 106;

pub const VK_FORMAT_R32G32B32A32_SFLOAT: u32 = 109;

pub const VK_FORMAT_D32_SFLOAT: u32 = 126;

pub const VK_COMPONENT_SWIZZLE_R: u32 = 3;

pub const VK_IMAGE_LAYOUT_UNDEFINED: u32 = 0;

pub const VK_IMAGE_LAYOUT_GENERAL: u32 = 1;

pub const VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL: u32 = 2;

pub const VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL: u32 = 3;

pub const VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL: u32 = 5;

pub const VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL: u32 = 6;

pub const VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL: u32 = 7;

pub const VK_ATTACHMENT_LOAD_OP_LOAD: u32 = 0;

pub const VK_ATTACHMENT_LOAD_OP_CLEAR: u32 = 1;

pub const VK_ATTACHMENT_LOAD_OP_DONT_CARE: u32 = 2;

pub const VK_ATTACHMENT_STORE_OP_STORE: u32 = 0;

pub const VK_ATTACHMENT_STORE_OP_DONT_CARE: u32 = 1;

pub const VK_IMAGE_USAGE_TRANSFER_SRC_BIT: VkFlags = 0x00000001;

pub const VK_IMAGE_USAGE_TRANSFER_DST_BIT: VkFlags = 0x00000002;

pub const VK_IMAGE_USAGE_SAMPLED_BIT: VkFlags = 0x00000004;

pub const VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT: VkFlags = 0x00000010;

pub const VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT: VkFlags = 0x00000020;

pub const VK_IMAGE_ASPECT_COLOR_BIT: VkFlags = 0x00000001;

pub const VK_IMAGE_ASPECT_DEPTH_BIT: VkFlags = 0x00000002;

pub const VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT: VkFlags = 0x00000001;

pub const VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT: VkFlags = 0x00000002;

pub const VK_MEMORY_PROPERTY_HOST_COHERENT_BIT: VkFlags = 0x00000004;

pub const VK_MEMORY_PROPERTY_HOST_CACHED_BIT: VkFlags = 0x00000008;

pub const VK_SHADER_STAGE_VERTEX_BIT: VkFlags = 0x00000001;

pub const VK_SHADER_STAGE_FRAGMENT_BIT: VkFlags = 0x00000010;

pub const VK_SHADER_STAGE_ALL_GRAPHICS: VkFlags = 0x0000001F;

pub const VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT: VkFlags = 0x00000001;

pub const VK_PIPELINE_STAGE_ALL_COMMANDS_BIT: VkFlags = 0x00010000;

pub const VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT: VkFlags = 0x00002000;

pub const VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT: VkFlags = 0x00000080;

pub const VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT: VkFlags = 0x00000400;

pub const VK_PIPELINE_STAGE_TRANSFER_BIT: VkFlags = 0x00001000;

pub const VK_ACCESS_SHADER_READ_BIT: VkFlags = 0x00000020;

pub const VK_ACCESS_COLOR_ATTACHMENT_READ_BIT: VkFlags = 0x00000080;

pub const VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT: VkFlags = 0x00000100;

pub const VK_ACCESS_TRANSFER_READ_BIT: VkFlags = 0x00000800;

pub const VK_ACCESS_TRANSFER_WRITE_BIT: VkFlags = 0x00001000;

pub const VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: u32 = 1;

pub const VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC: u32 = 8;

pub const VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT: VkFlags = 0x00000001;

pub const VK_INDEX_TYPE_UINT16: u32 = 0;

pub const VK_INDEX_TYPE_UINT32: u32 = 1;

pub const VK_CULL_MODE_NONE: VkFlags = 0;

pub const VK_CULL_MODE_FRONT_BIT: VkFlags = 1;

pub const VK_CULL_MODE_BACK_BIT: VkFlags = 2;

pub const VK_FRONT_FACE_COUNTER_CLOCKWISE: u32 = 0;

pub const VK_FRONT_FACE_CLOCKWISE: u32 = 1;

pub const VkOffset3D = extern struct {
    x: i32 = 0,
    y: i32 = 0,
    z: i32 = 0,
};

pub const VkExtent3D = extern struct {
    width: u32,
    height: u32,
    depth: u32 = 1,
};

pub const VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT: u32 = 0x00000200;

pub const VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT: u32 = 1000158000;

pub const VK_QUEUE_FAMILY_EXTERNAL: u32 = 0xFFFFFFFE;

pub const VK_IMAGE_ASPECT_COLOR: VkFlags = 0x00000001;

pub const VK_SEMAPHORE_TYPE_TIMELINE: u32 = 1;

pub const VK_SEMAPHORE_IMPORT_TEMPORARY_BIT: VkFlags = 0x00000001;

pub const VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT: u32 = 0x00000010;

pub const VkSemaphoreCreateInfo = extern struct {
    sType: VkStructureType = .semaphore_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
};

pub const VkSemaphoreTypeCreateInfo = extern struct {
    sType: VkStructureType = .semaphore_type_create_info,
    pNext: ?*const anyopaque = null,
    semaphoreType: u32 = VK_SEMAPHORE_TYPE_TIMELINE,
    initialValue: u64 = 0,
};

pub const VkTimelineSemaphoreSubmitInfo = extern struct {
    sType: VkStructureType = .timeline_semaphore_submit_info,
    pNext: ?*const anyopaque = null,
    waitSemaphoreValueCount: u32 = 0,
    pWaitSemaphoreValues: ?[*]const u64 = null,
    signalSemaphoreValueCount: u32 = 0,
    pSignalSemaphoreValues: ?[*]const u64 = null,
};

pub const VkSemaphoreWaitInfo = extern struct {
    sType: VkStructureType = .semaphore_wait_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    semaphoreCount: u32 = 1,
    pSemaphores: [*]const VkSemaphore,
    pValues: [*]const u64,
};

pub const VkSemaphoreSignalInfo = extern struct {
    sType: VkStructureType = .semaphore_signal_info,
    pNext: ?*const anyopaque = null,
    semaphore: VkSemaphore,
    value: u64,
};

pub const VkPhysicalDeviceTimelineSemaphoreFeatures = extern struct {
    sType: VkStructureType = .physical_device_timeline_semaphore_features,
    pNext: ?*anyopaque = null,
    timelineSemaphore: VkBool32 = VK_TRUE,
};

pub const VkImportSemaphoreFdInfoKHR = extern struct {
    sType: VkStructureType = .import_semaphore_fd_info_khr,
    pNext: ?*const anyopaque = null,
    semaphore: VkSemaphore,
    flags: VkFlags = VK_SEMAPHORE_IMPORT_TEMPORARY_BIT,
    handleType: u32 = VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_SYNC_FD_BIT,
    fd: c_int,
};

pub const VkPhysicalDeviceDrmPropertiesEXT = extern struct {
    sType: VkStructureType = .physical_device_drm_properties_ext,
    pNext: ?*anyopaque = null,
    hasPrimary: VkBool32 = VK_FALSE,
    hasRender: VkBool32 = VK_FALSE,
    primaryMajor: i64 = 0,
    primaryMinor: i64 = 0,
    renderMajor: i64 = 0,
    renderMinor: i64 = 0,
};

pub const VkPhysicalDeviceProperties2 = extern struct {
    sType: VkStructureType = .physical_device_properties_2,
    pNext: ?*anyopaque = null,
    /// `VkPhysicalDeviceProperties`, which is not looked at (it is smaller).
    properties: [1024]u8 align(8) = undefined,
};

pub const VkExtensionProperties = extern struct {
    extensionName: [256]u8,
    specVersion: u32,
};

pub const VkSubresourceLayout = extern struct {
    offset: VkDeviceSize,
    size: VkDeviceSize,
    rowPitch: VkDeviceSize,
    arrayPitch: VkDeviceSize,
    depthPitch: VkDeviceSize,
};

pub const VkImageDrmFormatModifierExplicitCreateInfoEXT = extern struct {
    sType: VkStructureType = .image_drm_format_modifier_explicit_create_info_ext,
    pNext: ?*const anyopaque = null,
    drmFormatModifier: u64,
    drmFormatModifierPlaneCount: u32 = 1,
    pPlaneLayouts: [*]const VkSubresourceLayout,
};

pub const VkExternalMemoryImageCreateInfo = extern struct {
    sType: VkStructureType = .external_memory_image_create_info,
    pNext: ?*const anyopaque = null,
    handleTypes: VkFlags,
};

pub const VkImportMemoryFdInfoKHR = extern struct {
    sType: VkStructureType = .import_memory_fd_info_khr,
    pNext: ?*const anyopaque = null,
    handleType: u32,
    fd: c_int,
};

pub const VkMemoryFdPropertiesKHR = extern struct {
    sType: VkStructureType = .memory_fd_properties_khr,
    pNext: ?*anyopaque = null,
    memoryTypeBits: u32 = 0,
};

pub const VkMemoryDedicatedAllocateInfo = extern struct {
    sType: VkStructureType = .memory_dedicated_allocate_info,
    pNext: ?*const anyopaque = null,
    image: VkImage = VK_NULL_HANDLE,
    buffer: VkBuffer = VK_NULL_HANDLE,
};

pub const VkFenceCreateInfo = extern struct {
    sType: VkStructureType = .fence_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
};

pub const VkClearAttachment = extern struct {
    aspectMask: VkFlags,
    colorAttachment: u32,
    clearValue: VkClearValue,
};

pub const VkClearRect = extern struct {
    rect: VkRect2D,
    baseArrayLayer: u32 = 0,
    layerCount: u32 = 1,
};

pub const VkApplicationInfo = extern struct {
    sType: VkStructureType = .application_info,
    pNext: ?*const anyopaque = null,
    pApplicationName: ?[*:0]const u8 = "Kete",
    applicationVersion: u32 = 1,
    pEngineName: ?[*:0]const u8 = "Kete",
    engineVersion: u32 = 1,
    apiVersion: u32 = (1 << 22) | (1 << 12), // Vulkan 1.1
};

pub const VkInstanceCreateInfo = extern struct {
    sType: VkStructureType = .instance_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    pApplicationInfo: ?*const VkApplicationInfo = null,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32 = 0,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8 = null,
};

pub const VkQueueFamilyProperties = extern struct {
    queueFlags: VkFlags,
    queueCount: u32,
    timestampValidBits: u32,
    minImageTransferGranularity: VkExtent3D,
};

pub const VkMemoryType = extern struct {
    propertyFlags: VkFlags,
    heapIndex: u32,
};

pub const VkMemoryHeap = extern struct {
    size: VkDeviceSize,
    flags: VkFlags,
};

pub const VkPhysicalDeviceMemoryProperties = extern struct {
    memoryTypeCount: u32,
    memoryTypes: [32]VkMemoryType,
    memoryHeapCount: u32,
    memoryHeaps: [16]VkMemoryHeap,
};

pub const VkDeviceQueueCreateInfo = extern struct {
    sType: VkStructureType = .device_queue_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    queueFamilyIndex: u32,
    queueCount: u32 = 1,
    pQueuePriorities: [*]const f32,
};

pub const VkDeviceCreateInfo = extern struct {
    sType: VkStructureType = .device_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    queueCreateInfoCount: u32 = 1,
    pQueueCreateInfos: [*]const VkDeviceQueueCreateInfo,
    enabledLayerCount: u32 = 0,
    ppEnabledLayerNames: ?[*]const [*:0]const u8 = null,
    enabledExtensionCount: u32 = 0,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8 = null,
    pEnabledFeatures: ?*const anyopaque = null,
};

pub const VkCommandPoolCreateInfo = extern struct {
    sType: VkStructureType = .command_pool_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0x00000002, // VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
    queueFamilyIndex: u32,
};

pub const VkCommandBufferAllocateInfo = extern struct {
    sType: VkStructureType = .command_buffer_allocate_info,
    pNext: ?*const anyopaque = null,
    commandPool: VkCommandPool,
    level: u32 = 0, // PRIMARY
    commandBufferCount: u32 = 1,
};

pub const VkCommandBufferBeginInfo = extern struct {
    sType: VkStructureType = .command_buffer_begin_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0x00000001, // ONE_TIME_SUBMIT_BIT
    pInheritanceInfo: ?*const anyopaque = null,
};

pub const VkSubmitInfo = extern struct {
    sType: VkStructureType = .submit_info,
    pNext: ?*const anyopaque = null,
    waitSemaphoreCount: u32 = 0,
    pWaitSemaphores: ?*const anyopaque = null,
    pWaitDstStageMask: ?*const u32 = null,
    commandBufferCount: u32 = 1,
    pCommandBuffers: [*]const VkCommandBuffer,
    signalSemaphoreCount: u32 = 0,
    pSignalSemaphores: ?*const anyopaque = null,
};

pub const VkAttachmentDescription = extern struct {
    flags: VkFlags = 0,
    format: u32,
    samples: u32,
    loadOp: u32,
    storeOp: u32,
    stencilLoadOp: u32 = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    stencilStoreOp: u32 = VK_ATTACHMENT_STORE_OP_DONT_CARE,
    initialLayout: u32 = VK_IMAGE_LAYOUT_UNDEFINED,
    finalLayout: u32,
};

pub const VkAttachmentReference = extern struct {
    attachment: u32,
    layout: u32,
};

pub const VkSubpassDescription = extern struct {
    flags: VkFlags = 0,
    pipelineBindPoint: u32 = VK_PIPELINE_BIND_POINT_GRAPHICS,
    inputAttachmentCount: u32 = 0,
    pInputAttachments: ?*const anyopaque = null,
    colorAttachmentCount: u32 = 1,
    pColorAttachments: [*]const VkAttachmentReference,
    pResolveAttachments: ?[*]const VkAttachmentReference = null,
    pDepthStencilAttachment: ?*const VkAttachmentReference = null,
    preserveAttachmentCount: u32 = 0,
    pPreserveAttachments: ?*const u32 = null,
};

pub const VkSubpassDependency = extern struct {
    srcSubpass: u32,
    dstSubpass: u32,
    srcStageMask: VkFlags,
    dstStageMask: VkFlags,
    srcAccessMask: VkFlags,
    dstAccessMask: VkFlags,
    dependencyFlags: VkFlags = 0,
};

pub const VkRenderPassCreateInfo = extern struct {
    sType: VkStructureType = .render_pass_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    attachmentCount: u32,
    pAttachments: [*]const VkAttachmentDescription,
    subpassCount: u32 = 1,
    pSubpasses: [*]const VkSubpassDescription,
    dependencyCount: u32 = 0,
    pDependencies: ?[*]const VkSubpassDependency = null,
};

pub const VkImageCreateInfo = extern struct {
    sType: VkStructureType = .image_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    imageType: u32 = 1, // 2D
    format: u32,
    extent: VkExtent3D,
    mipLevels: u32 = 1,
    arrayLayers: u32 = 1,
    samples: u32,
    tiling: u32 = 0, // OPTIMAL
    usage: VkFlags,
    sharingMode: u32 = 0,
    queueFamilyIndexCount: u32 = 0,
    pQueueQueueFamilyIndices: ?*const u32 = null,
    initialLayout: u32 = VK_IMAGE_LAYOUT_UNDEFINED,
};

pub const VkComponentMapping = extern struct {
    r: u32 = 0,
    g: u32 = 0,
    b: u32 = 0,
    a: u32 = 0,
};

pub const VkImageSubresourceRange = extern struct {
    aspectMask: VkFlags,
    baseMipLevel: u32 = 0,
    levelCount: u32 = 1,
    baseArrayLayer: u32 = 0,
    layerCount: u32 = 1,
};

pub const VkImageViewCreateInfo = extern struct {
    sType: VkStructureType = .image_view_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    image: VkImage,
    viewType: u32 = 1, // 2D
    format: u32,
    components: VkComponentMapping = .{},
    subresourceRange: VkImageSubresourceRange,
};

pub const VkFramebufferCreateInfo = extern struct {
    sType: VkStructureType = .framebuffer_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    renderPass: VkRenderPass,
    attachmentCount: u32,
    pAttachments: [*]const VkImageView,
    width: u32,
    height: u32,
    layers: u32 = 1,
};

pub const VkClearValue = extern union {
    color: [4]f32,
    depth_stencil: extern struct {
        depth: f32,
        stencil: u32,
    },
};

pub const VkRenderPassBeginInfo = extern struct {
    sType: VkStructureType = .render_pass_begin_info,
    pNext: ?*const anyopaque = null,
    renderPass: VkRenderPass,
    framebuffer: VkFramebuffer,
    renderArea: VkRect2D,
    clearValueCount: u32,
    pClearValues: [*]const VkClearValue,
};

pub const VkImageSubresourceLayers = extern struct {
    aspectMask: VkFlags = VK_IMAGE_ASPECT_COLOR_BIT,
    mipLevel: u32 = 0,
    baseArrayLayer: u32 = 0,
    layerCount: u32 = 1,
};

pub const VkImageCopy = extern struct {
    srcSubresource: VkImageSubresourceLayers = .{},
    srcOffset: VkOffset3D = .{},
    dstSubresource: VkImageSubresourceLayers = .{},
    dstOffset: VkOffset3D = .{},
    extent: VkExtent3D,
};

pub const VkBufferImageCopy = extern struct {
    bufferOffset: VkDeviceSize = 0,
    bufferRowLength: u32 = 0,
    bufferImageHeight: u32 = 0,
    imageSubresource: VkImageSubresourceLayers = .{},
    imageOffset: VkOffset3D = .{},
    imageExtent: VkExtent3D,
};

pub const VkDescriptorSetLayoutBinding = extern struct {
    binding: u32,
    descriptorType: u32,
    descriptorCount: u32 = 1,
    stageFlags: VkFlags,
    pImmutableSamplers: ?*const anyopaque = null,
};

pub const VkDescriptorSetLayoutCreateInfo = extern struct {
    sType: VkStructureType = .descriptor_set_layout_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    bindingCount: u32,
    pBindings: [*]const VkDescriptorSetLayoutBinding,
};

pub const VkDescriptorPoolSize = extern struct {
    type: u32,
    descriptorCount: u32,
};

pub const VkDescriptorPoolCreateInfo = extern struct {
    sType: VkStructureType = .descriptor_pool_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    maxSets: u32,
    poolSizeCount: u32,
    pPoolSizes: [*]const VkDescriptorPoolSize,
};

pub const VkDescriptorSetAllocateInfo = extern struct {
    sType: VkStructureType = .descriptor_set_allocate_info,
    pNext: ?*const anyopaque = null,
    descriptorPool: VkDescriptorPool,
    descriptorSetCount: u32 = 1,
    pSetLayouts: [*]const VkDescriptorSetLayout,
};

pub const VkSamplerCreateInfo = extern struct {
    sType: VkStructureType = .sampler_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    magFilter: u32,
    minFilter: u32,
    mipmapMode: u32 = 0,
    addressModeU: u32 = 2, // CLAMP_TO_EDGE
    addressModeV: u32 = 2, // CLAMP_TO_EDGE
    addressModeW: u32 = 2, // CLAMP_TO_EDGE
    mipLodBias: f32 = 0.0,
    anisotropyEnable: VkBool32 = VK_FALSE,
    maxAnisotropy: f32 = 1.0,
    compareEnable: VkBool32 = VK_FALSE,
    compareOp: u32 = 0,
    minLod: f32 = 0.0,
    maxLod: f32 = 0.0,
    borderColor: u32 = 0,
    unnormalizedCoordinates: VkBool32 = VK_FALSE,
};

pub const VkDescriptorImageInfo = extern struct {
    sampler: VkSampler,
    imageView: VkImageView,
    imageLayout: u32,
};

pub const VkImageMemoryBarrier = extern struct {
    sType: VkStructureType = .image_memory_barrier,
    pNext: ?*const anyopaque = null,
    srcAccessMask: VkFlags,
    dstAccessMask: VkFlags,
    oldLayout: u32,
    newLayout: u32,
    srcQueueFamilyIndex: u32 = 0xFFFFFFFF,
    dstQueueFamilyIndex: u32 = 0xFFFFFFFF,
    image: VkImage,
    subresourceRange: VkImageSubresourceRange,
};

pub const VkDescriptorBufferInfo = extern struct {
    buffer: VkBuffer,
    offset: VkDeviceSize,
    range: VkDeviceSize,
};

pub const VkWriteDescriptorSet = extern struct {
    sType: VkStructureType = .write_descriptor_set,
    pNext: ?*const anyopaque = null,
    dstSet: VkDescriptorSet,
    dstBinding: u32,
    dstArrayElement: u32 = 0,
    descriptorCount: u32 = 1,
    descriptorType: u32,
    pImageInfo: ?*const VkDescriptorImageInfo = null,
    pBufferInfo: ?*const VkDescriptorBufferInfo = null,
    pTexelBufferView: ?*const anyopaque = null,
};

pub const VkPipelineShaderStageCreateInfo = extern struct {
    sType: VkStructureType = .pipeline_shader_stage_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    stage: VkFlags,
    module: VkShaderModule,
    pName: [*:0]const u8,
    pSpecializationInfo: ?*const anyopaque = null,
};

pub const VkVertexInputBindingDescription = extern struct {
    binding: u32 = 0,
    stride: u32,
    inputRate: u32 = 0, // VERTEX
};

pub const VkVertexInputAttributeDescription = extern struct {
    location: u32,
    binding: u32 = 0,
    format: u32,
    offset: u32,
};

pub const VkPipelineVertexInputStateCreateInfo = extern struct {
    sType: VkStructureType = .pipeline_vertex_input_state_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    vertexBindingDescriptionCount: u32,
    pVertexBindingDescriptions: ?[*]const VkVertexInputBindingDescription,
    vertexAttributeDescriptionCount: u32,
    pVertexAttributeDescriptions: ?[*]const VkVertexInputAttributeDescription,
};

pub const VkPipelineInputAssemblyStateCreateInfo = extern struct {
    sType: VkStructureType = .pipeline_input_assembly_state_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    topology: u32 = 3, // TRIANGLE_LIST
    primitiveRestartEnable: VkBool32 = VK_FALSE,
};

pub const VkPipelineViewportStateCreateInfo = extern struct {
    sType: VkStructureType = .pipeline_viewport_state_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    viewportCount: u32 = 1,
    pViewports: ?*const VkViewport = null,
    scissorCount: u32 = 1,
    pScissors: ?*const VkRect2D = null,
};

pub const VkPipelineRasterizationStateCreateInfo = extern struct {
    sType: VkStructureType = .pipeline_rasterization_state_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    depthClampEnable: VkBool32 = VK_FALSE,
    rasterizerDiscardEnable: VkBool32 = VK_FALSE,
    polygonMode: u32 = 0, // FILL
    cullMode: VkFlags = VK_CULL_MODE_BACK_BIT,
    frontFace: u32 = VK_FRONT_FACE_COUNTER_CLOCKWISE,
    depthBiasEnable: VkBool32 = VK_FALSE,
    depthBiasConstantFactor: f32 = 0,
    depthBiasClamp: f32 = 0,
    depthBiasSlopeFactor: f32 = 0,
    lineWidth: f32 = 1.0,
};

pub const VkPipelineMultisampleStateCreateInfo = extern struct {
    sType: VkStructureType = .pipeline_multisample_state_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    rasterizationSamples: u32 = 4,
    sampleShadingEnable: VkBool32 = VK_FALSE,
    minSampleShading: f32 = 1.0,
    pSampleMask: ?*const u32 = null,
    alphaToCoverageEnable: VkBool32 = VK_FALSE,
    alphaToOneEnable: VkBool32 = VK_FALSE,
};

pub const VkStencilOpState = extern struct {
    failOp: u32 = 0,
    passOp: u32 = 0,
    depthFailOp: u32 = 0,
    compareOp: u32 = 0,
    compareMask: u32 = 0,
    writeMask: u32 = 0,
    reference: u32 = 0,
};

pub const VkPipelineDepthStencilStateCreateInfo = extern struct {
    sType: VkStructureType = .pipeline_depth_stencil_state_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    depthTestEnable: VkBool32 = VK_TRUE,
    depthWriteEnable: VkBool32 = VK_TRUE,
    depthCompareOp: u32 = 3, // LESS_OR_EQUAL
    depthBoundsTestEnable: VkBool32 = VK_FALSE,
    stencilTestEnable: VkBool32 = VK_FALSE,
    front: VkStencilOpState = .{},
    back: VkStencilOpState = .{},
    minDepthBounds: f32 = 0.0,
    maxDepthBounds: f32 = 1.0,
};

pub const VkPipelineColorBlendAttachmentState = extern struct {
    blendEnable: VkBool32 = VK_FALSE,
    srcColorBlendFactor: u32 = 1,
    dstColorBlendFactor: u32 = 0,
    colorBlendOp: u32 = 0,
    srcAlphaBlendFactor: u32 = 1,
    dstAlphaBlendFactor: u32 = 0,
    alphaBlendOp: u32 = 0,
    colorWriteMask: VkFlags = 0xF,
};

pub const VkPipelineColorBlendStateCreateInfo = extern struct {
    sType: VkStructureType = .pipeline_color_blend_state_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    logicOpEnable: VkBool32 = VK_FALSE,
    logicOp: u32 = 0,
    attachmentCount: u32 = 1,
    pAttachments: [*]const VkPipelineColorBlendAttachmentState,
    blendConstants: [4]f32 = .{ 0, 0, 0, 0 },
};

pub const VkPipelineDynamicStateCreateInfo = extern struct {
    sType: VkStructureType = .pipeline_dynamic_state_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    dynamicStateCount: u32,
    pDynamicStates: [*]const u32,
};

pub const VkPushConstantRange = extern struct {
    stageFlags: VkFlags,
    offset: u32 = 0,
    size: u32,
};

pub const VkPipelineLayoutCreateInfo = extern struct {
    sType: VkStructureType = .pipeline_layout_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    setLayoutCount: u32,
    pSetLayouts: ?[*]const VkDescriptorSetLayout,
    pushConstantRangeCount: u32 = 0,
    pPushConstantRanges: ?[*]const VkPushConstantRange = null,
};

pub const VkGraphicsPipelineCreateInfo = extern struct {
    sType: VkStructureType = .graphics_pipeline_create_info,
    pNext: ?*const anyopaque = null,
    flags: VkFlags = 0,
    stageCount: u32 = 2,
    pStages: [*]const VkPipelineShaderStageCreateInfo,
    pVertexInputState: *const VkPipelineVertexInputStateCreateInfo,
    pInputAssemblyState: *const VkPipelineInputAssemblyStateCreateInfo,
    pTessellationState: ?*const anyopaque = null,
    pViewportState: *const VkPipelineViewportStateCreateInfo,
    pRasterizationState: *const VkPipelineRasterizationStateCreateInfo,
    pMultisampleState: *const VkPipelineMultisampleStateCreateInfo,
    pDepthStencilState: *const VkPipelineDepthStencilStateCreateInfo,
    pColorBlendState: *const VkPipelineColorBlendStateCreateInfo,
    pDynamicState: *const VkPipelineDynamicStateCreateInfo,
    layout: VkPipelineLayout,
    renderPass: VkRenderPass,
    subpass: u32 = 0,
    basePipelineHandle: VkPipeline = VK_NULL_HANDLE,
    basePipelineIndex: i32 = -1,
};

pub const VkImageBlit = extern struct {
    srcSubresource: VkImageSubresourceLayers = .{},
    srcOffsets: [2]VkOffset3D,
    dstSubresource: VkImageSubresourceLayers = .{},
    dstOffsets: [2]VkOffset3D,
};

// (Not among kete's: what Motu's pipelines and textures need besides.)
pub const VK_BLEND_FACTOR_ONE: u32 = 1;
pub const VK_BLEND_FACTOR_SRC_ALPHA: u32 = 6;
pub const VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA: u32 = 7;
pub const VK_FILTER_NEAREST: u32 = 0;
pub const VK_FILTER_LINEAR: u32 = 1;
pub const VK_SAMPLER_MIPMAP_MODE_NEAREST: u32 = 0;
pub const VK_SAMPLER_MIPMAP_MODE_LINEAR: u32 = 1;
pub const VK_SAMPLER_ADDRESS_MODE_REPEAT: u32 = 0;
pub const VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT: u32 = 1;
pub const VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE: u32 = 2;
pub const VK_PRIMITIVE_TOPOLOGY_LINE_LIST: u32 = 1;
pub const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST: u32 = 3;
pub const VK_COMPARE_OP_LESS: u32 = 1;
pub const VK_DYNAMIC_STATE_VIEWPORT: u32 = 0;
pub const VK_DYNAMIC_STATE_SCISSOR: u32 = 1;
pub const VK_SAMPLE_COUNT_1_BIT: u32 = 1;
pub const VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT: VkFlags = 0x00000100;
pub const VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT: VkFlags = 0x00000200;
pub const VK_PIPELINE_STAGE_VERTEX_INPUT_BIT: VkFlags = 0x00000004;
pub const VK_PIPELINE_STAGE_VERTEX_SHADER_BIT: VkFlags = 0x00000008;
pub const VK_PIPELINE_STAGE_HOST_BIT: VkFlags = 0x00004000;
pub const VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT: VkFlags = 0x00000200;
pub const VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT: VkFlags = 0x00000400;
pub const VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT: VkFlags = 0x00000004;
pub const VK_ACCESS_INDEX_READ_BIT: VkFlags = 0x00000002;
pub const VK_ACCESS_UNIFORM_READ_BIT: VkFlags = 0x00000008;
pub const VK_ACCESS_HOST_WRITE_BIT: VkFlags = 0x00004000;
pub const VK_SUBPASS_EXTERNAL: u32 = 0xFFFFFFFF;
pub const VK_WHOLE_SIZE: u64 = 0xFFFFFFFFFFFFFFFF;
