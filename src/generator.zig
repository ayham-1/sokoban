//! This modules provides a set of algorithms to generate random sokoban puzzles.
//! Follows a study from University of Minnesota, authored by Bilal Kartal,
//! Nick Sohre and Stephen J. Guy, titled: "Data-Driven Sokoban Puzzle Generation
//! with Monte Carlo Tree Search", published on 2021-06-25.
//!
//! link: http://motion.cs.umn.edu/r/sokoban-pcg
//!
//! This implementation assumes a square map.
//!
//! Formal Citation (needed? appropriate?):
//! Kartal, B., Sohre, N., & Guy, S. (2021). 
//! Data Driven Sokoban Puzzle Generation with Monte Carlo Tree Search. 
//! Proceedings of the AAAI Conference on Artificial Intelligence 
//! and Interactive Digital Entertainment, 
//! 12(1), 
//! 58-64. 
//! Retrieved from https://ojs.aaai.org/index.php/AIIDE/article/view/12859

const std = @import("std");
const log = @import("log.zig");
const soko = @import("constants.zig");
const Map = @import("map.zig").Map;

const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
var zalloc = ZecsiAllocator{};
var alloc = zalloc.allocator();

pub fn generateRandom(levelSize: u8, boxesCount: u8) []u8 {
    var map = soko.MapArray.init(alloc, levelSize);
    for (map.items) |row| {
        row = std.ArrayList(soko.TexType).init(alloc, levelSize);
    }

    _ = boxesCount;
}

/// The higher the return value the higher the congested factor of the sokoban
/// puzzle given. Meaning, puzzles with overlapping box path solutions are
/// valued more. This also factors the amount of obstacles present.
///
/// map - Sokoban puzzle map to evaluate its congestion value.
/// boxPairs - list of bounding rectangles of every box and its final position/goal
///
/// returns the congestion feature analysis factor
pub fn computeCongestion(map: Map, boxGoalPairs: std.ArrayList(soko.BoxGoalPair), wBoxCount: f32, wGoalCount: f32, wObstacleCount: f32) !f32 {
    var congestion: f32 = 0.0;
    for (boxGoalPairs.items) |pair| {
        // retreive the bounding rectangle
        const xMax = @maximum(pair.box.x, pair.goal.x);
        const xMin = @minimum(pair.box.x, pair.goal.x);
        const yMax = @maximum(pair.box.y, pair.goal.y);
        const yMin = @minimum(pair.box.y, pair.goal.y);

        var boundingBox: soko.MapArray = soko.MapArray.init(alloc);
        defer {
            for (boundingBox.items) |item| {
                item.deinit();
            }
            boundingBox.deinit();
        }

        for (map.rows.items[yMin .. yMax + 1]) |row| {
            var newRow = soko.MapRowArray.init(alloc);
            for (row.items[xMin .. xMax + 1]) |item| {
                try newRow.append(item);
            }
            try boundingBox.append(newRow);
        }
        log.warn("{s}", .{boundingBox.items});

        // count & calculate the congestion variables
        var boxArea: f32 = @intToFloat(f32, std.math.absCast((xMax + 1) - xMin + 1) * std.math.absCast((yMax + 1) - yMin));
        var nInitialBoxes: f32 = 0;
        var nGoal: f32 = 0;
        var nObstacles: f32 = 0;
        for (boundingBox.items) |row| {
            for (row.items) |item| {
                switch (item) {
                    .box => nInitialBoxes += 1,
                    .boxDocked => nGoal += 1,
                    .dock => nGoal += 1,
                    .wall => nObstacles += 1,
                    .none => nObstacles += 1,
                    else => {},
                }
            }
        }

        // calculate factor and sum
        congestion += (wBoxCount * nInitialBoxes + wGoalCount * nGoal) / (wObstacleCount * (boxArea - nObstacles));
    }
    return congestion;
}

/// The higher the return value the more "complex" it looks. This is used to
/// punish puzzles that have spatious floors or obstacles, effectively filtering
/// out puzzles that look easy due to its spatious nature.
///
/// map - Sokoban puzzle to evaluate its congestion value.
///
/// returns the number of blocks in a map that are not 3x3 blobs.
pub fn compute3x3Blocks(
    map: Map,
) !f32 {
    // calculate area
    var areaMap: usize = map.rows.items.len * map.rows.items.len;

    // calculate 3x3 area
    var i: usize = 0;
    var j: usize = 0;
    while (i < map.rows.items.len) {
        defer i += 2;
        while (j < map.rows.items.len) {
            var slice3x3: soko.MapArray = soko.MapArray.init(alloc);
            defer j += 2;
            for (map.rows.items[i .. i + 3]) |row| {
                var newRow = soko.MapRowArray.init(alloc);
                for (row.items[j .. j + 3]) |item| {
                    try newRow.append(item);
                }
                try slice3x3.append(newRow);
            }
            log.warn("hello", .{});
            log.warn("{s}", .{(try Map.buildDisplayed(alloc, slice3x3)).items});
        }
    }

    _ = areaMap;
    return 0.0;
}
