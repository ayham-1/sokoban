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
//! TODO: remove public property
//! TODO: remov assumption of square map

const std = @import("std");
const log = @import("log.zig");
const soko = @import("constants.zig");
const Map = @import("map.zig").Map;
const Puzzle = @import("puzzle.zig").Puzzle;

const Allocator = std.mem.Allocator;

pub fn get(alloc: Allocator, levelSize: u8, boxesCount: u8) !Map {
    var map: Map = Map.init(alloc);

    var i: usize = 0;
    var j: usize = 0;
    while (i < levelSize) {
        defer i += 1;
        j = 0;
        var newRow: soko.MapRowArray = soko.MapRowArray.init(alloc);
        while (j < levelSize) {
            defer j += 1;
            try newRow.append(soko.Textile{ .id = map.highestId, .tex = soko.TexType.floor });
            map.highestId += 1;
        }
        try map.rows.append(newRow);
    }

    try map.buildDisplayed();
    std.log.warn("\n{s}", .{map.displayed.items});

    _ = boxesCount;
    return map;
}

const NodeActionSet = enum(u3) { deleteWalls, placeBoxes, freezeLevel };
const NodeFreezedActionSet = enum(u2) { moveAgent, finalizeLevel };
const Node = struct {
    alloc: Allocator,
    parent: *Node = undefined,
    rootGeneratedPuzzles: std.ArrayList(.{ *soko.Map, f32 }) = undefined,
    children: std.ArrayList(*Node),

    isFreezed: bool = false,

    visits: usize = 0,
    totalEvaluation: f32 = 0,

    puzzle: Puzzle = undefined,
    boxGoal: std.AutoArrayHashMap(u8, soko.BoxGoalPair) = undefined,

    pub fn initAsParent(alloc: Allocator, map: Map) Node {
        var node = Node{ .alloc = alloc, .puzzle = Puzzle.init(alloc, map), .children = std.ArrayList(*Node).init(alloc), .boxGoal = std.AutoArrayHashMap(u8, soko.BoxGoalpair).init(alloc) };
        return node;
    }

    pub fn initAsChild(alloc: Allocator, map: Map, parent: *Node) Node {
        var result = Node.initAsParent(alloc, map);
        result.parent = parent;
        return result;
    }
    pub fn initAsFreezedChild(alloc: Allocator, map: Map, parent: *Node) Node {
        var result = Node.initAsChild(alloc, map, parent);
        result.isFreezed = true;
        result.boxGoal = std.AutoArrayHashMap(u8, soko.BoxGoalPair).init(alloc);
        return result;
    }

    pub fn iterate(self: *Node) !void {
        // get the list of best leaves
        var bestLeaves: std.ArrayList(*Node) = std.ArrayList(*Node).init(self.alloc);
        defer bestLeaves.deinit();
        bestLeaves = self.getListOfBestLeaves(bestLeaves);

        for (bestLeaves) |leaf| {
            if (leaf.visits == 0) {
                leaf.evalBackProp();
            } else {
                leaf.expand();
                leaf.evalBackProp();
            }
        }
    }

    fn evalBackProp(self: *Node) void {
        // calculate congestionVal
        var goalPositions = self.puzzle.map.getBoxPositions();
        for (goalPositions.items) |goal| {
            if (self.boxGoal.get(goal[0])) |pair| {
                var newPair = soko.BoxGoalPair{ .box = pair.box, .goal = goal[1] };
                self.boxGoal.put(goal[0], newPair);
            }
        }
        var passablePairs = std.ArrayList(soko.BoxGoalPair).init(self.alloc);
        defer passablePairs.deinit();
        for (self.boxGoal.keys) |key| {
            passablePairs.append(self.boxGoal.get(key));
        }
        var congestionVal = computeCongestion(self.alloc, self.puzzle.map, passablePairs, 4, 4, 1);

        // calculate evaluation using computeMapEval
        var slice3x3Val = compute3x3Blocks(self.alloc, self.puzzle.map);
        var score = computeMapEval(10, 5, 1, slice3x3Val, congestionVal);

        // backpropagate to update parent nodes
        self.visits += 1;
        self.totalEvaluation += score;
        var currentNode: *Node = self;
        while (currentNode.parent != undefined) {
            currentNode.parent.visits += 1;
            currentNode.parent.totalEvaluation += score;

            currentNode = currentNode.parent;
        }
    }

    pub fn expand(self: *Node) void {
        if (!self.isFreezed) {
            for (NodeActionSet) |action| {
                self.children.append(Node.initAsChild(self.alloc, self.puzzle.map, self));
                switch (action) {
                    .deleteWalls => self.children[self.children.items.len - 1].deleteWalls(),
                    .placeBoxes => self.children[self.children.items.len - 1].placeBoxes(),
                    .freezeLevel => self.children[self.children.items.len - 1].freezeLevel(),
                }
            }
        } else {
            for (NodeFreezedActionSet) |action| {
                self.children.append(Node.initAsFreezedChild(self.alloc, self.puzzle.map, self));
                switch (action) {
                    .moveAgent => self.children[self.children.items.len - 1].moveAgent(),
                    .evalBackPropLevel => self.children[self.children.items.len - 1].finalizeLevel(),
                }
            }
        }
    }

    pub fn deleteWall(self: *Node) !void {
        // get all obstacles adjacent to free space non-diagonally.
        var obstacles = std.ArrayList(soko.Pos).init(self.alloc);
        defer obstacles.deinit();

        for (self.puzzle.map.rows.items) |row, i| {
            for (row.items) |item, j| {
                if (item == .floor or item == .worker) {
                    if (j - 1 >= 0 and self.puzzle.map.rows.items[i].items[j - 1] == .wall) {
                        try obstacles.append(soko.Pos{ .x = j - 1, .y = i });
                    } else if (j + 1 < self.puzzle.map.rows.items.len and self.puzzle.map.rows.items[i].items[j + 1] == .wall) {
                        try obstacles.append(soko.Pos{ .x = j + 1, .y = i });
                    } else if (i - 1 >= 0 and self.puzzle.map.rows.items[i - 1].items[j] == .wall) {
                        try obstacles.append(soko.Pos{ .x = j, .y = i - 1 });
                    } else if (i + 1 < self.puzzle.map.rows.items.len and self.puzzle.map.rows.items[i + 1].items[j] == .wall) {
                        try obstacles.append(soko.Pos{ .x = j, .y = i - 1 });
                    }
                }
            }
        }

        // pick random obstacle to remove
        const RndGen = std.rand.DefaultPrng;
        var rnd = RndGen.init(0);
        var randomNumber = rnd.random().intRangeAtMost(usize, 0, obstacles.items.len);
        var x = obstacles.items[randomNumber].x;
        var y = obstacles.items[randomNumber].y;

        self.puzzle.map.*.rows.items[y].items[x] = soko.TexType.floor;
    }

    pub fn placeBox(self: *Node) void {
        var floorTiles = std.ArrayList(soko.Pos).init(self.alloc);
        defer floorTiles.deinit();

        for (self.map.rows.items) |row, i| {
            for (row.items) |item, j| {
                if (item == .floor) {
                    floorTiles.append(soko.Pos{ .x = j, .y = i });
                }
            }
        }

        // convert random floor item to box
        const RndGen = std.rand.DefaultPrng;
        var rnd = RndGen.init(0);
        var randomNumber = rnd.random().intRangeAtMost(usize, 0, floorTiles.items.len);
        var x = floorTiles.items[randomNumber].x;
        var y = floorTiles.items[randomNumber].y;

        self.map.*.rows.items[y].items[x].tex = soko.TexType.box;

        // save box location
        var boxId = self.map.*.rows.items[y].items[x].id;
        self.boxGoal.put(boxId, soko.BoxGoalPair{ soko.Pos{ .x = x, .y = y }, soko.Pos{ .x = std.math.inf_u64, .y = std.math.inf_u64 } });
    }

    /// stops the editing of the map state for the current tree branch
    /// saves the current box locations in the freezed state
    pub fn freezeLevel(self: *Node) void {
        self.isFreezed = true;
    }

    pub fn moveAgent(self: *Node) !void {
        var puzzle = Puzzle.init(self.alloc);
        puzzle.map = self.map;

        // for each possible worker move create another node.
        for (soko.ActType) |act| {
            if (puzzle.move(act)) {
                var node = Node.init(self.alloc, self.map);
                try self.children.append(node);
            }
        }
        _ = self;
    }

    /// save current box locations as goal locations
    /// inform root node of generated puzzle + score
    pub fn finalizeLevel(self: *Node) f32 {
        self.puzzle.map.storeBoxPositions();
        for (self.puzzle.map.boxPositions.items) |pos| {
            for (self.freezedGoalPosition.items) |originalPos| {
                if (pos == originalPos)
                    self.puzzle.map.rows.items[pos.y].items[pos.x] == soko.TexType.wall;
            }
        }

        // save current puzzle
        self.getTreeRoot().rootGeneratedPuzzles.append(.{ &self.puzzle.map, self.totalEvaluation });
        _ = self;
    }

    pub fn ucb(self: Node) f32 {
        if (self.visits == 0) return std.math.f32_max;
        const C = std.math.pow(2, 0.5);
        const firstTerm = (self.totalEvaluation / self.visits);
        const secondTerm = C * std.math.pow(std.math.log(self.parent.visits) / self.vists, 0.5);
        return firstTerm + secondTerm;
    }

    pub fn getListOfBestLeaves(self: *Node, list: *std.ArrayList(*Node)) *std.ArrayList(*Node) {
        if (self.children.items != 0) {
            // get list of best UCB of children
            var childrenList = std.ArrayList(*Node).init(self.alloc);
            for (self.children.items) |child| {
                var bestUCB = if (childrenList.items.len != 0) {
                    list.items[list.items.len - 1].ucb();
                } else {
                    0;
                };
                if (child.ucb() == bestUCB) {
                    childrenList.append(child);
                    list = child.getListOfBestLeaves(list);
                } else if (self.ucb() > bestUCB) {
                    childrenList.clearAndFree();
                    try childrenList.append(child);
                    list = child.getListOfBestLeaves(list);
                }
            }
        } else {
            var bestUCB = if (list.items.len != 0) {
                list.items[list.items.len - 1].ucb();
            } else {
                0;
            };
            if (self.ucb() == bestUCB) {
                try list.*.append(self);
            } else if (self.ucb() > bestUCB) {
                list.clearAndFree();
                try list.append(self);
            }
        }

        return list;
    }

    pub fn getTreeRoot(self: Node) *Node {
        var rootNode: *Node = &self;
        while (rootNode.parent != undefined) {
            rootNode = rootNode.parent;
        }
        return rootNode;
    }
};

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
/// map - Sokoban puzzle map to evalBackProp its congestion value.
/// boxPairs - list of bounding rectangles of every box and its final position/goal
///
/// returns the congestion feature analysis factor
pub fn computeCongestion(alloc: Allocator, map: Map, boxGoalPairs: std.ArrayList(soko.BoxGoalPair), wBoxCount: f32, wGoalCount: f32, wObstacleCount: f32) !f32 {
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
                switch (item.tex) {
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
    alloc: Allocator,
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
            var prevItem: soko.TexType = slice3x3.items[0].items[0].tex;
            var similar: bool = true;
            sliceCheck: for (slice3x3.items) |sliceRow| {
                for (sliceRow.items) |sliceItem| {
                    if (sliceItem.tex != prevItem) {
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
