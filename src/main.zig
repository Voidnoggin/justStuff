const std = @import("std");
const graphics = @import("graphics.zig");

pub fn main() !void {
    var heap = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = heap.deinit(); // memory leak check inside deinit
    const alloc = heap.allocator();

    try graphics.init(alloc);
}
