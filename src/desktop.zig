const std = @import("std");
const Allocator = std.mem.Allocator;

const game = @import("game.zig");
const raylib = @import("raylib/raylib.zig");

pub fn main() anyerror!void {
    try game.start();
    defer game.stop();

    while (!raylib.WindowShouldClose()) {
        game.loop(raylib.GetFrameTime());
    }
}
