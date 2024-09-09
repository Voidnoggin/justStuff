const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const zmath = @import("zmath");
const zmesh = @import("zmesh");
const zstbi = @import("zstbi");
const wgsl = @import("shader_wgsl.zig");

//---------- PUBLIC METHODS ---------//

pub fn init(alloc: std.mem.Allocator) !void {
    try zglfw.init();
    ctx.window = try zglfw.Window.create(ctx.cur_res_x, ctx.cur_res_y, "just stuff", null);

    ctx.gctx = try zgpu.GraphicsContext.create(
        alloc,
        .{
            .window = ctx.window,
            .fn_getTime = @ptrCast(&zglfw.getTime),
            .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
            .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
            .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
            .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
            .fn_getWaylandDisplay = @ptrCast(&zglfw.getWaylandDisplay),
            .fn_getWaylandSurface = @ptrCast(&zglfw.getWaylandWindow),
            .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
        },
        .{},
    );

    // Uniform buffer and layout
    ctx.uniform_bgl = ctx.gctx.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, true, 0),
        zgpu.textureEntry(1, .{ .fragment = true }, .float, .tvdim_2d, false),
        zgpu.samplerEntry(2, .{ .fragment = true }, .filtering),
    });
    defer ctx.gctx.releaseResource(ctx.uniform_bgl);

    const sampler = ctx.gctx.createSampler(.{});

    ctx.uniform_bg = ctx.gctx.createBindGroup(ctx.uniform_bgl, &.{
        .{
            .binding = 0,
            .buffer_handle = ctx.gctx.uniforms.buffer,
            .offset = 0,
            .size = @max(@sizeOf(Context.FrameUniforms), @sizeOf(Context.DrawUniforms)),
        },

        .{
            .binding = 1,
            .texture_view_handle = ctx.material.base_view,
        },

        .{ .binding = 2, .sampler_handle = sampler },
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
    zglfw.terminate();
}

pub fn shouldContinue() bool {
    const no_exit_requested = !ctx.window.shouldClose() and ctx.window.getKey(.escape) != .press;
    zglfw.pollEvents();
    return no_exit_requested;
}

const Object = struct {
    indices: std.ArrayList(u32) = undefined,
    vertices: std.ArrayList(Context.Vertex) = undefined,
    texture: zstbi.Image = undefined,
};
var single_object: Object = .{};

pub fn loadGltfMesh(alloc: std.mem.Allocator, file_name: [:0]const u8) !void {
    var gltf_indices = std.ArrayList(u32).init(alloc);
    defer gltf_indices.deinit();

    var gltf_positions = std.ArrayList([3]f32).init(alloc);
    defer gltf_positions.deinit();

    var gltf_normals = std.ArrayList([3]f32).init(alloc);
    defer gltf_normals.deinit();

    var gltf_texcoords = std.ArrayList([2]f32).init(alloc);
    defer gltf_texcoords.deinit();

    zmesh.init(alloc);
    defer zmesh.deinit();

    const gltf_data = try zmesh.io.parseAndLoadFile(file_name);
    defer zmesh.io.freeData(gltf_data);

    try zmesh.io.appendMeshPrimitive(
        gltf_data,
        0,
        0,
        &gltf_indices,
        &gltf_positions,
        &gltf_normals,
        &gltf_texcoords,
        null,
    );

    var vertices = try std.ArrayList(Context.Vertex).initCapacity(alloc, gltf_positions.items.len);
    defer vertices.deinit();

    for (gltf_positions.items, 0..) |vert, i| {
        try vertices.append(.{
            .position = vert,
            .normal = gltf_normals.items[i],
            .texcoord = gltf_texcoords.items[i],
        });
    }

    if (gltf_data.textures) |textures| {
        if (textures[0].name) |name| {
            std.debug.print("texture name: {s}\n", .{name});
        } else std.debug.print("texture (no name)\n", .{});
        const image_bytes_ptr = @as([*]u8, @ptrCast(textures[0].image.?.buffer_view.?.buffer.data.?));
        const image_bytes = image_bytes_ptr[0..textures[0].image.?.buffer_view.?.buffer.size];
        for (0..16) |i| {
            std.debug.print("{x}\n", .{image_bytes[i]});
        }

        zstbi.init(alloc);
        defer zstbi.deinit();

        var image = try zstbi.Image.loadFromMemory(image_bytes, 4);
        defer image.deinit();

        single_object.texture = image;
    } else std.debug.print("no textures", .{});

    single_object.indices = gltf_indices;
    single_object.vertices = vertices;
}

pub fn processGltfMesh() !void {
    const vertices = single_object.vertices;
    const image = single_object.texture;
    ctx.vertex_buf = ctx.gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = vertices.items.len * @sizeOf(Context.Vertex),
    });
    ctx.gctx.queue.writeBuffer(ctx.gctx.lookupResource(ctx.vertex_buf).?, 0, Context.Vertex, vertices.items);

    ctx.index_buf = ctx.gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = single_object.indices.items.len * @sizeOf(u32),
    });
    ctx.gctx.queue.writeBuffer(ctx.gctx.lookupResource(ctx.index_buf).?, 0, u32, single_object.indices.items);

    ctx.num_indices = @as(u32, @intCast(single_object.indices.items.len));

    const base_tex = ctx.gctx.createTexture(.{
        .usage = .{ .texture_binding = true, .copy_dst = true },
        .size = .{ .width = image.width, .height = image.height, .depth_or_array_layers = 1 },
        .format = zgpu.imageInfoToTextureFormat(
            image.num_components,
            image.bytes_per_component,
            image.is_hdr,
        ),
    });
    ctx.gctx.queue.writeTexture(
        .{ .texture = ctx.gctx.lookupResource(base_tex).? },
        .{
            .bytes_per_row = image.bytes_per_row,
            .rows_per_image = image.height,
        },
        .{ .width = image.width, .height = image.height },
        u8,
        image.data,
    );
    ctx.material = .{ .base_map = base_tex };

    const base_tex_view = ctx.gctx.createTextureView(base_tex, .{});
    ctx.material = .{ .base_view = base_tex_view };
}

pub fn drawFrame() !void {
    const gctx = ctx.gctx;
    const fb_width = gctx.swapchain_descriptor.width;
    const fb_height = gctx.swapchain_descriptor.height;

    const eye = zmath.f32x4(-0.08, -0.05, -0.08, 0);
    const focus = zmath.f32x4s(0);
    const up = zmath.f32x4(0, 0, 1, 0);
    const view = zmath.lookAtRh(eye, focus, up);

    const near = 0.01;
    const fov_y = 0.33 * std.math.pi;
    const f = 1.0 / std.math.tan(fov_y / 2.0);
    const a: f32 = @as(f32, @floatFromInt(fb_width)) / @as(f32, @floatFromInt(fb_height));
    const projection = zmath.Mat{ // infinite far plane, reversed z
        zmath.f32x4(f / a, 0.0, 0.0, 0.0),
        zmath.f32x4(0.0, f, 0.0, 0.0),
        zmath.f32x4(0.0, 0.0, 0.0, -1.0),
        zmath.f32x4(0.0, 0.0, near, 0.0),
    };

    const depth_texv = gctx.lookupResource(ctx.depth.texv) orelse return error.a;
    const uniform_bg = gctx.lookupResource(ctx.uniform_bg) orelse return error.b;
    const vertex_buf_info = gctx.lookupResourceInfo(ctx.vertex_buf) orelse return error.c;
    const index_buf_info = gctx.lookupResourceInfo(ctx.index_buf) orelse return error.d;

    const swapchain_texv = gctx.swapchain.getCurrentTextureView();
    defer swapchain_texv.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        const frame_unif_mem = frame_unif_mem: {
            const mem = gctx.uniformsAllocate(Context.FrameUniforms, 1);
            mem.slice[0] = .{
                .world_to_clip = zmath.transpose(zmath.mul(view, projection)),
            };
            break :frame_unif_mem mem;
        };

        pass: {
            const render_pipe = gctx.lookupResource(ctx.render_pipe) orelse break :pass;

            const pass = zgpu.beginRenderPassSimple(
                encoder,
                .clear,
                swapchain_texv,
                .{ .r = 0.2, .g = 0.1, .b = 0.0, .a = 1.0 },
                depth_texv,
                0.0,
            );
            defer zgpu.endReleasePass(pass);

            pass.setVertexBuffer(0, vertex_buf_info.gpuobj.?, 0, vertex_buf_info.size);
            pass.setIndexBuffer(
                index_buf_info.gpuobj.?,
                .uint32,
                0,
                index_buf_info.size,
            );

            pass.setPipeline(render_pipe);
            pass.setBindGroup(0, uniform_bg, &.{frame_unif_mem.offset});

            const mem = gctx.uniformsAllocate(Context.DrawUniforms, 1);
            mem.slice[0] = .{
                .object_to_world = zmath.identity(),
            };
            pass.setBindGroup(1, uniform_bg, &.{mem.offset});
            pass.drawIndexed(ctx.num_indices, 1, 0, 0, 0);
        }
        break :commands encoder.finish(null);
    };
    defer commands.release();

    gctx.submit(&.{commands});

    if (ctx.gctx.present() == .swap_chain_resized) { // if the window size changed
        // Release old depth texture.
        ctx.gctx.releaseResource(ctx.depth.texv);
        ctx.gctx.destroyResource(ctx.depth.tex);

        // Create a new depth texture to match the new window size.
        ctx.depth.tex = ctx.gctx.createTexture(.{
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
        ctx.depth.texv = ctx.gctx.createTextureView(ctx.depth.tex, .{});
    }
}

//---------- FILE PRIVATES ----------//

var ctx = Context{};

fn createPipeline(alloc: std.mem.Allocator) !void {
    const pl = ctx.gctx.createPipelineLayout(&.{ ctx.uniform_bgl, ctx.uniform_bgl });
    defer ctx.gctx.releaseResource(pl);

    const vs_mod = zgpu.createWgslShaderModule(ctx.gctx.device, wgsl.basic.vs, null);
    defer vs_mod.release();

    const fs_mod = zgpu.createWgslShaderModule(ctx.gctx.device, wgsl.basic.fs, null);
    defer fs_mod.release();

    const color_targets = [_]zgpu.wgpu.ColorTargetState{.{
        .format = zgpu.GraphicsContext.swapchain_format,
        .blend = &zgpu.wgpu.BlendState{ .color = zgpu.wgpu.BlendComponent{
            .operation = .add,
            .src_factor = .one,
            .dst_factor = .zero,
        }, .alpha = zgpu.wgpu.BlendComponent{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .zero,
        } },
    }};

    const vertex_attributes = [_]zgpu.wgpu.VertexAttribute{
        .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
        .{ .format = .float32x3, .offset = @offsetOf(Context.Vertex, "normal"), .shader_location = 1 },
        .{ .format = .float32x2, .offset = @offsetOf(Context.Vertex, "texcoord"), .shader_location = 2 },
    };

    const vertex_buffers = [_]zgpu.wgpu.VertexBufferLayout{.{
        .array_stride = @sizeOf(Context.Vertex),
        .attribute_count = vertex_attributes.len,
        .attributes = &vertex_attributes,
    }};

    const pipe_desc = zgpu.wgpu.RenderPipelineDescriptor{
        .vertex = zgpu.wgpu.VertexState{
            .module = vs_mod,
            .entry_point = "main",
            .buffer_count = vertex_buffers.len,
            .buffers = &vertex_buffers,
        },
        .fragment = &zgpu.wgpu.FragmentState{
            .module = fs_mod,
            .entry_point = "main",
            .target_count = color_targets.len,
            .targets = &color_targets,
        },
        .depth_stencil = &zgpu.wgpu.DepthStencilState{
            .format = .depth32_float,
            .depth_write_enabled = true,
            .depth_compare = .greater,
        },
        .primitive = .{
            .topology = .triangle_list,
            .front_face = .ccw,
            .cull_mode = .back,
        },
    };
    ctx.gctx.createRenderPipelineAsync(alloc, pl, pipe_desc, &ctx.render_pipe);
}

const Context = struct {
    window: *zglfw.Window = undefined,
    gctx: *zgpu.GraphicsContext = undefined,
    cur_res_x: i32 = 1024,
    cur_res_y: i32 = 768,

    render_pipe: zgpu.RenderPipelineHandle = .{},
    uniform_bg: zgpu.BindGroupHandle = undefined,
    uniform_bgl: zgpu.BindGroupLayoutHandle = undefined,
    depth: Depth = undefined,
    draw_commands: ?zgpu.wgpu.CommandBuffer = null,

    vertex_buf: zgpu.BufferHandle = undefined,
    index_buf: zgpu.BufferHandle = undefined,
    texture: zgpu.TextureHandle = undefined,
    material: Material = undefined,
    num_indices: u32 = 0,

    // Anything that needs to be uploaded to GPU as a block (like this struct) needs extern to be safe.
    pub const FrameUniforms = extern struct {
        world_to_clip: zmath.Mat,
    };
    pub const DrawUniforms = extern struct {
        object_to_world: zmath.Mat,
    };
    pub const Vertex = extern struct {
        position: [3]f32,
        normal: [3]f32,
        texcoord: [2]f32,
    };
    pub const Mesh = extern struct {
        index_offset: u32,
        vertex_offset: i32,
        num_indices: u32,
        num_vertices: u32,
    };
    pub const Depth = extern struct {
        tex: zgpu.TextureHandle = undefined,
        texv: zgpu.TextureViewHandle = undefined,
    };
    pub const Material = extern struct {
        base_map: zgpu.TextureHandle = undefined,
        base_view: zgpu.TextureViewHandle = undefined,
    };
};
