const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // All the stuff from zig-gamedev
    const zglfw = b.dependency("zglfw", .{
        .target = target,
    });
    const zgpu = b.dependency("zgpu", .{
        .target = target,
    });
    const zgui = b.dependency("zgui", .{
        .target = target,
        .backend = .glfw_wgpu,
        .use_wchar32 = true,
    });
    const zmath = b.dependency("zmath", .{
        .target = target,
    });
    const zmesh = b.dependency("zmesh", .{
        .target = target,
    });
    const zstbi = b.dependency("zstbi", .{
        .target = target,
    });

    // The executable
    const exe = b.addExecutable(.{
        .name = "justStuff",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    exe.root_module.addImport("zgpu", zgpu.module("root"));
    exe.root_module.addImport("zgui", zgui.module("root"));
    exe.root_module.addImport("zmath", zmath.module("root"));
    exe.root_module.addImport("zmesh", zmesh.module("root"));
    exe.root_module.addImport("zstbi", zstbi.module("root"));

    b.installArtifact(exe);
    exe.linkLibrary(zglfw.artifact("glfw"));
    exe.linkLibrary(zgpu.artifact("zdawn"));
    exe.linkLibrary(zgui.artifact("imgui"));
    exe.linkLibrary(zmesh.artifact("zmesh"));
    exe.linkLibrary(zstbi.artifact("zstbi"));
    @import("zgpu").addLibraryPathsTo(exe);

    // Tests
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .name = "tests",
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
