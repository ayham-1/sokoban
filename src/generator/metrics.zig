const std = @import("std");
const log = @import("../log.zig");
const soko = @import("../constants.zig");
const NodeState = @import("nodestate.zig").NodeState;

const Allocator = std.mem.Allocator;

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
pub fn computeMapEval(
    weightSlice3x3: f32,
    weightCongestion: f32,
    weightBoxCount: f32,
    slice3x3Val: i32,
    congestionVal: f32,
    boxCount: usize,
) f32 {
    const k = 200;
    return (weightSlice3x3 * @intToFloat(f32, slice3x3Val) +
        weightCongestion * congestionVal +
        weightBoxCount * @intToFloat(f32, boxCount)) / k;
}

/// The higher the return value the higher the congested factor of the sokoban
/// puzzle given. Meaning, puzzles with overlapping box path solutions are
/// valued more. This also factors the amount of obstacles present.
///
/// state - Sokoban puzzle generate node state
/// boxPairs - list of bounding rectangles of every box and its final position/goal
///
/// returns the congestion feature analysis factor
pub fn computeCongestion(
    state: *NodeState,
    wBoxCount: f32,
    wGoalCount: f32,
    wObstacleCount: f32,
) f32 {
    var areaMod: usize = 0;
    for (state.boxes.items) |boxPos, boxId| {
        var goalPos = if (state.goals.items.len == 0) boxPos else state.goals.items[boxId];

        var minX = @minimum(goalPos.x, boxPos.x);
        var maxX = @maximum(goalPos.x, boxPos.x);
        var minY = @minimum(goalPos.y, boxPos.y);
        var maxY = @maximum(goalPos.y, boxPos.y);
        var width = maxX - minX + 2;
        var height = maxY - minY + 2;
        var area: usize = width * height;

        var nObstacles: usize = 0;
        for (state.obstacles.items) |obstacle| {
            if (obstacle.x >= minX and obstacle.x <= maxX) {
                if (obstacle.y >= minY and obstacle.y <= maxY) {
                    nObstacles += 1;
                }
            }
        }
        areaMod += area - nObstacles;
    }
    var numerator: f32 = wBoxCount * @intToFloat(f32, state.boxes.items.len) +
        wGoalCount * @intToFloat(f32, state.goals.items.len);
    var denominator: f32 = wObstacleCount * @intToFloat(f32, areaMod);

    return numerator / denominator;
}

/// The higher the return value the more "complex" the state looks. This is
/// used to punish puzzles that have spatious floors or obstacles, effectively
/// filtering out puzzles that look easy due to its spatious nature.
///
/// state - Sokoban puzzle generate node state
///
/// returns the number of blocks in a map that are not 3x3 blobs.
pub fn compute3x3Blocks(
    alloc: Allocator,
    state: *NodeState,
) i32 {
    var areaMap: i32 = state.width * state.height;
    var possibleHeightSlices: usize = std.math.divCeil(usize, state.height, 3) catch unreachable;
    var possibleWidthSlices: usize = std.math.divCeil(usize, state.width, 3) catch unreachable;
    var nSimilar3x3: i32 = 0;
    var nSlicesFloors = std.ArrayList(std.ArrayList(u32)).initCapacity(
        alloc,
        possibleHeightSlices,
    ) catch unreachable;

    var nSlicesObstacles = std.ArrayList(std.ArrayList(u32)).initCapacity(
        alloc,
        possibleHeightSlices,
    ) catch unreachable;

    // initialize nSlices counting
    var i: usize = 0;
    while (i < possibleHeightSlices) {
        defer i += 1;
        var newRow = std.ArrayList(u32).initCapacity(alloc, possibleWidthSlices) catch unreachable;
        newRow.appendNTimes(0, possibleWidthSlices) catch unreachable;
        nSlicesFloors.append(newRow) catch unreachable;
    }
    i = 0;
    while (i < possibleHeightSlices) {
        defer i += 1;
        var newRow = std.ArrayList(u32).initCapacity(alloc, possibleWidthSlices) catch unreachable;
        newRow.appendNTimes(0, possibleWidthSlices) catch unreachable;
        nSlicesObstacles.append(newRow) catch unreachable;
    }

    // count number of floors and obstacles and add them to the appropriate
    // counter
    //
    // update nSimilar3x3 before doing obstacles
    //
    if (state.floors.items.len > 9) {
        for (state.floors.items) |pos| {
            var slicePosX = @divFloor(pos.x, 3);
            var slicePosY = @divFloor(pos.y, 3);

            nSlicesFloors.items[slicePosY].items[slicePosX] += 1;
        }
    }

    for (nSlicesFloors.items) |row| {
        for (row.items) |item| {
            if (item >= 9) {
                nSimilar3x3 += 1;
            }
        }
    }

    if (state.obstacles.items.len > 9) {
        for (state.obstacles.items) |pos| {
            var slicePosX = @divFloor(pos.x, 3);
            var slicePosY = @divFloor(pos.y, 3);

            nSlicesObstacles.items[slicePosY].items[slicePosX] += 1;
        }
    }

    for (nSlicesObstacles.items) |row| {
        for (row.items) |item| {
            if (item >= 9) {
                nSimilar3x3 += 1;
            }
        }
    }

    return areaMap - (9 * nSimilar3x3);
}
