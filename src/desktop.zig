const std = @import("std");
const raylib = @import("raylib/raylib.zig");
const game = @import("game.zig");
const soko = @import("constants.zig");
const Map = @import("map.zig").Map;
const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
var zalloc = ZecsiAllocator{};
var alloc = zalloc.allocator();

pub fn main() anyerror!void {
    const testMap =
        \\..........
        \\.b........
        \\...d......
        \\...d......
        \\..p.......
        \\wwwww.....
        \\wwwww.....
        \\wwwww.....
        \\wwwww.....
        \\wwwwwwwwwb
    ;
    var gameMap = try alloc.alloc(u8, testMap.len);
    std.mem.copy(u8, gameMap, testMap);
    defer alloc.free(gameMap);
    var map = Map.init(alloc);
    try map.build(gameMap);
    try game.start(map);
    defer game.stop();
    while (!raylib.WindowShouldClose() and !game.won) {
        game.loop(raylib.GetFrameTime());
    }
}
