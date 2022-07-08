const std = @import("std");
const raylib = @import("raylib/raylib.zig");

const game = @import("game.zig");
const generator = @import("generator.zig");
const soko = @import("constants.zig");

const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
var zalloc = ZecsiAllocator{};
var alloc = zalloc.allocator();

pub fn main() anyerror!void {
    //var testMap =
    //    \\#www#www#wwwwww#
    //    \\w...w.w.w.w....w
    //    \\w.pb..d.w...w..w
    //    \\w.......w......w
    //    \\w.......w......w
    //    \\wwwwwwwwwwwwwwww
    //    \\
    //;

    //var gameMap = try alloc.alloc(u8, testMap.len);
    //std.mem.copy(u8, gameMap, testMap);

    var map = try generator.get(alloc, 5, 3);
    defer map.deinit();
    try game.start(map.displayed.items);
    defer game.stop();
    //defer alloc.free(gameMap);

    while (!raylib.WindowShouldClose() and !game.won) {
        game.loop(raylib.GetFrameTime());
    }
}
