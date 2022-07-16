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
    log.info("score: {}", .{highestPuzzle.score});
    log.info("generated puzzles: {}", .{generatedPuzzles.items.len});

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
            .boxesPlaced = map.boxPos.keys().len,
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

    //pub fn iterator(self: *Node, epoch: usize) void {
    //    var epochsLeft: usize = epoch;
    //    while (epochsLeft > 0) {
    //        defer epochsLeft -= 1;

    //    }
    //}

    pub fn iterate(self: *Node) !void {
        // get the list of best leaves
        var bestLeaves: std.ArrayList(*Node) = try std.ArrayList(*Node).initCapacity(self.alloc, 50);
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
        var finalPositions = self.map.boxPos;
        for (finalPositions.keys()) |goalKey| {
            if (finalPositions.get(goalKey)) |finalBoxPos| {
                if (self.freezedBoxPos.get(goalKey)) |initialBoxPos| {
                    try boxDockPairs.append(soko.BoxGoalPair{ .box = initialBoxPos, .goal = finalBoxPos });
                }
            }
        }
        var congestionVal = try computeCongestion(self.alloc, processedLevel.map, boxDockPairs, 4, 4, 1);

        // calculate evaluation using computeMapEval
        var slice3x3Val = try compute3x3Blocks(processedLevel.map);
        var score = try computeMapEval(10, 5, 1, slice3x3Val, congestionVal, @intCast(i32, boxDockPairs.items.len));

        return score;
    }

    /// save current box locations as goal locations
    /// inform root node of generated puzzle + score
    pub fn postProcessLevel(self: *Node) !GeneratedPuzzle {
        self.isReady = true;
        if (self.parent == null or self.freezedMap == null or self.freezedBoxPos.keys().len == 0) { // return current map
            var generatedPuzzle = GeneratedPuzzle{
                .map = self.map,
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

        var currentBoxPos = self.map.boxPos;

        for (self.freezedBoxPos.keys()) |pair| {
            if (self.freezedBoxPos.get(pair)) |initialBoxPos| {
                if (currentBoxPos.get(pair)) |finalBoxPos| {
                    if (initialBoxPos.x == finalBoxPos.x and initialBoxPos.y == finalBoxPos.y) {
                        generatedPuzzle.map.rows.items[initialBoxPos.y].items[initialBoxPos.x].tex = .wall;
                    } else if ((try std.math.absInt(@intCast(i32, initialBoxPos.x) - @intCast(i32, finalBoxPos.x))) == 1 and
                        (try std.math.absInt(@intCast(i32, initialBoxPos.y) - @intCast(i32, finalBoxPos.y))) == 0)
                    {
                        generatedPuzzle.map.rows.items[initialBoxPos.y].items[initialBoxPos.x].tex = .floor;
                        generatedPuzzle.map.rows.items[finalBoxPos.y].items[finalBoxPos.x].tex = .floor;
                    } else if ((try std.math.absInt(@intCast(i32, initialBoxPos.y) - @intCast(i32, finalBoxPos.y))) == 1 and
                        (try std.math.absInt(@intCast(i32, initialBoxPos.x) - @intCast(i32, finalBoxPos.x))) == 0)
                    {
                        generatedPuzzle.map.rows.items[initialBoxPos.y].items[initialBoxPos.x].tex = .floor;
                        generatedPuzzle.map.rows.items[finalBoxPos.y].items[finalBoxPos.x].tex = .floor;
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

            if (self.boxesPlaced < self.boxCountTarget)
                try self.placeBox();

            if (self.boxesPlaced == self.boxCountTarget) {
                // fruitless to freezeLevel without completing boxes
                try self.appendChild(self.map);
                try self.children.items[self.children.items.len - 1].freezeLevel();
            }
        } else {
            try self.moveAgent();
        }
    }

    /// saves the board
    pub fn evaluateLevel(self: *Node) !void {
        self.action = .evaluateLevel;

        try generatedPuzzles.append(try self.postProcessLevel());
        generatedPuzzles.items[generatedPuzzles.items.len - 1].score = try self.evaluationFunction();
    }

    pub fn deleteWall(self: *Node) !void {
        // get all obstacles adjacent to free space non-diagonally.
        // doesn't return edge obstacles
        //
        var obstacles = std.ArrayList(soko.Pos).init(self.alloc);
        defer obstacles.deinit();

        for (self.map.rows.items) |row, i| {
            if (i == 0 or i == self.map.rows.items.len - 1) continue;
            for (row.items) |item, j| {
                if (j == 0 or j == row.items.len - 1) continue;
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
        newSelf.action = .deleteWall;

        if (newSelf.*.obstacleFirstTime) {
            for (obstacles.items) |pos| {
                newSelf.map.rows.items[pos.y].items[pos.x].tex = .floor;
            }
            newSelf.*.obstacleFirstTime = false;
        } else {
            // remove number of left over obstacles, if left over is over 1
            var leftOver = newSelf.boxCountTarget - newSelf.boxesPlaced;
            if (leftOver > 1 and leftOver < obstacles.items.len) {
                while (leftOver > 0) {
                    var randomNumber = rnd.random().intRangeAtMost(usize, 0, obstacles.items.len - 1);
                    var x = obstacles.items[randomNumber].x;
                    var y = obstacles.items[randomNumber].y;
                    if (newSelf.map.rows.items[y].items[x].tex == .floor) continue;
                    defer leftOver -= 1;

                    newSelf.map.rows.items[y].items[x].tex = .floor;
                }
            } else {
                // pick random obstacle to remove
                var randomNumber = rnd.random().intRangeAtMost(usize, 0, obstacles.items.len - 1);
                var x = obstacles.items[randomNumber].x;
                var y = obstacles.items[randomNumber].y;

                newSelf.map.rows.items[y].items[x].tex = .floor;
            }
        }
    }

    pub fn placeBox(self: *Node) !void {
        var floorTiles = try std.ArrayList(soko.Pos).initCapacity(
            self.alloc,
            @intCast(usize, self.map.sizeHeight * self.map.sizeWidth),
        );
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

        // convert movable tile position item to box
        //var removeOffset: usize = 0;
        var newMap = try self.map.clone();
        defer newMap.deinit();
        while (floorTiles.items.len != 0) {
            // validate random number
            var randomNumber = rnd.random().intRangeAtMost(usize, 0, floorTiles.items.len - 1);
            var x = floorTiles.items[randomNumber].x;
            var y = floorTiles.items[randomNumber].y;

            if (x == 0 or x >= newMap.rows.items[y].items.len) continue;
            if (y == 0 or y >= newMap.rows.items.len) continue;

            // place box in a random location
            newMap.rows.items[y].items[x].tex = .box;

            // ensure that box placed can move
            if (!Node.canAllBoxesMove(newMap)) {
                newMap.rows.items[y].items[x].tex = .floor;
                _ = floorTiles.swapRemove(randomNumber);
                if (floorTiles.items.len != 0) {
                    try floorTiles.resize(floorTiles.items.len - 1);
                } else {
                    floorTiles.clearAndFree();
                }
                continue;
            }

            // create a new node
            try self.appendChild(newMap);
            var newSelf = self.children.items[self.children.items.len - 1];

            // save box
            newSelf.boxesPlaced += 1;
            newSelf.action = NodeActionSet.placeBox;
            try newSelf.map.boxPos.put(newMap.rows.items[y].items[x].id, soko.Pos{ .x = x, .y = y });

            break;
        }
    }

    /// stops the editing of the map state for the current tree branch
    /// saves the current box locations in the freezed state
    pub fn freezeLevel(self: *Node) !void {
        self.action = NodeActionSet.freezeLevel;
        self.isFreezed = true;
        self.freezedMap = try self.map.clone();
        self.freezedBoxPos = self.freezedMap.?.boxPos;
    }

    /// move agent randomly until all boxes are moved
    /// doesn't physically move agent, but rather gets list movable boxes and
    /// moves them all, one position each.
    const BoxMove = struct { tex: soko.Textile, act: soko.ActType };
    pub fn moveAgent(self: *Node) !void {
        if (!Node.canAllBoxesMove(self.map)) return;
        var puzzle = Puzzle.init(self.alloc, (try self.map.clone()).*);
        defer puzzle.deinit();

        // reject creation of a move node if we can't move boxes
        // stops player mania when a box can't be moved.
        var boxMoves = try Node.getAllBoxMoves(self.alloc, self.map);
        if (boxMoves.items.len == 0) return;

        var initialBoxPositions = self.map.boxPos;
        defer initialBoxPositions.deinit();

        while (!Node.areAllBoxesMoved(&puzzle.map, initialBoxPositions) and Node.canAtleastOneBoxMove(&puzzle.map)) {
            var randomNumber = rnd.random().intRangeAtMost(usize, 0, 3);
            switch (randomNumber) {
                0 => puzzle.move(soko.ActType.up) catch {},
                1 => puzzle.move(soko.ActType.down) catch {},
                2 => puzzle.move(soko.ActType.left) catch {},
                3 => puzzle.move(soko.ActType.right) catch {},
                else => {},
            }
        }

        try self.appendFreezedChild(try puzzle.map.clone());
        var newSelf = self.children.items[self.children.items.len - 1];
        newSelf.action = .moveAgent;

        // after moving agent, evaluate.
        // enter phase 3
        if (Node.areAllBoxesMoved(newSelf.map, newSelf.freezedBoxPos)) {
            // fruitless to evaluate without moved boxes
            try newSelf.appendFreezedChild(newSelf.map);
            try newSelf.children.items[self.children.items.len - 1].evaluateLevel();
        }
    }

    fn canAtleastOneBoxMove(map: *Map) bool {
        var boxPositions = map.boxPos;
        for (boxPositions.keys()) |id| {
            if (boxPositions.get(id)) |pos| {

                // check horizontal
                if (pos.x > 0 and pos.x < map.rows.items[0].items.len - 1) {
                    if ((map.rows.items[pos.y].items[pos.x - 1].tex == .floor or
                        map.rows.items[pos.y].items[pos.x - 1].tex == .worker or
                        map.rows.items[pos.y].items[pos.x - 1].tex == .workerDocked) and
                        (map.rows.items[pos.y].items[pos.x + 1].tex == .floor or
                        map.rows.items[pos.y].items[pos.x + 1].tex == .worker or
                        map.rows.items[pos.y].items[pos.x + 1].tex == .workerDocked))
                        return true;
                }

                // check vertical
                if (pos.y > 0 and pos.y < map.rows.items.len - 1) {
                    if ((map.rows.items[pos.y - 1].items[pos.x].tex == .floor or
                        map.rows.items[pos.y - 1].items[pos.x].tex == .worker or
                        map.rows.items[pos.y - 1].items[pos.x].tex == .workerDocked) and
                        (map.rows.items[pos.y + 1].items[pos.x].tex == .floor or
                        map.rows.items[pos.y + 1].items[pos.x].tex == .worker or
                        map.rows.items[pos.y + 1].items[pos.x].tex == .workerDocked))
                        return true;
                }
            }
        }
        return false;
    }

    fn canAllBoxesMove(map: *Map) bool {
        var boxPositions = map.boxPos;
        for (boxPositions.keys()) |id| {
            if (boxPositions.get(id)) |pos| {
                var isBoxMovable = false;

                // check horizontal
                if (pos.x > 0 and pos.x < map.rows.items[0].items.len - 1) {
                    if ((map.rows.items[pos.y].items[pos.x - 1].tex == .floor or
                        map.rows.items[pos.y].items[pos.x - 1].tex == .worker or
                        map.rows.items[pos.y].items[pos.x - 1].tex == .workerDocked) and
                        (map.rows.items[pos.y].items[pos.x + 1].tex == .floor or
                        map.rows.items[pos.y].items[pos.x + 1].tex == .worker or
                        map.rows.items[pos.y].items[pos.x + 1].tex == .workerDocked))
                        isBoxMovable = true;
                }

                // check vertical
                if (pos.y > 0 and pos.y < map.rows.items.len - 1) {
                    if ((map.rows.items[pos.y - 1].items[pos.x].tex == .floor or
                        map.rows.items[pos.y - 1].items[pos.x].tex == .worker or
                        map.rows.items[pos.y - 1].items[pos.x].tex == .workerDocked) and
                        (map.rows.items[pos.y + 1].items[pos.x].tex == .floor or
                        map.rows.items[pos.y + 1].items[pos.x].tex == .worker or
                        map.rows.items[pos.y + 1].items[pos.x].tex == .workerDocked))
                        isBoxMovable = true;
                }

                if (!isBoxMovable) return false;
            }
        }
        return true;
    }

    fn getAllBoxMoves(alloc: Allocator, map: *Map) !std.ArrayList(BoxMove) {
        var resultMoves = std.ArrayList(BoxMove).init(alloc);
        const maxI = map.rows.items.len - 1;
        for (map.rows.items) |row, i| {
            for (row.items) |item, j| {
                if (item.tex != .box) continue;

                const maxJ = row.items.len - 1;
                if (i == maxI and j == maxJ) continue;
                if (i == 0 and j == 0) continue;
                if (i == 0 and j == maxJ) continue;
                if (i == maxI and j == 0) continue;

                // check horizontal
                if (j > 0 and j < row.items.len) {
                    if (row.items[j - 1].tex == .floor and row.items[j + 1].tex == .floor) {
                        try resultMoves.append(BoxMove{ .tex = item, .act = .right });
                        try resultMoves.append(BoxMove{ .tex = item, .act = .left });
                    }
                }

                // check vertical
                if (i > 0 and i < map.rows.items.len) {
                    if (map.rows.items[i - 1].items[j].tex == .floor and map.rows.items[i + 1].items[j].tex == .floor) {
                        try resultMoves.append(BoxMove{ .tex = item, .act = .up });
                        try resultMoves.append(BoxMove{ .tex = item, .act = .down });
                    }
                }
            }
        }
        return resultMoves;
    }

    fn areAllBoxesMoved(map: *Map, initialBoxPos: std.AutoArrayHashMap(u8, soko.Pos)) bool {
        var currentBoxPositions = map.boxPos;
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
            //
            // currently there can't/rare to have more than 4?
            var viableChildren = std.ArrayList(*Node).initCapacity(self.alloc, 4) catch unreachable;
            defer viableChildren.deinit();
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
    map: *Map,
) !i32 {
    // considerably increase speed of allocation and deallocation
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // calculate area
    var areaMap: i32 = @intCast(i32, map.rows.items.len * map.rows.items[0].items.len);

    // generate map search state
    var mapCheckState = try std.ArrayList(std.ArrayList(bool)).initCapacity(arena.allocator(), map.rows.items.len);
    for (map.rows.items) |row| {
        var newRow = try std.ArrayList(bool).initCapacity(arena.allocator(), row.items.len);
        for (row.items) |_| {
            try newRow.append(false);
        }
        try mapCheckState.append(newRow);
    }

    // initialize slice3x3
    var slice3x3: soko.MapArray = try soko.MapArray.initCapacity(arena.allocator(), 3);
    inline for ([_]usize{ 0, 1, 2 }) |_| {
        var newRow = try soko.MapRowArray.initCapacity(arena.allocator(), 3);
        inline for ([_]usize{ 0, 1, 2 }) |_| {
            try newRow.append(soko.Textile{ .tex = .wall, .id = 0 });
        }
        try slice3x3.append(newRow);
    }

    // count number of 3x3 area which are all similar

    var nSimilar3x3: i32 = 0;
    for (map.rows.items) |row, i| {
        var j: usize = 0;
        while (j + 3 < row.items.len) {
            defer j += 1;
            if (mapCheckState.items[i].items[j] == true) continue;

            var iOffset: usize = @minimum(map.rows.items.len, i + 3);
            var jOffset: usize = @minimum(map.rows.items[0].items.len, j + 3);
            for (map.rows.items[i..iOffset]) |sliceRow, y| {
                for (sliceRow.items[j..jOffset]) |sliceItem, x|
                    slice3x3.items[y].items[x] = sliceItem;
            }

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
