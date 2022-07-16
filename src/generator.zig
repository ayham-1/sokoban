//! This modules provides a set of algorithms to generate random sokoban puzzles.
//! Follows (losely) a study from University of Minnesota, authored by Bilal Kartal,
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
//! TODO: remove assumption of square map

const std = @import("std");
const log = @import("log.zig");
const soko = @import("constants.zig");
const Map = @import("map.zig").Map;
const Puzzle = @import("puzzle.zig").Puzzle;
usingnamespace @import("generator/metrics.zig");

const nodezig = @import("generator/node.zig");
const GeneratedPuzzle = nodezig.GeneratedPuzzle;
const Node = nodezig.Node;
const NodeActionSet = nodezig.NodeActionSet;

const Allocator = std.mem.Allocator;
const RndGen = std.rand.DefaultPrng;

var seed: u64 = undefined;
var rnd: std.rand.Xoshiro256 = undefined;

pub fn get(alloc: Allocator, levelSize: u8, boxCount: u8) !*Map {
    try std.os.getrandom(std.mem.asBytes(&seed));
    rnd = std.rand.DefaultPrng.init(seed);

    var map: Map = Map.init(alloc);

    var i: usize = 0;
    var j: usize = 0;
    while (i < levelSize) {
        defer i += 1;
        j = 0;
        var newRow: soko.MapRowArray = soko.MapRowArray.init(alloc);
        while (j < levelSize) {
            defer j += 1;
            try newRow.append(soko.Textile{ .id = map.highestId, .tex = soko.TexType.wall });
            map.highestId += 1;
        }
        try map.rows.append(newRow);
    }

    // plob worker in a random place
    var workerX = rnd.random().intRangeAtMost(usize, 1, levelSize - 2);
    var workerY = rnd.random().intRangeAtMost(usize, 1, levelSize - 2);

    map.rows.items[workerY].items[workerX].tex = .worker;
    map.setWorkerPos();

    try map.buildDisplayed();
    map.sizeHeight = levelSize;
    map.sizeWidth = levelSize;

    nodezig.generatedPuzzles = std.ArrayList(GeneratedPuzzle).init(alloc);
    var parentNode = Node.initAsParent(alloc, &map, boxCount);
    parentNode.iterator(500);

    var finalMap: *Map = try map.clone();
    var highestPuzzle: GeneratedPuzzle = nodezig.generatedPuzzles.items[0];
    for (nodezig.generatedPuzzles.items) |puzzle| {
        if (puzzle.score >= highestPuzzle.score)
            highestPuzzle = puzzle;
    }

    finalMap.deinit();
    finalMap = highestPuzzle.map;
    log.info("score: {d:.3}", .{highestPuzzle.score});
    log.info("generated puzzles: {}", .{nodezig.generatedPuzzles.items.len});

    finalMap.setWorkerPos();
    try finalMap.buildDisplayed();
    return finalMap;
}
