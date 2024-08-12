const std = @import("std");
const zg = @import("zig_gamedev");

var ctx = Context{};

pub fn init(alloc: std.mem.Allocator) !void {
    _ = alloc;
}

pub const Context = struct {
    gctx: *zg.zgpu.GraphicsContext = undefined,
    cur_res_x: u32 = 1024,
    cur_res_y: u32 = 768,

    render_pipe: zg.zgpu.RenderPipelineHandle = .{},
    uniform_bg: zg.zgpu.BindGroupHandle = undefined,
    uniform_bgl: zg.zgpu.BindGroupLayoutHandle = undefined,
    depth: Depth = undefined,
    draw_commands: ?zg.zgpu.CommandBuffer = null,

    // Mesh Buffers
    vertex_buf: zg.zgpu.BufferHandle = undefined,
    index_buf: zg.zgpu.BufferHandle = undefined,
    meshes: std.ArrayList(Mesh) = undefined,

    // Anything that needs to be uploaded to GPU as a block (like this struct) needs extern to be safe.
    pub const FrameUniforms = extern struct {
        world_to_clip: zg.zmath.Mat,
        camera_position: [4]f32,
        camera_facing: [4]f32,
    };
    pub const DrawUniforms = extern struct {
        object_to_world: zg.zmath.Mat,
        basecolor_roughness: [4]f32,
    };
    pub const Vertex = extern struct {
        position: [3]f32,
        normal: [3]f32,
        color: [4]f32,
    };
    pub const Mesh = extern struct {
        index_offset: u32,
        vertex_offset: i32,
        num_indices: u32,
        num_vertices: u32,

        pub const IndexType = zg.zmesh.Shape.IndexType;
    };
    pub const Depth = extern struct {
        tex: zg.zgpu.TextureHandle = undefined,
        texv: zg.zgpu.TextureViewHandle = undefined,
    };
};
