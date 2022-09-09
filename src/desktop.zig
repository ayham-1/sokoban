const std = @import("std");
const raylib = @import("raylib/raylib.zig");
const game = @import("game.zig");
const soko = @import("constants.zig");
const Map = @import("map.zig").Map;
const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
var zalloc = ZecsiAllocator{};
var alloc = zalloc.allocator();

pub fn main() anyerror!void {
    try game.start();
    defer game.stop();
    while (!raylib.WindowShouldClose() and !game.won) {
        game.loop(raylib.GetFrameTime());
    }
}
