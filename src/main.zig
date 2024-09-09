const std = @import("std");
const graphics = @import("graphics.zig");

pub fn main() !void {
    var heap = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = heap.deinit(); // memory leak check inside deinit
    const alloc = heap.allocator();

	try graphics.loadGltfMesh(alloc, "assets/Avocado.glb");

    try graphics.init(alloc);
    defer graphics.deinit(alloc);

	try graphics.processGltfMesh();

    var was_error: ?anyerror = null;
    while (graphics.shouldContinue()) {
        graphics.drawFrame() catch |err| {
            std.debug.print("\n\nERROR: {}\n\n", .{err});
            was_error = err;
            break;
        };
    }
    if (was_error) |err| return err;
}
