const std = @import("std");
const zg = @import("zig_gamedev");
const glfw = zg.zglfw;
const gpu = zg.zgpu;
const zm = zg.zmath;
const wgsl = @import("shader_wgsl.zig");

var ctx = Context{};

pub fn shouldContinue() bool {
    const no_exit_requested = !ctx.window.shouldClose() and ctx.window.getKey(.escape) != .press;
    glfw.pollEvents();
    return no_exit_requested;
}

pub fn drawFrame() void {
    const gctx = ctx.gctx;
    const fb_width = gctx.swapchain_descriptor.width;
    const fb_height = gctx.swapchain_descriptor.height;

    const eye = zm.f32x4(0.0, 0.0, 0.0, 0.0);
    const up = zm.f32x4(0.0, 1.0, 0.0, 0.0);
    const forward = zm.f32x4(0.0, 0.0, 1.0, 0.0);
    const az = zm.normalize3(forward);
    const ax = zm.normalize3(zm.cross3(up, az));
    const ay = zm.normalize3(zm.cross3(az, ax));
    const cam_world_to_view = zm.Mat{
        zm.f32x4(ax[0], ax[1], ax[2], -zm.dot3(ax, eye)[0]),
        zm.f32x4(ay[0], ay[1], ay[2], -zm.dot3(ay, eye)[0]),
        zm.f32x4(az[0], az[1], az[2], -zm.dot3(az, eye)[0]),
        zm.f32x4(0.0, 0.0, 0.0, 1.0),
    };

    const near = 1.0;
    const fov_y = 0.33 * std.math.pi;
    const f = 1.0 / std.math.tan(fov_y / 2.0);
    const a: f32 = @as(f32, @floatFromInt(fb_width)) / @as(f32, @floatFromInt(fb_height));
    const cam_view_to_clip = zm.Mat{
        zm.f32x4(f / a, 0.0, 0.0, 0.0),
        zm.f32x4(0.0, f, 0.0, 0.0),
        zm.f32x4(0.0, 0.0, 0.0, near),
        zm.f32x4(0.0, 0.0, 1.0, 0.0),
    };

    // Lookup common resources which may be needed for all the passes.
    const depth_texv = gctx.lookupResource(ctx.depth.texv) orelse return;
    const uniform_bg = gctx.lookupResource(ctx.uniform_bg) orelse return;

    const swapchain_texv = gctx.swapchain.getCurrentTextureView();
    defer swapchain_texv.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        const frame_unif_mem = frame_unif_mem: {
            const mem = gctx.uniformsAllocate(Context.FrameUniforms, 1);
            mem.slice[0] = .{
                .world_to_clip = zm.mul(cam_view_to_clip, cam_world_to_view),
            };
            break :frame_unif_mem mem;
        };

        pass: {
            const render_pipe = gctx.lookupResource(ctx.render_pipe) orelse break :pass;

            const pass = gpu.beginRenderPassSimple(
                encoder,
                .clear,
                swapchain_texv,
                .{ .r = 0.0, .g = 0.0, .b = 0.5, .a = 1.0 },
                depth_texv,
                0.0,
            );
            defer gpu.endReleasePass(pass);

            pass.setPipeline(render_pipe);
            pass.setBindGroup(0, uniform_bg, &.{frame_unif_mem.offset});
        }
        break :commands encoder.finish(null);
    };
    defer commands.release();

    gctx.submit(&.{commands});
}

pub fn init(alloc: std.mem.Allocator) !void {
    try glfw.init();
    ctx.window = try glfw.Window.create(ctx.cur_res_x, ctx.cur_res_y, "just stuff", null);

    ctx.gctx = try gpu.GraphicsContext.create(
        alloc,
        .{
            .window = ctx.window,
            .fn_getTime = @ptrCast(&glfw.getTime),
            .fn_getFramebufferSize = @ptrCast(&glfw.Window.getFramebufferSize),
            .fn_getWin32Window = @ptrCast(&glfw.getWin32Window),
            .fn_getX11Display = @ptrCast(&glfw.getX11Display),
            .fn_getX11Window = @ptrCast(&glfw.getX11Window),
            .fn_getWaylandDisplay = @ptrCast(&glfw.getWaylandDisplay),
            .fn_getWaylandSurface = @ptrCast(&glfw.getWaylandWindow),
            .fn_getCocoaWindow = @ptrCast(&glfw.getCocoaWindow),
        },
        .{},
    );

    // Uniform buffer and layout
    ctx.uniform_bgl = ctx.gctx.createBindGroupLayout(&.{
        gpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, true, 0),
    });
    defer ctx.gctx.releaseResource(ctx.uniform_bgl);

    ctx.uniform_bg = ctx.gctx.createBindGroup(ctx.uniform_bgl, &.{
        .{
            .binding = 0,
            .buffer_handle = ctx.gctx.uniforms.buffer,
            .offset = 0,
            .size = @max(@sizeOf(Context.FrameUniforms), @sizeOf(Context.DrawUniforms)),
        },
    });

    const depth_tex = ctx.gctx.createTexture(.{
        .usage = .{ .render_attachment = true },
        .dimension = .tdim_2d,
        .size = .{
            .width = ctx.gctx.swapchain_descriptor.width,
            .height = ctx.gctx.swapchain_descriptor.height,
            .depth_or_array_layers = 1,
        },
        .format = .depth32_float,
        .mip_level_count = 1,
        .sample_count = 1,
    });
    const depth_texv = ctx.gctx.createTextureView(depth_tex, .{});
    ctx.depth = .{ .tex = depth_tex, .texv = depth_texv };

    try createPipeline(alloc);
}

pub fn deinit(alloc: std.mem.Allocator) void {
    ctx.gctx.destroy(alloc);
    glfw.terminate();
}

pub fn createPipeline(alloc: std.mem.Allocator) !void {
    const pl = ctx.gctx.createPipelineLayout(&.{ ctx.uniform_bgl, ctx.uniform_bgl });
    defer ctx.gctx.releaseResource(pl);

    const vs_mod = gpu.createWgslShaderModule(ctx.gctx.device, wgsl.basic.vs, null);
    defer vs_mod.release();

    const fs_mod = gpu.createWgslShaderModule(ctx.gctx.device, wgsl.basic.fs, null);
    defer fs_mod.release();

    const color_targets = [_]gpu.wgpu.ColorTargetState{.{
        .format = gpu.GraphicsContext.swapchain_format,
        .blend = &gpu.wgpu.BlendState{ .color = gpu.wgpu.BlendComponent{
            .operation = .add,
            .src_factor = .one,
            .dst_factor = .zero,
        }, .alpha = gpu.wgpu.BlendComponent{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .zero,
        } },
    }};

    const vertex_attributes = [_]gpu.wgpu.VertexAttribute{
        .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
    };

    const vertex_buffers = [_]gpu.wgpu.VertexBufferLayout{.{
        .array_stride = @sizeOf(Context.Vertex),
        .attribute_count = vertex_attributes.len,
        .attributes = &vertex_attributes,
    }};

    const pipe_desc = gpu.wgpu.RenderPipelineDescriptor{
        .vertex = gpu.wgpu.VertexState{
            .module = vs_mod,
            .entry_point = "main",
            .buffer_count = vertex_buffers.len,
            .buffers = &vertex_buffers,
        },
        .fragment = &gpu.wgpu.FragmentState{
            .module = fs_mod,
            .entry_point = "main",
            .target_count = color_targets.len,
            .targets = &color_targets,
        },
        .depth_stencil = &gpu.wgpu.DepthStencilState{
            .format = .depth32_float,
            .depth_write_enabled = true,
            .depth_compare = .greater,
        },
        .primitive = .{
            .topology = .triangle_list,
            .front_face = .cw,
            .cull_mode = .back,
        },
    };
    ctx.gctx.createRenderPipelineAsync(alloc, pl, pipe_desc, &ctx.render_pipe);
}

pub const Context = struct {
    window: *glfw.Window = undefined,
    gctx: *gpu.GraphicsContext = undefined,
    cur_res_x: i32 = 1024,
    cur_res_y: i32 = 768,

    render_pipe: gpu.RenderPipelineHandle = .{},
    uniform_bg: gpu.BindGroupHandle = undefined,
    uniform_bgl: gpu.BindGroupLayoutHandle = undefined,
    depth: Depth = undefined,
    draw_commands: ?gpu.wgpu.CommandBuffer = null,

    // Mesh Buffers
    vertex_buf: gpu.BufferHandle = undefined,
    index_buf: gpu.BufferHandle = undefined,
    meshes: std.ArrayList(Mesh) = undefined,

    // Anything that needs to be uploaded to GPU as a block (like this struct) needs extern to be safe.
    pub const FrameUniforms = extern struct {
        world_to_clip: zg.zmath.Mat,
    };
    pub const DrawUniforms = extern struct {
        object_to_world: zg.zmath.Mat,
    };
    pub const Vertex = extern struct {
        position: [3]f32,
    };
    pub const Mesh = extern struct {
        index_offset: u32,
        vertex_offset: i32,
        num_indices: u32,
        num_vertices: u32,

        pub const IndexType = zg.zmesh.Shape.IndexType;
    };
    pub const Depth = extern struct {
        tex: gpu.TextureHandle = undefined,
        texv: gpu.TextureViewHandle = undefined,
    };
};
