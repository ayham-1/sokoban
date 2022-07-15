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
//! TODO: remove public properties
//! TODO: remove assumption of square map

const std = @import("std");
const log = @import("log.zig");
const soko = @import("constants.zig");
const Map = @import("map.zig").Map;
const Puzzle = @import("puzzle.zig").Puzzle;

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

    generatedPuzzles = std.ArrayList(GeneratedPuzzle).init(alloc);
    var parentNode = Node.initAsParent(alloc, &map, boxCount);
    var epoch: usize = 500;
    while (epoch > 0) {
        log.info("epoch number: {}", .{epoch});
        try parentNode.iterate();
        epoch -= 1;
    }

    var finalMap: *Map = try map.clone();
    var highestPuzzle: GeneratedPuzzle = generatedPuzzles.items[0];
    for (generatedPuzzles.items) |puzzle| {
        if (puzzle.score >= highestPuzzle.score)
            highestPuzzle = puzzle;
    }

    finalMap.deinit();
    finalMap = highestPuzzle.map;

    finalMap.setWorkerPos();
    try finalMap.buildDisplayed();
    return finalMap;
}

pub const GeneratedPuzzle = struct { map: *Map, score: f32 };
pub var generatedPuzzles: std.ArrayList(GeneratedPuzzle) = undefined;

pub const NodeActionSet = enum(u6) { root, deleteWall, placeBox, freezeLevel, moveAgent, evaluateLevel };
pub const Node = struct {
    alloc: Allocator,
    parent: ?*Node = null,

    children: std.ArrayList(*Node),
    obstacleFirstTime: bool,
    boxCountTarget: usize,
    boxesPlaced: usize,

    isFreezed: bool = false,
    freezedMap: ?*Map = null,
    isReady: bool = false,

    visits: usize = 0,
    totalEvaluation: f32 = 0,

    map: *Map,
    freezedBoxPos: std.AutoArrayHashMap(u8, soko.Pos),

    action: NodeActionSet = NodeActionSet.root,

    pub fn initAsParent(alloc: Allocator, map: *Map, boxCount: usize) *Node {
        std.os.getrandom(std.mem.asBytes(&seed)) catch unreachable;
        rnd = std.rand.DefaultPrng.init(seed);

        var node = Node{
            .alloc = alloc,
            .map = map.clone() catch unreachable,
            .children = std.ArrayList(*Node).init(alloc),
            .freezedBoxPos = std.AutoArrayHashMap(u8, soko.Pos).init(alloc),
            .boxCountTarget = boxCount,
            .boxesPlaced = map.getBoxPositions().keys().len,
            .obstacleFirstTime = true,
        };

        var allocNode: *Node = alloc.create(Node) catch unreachable;
        allocNode.* = node;
        return allocNode;
    }

    pub fn appendChild(self: *Node, map: *Map) !void {
        var result = Node.initAsParent(self.alloc, map, self.boxCountTarget);
        result.*.parent = self;
        result.*.freezedBoxPos = try self.freezedBoxPos.clone();
        result.*.obstacleFirstTime = self.obstacleFirstTime;

        try self.children.append(result);
    }
    pub fn appendFreezedChild(self: *Node, map: *Map) !void {
        var result = Node.initAsParent(self.alloc, map, self.boxCountTarget);
        result.*.parent = self;
        result.*.freezedBoxPos = try self.freezedBoxPos.clone();
        result.*.isFreezed = true;
        result.*.freezedMap = self.freezedMap;
        result.*.obstacleFirstTime = self.obstacleFirstTime;

        try self.children.append(result);
    }

    pub fn iterate(self: *Node) !void {
        // get the list of best leaves
        var bestLeaves: std.ArrayList(*Node) = std.ArrayList(*Node).init(self.alloc);
        defer bestLeaves.deinit();
        self.getListOfBestLeaves(&bestLeaves);

        for (bestLeaves.items) |leaf| {
            if (leaf.parent) |_| {
                if (leaf.visits == 0) {
                    try leaf.evalBackProp();
                } else {
                    try leaf.expand();
                    try leaf.evalBackProp();
                }
            } else {
                try leaf.expand();
                try leaf.evalBackProp();
            }
        }
    }

    fn evalBackProp(self: *Node) !void {
        // backpropagate to update parent nodes
        var score = try self.evaluationFunction();
        self.visits += 1;
        self.totalEvaluation += score;
        var currentNode: *Node = self;
        while (currentNode.*.parent) |node| {
            node.*.visits += 1;
            node.*.totalEvaluation += score;

            currentNode = currentNode.parent orelse unreachable;
        }
    }

    fn evaluationFunction(self: *Node) !f32 {
        // do post processing and store what we have of a puzzle
        var processedLevel = try self.postProcessLevel();

        // calculate congestionVal
        var boxDockPairs = std.ArrayList(soko.BoxGoalPair).init(self.alloc);
        var finalPositions = self.map.getBoxPositions();
        for (finalPositions.keys()) |goalKey| {
            if (finalPositions.get(goalKey)) |finalBoxPos| {
                if (self.freezedBoxPos.get(goalKey)) |initialBoxPos| {
                    try boxDockPairs.append(soko.BoxGoalPair{ .box = initialBoxPos, .goal = finalBoxPos });
                }
            }
        }
        var congestionVal = try computeCongestion(self.alloc, processedLevel.map, boxDockPairs, 4, 4, 1);

        // calculate evaluation using computeMapEval
        var slice3x3Val = try compute3x3Blocks(self.alloc, processedLevel.map);
        var score = try computeMapEval(10, 5, 1, slice3x3Val, congestionVal, @intCast(i32, boxDockPairs.items.len));

        return score;
    }

    /// save current box locations as goal locations
    /// inform root node of generated puzzle + score
    pub fn postProcessLevel(self: *Node) !GeneratedPuzzle {
        self.isReady = true;
        if (self.parent == null or self.freezedMap == null or self.freezedBoxPos.keys().len == 0) { // return current map
            var generatedPuzzle = GeneratedPuzzle{
                .map = try self.map.clone(),
                .score = self.totalEvaluation,
            };
            return generatedPuzzle;
        }

        // set current box positions as dock boxes
        // and
        // swap unmoved boxes as obstacles.
        // do not use freezed map
        //
        // reset agent position
        var generatedPuzzle = GeneratedPuzzle{
            .map = try self.map.clone(),
            .score = self.totalEvaluation,
        };

        var currentBoxPos = self.map.getBoxPositions();

        for (self.freezedBoxPos.keys()) |pair| {
            if (self.freezedBoxPos.get(pair)) |initialBoxPos| {
                if (currentBoxPos.get(pair)) |finalBoxPos| {
                    if (initialBoxPos.x == finalBoxPos.x and initialBoxPos.y == finalBoxPos.y) {
                        generatedPuzzle.map.rows.items[initialBoxPos.y].items[initialBoxPos.x].tex = .wall;
                    } else {
                        generatedPuzzle.map.rows.items[initialBoxPos.y].items[initialBoxPos.x].tex = .box;
                        generatedPuzzle.map.rows.items[finalBoxPos.y].items[finalBoxPos.x].tex = .dock;
                    }
                }
            }
        }
        generatedPuzzle.map.rows.items[self.freezedMap.?.workerPos.y].items[self.freezedMap.?.workerPos.x].tex = .floor;
        generatedPuzzle.map.rows.items[self.map.workerPos.y].items[self.map.workerPos.x].tex = .worker;
        generatedPuzzle.map.setWorkerPos();
        return generatedPuzzle;
    }

    pub fn ucb(self: *Node) f32 {
        if (self.visits == 0) return std.math.f32_max;
        const C: f32 = std.math.sqrt(2);
        //const firstTerm: f32 = self.evaluationFunction() * (self.totalEvaluation / @intToFloat(f32, self.visits));
        const firstTerm: f32 = ((self.parent orelse self).totalEvaluation / @intToFloat(f32, self.visits));
        const secondTerm = C * std.math.sqrt(std.math.ln(@intToFloat(f32, (self.parent orelse self).visits)) / @intToFloat(f32, self.visits));
        return firstTerm + secondTerm;
    }

    pub fn expand(self: *Node) !void {
        // evaluate function is last
        // in the action chain
        if (self.action == .evaluateLevel) return;
        if (!self.isFreezed) {
            try self.deleteWall();

            if (self.boxesPlaced != self.boxCountTarget)
                try self.placeBox();

            if (self.boxesPlaced == self.boxCountTarget) {
                // fruitless to freezeLevel without completing boxes
                try self.appendChild(self.map);
                try self.children.items[self.children.items.len - 1].freezeLevel();
            }
        } else {
            try self.moveAgent();

            try self.appendFreezedChild(self.map);
            try self.children.items[self.children.items.len - 1].evaluateLevel();
        }
    }

    /// saves the board
    pub fn evaluateLevel(self: *Node) !void {
        self.action = .evaluateLevel;

        try generatedPuzzles.append(try self.postProcessLevel());
    }

    pub fn deleteWall(self: *Node) !void {
        // get all obstacles adjacent to free space non-diagonally.
        var obstacles = std.ArrayList(soko.Pos).init(self.alloc);
        defer obstacles.deinit();

        for (self.map.rows.items) |row, i| {
            for (row.items) |item, j| {
                if (item.tex == .floor or item.tex == .worker or item.tex == .box) {
                    if (j != 0 and self.map.rows.items[i].items[j - 1].tex == .wall) {
                        try obstacles.append(soko.Pos{ .x = j - 1, .y = i });
                    }
                    if (j + 1 < self.map.rows.items.len and self.map.rows.items[i].items[j + 1].tex == .wall) {
                        try obstacles.append(soko.Pos{ .x = j + 1, .y = i });
                    }
                    if (i != 0 and self.map.rows.items[i - 1].items[j].tex == .wall) {
                        try obstacles.append(soko.Pos{ .x = j, .y = i - 1 });
                    }
                    if (i + 1 < self.map.rows.items.len and self.map.rows.items[i + 1].items[j].tex == .wall) {
                        try obstacles.append(soko.Pos{ .x = j, .y = i + 1 });
                    }
                }
            }
        }
        if (obstacles.items.len == 0) return;

        try self.appendChild(self.map);
        var newSelf = self.children.items[self.children.items.len - 1];

        if (newSelf.*.obstacleFirstTime) {
            for (obstacles.items) |pos| {
                newSelf.map.rows.items[pos.y].items[pos.x].tex = .floor;
            }
            newSelf.*.obstacleFirstTime = false;
        } else {
            //// remove number of left over obstacles, if left over is over 1
            //var leftOver = newSelf.boxCountTarget - newSelf.boxesPlaced;
            //if (leftOver > 1) {
            //    for (obstacles.items) |pos| {
            //        if (leftOver == 0) break;
            //        defer leftOver -= 1;

            //        newSelf.map.rows.items[pos.y].items[pos.x].tex = .floor;
            //    }
            //} else {
            // pick random obstacle to remove
            var randomNumber = rnd.random().intRangeAtMost(usize, 0, obstacles.items.len - 1);
            var x = obstacles.items[randomNumber].x;
            var y = obstacles.items[randomNumber].y;

            newSelf.map.rows.items[y].items[x].tex = .floor;
            newSelf.action = .deleteWall;
            //}
        }
    }

    pub fn placeBox(self: *Node) !void {
        var floorTiles = std.ArrayList(soko.Pos).init(self.alloc);
        defer floorTiles.deinit();

        for (self.map.rows.items) |row, i| {
            if (i == self.map.rows.items.len - 1) continue;
            if (i == 0) continue;
            for (row.items) |item, j| {
                if (j == 0) continue;
                if (j == row.items.len - 1) continue;
                if (item.tex == .floor) {
                    try floorTiles.append(soko.Pos{ .x = j, .y = i });
                }
            }
        }

        if (floorTiles.items.len <= self.boxCountTarget) return;

        // create a new node
        try self.appendChild(self.map);

        // convert random floor item to box
        var randomNumber = rnd.random().intRangeAtMost(usize, 0, floorTiles.items.len - 1);
        var x = floorTiles.items[randomNumber].x;
        var y = floorTiles.items[randomNumber].y;

        // place box in a random location
        self.children.items[self.children.items.len - 1].map.rows.items[y].items[x].tex = soko.TexType.box;

        // save box location
        self.children.items[self.children.items.len - 1].boxesPlaced += 1;
        self.children.items[self.children.items.len - 1].action = NodeActionSet.placeBox;
    }

    /// stops the editing of the map state for the current tree branch
    /// saves the current box locations in the freezed state
    pub fn freezeLevel(self: *Node) !void {
        self.action = NodeActionSet.freezeLevel;
        self.isFreezed = true;
        self.freezedMap = try self.map.clone();
        self.freezedBoxPos = self.freezedMap.?.getBoxPositions();
    }

    /// move agent randomly until all boxes are moved
    pub fn moveAgent(self: *Node) !void {
        // reject creation of a move node if we can't move boxes
        // stops player mania when a box can't be moved.
        if (!self.canAllBoxesMove()) return;

        var puzzle = Puzzle.init(self.alloc, try self.map.clone().*);
        defer puzzle.deinit();

        var initialBoxPositions = self.map.getBoxPositions();
        defer initialBoxPositions.deinit();

        var randomNumber = rnd.random().intRangeAtMost(usize, 0, 3);
        while (!Node.areAllBoxesMoved(puzzle, initialBoxPositions)) {
            switch (randomNumber) {
                0 => puzzle.move(soko.ActType.up),
                1 => puzzle.move(soko.ActType.down),
                2 => puzzle.move(soko.ActType.left),
                3 => puzzle.move(soko.ActType.right),
            }
        }
    }

    fn canAllBoxesMove(map: *Map) bool {
        const maxI = map.rows.items.len;
        for (map.rows.items) |rows, i| {
            for (rows.items) |item, j| {
                if (item != .box) continue;

                const maxJ = rows.items.len;
                if (i == maxI and j == maxJ) return false;
                if (i == 0 and j == 0) return false;
            }
        }
        _ = map;
    }

    fn areAllBoxesMoved(puzzle: Puzzle, initialBoxPos: std.AutoArrayHashMap(u8, soko.Pos)) bool {
        var currentBoxPositions = puzzle.map.getBoxPositions();
        for (currentBoxPositions.keys()) |key| {
            if (currentBoxPositions.get(key)) |finalPos|
                if (initialBoxPos.get(key)) |initialPos|
                    if (finalPos.x == initialPos.x and finalPos.y == initialPos.y)
                        return false;
        }
        return true;
    }

    pub fn getListOfBestLeaves(self: *Node, list: *std.ArrayList(*Node)) void {
        if (self.children.items.len != 0) {
            // we have children, recurse till we
            // reach viable list of children
            var viableChildren = std.ArrayList(*Node).init(self.alloc);
            var bestUCB: f32 = 0;
            for (self.children.items) |child| {
                if (child.ucb() == bestUCB) {
                    viableChildren.append(child) catch unreachable;
                } else if (child.ucb() > bestUCB) {
                    bestUCB = child.ucb();
                    viableChildren.clearAndFree();
                    viableChildren.append(child) catch unreachable;
                }
            }
            for (viableChildren.items) |viableChild| {
                viableChild.*.getListOfBestLeaves(list);
            }
            viableChildren.deinit();
        } else {
            // our current node has no children
            // iterate and judge if we are worthy of the list
            var bestUCB = if (list.items.len != 0)
                list.items[list.items.len - 1].ucb()
            else
                0;
            if (self.ucb() == bestUCB) {
                list.*.append(self) catch unreachable;
            } else if (self.ucb() > bestUCB) {
                list.*.clearAndFree();
                list.append(self) catch unreachable;
            }
        }

        //return list;
    }

    pub fn getTreeRoot(self: *Node) *Node {
        var rootNode: *Node = self;
        while (rootNode.parent) |node| {
            rootNode = node;
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
    const k = 200;
    return (weightSlice3x3 * @intToFloat(f32, slice3x3Val) + weightCongestion * congestionVal + weightBoxCount * @intToFloat(f32, boxCount)) / k;
}

/// The higher the return value the higher the congested factor of the sokoban
/// puzzle given. Meaning, puzzles with overlapping box path solutions are
/// valued more. This also factors the amount of obstacles present.
///
/// map - Sokoban puzzle map to evalBackProp its congestion value.
/// boxPairs - list of bounding rectangles of every box and its final position/goal
///
/// returns the congestion feature analysis factor
pub fn computeCongestion(alloc: Allocator, map: *Map, boxGoalPairs: std.ArrayList(soko.BoxGoalPair), wBoxCount: f32, wGoalCount: f32, wObstacleCount: f32) !f32 {
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
    map: *Map,
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
                    if (sliceItem.tex != .worker and sliceItem.tex != .workerDocked and sliceItem.tex != prevItem) {
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
