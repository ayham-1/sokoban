const std = @import("std");
const raylib = @import("raylib/raylib.zig");

const game = @import("game.zig");
const puzzle = @import("puzzle.zig");
const soko = @import("constants.zig");

const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
var zalloc = ZecsiAllocator{};
var alloc = zalloc.allocator();

pub fn main() anyerror!void {
    var testMap =
        \\#www#www#wwwwww#
        \\w...w...w......w
        \\w.pbbbd........w
        \\w.bbdd..w......w
        \\w.bdbd..w......w
        \\wwwwwwwwwwwwwwww
        \\
    ;

    var gameMap = try alloc.alloc(u8, testMap.len);
    std.mem.copy(u8, gameMap, testMap);

    try game.start(gameMap);
    defer game.stop();
    defer alloc.free(gameMap);

    // TESTING
    //
    var boxPairs = std.ArrayList(soko.BoxGoalPair).init(alloc);
    defer boxPairs.deinit();
    try boxPairs.append(soko.BoxGoalPair{ .box = soko.Pos{ .x = 4, .y = 2 }, .goal = soko.Pos{ .x = 6, .y = 2 } });
    try boxPairs.append(soko.BoxGoalPair{ .box = soko.Pos{ .x = 2, .y = 3 }, .goal = soko.Pos{ .x = 5, .y = 3 } });
    std.log.warn("{}", .{try puzzle.computeCongestion(game.map, boxPairs, 1, 1, 1)});

    while (!raylib.WindowShouldClose() and !game.won) {
        game.loop(raylib.GetFrameTime());
    }
}
