// zig fmt: off
const common =
\\  struct DrawUniforms {
\\      object_to_world: mat4x4<f32>,
\\  }
\\  @group(1) @binding(0) var<uniform> draw_uniforms: DrawUniforms;
\\
\\  struct FrameUniforms {
\\      world_to_clip: mat4x4<f32>,
\\  }
\\  @group(0) @binding(0) var<uniform> frame_uniforms: FrameUniforms;
;
pub const basic = struct {
    pub const vs = common ++
    \\  struct VertexOut {
    \\      @builtin(position) position_clip: vec4<f32>,
    \\  }
    \\  @vertex fn main(
    \\      @location(0) position: vec3<f32>,
    \\  ) -> VertexOut {
    \\      var output: VertexOut;
    \\      output.position_clip = vec4(position, 1.0) * draw_uniforms.object_to_world * frame_uniforms.world_to_clip;
    \\      return output;
    \\  }
    ;
    pub const fs = common ++
    \\  @fragment fn main(
    \\      @location(0) position: vec3<f32>,
    \\  ) -> @location(0) vec4<f32> {
    \\      return vec4(1.0, 0.5, 1.0, 1.0);
    \\  }
    ;
};
// zig fmt: on
