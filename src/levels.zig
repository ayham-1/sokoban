const std = @import("std");
const fmt = @import("std").fmt;
const raylib = @import("./raylib/raylib.zig");
const Map = @import("map.zig").Map;
const log = @import("log.zig");

const Allocator = std.mem.Allocator;

pub const Levels = struct {
    alloc: Allocator,

    pub fn init(alloc: Allocator) !Levels {
        var levels = Levels{
            .alloc = alloc,
        };

        return levels;
    }

    pub fn getRandomLevel(self: Levels) !Map {
        const collectionData = @embedFile("levels.txt");
        const puzzlesCount = 4544;

        var seed: u64 = @intCast(u64, std.time.milliTimestamp());
        var rnd: std.rand.DefaultPrng = undefined;
        rnd = std.rand.DefaultPrng.init(seed);
        var mapNumber = rnd.random().intRangeAtMost(usize, 0, puzzlesCount);

        var charSeekStart = (10 * 11 * (mapNumber));
        var charSeekEnd = (10 * 11 * (mapNumber + 1));

        var map: Map = Map.init(self.alloc);
        try map.build(collectionData[charSeekStart..charSeekEnd]);
        try map.buildDisplayed();
        return map;
    }
};
