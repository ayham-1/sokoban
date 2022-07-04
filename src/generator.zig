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
//! TODO: remove public property

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

/// Computes map evaluation
///
/// weightSlice3x3 - weight value
/// weightCongestion - weight value
/// weightBoxCount - weight value
///
/// slice3x3Val - value
/// congestionVal - value
/// boxCount - value
///
/// returns - float value of evaluation
pub fn computeMapEval(weightSlice3x3: f32, weightCongestion: f32, weightBoxCount: f32, slice3x3Val: i32, congestionVal: f32, boxCount: i32) !f32 {
    const k = 50;
    return (weightSlice3x3 * slice3x3Val + weightCongestion * congestionVal + weightBoxCount * boxCount) / k;
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
) !i32 {
    // calculate area
    var areaMap: i32 = @intCast(i32, map.rows.items.len * map.rows.items[0].items.len);

    // generate map search state
    var mapCheckState = try std.ArrayList(std.ArrayList(bool)).initCapacity(alloc, map.rows.items.len);
    for (map.rows.items) |row| {
        var newRow = try std.ArrayList(bool).initCapacity(alloc, row.items.len);
        for (row.items) |_| {
            try newRow.append(false);
        }
        try mapCheckState.append(newRow);
    }
    defer {
        for (mapCheckState.items) |row| {
            row.deinit();
        }
        mapCheckState.deinit();
    }

    // count number of 3x3 area which are all similar
    var nSimilar3x3: i32 = 0;
    for (map.rows.items) |row, i| {
        var j: usize = 0;
        while (j + 3 < row.items.len) {
            defer j += 1;
            if (mapCheckState.items[i].items[j] == true) continue;

            var slice3x3: soko.MapArray = soko.MapArray.init(alloc);
            defer {
                for (slice3x3.items) |sliceRow| {
                    sliceRow.deinit();
                }
                slice3x3.deinit();
            }
            var iOffset: usize = @minimum(map.rows.items.len, i + 3);
            var jOffset: usize = @minimum(map.rows.items[0].items.len, j + 3);
            for (map.rows.items[i..iOffset]) |sliceRow| {
                var newRow = soko.MapRowArray.init(alloc);
                for (sliceRow.items[j..jOffset]) |sliceItem| {
                    try newRow.append(sliceItem);
                }
                try slice3x3.append(newRow);
            }

            if (slice3x3.items.len != 3) break;
            if (slice3x3.items[0].items.len != 3) break;
            var prevItem: soko.TexType = slice3x3.items[0].items[0];
            var similar: bool = true;
            sliceCheck: for (slice3x3.items) |sliceRow| {
                for (sliceRow.items) |sliceItem| {
                    if (sliceItem != prevItem) {
                        similar = false;
                        break :sliceCheck;
                    }
                }
            }

            if (similar) {
                // update all mapCheckState relevant data
                for (map.rows.items[i..iOffset]) |_, sliceI| {
                    for (map.rows.items[sliceI].items[j..jOffset]) |_, sliceJ| {
                        mapCheckState.items[i + sliceI].items[j + sliceJ] = true;
                    }
                }

                j += 2;
                nSimilar3x3 += 1;
            }
        }
    }
    return areaMap - (9 * nSimilar3x3);
}
