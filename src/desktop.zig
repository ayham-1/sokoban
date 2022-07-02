const std = @import("std");

const game = @import("game.zig");
const raylib = @import("raylib/raylib.zig");

const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
var zalloc = ZecsiAllocator{};
var alloc = zalloc.allocator();

pub fn main() anyerror!void {
    var testMap =
        \\#www#www#wwwwww#
        \\w...w...w......w
        \\w.p.b.d........w
        \\w.bdw..bw......w
        \\wwwwwwwwwwwwwww#
        \\
    ;

    var gameMap = try alloc.alloc(u8, testMap.len);
    std.mem.copy(u8, gameMap, testMap);

    try game.start(gameMap);
    defer game.stop();
    defer alloc.free(gameMap);

    while (!raylib.WindowShouldClose() and !game.won) {
        game.loop(raylib.GetFrameTime());
    }
}
