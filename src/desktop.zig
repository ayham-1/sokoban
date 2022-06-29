const std = @import("std");

const game = @import("game.zig");
const raylib = @import("raylib/raylib.zig");

const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
var zalloc = ZecsiAllocator{};
var alloc = zalloc.allocator();

pub fn main() anyerror!void {
    var testMap =
        \\#www#www#
        \\w...w...w
        \\w.p.b.d.w
        \\wwwwwwwww
        \\
    ;

    var gameMap = try alloc.alloc(u8, testMap.len);
    std.mem.copy(u8, gameMap, testMap);

    try game.start(gameMap);
    defer game.stop();

    while (!raylib.WindowShouldClose()) {
        game.loop(raylib.GetFrameTime());
    }
}
