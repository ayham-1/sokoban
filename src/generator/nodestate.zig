//! Module defining NodeState.
//!
//! NodeState is designed to work coupled with a larger-scope "Node", in the
//! context of MCTS trees. It attempts to represent a sokoban puzzle generation
//! node state.
//!
//! In addition, this modules provides action functions on the state. Those
//! actions are:
//!     - placePlayer
//!     - placeBox
//!     - placeFloor
//!     - moveBox
//!     - evaluate
//! These actions can be considered as the MCTS available actions, they are
//! designed to model Bilal Kartal's algorithm (2016). However, with the notable
//! addition of placePlayer, which is taken from Olivier Lemer's
//! implementation. Also, the freezeLevel action is not.
//!
//! This implementation might strike very similar to Oliver's implmenation,
//! which is the case, except for small minor optimazations and removal of code
//! repetition. It should be noted, that this Module is not Olivier's complete
//! implementation. For that, refer to other parts of the program.
const std = @import("std");
const log = @import("../log.zig");
const soko = @import("../constants.zig");
const Map = @import("../map.zig").Map;

const Allocator = std.mem.Allocator;

const RndGen = std.rand.DefaultPrng;
var seed: u64 = undefined;
var rnd: std.rand.Xoshiro256 = undefined;

// holds the map representation of the node
pub const NodeState = struct {
    alloc: Allocator,

    width: u8,
    height: u8,

    action: ActionFn,
    nextActions: std.ArrayList(Action),
    evaluated: bool = false,

    floors: std.ArrayList(soko.Pos),
    boxes: std.ArrayList(soko.Pos),
    goals: std.ArrayList(soko.Pos),
    obstacles: std.ArrayList(soko.Pos),
    playerReach: std.ArrayList(soko.Pos),
    boxMoveCount: std.ArrayList(i16), // boxIndex, moves

    pub fn init(alloc: Allocator, width: u8, height: u8) *NodeState {
        var state = NodeState{
            .alloc = alloc,
            .width = width,
            .height = height,
            .action = NodeState.placeFloor,
            .nextActions = std.ArrayList(Action).init(alloc),
            .floors = std.ArrayList(soko.Pos).init(alloc),
            .boxes = std.ArrayList(soko.Pos).init(alloc),
            .boxMoveCount = std.ArrayList(i16).init(alloc),
            .obstacles = std.ArrayList(soko.Pos).init(alloc),
            .playerReach = std.ArrayList(soko.Pos).init(alloc),
            .goals = std.ArrayList(soko.Pos).init(alloc),
        };

        // plot random floor tile
        std.os.getrandom(std.mem.asBytes(&seed)) catch unreachable;
        rnd = RndGen.init(seed);
        var x = rnd.random().intRangeAtMost(u8, 1, width - 1);
        var y = rnd.random().intRangeAtMost(u8, 1, height - 1);
        var pos = soko.Pos{ .x = x, .y = y };
        state.nextActions.append(Action{
            .func = placeFloor,
            .params = ActionParams{ .pos = pos, .boxIndex = null, .direction = null },
        }) catch unreachable;

        var allocState: *NodeState = alloc.create(NodeState) catch unreachable;
        allocState.* = state;
        return allocState;
    }

    pub fn deinit(self: *NodeState) void {
        self.floors.deinit();
        self.boxes.deinit();
        self.obstacles.deinit();
        self.boxMoveCount.deinit();
        self.playerReach.deinit();
    }

    pub fn clone(self: *NodeState) !*NodeState {
        var result = NodeState.init(self.alloc, self.width, self.height);
        result.floors = try self.floors.clone();
        result.boxes = try self.boxes.clone();
        result.obstacles = try self.obstacles.clone();
        result.boxMoveCount = try self.boxMoveCount.clone();
        result.playerReach = try self.playerReach.clone();
        result.boxes = try self.boxes.clone();
        return result;
    }

    pub fn hash(self: NodeState) u64 {
        var hasher = std.hash.Wyhash.init(@intCast(u64, std.time.milliTimestamp()));
        std.hash.autoHashStrat(&hasher, self, .Shallow);
        return hasher.final();
    }

    pub fn postProcess(self: *NodeState) NodeState {
        var boxes = std.ArrayList(soko.Pos).init(self.alloc);
        var goals = std.ArrayList(soko.Pos).init(self.alloc);
        var obstacles = std.ArrayList(soko.Pos).init(self.alloc);
        var boxMoveCount = std.ArrayList(i16).init(self.alloc);
        for (self.boxes.items) |box, i| {
            var moveCount = self.boxMoveCount.items[i];

            if (moveCount > 0) {
                obstacles.append(box) catch unreachable;
                goals.append(self.goals.items[i]) catch unreachable;
                boxMoveCount.append(moveCount) catch unreachable;
            } else {
                obstacles.append(self.boxes.items[i]) catch unreachable;
            }
        }

        var processed = NodeState{
            .alloc = self.alloc,
            .width = self.width,
            .height = self.height,
            .action = NodeState.placeFloor,
            .nextActions = std.ArrayList(Action).init(self.alloc),
            .boxes = boxes,
            .floors = std.ArrayList(soko.Pos).init(self.alloc),
            .obstacles = obstacles,
            .boxMoveCount = boxMoveCount,
            .playerReach = std.ArrayList(soko.Pos).init(self.alloc),
            .goals = std.ArrayList(soko.Pos).init(self.alloc),
        };

        if (self.playerReach.popOrNull()) |popped| {
            processed.playerReach = processed.getReachFrom(popped);
        }
        processed.floors = processed.playerReach.clone() catch unreachable;

        return processed;
    }
    pub fn buildMap(self: *NodeState) *Map {
        var map = Map.init(self.alloc);

        var rows = std.ArrayList(std.ArrayList(soko.Textile)).initCapacity(self.alloc, self.height) catch unreachable;

        var newRow = std.ArrayList(soko.Textile).initCapacity(self.alloc, self.width) catch unreachable;
        var i: usize = 0;
        while (i < self.width) {
            newRow.append(soko.Textile{
                .tex = .floor,
                .id = 0,
            }) catch unreachable;
        }

        i = 0;
        while (i < self.height) {
            rows.append(newRow.clone() catch unreachable) catch unreachable;
        }

        for (self.floors.items) |floor| {
            rows.items[floor.y].items[floor.x] = soko.Textile{ .tex = .floor, .id = map.highestId };
            map.highestId += 1;
        }
        for (self.obstacles.items) |obstacle| {
            rows.items[obstacle.y].items[obstacle.x] = soko.Textile{ .tex = .wall, .id = map.highestId };
            map.highestId += 1;
        }
        for (self.goals.items) |goal| {
            rows.items[goal.y].items[goal.x] = soko.Textile{ .tex = .dock, .id = map.highestId };
            map.highestId += 1;
        }

        var mapAlloc = self.alloc.create(Map) catch unreachable;
        mapAlloc.* = map;

        return mapAlloc;
    }

    pub fn simulate(self: *NodeState) void {
        var randomChild = rnd.random().intRangeAtMost(usize, 0, self.nextActions.items.len - 1);
        var action = self.nextActions.items[randomChild];
        action.func(self, action.params);
        self.action = action.func;
        //randomChild.deinit();
        if (self.nextActions.items.len > 1) {
            self.nextActions.resize(self.nextActions.items.len - 1) catch unreachable;
        } else {
            self.nextActions.clearAndFree();
        }
    }
    /// assumes first argument is position
    pub fn placeBox(self: *NodeState, args: ActionParams) void {
        var pos = args.pos.?;
        if (!self.testPosBoundaries(pos)) return;

        self.boxes.append(pos) catch unreachable;
        self.goals.append(pos) catch unreachable;
        self.boxMoveCount.append(0) catch unreachable;
        for (self.floors.items) |floor, i| {
            if (std.meta.eql(pos, floor)) {
                _ = self.floors.swapRemove(i);
                if (self.floors.items.len > 0) {
                    self.floors.resize(self.floors.items.len - 1) catch unreachable;
                } else {
                    self.floors.clearAndFree();
                }
                break;
            }
        }

        for (self.nextActions.items) |action, i| {
            if (action.func == placePlayer) {
                if (action.params.pos) |posPlayer| {
                    if (std.meta.eql(posPlayer, pos)) {
                        _ = self.nextActions.swapRemove(i);
                        if (self.nextActions.items.len > 1) {
                            self.nextActions.resize(self.nextActions.items.len - 1) catch unreachable;
                        } else {
                            self.nextActions.clearAndFree();
                        }
                    }
                }
            }
        }
    }

    /// assumes first argument is position
    ///
    /// places floor, then adds more actions:
    ///     - placeBox
    ///     - placePlayer
    pub fn placeFloor(self: *NodeState, args: ActionParams) void {
        var pos = args.pos.?;

        if (!self.testPosBoundaries(pos)) return;

        self.floors.append(pos) catch unreachable;

        for (self.obstacles.items) |obstacle, i| {
            if (std.meta.eql(pos, obstacle)) {
                _ = self.obstacles.swapRemove(i);
                if (self.obstacles.items.len > 0) {
                    self.obstacles.resize(self.obstacles.items.len - 1) catch unreachable;
                } else {
                    self.obstacles.clearAndFree();
                }
            }
        }
        for (directions) |dir| {
            var newPos = self.movePos(pos, dir);
            var isValid = true;
            for (self.boxes.items) |box| {
                if (std.meta.eql(pos, box)) isValid = false;
            }

            if (isValid)
                self.nextActions.append(Action{
                    .func = placeFloor,
                    .params = ActionParams{ .pos = newPos, .boxIndex = 0, .direction = dir },
                }) catch unreachable;
        }
        self.nextActions.append(Action{
            .func = placeBox,
            .params = ActionParams{ .pos = pos, .boxIndex = null, .direction = null },
        }) catch unreachable;
        self.nextActions.append(Action{
            .func = placePlayer,
            .params = ActionParams{ .pos = pos, .boxIndex = null, .direction = null },
        }) catch unreachable;
    }

    /// assumes first argument is position
    pub fn placePlayer(self: *NodeState, args: ActionParams) void {
        var pos = args.pos.?;
        if (!self.testPosBoundaries(pos)) unreachable;

        self.playerReach = self.getReachFrom(pos);
        self.goals = self.boxes.clone() catch unreachable;
        self.nextActions.clearAndFree();
        self.nextActions.append(Action{
            .func = evaluate,
            .params = ActionParams{ .pos = null, .boxIndex = null, .direction = null },
        }) catch unreachable;

        self.appendBoxMoves();
    }

    /// assumes second argument is boxIndex
    /// assumes third argument is direction
    pub fn moveBox(self: *NodeState, args: ActionParams) void {
        var boxIndex = args.boxIndex.?;
        var direction = args.direction.?;

        var boxOldPos = self.boxes.items[boxIndex];
        self.floors.append(boxOldPos) catch unreachable;
        var boxNewPos = self.movePos(boxOldPos, direction);

        for (self.floors.items) |floor, i| {
            if (std.meta.eql(boxNewPos, floor)) {
                _ = self.floors.swapRemove(i);
                if (self.floors.items.len > 0) {
                    self.floors.resize(self.obstacles.items.len - 1) catch unreachable;
                } else {
                    self.floors.clearAndFree();
                }
            }
        }

        self.boxes.items[boxIndex] = boxNewPos;
        self.playerReach = self.getReachFrom(self.movePos(boxNewPos, direction));
        self.boxMoveCount.items[boxIndex] += 1;

        self.appendBoxMoves();
    }

    pub fn evaluate(self: *NodeState, args: ActionParams) void {
        _ = args;
        self.evaluated = true;
        self.nextActions.clearAndFree();
    }

    pub fn getReachFrom(self: *NodeState, pos: soko.Pos) std.ArrayList(soko.Pos) {
        var reach = std.ArrayList(soko.Pos).init(self.alloc);
        reach.append(pos) catch unreachable;
        var queue = std.ArrayList(soko.Pos).init(self.alloc);
        queue.append(pos) catch unreachable;
        defer queue.deinit();
        while (queue.items.len > 0) {
            var lastPos = queue.pop();
            for (directions) |direction| {
                var newPos = self.movePos(lastPos, direction);
                for (reach.items) |alreadyFound|
                    if (std.meta.eql(alreadyFound, newPos)) continue;
                for (self.floors.items) |floor| {
                    if (std.meta.eql(floor, newPos)) {
                        queue.append(newPos) catch unreachable;
                        reach.append(newPos) catch unreachable;
                    }
                }
            }
        }
        return reach;
    }
    pub fn movePos(self: *NodeState, pos: soko.Pos, direction: [2]i2) soko.Pos {
        var newX = @intCast(i16, pos.x) + direction[0];
        var newY = @intCast(i16, pos.y) + direction[1];
        if (newX >= 0 and newY >= 0 and newX < self.width and newY < self.height) {
            return soko.Pos{ .x = @intCast(u8, @intCast(i16, pos.x) + direction[0]), .y = @intCast(u8, (@intCast(i16, pos.y) + direction[1])) };
        } else {
            return pos;
        }
    }

    fn testPosBoundaries(self: *NodeState, pos: soko.Pos) bool {
        return pos.x >= 0 and
            pos.y >= 0 and
            pos.x < self.width and
            pos.y < self.height;
    }

    fn appendBoxMoves(self: *NodeState) void {
        for (self.boxes.items) |box, boxIndex| {
            for (directions) |dir| {
                var newBoxPos = self.movePos(box, dir);
                var newPlayerPos = self.movePos(newBoxPos, dir);

                var isBoxValid = false;
                var isPlayerValid = false;
                for (self.floors.items) |floor| {
                    if (std.meta.eql(floor, newBoxPos)) isBoxValid = true;
                    if (std.meta.eql(floor, newPlayerPos)) isPlayerValid = true;
                }

                if (isBoxValid and isPlayerValid)
                    self.nextActions.append(Action{
                        .func = moveBox,
                        .params = ActionParams{ .pos = null, .boxIndex = boxIndex, .direction = dir },
                    }) catch unreachable;
            }
        }
    }
};
pub const MoveBox = struct { boxIndex: u8, act: soko.ActType };

pub const Action = struct {
    params: ActionParams,
    func: ActionFn,
};
pub const ActionParams = struct { pos: ?soko.Pos, boxIndex: ?usize, direction: ?[2]i2 };
pub const ActionFn = fn (self: *NodeState, args: ActionParams) void;

// Useful Functions
//
pub var directions = [4][2]i2{
    [_]i2{ 0, -1 }, // up
    [_]i2{ 1, 0 }, // right
    [_]i2{ 0, 1 }, // down
    [_]i2{ -1, 0 }, // left
};
