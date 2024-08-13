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

    // Dependencies Module
    _ = b.addModule("zig_gamedev", .{
        .root_source_file = b.path("src/dependencies.zig"),
        .imports = &.{
            .{ .name = "zmesh", .module = zmesh.module("root") },
            .{ .name = "zgui", .module = zgui.module("root") },
            .{ .name = "zglfw", .module = zglfw.module("root") },
            .{ .name = "zgpu", .module = zgpu.module("root") },
            .{ .name = "zmath", .module = zmath.module("root") },
        },
    });
    const zig_gamedev = b.modules.get("zig_gamedev").?;

    // The executable
    const exe = b.addExecutable(.{
        .name = "justStuff",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (exe.root_module.optimize != .Debug) exe.want_lto = false; // Problems with LTO in Release modes on Windows.
    exe.root_module.addImport("zig_gamedev", zig_gamedev);
    b.installArtifact(exe);
    exe.linkLibrary(zglfw.artifact("glfw"));
    exe.linkLibrary(zgpu.artifact("zdawn"));
    exe.linkLibrary(zgui.artifact("imgui"));
    exe.linkLibrary(zmesh.artifact("zmesh"));
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
