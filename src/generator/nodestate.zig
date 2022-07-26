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

    action: Action,
    nextActions: std.ArrayList(Action),
    evaluated: bool = false,

    floors: std.ArrayList(soko.Pos),
    boxes: std.ArrayList(soko.Pos),
    goals: std.ArrayList(soko.Pos),
    obstacles: std.ArrayList(soko.Pos),
    playerReach: std.ArrayList(soko.Pos),
    boxMoveCount: std.ArrayList(i16), // boxIndex, moves

    pub fn init(alloc: Allocator, width: u8, height: u8) *NodeState {
        // plot random floor tile
        std.os.getrandom(std.mem.asBytes(&seed)) catch unreachable;
        rnd = RndGen.init(seed);
        var x = rnd.random().intRangeAtMost(u8, 1, width - 1);
        var y = rnd.random().intRangeAtMost(u8, 1, height - 1);
        var pos = soko.Pos{ .x = x, .y = y };
        var floorAct = Action{
            .func = placeFloor,
            .params = ActionParams{ .pos = pos, .boxIndex = null, .direction = null },
        };

        var state = NodeState{
            .alloc = alloc,
            .width = width,
            .height = height,
            .action = floorAct,
            .nextActions = std.ArrayList(Action).init(alloc),
            .floors = std.ArrayList(soko.Pos).init(alloc),
            .boxes = std.ArrayList(soko.Pos).init(alloc),
            .boxMoveCount = std.ArrayList(i16).init(alloc),
            .obstacles = std.ArrayList(soko.Pos).init(alloc),
            .playerReach = std.ArrayList(soko.Pos).init(alloc),
            .goals = std.ArrayList(soko.Pos).init(alloc),
        };

        state.nextActions.append(floorAct) catch unreachable;

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
        var result = NodeState{
            .alloc = self.alloc,
            .action = undefined,
            .width = self.width,
            .height = self.height,
            .floors = try self.floors.clone(),
            .boxes = try self.boxes.clone(),
            .obstacles = try self.obstacles.clone(),
            .goals = try self.goals.clone(),
            .boxMoveCount = try self.boxMoveCount.clone(),
            .playerReach = try self.playerReach.clone(),
            //.nextActions = std.ArrayList(Action).init(self.alloc),
            .nextActions = try self.nextActions.clone(),
        };

        var cloneAlloc = self.alloc.create(NodeState) catch unreachable;
        cloneAlloc.* = result;
        return cloneAlloc;
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
                boxes.append(box) catch unreachable;
                goals.append(self.goals.items[i]) catch unreachable;
                boxMoveCount.append(moveCount) catch unreachable;
            } else {
                obstacles.append(box) catch unreachable;
            }
        }

        var processed = NodeState{
            .alloc = self.alloc,
            .action = undefined,
            .width = self.width,
            .height = self.height,
            .nextActions = std.ArrayList(Action).init(self.alloc),
            .boxes = boxes,
            .floors = std.ArrayList(soko.Pos).init(self.alloc),
            .obstacles = obstacles,
            .boxMoveCount = boxMoveCount,
            .playerReach = std.ArrayList(soko.Pos).init(self.alloc),
            .goals = goals,
        };

        //if (self.playerReach.popOrNull()) |popped| {
        //    processed.playerReach = processed.getReachFrom(popped);
        //    self.playerReach.append(popped) catch unreachable;
        //} else {
        processed.floors = self.floors.clone() catch unreachable;
        //}
        //processed.floors = processed.playerReach.clone() catch unreachable;

        return processed;
    }
    pub fn buildMap(self: *NodeState) *Map {
        var map = Map.init(self.alloc);

        var rows = std.ArrayList(std.ArrayList(soko.Textile)).initCapacity(self.alloc, self.height) catch unreachable;

        var newRow = std.ArrayList(soko.Textile).initCapacity(self.alloc, self.width) catch unreachable;
        var i: usize = 0;
        while (i < self.width) {
            defer i += 1;
            newRow.append(soko.Textile{
                .tex = .none,
                .id = 0,
            }) catch unreachable;
        }

        i = 0;
        while (i < self.height) {
            defer i += 1;
            rows.append(newRow.clone() catch unreachable) catch unreachable;
        }

        for (self.floors.items) |floor| {
            rows.items[floor.y].items[floor.x] = soko.Textile{ .tex = .floor, .id = map.highestId };
        }
        for (self.goals.items) |goal| {
            rows.items[goal.y].items[goal.x] = soko.Textile{ .tex = .dock, .id = map.highestId };
        }
        for (self.boxes.items) |goal| {
            rows.items[goal.y].items[goal.x] = soko.Textile{ .tex = .box, .id = map.highestId };
        }
        for (self.obstacles.items) |obstacle| {
            rows.items[obstacle.y].items[obstacle.x] = soko.Textile{ .tex = .wall, .id = map.highestId };
        }

        map.rows.deinit();
        map.rows = rows.clone() catch unreachable;
        var mapAlloc = self.alloc.create(Map) catch unreachable;
        mapAlloc.* = map;

        return mapAlloc;
    }

    pub fn simulate(self: *NodeState) void {
        while (self.nextActions.items.len > 0) {
            var i: usize = rnd.random().intRangeAtMost(usize, 0, self.nextActions.items.len - 1);
            var action = self.nextActions.items[i];
            if (self.nextActions.items.len > 1) {
                _ = self.nextActions.swapRemove(i);
                self.nextActions.resize(self.nextActions.items.len - 1) catch unreachable;
            } else {
                self.nextActions.clearAndFree();
            }
            action.func(self, action.params);
            i += 1;
        }
    }

    pub fn placeBox(node: *NodeState, args: ActionParams) void {
        var pos = args.pos.?;
        if (!node.testPosBoundaries(pos)) return;

        node.boxes.append(pos) catch unreachable;
        node.goals.append(pos) catch unreachable;
        node.boxMoveCount.append(0) catch unreachable;
        for (node.floors.items) |floor, i| {
            if (std.meta.eql(pos, floor)) {
                if (node.floors.items.len > 1) {
                    _ = node.floors.swapRemove(i);
                    node.floors.resize(node.floors.items.len - 1) catch unreachable;
                } else {
                    node.floors.clearAndFree();
                }
                break;
            }
        }
        for (node.nextActions.items) |action, i| {
            if (action.func == placePlayer) {
                if (action.params.pos) |posPlayer| {
                    if (std.meta.eql(posPlayer, pos)) {
                        if (node.nextActions.items.len > 1) {
                            _ = node.nextActions.swapRemove(i);
                            node.nextActions.resize(node.nextActions.items.len - 1) catch unreachable;
                        } else {
                            node.nextActions.clearAndFree();
                        }
                        break;
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
    pub fn placeFloor(node: *NodeState, args: ActionParams) void {
        var pos = args.pos.?;
        if (!node.testPosBoundaries(pos)) return;

        node.floors.append(pos) catch unreachable;

        for (node.obstacles.items) |obstacle, i| {
            if (std.meta.eql(pos, obstacle)) {
                if (node.obstacles.items.len > 1) {
                    _ = node.obstacles.swapRemove(i);
                    node.obstacles.resize(node.obstacles.items.len - 1) catch unreachable;
                } else {
                    node.obstacles.clearAndFree();
                }
            }
        }
        for (directions) |dir| {
            var newPos = node.movePos(pos, dir);
            var isValid: bool = true;
            for (node.boxes.items) |box| {
                if (std.meta.eql(newPos, box)) {
                    isValid = false;
                    break;
                }
            }
            for (node.floors.items) |floor| {
                if (std.meta.eql(newPos, floor)) {
                    isValid = false;
                    break;
                }
            }

            if (isValid) {
                node.nextActions.append(Action{
                    .func = placeFloor,
                    .params = ActionParams{ .pos = newPos, .boxIndex = null, .direction = null },
                }) catch unreachable;
            }
        }
        node.nextActions.append(Action{
            .func = placeBox,
            .params = ActionParams{ .pos = pos, .boxIndex = null, .direction = null },
        }) catch unreachable;
        node.nextActions.append(Action{
            .func = placePlayer,
            .params = ActionParams{ .pos = pos, .boxIndex = null, .direction = null },
        }) catch unreachable;
    }

    /// assumes first argument is position
    pub fn placePlayer(node: *NodeState, args: ActionParams) void {
        var pos = args.pos.?;
        if (!node.testPosBoundaries(pos)) unreachable;

        node.playerReach = node.getReachFrom(pos);
        node.goals = node.boxes.clone() catch unreachable;
        node.nextActions.clearAndFree();
        node.nextActions.append(Action{
            .func = evaluate,
            .params = ActionParams{ .pos = null, .boxIndex = null, .direction = null },
        }) catch unreachable;

        node.appendBoxMoves();
    }

    /// assumes second argument is boxIndex
    /// assumes third argument is direction
    pub fn moveBox(node: *NodeState, args: ActionParams) void {
        var boxIndex = args.boxIndex.?;
        var direction = args.direction.?;

        var boxOldPos = node.boxes.items[boxIndex];
        node.floors.append(boxOldPos) catch unreachable;
        var boxNewPos = node.movePos(boxOldPos, direction);

        for (node.floors.items) |floor, i| {
            if (std.meta.eql(boxNewPos, floor)) {
                if (node.floors.items.len > 1) {
                    _ = node.floors.swapRemove(i);
                    node.floors.resize(node.floors.items.len - 1) catch unreachable;
                } else {
                    node.floors.clearAndFree();
                }
                break;
            }
        }

        node.boxes.items[boxIndex] = boxNewPos;
        node.playerReach = node.getReachFrom(node.movePos(boxNewPos, direction));
        node.boxMoveCount.items[boxIndex] += 1;

        node.appendBoxMoves();
    }

    pub fn evaluate(node: *NodeState, args: ActionParams) void {
        _ = args;
        node.evaluated = true;
        node.nextActions.clearAndFree();
    }

    pub fn getReachFrom(self: *NodeState, pos: soko.Pos) std.ArrayList(soko.Pos) {
        var reach = std.ArrayList(soko.Pos).init(self.alloc);
        reach.append(pos) catch unreachable;
        var queue = std.ArrayList(soko.Pos).init(self.alloc);
        queue.append(pos) catch unreachable;
        defer queue.deinit();
        while (queue.items.len > 0) {
            var lastPos = queue.pop();
            directionLoop: for (directions) |direction| {
                var newPos = self.movePos(lastPos, direction);
                for (reach.items) |alreadyFound|
                    if (std.meta.eql(alreadyFound, newPos)) continue :directionLoop;
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
    fn movePos(self: *NodeState, pos: soko.Pos, direction: u2) soko.Pos {
        var newX: i16 = 0;
        var newY: i16 = 0;
        switch (direction) {
            0 => {
                newX = @intCast(i16, pos.x);
                newY = @intCast(i16, pos.y) - 1;
            }, // up
            1 => {
                newX = @intCast(i16, pos.x) + 1;
                newY = @intCast(i16, pos.y);
            }, // right
            2 => {
                newX = @intCast(i16, pos.x);
                newY = @intCast(i16, pos.y) + 1;
            }, // down
            3 => {
                newX = @intCast(i16, pos.x) - 1;
                newY = @intCast(i16, pos.y);
            }, // left
        }
        if (newX >= 0 and newY >= 0 and newX < self.width and newY < self.height) {
            return soko.Pos{ .x = @intCast(u8, newX), .y = @intCast(u8, newY) };
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
pub const ActionParams = struct { pos: ?soko.Pos, boxIndex: ?usize, direction: ?u2 };
pub const ActionFn = fn (node: *NodeState, args: ActionParams) void;

pub var directions = [4]u2{
    0, // up
    1, // right
    2, // down
    3, // left
};
