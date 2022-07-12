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

    var parentNode = Node.initAsParent(alloc, &map, boxCount);
    var epoch: usize = 50;
    while (epoch > 0) {
        log.info("epoch number: {}", .{epoch});
        try parentNode.iterate();
        epoch -= 1;
    }

    var finalMap: *Map = try map.clone();
    if (parentNode.rootGeneratedPuzzles.items.len > 0) {
        var highestPuzzle: GeneratedPuzzle = parentNode.rootGeneratedPuzzles.items[parentNode.rootGeneratedPuzzles.items.len - 1];

        for (parentNode.rootGeneratedPuzzles.items) |puzzle| {
            if (puzzle.score >= highestPuzzle.score) {
                highestPuzzle = puzzle;
            }
        }

        finalMap = highestPuzzle.map.clone() catch unreachable;
    }

    finalMap.setWorkerPos();
    try finalMap.buildDisplayed();
    log.warn("{s}", .{finalMap.displayed.items});
    log.warn("{}", .{finalMap.rows.items.len});
    return finalMap;
}

pub const GeneratedPuzzle = struct { map: *Map, score: f32 };
pub const NodeActionSet = enum(u6) { root, deleteWall, placeBox, freezeLevel, moveAgent, finalizeLevel };
pub const Node = struct {
    alloc: Allocator,
    parent: ?*Node = null,
    rootGeneratedPuzzles: std.ArrayList(GeneratedPuzzle),

    children: std.ArrayList(*Node),
    obstacleFirstTime: bool,

    isFreezed: bool = false,
    freezedMap: *Map = undefined,

    visits: usize = 0,
    totalEvaluation: f32 = 0,

    boxesLeftToPlace: usize,

    map: *Map,
    boxGoal: std.AutoArrayHashMap(u8, soko.BoxGoalPair),
    isFinalizable: bool = true,

    action: NodeActionSet = NodeActionSet.root,

    pub fn initAsParent(alloc: Allocator, map: *Map, boxCount: usize) *Node {
        std.os.getrandom(std.mem.asBytes(&seed)) catch unreachable;
        rnd = std.rand.DefaultPrng.init(seed);

        var node = Node{
            .alloc = alloc,
            .map = map.clone() catch unreachable,
            .children = std.ArrayList(*Node).init(alloc),
            .boxGoal = std.AutoArrayHashMap(u8, soko.BoxGoalPair).init(alloc),
            .rootGeneratedPuzzles = std.ArrayList(GeneratedPuzzle).init(alloc),
            .boxesLeftToPlace = boxCount,
            .obstacleFirstTime = true,
        };
        var allocNode: *Node = alloc.create(Node) catch unreachable;
        allocNode.* = node;
        return allocNode;
    }

    pub fn appendChild(self: *Node, map: *Map) !void {
        var result = Node.initAsParent(self.alloc, map, self.boxesLeftToPlace);
        result.*.parent = self;
        result.*.boxGoal = try self.boxGoal.clone();
        result.*.obstacleFirstTime = self.obstacleFirstTime;

        try self.children.append(result);
    }
    pub fn appendFreezedChild(self: *Node, map: *Map) !void {
        var result = Node.initAsParent(self.alloc, map, self.boxesLeftToPlace);
        result.*.parent = self;
        result.*.boxGoal = try self.boxGoal.clone();
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
            //node.*.visits += 1;
            node.*.totalEvaluation += score;

            currentNode = currentNode.parent orelse unreachable;
        }
    }

    fn evaluationFunction(self: *Node) !f32 {
        // calculate congestionVal
        var goalPositions = try self.map.getBoxPositions();
        for (goalPositions.keys()) |goalKey| {
            if (goalPositions.get(goalKey)) |goal| {
                if (self.boxGoal.get(goalKey)) |pair| {
                    var newPair = soko.BoxGoalPair{ .box = pair.box, .goal = goal };
                    try self.boxGoal.put(goalKey, newPair);
                }
            }
        }
        var passablePairs = std.ArrayList(soko.BoxGoalPair).init(self.alloc);
        defer passablePairs.deinit();
        for (self.boxGoal.keys()) |key| {
            try passablePairs.append(self.boxGoal.get(key) orelse unreachable);
        }
        var congestionVal = try computeCongestion(self.alloc, self.map, passablePairs, 4, 4, 1);

        // calculate evaluation using computeMapEval
        var slice3x3Val = try compute3x3Blocks(self.alloc, self.map);
        var score = try computeMapEval(10, 5, 20, slice3x3Val, congestionVal, @intCast(i32, goalPositions.keys().len));

        return score;
    }

    pub fn expand(self: *Node) !void {
        if (!self.isFreezed) {
            try self.appendChild(self.map);
            try self.children.items[self.children.items.len - 1].deleteWall();

            if (self.getTreeRoot().boxesLeftToPlace > 0) {
                try self.appendChild(self.map);
                try self.children.items[self.children.items.len - 1].placeBox();
                self.*.getTreeRoot().*.boxesLeftToPlace -= 1;
            }

            try self.appendChild(self.map);
            try self.children.items[self.children.items.len - 1].freezeLevel();
        } else {
            try self.appendFreezedChild(self.map);
            try self.children.items[self.children.items.len - 1].moveAgent();

            if (self.isFinalizable) {
                //try self.children.append(Node.initAsFreezedChild(self.alloc, self.map.clone(), self));
                //try self.children.items[self.children.items.len - 1].finalizeLevel();
                var finalized = Node.initAsParent(self.alloc, self.map, self.boxesLeftToPlace);
                finalized.*.parent = self;
                finalized.*.boxGoal = try self.boxGoal.clone();
                finalized.*.freezedMap = try self.freezedMap.clone();
                finalized.*.obstacleFirstTime = self.obstacleFirstTime;
                try finalized.finalizeLevel();
                self.isFinalizable = false;
            }
        }
    }

    pub fn deleteWall(self: *Node) !void {
        self.action = NodeActionSet.deleteWall;
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

        if (self.getTreeRoot().obstacleFirstTime) {
            for (obstacles.items) |pos| {
                self.map.rows.items[pos.y].items[pos.x].tex = soko.TexType.floor;
            }
            self.getTreeRoot().*.obstacleFirstTime = false;
        }

        // pick random obstacle to remove
        if (obstacles.items.len != 0) {
            var randomNumber = rnd.random().intRangeAtMost(usize, 0, obstacles.items.len - 1);
            var x = obstacles.items[randomNumber].x;
            var y = obstacles.items[randomNumber].y;

            self.map.rows.items[y].items[x].tex = soko.TexType.floor;
        }
    }

    pub fn placeBox(self: *Node) !void {
        if (self.boxesLeftToPlace == 0) {
            return;
        } else {
            self.boxesLeftToPlace -= 1;
        }
        self.action = NodeActionSet.placeBox;
        var floorTiles = std.ArrayList(soko.Pos).init(self.alloc);
        defer floorTiles.deinit();

        for (self.map.rows.items) |row, i| {
            for (row.items) |item, j| {
                if (item.tex == .floor) {
                    try floorTiles.append(soko.Pos{ .x = j, .y = i });
                }
            }
        }

        if (floorTiles.items.len == 0) return;

        // convert random floor item to box
        var randomNumber = rnd.random().intRangeAtMost(usize, 0, floorTiles.items.len - 1);
        var x = floorTiles.items[randomNumber].x;
        var y = floorTiles.items[randomNumber].y;

        self.map.rows.items[y].items[x].tex = soko.TexType.box;

        // save box location
        var boxId = self.map.rows.items[y].items[x].id;
        try self.boxGoal.put(boxId, soko.BoxGoalPair{ .box = soko.Pos{ .x = x, .y = y }, .goal = soko.Pos{ .x = x, .y = y } });
    }

    /// stops the editing of the map state for the current tree branch
    /// saves the current box locations in the freezed state
    pub fn freezeLevel(self: *Node) !void {
        self.action = NodeActionSet.freezeLevel;
        self.isFreezed = true;
        self.freezedMap = try self.map.clone();
    }

    pub fn moveAgent(self: *Node) !void {
        self.action = NodeActionSet.freezeLevel;
        //try self.map.buildDisplayed();
        //log.warn("map:\n{s}", .{self.map.displayed.items});

        // for each possible worker move create another node.
        try self.moveAgentPerAct(soko.ActType.up);
        try self.moveAgentPerAct(soko.ActType.down);
        try self.moveAgentPerAct(soko.ActType.left);
        try self.moveAgentPerAct(soko.ActType.right);

        //try self.map.buildDisplayed();
        //log.warn("map:\n{s}", .{self.map.displayed.items});
    }

    fn moveAgentPerAct(self: *Node, act: soko.ActType) !void {
        self.action = NodeActionSet.moveAgent;
        var passableMap = try self.map.clone();
        var puzzle = Puzzle.init(self.alloc, passableMap.*);
        defer {
            puzzle.deinit();
            //passableMap.deinit();
            self.alloc.destroy(passableMap);
        }
        if (puzzle.move(act)) |any| {
            _ = any;
            try self.appendFreezedChild(try puzzle.map.clone());
        } else |_| {}
    }

    /// save current box locations as goal locations
    /// inform root node of generated puzzle + score
    pub fn finalizeLevel(self: *Node) !void {
        self.action = NodeActionSet.finalizeLevel;
        // set current box positions as dock boxes
        // and
        // swap unmoved boxes as obstacles.
        // use freezed map

        var currentBoxPos = try self.map.getBoxPositions();
        if (currentBoxPos.keys().len == 0) return;

        var isViable: bool = false;
        for (self.boxGoal.keys()) |pair| {
            if (self.boxGoal.get(pair)) |paired| {
                if (paired.box.x == paired.goal.x and paired.box.y == paired.goal.y) {
                    self.freezedMap.rows.items[paired.box.y].items[paired.box.x].tex = .wall;
                } else {
                    self.freezedMap.rows.items[paired.goal.y].items[paired.goal.x].tex = soko.TexType.dock;
                    self.freezedMap.rows.items[paired.box.y].items[paired.box.x].tex = soko.TexType.box;
                    isViable = true;
                }
            }
        }

        if (self.boxesLeftToPlace != 0) isViable = false;

        if (!isViable) return;

        // remove any left over workers
        //for (self.map.rows.items) |row| {
        //    for (row.items) |item| {
        //        if (item.tex == .worker or item.tex == .workerDocked) {

        //        }
        //    }
        //}

        //for (currentBoxPos.keys()) |pair| {
        //    if (currentBoxPos.get(pair)) |currentPos| {
        //        self.map.rows.items[currentPos.y].items[currentPos.x].tex = soko.TexType.dock;
        //    }
        //}

        // save current puzzle
        var generatedPuzzle = GeneratedPuzzle{
            .map = try self.freezedMap.clone(),
            .score = self.totalEvaluation,
        };
        try self.getTreeRoot().rootGeneratedPuzzles.append(generatedPuzzle);
    }

    pub fn ucb(self: *Node) f32 {
        if (self.visits == 0) return std.math.f32_max;
        const C: f32 = std.math.sqrt(2);
        //const firstTerm: f32 = self.evaluationFunction() * (self.totalEvaluation / @intToFloat(f32, self.visits));
        const firstTerm: f32 = (self.evaluationFunction() catch unreachable) * (@intToFloat(f32, (self.parent orelse self).visits) / @intToFloat(f32, self.visits));
        const secondTerm = C * std.math.sqrt(std.math.ln(@intToFloat(f32, (self.parent orelse self).visits)) / @intToFloat(f32, self.visits));
        return firstTerm + secondTerm;
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
    const k = 50;
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
