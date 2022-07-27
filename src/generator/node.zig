const std = @import("std");
const log = @import("../log.zig");
const soko = @import("../constants.zig");
const Map = @import("../map.zig").Map;
const Puzzle = @import("../puzzle.zig").Puzzle;
const NodeState = @import("nodestate.zig").NodeState;

const metricszig = @import("metrics.zig");
const computeCongestion = metricszig.computeCongestion;
const compute3x3Blocks = metricszig.compute3x3Blocks;
const computeMapEval = metricszig.computeMapEval;

const Allocator = std.mem.Allocator;

var visitedHashes: std.ArrayList(u64) = undefined;

pub const Node = struct {
    alloc: Allocator,
    parent: ?*Node = null,
    children: std.ArrayList(*Node),
    state: *NodeState,
    visits: usize = 1,
    totalEvaluation: f32 = 0,
    avgScore: f32 = 0,
    pub fn init(alloc: Allocator, state: *NodeState) *Node {
        visitedHashes = std.ArrayList(u64).init(alloc);
        var node = Node{
            .alloc = alloc,
            .children = std.ArrayList(*Node).init(alloc),
            .state = state,
        };
        var allocNode: *Node = alloc.create(Node) catch unreachable;
        allocNode.* = node;
        return allocNode;
    }
    pub fn clone(self: *Node) !*Node {
        var node = Node{
            .alloc = self.alloc,
            .children = try self.children.clone(),
            .state = try self.state.clone(),
        };
        var allocNode: *Node = try self.alloc.create(Node);
        allocNode.* = node;
        return allocNode;
    }
    pub fn appendChild(self: *Node, state: *NodeState) void {
        var node = Node{
            .alloc = self.alloc,
            .parent = self,
            .children = std.ArrayList(*Node).init(self.alloc),
            .state = state,
        };
        var allocNode: *Node = self.alloc.create(Node) catch unreachable;
        allocNode.* = node;
        self.children.append(allocNode) catch unreachable;
    }
    pub fn backPropagate(self: *Node, from: *Node) !void {
        // backpropagate to update parent nodes
        var score = try from.evaluationFunction();
        //self.visits += 1;
        self.totalEvaluation += score;
        self.avgScore = self.totalEvaluation / @intToFloat(f32, self.visits);
        var currentNode: ?*Node = self.parent;
        while (currentNode) |node| {
            node.*.visits += 1;
            node.*.totalEvaluation += score;
            node.*.avgScore = node.totalEvaluation / @intToFloat(f32, node.visits);
            currentNode = node.parent orelse null;
        }
    }
    pub fn expand(self: *Node) !void {
        actionLoop: for (self.state.nextActions.items) |action| {
            var clonedState = try self.state.clone();
            clonedState.action = action;
            action.func(clonedState, action.params);
            // make sure we don't revisit
            var childHash = clonedState.hash();
            for (visitedHashes.items) |hash| {
                if (hash == childHash)
                    continue :actionLoop;
            }
            self.appendChild(clonedState);
            visitedHashes.append(childHash) catch unreachable;
        }
    }
    pub fn select(self: *Node) *Node {
        var node = self;
        while (node.children.items.len != 0) {
            var maxUCB: f32 = 0.0;
            var maxNode = node.children.items[0];
            for (node.children.items) |child| {
                var currentUCB = child.ucb();
                if (currentUCB > maxUCB) {
                    maxUCB = currentUCB;
                    maxNode = child;
                }
            }
            node = maxNode;
        }
        return node;
    }
    pub fn removeFromParent(self: *Node) void {
        if (self.parent) |parent| {
            for (parent.children.items) |parentChild, i| {
                if (parentChild == self) {
                    if (parent.children.items.len > 1) {
                        _ = parent.children.swapRemove(i);
                        parent.children.resize(parent.children.items.len - 1) catch unreachable;
                    } else {
                        parent.children.clearAndFree();
                    }
                    return;
                }
            }
        }
    }
    fn evaluationFunction(self: *Node) !f32 {
        // do post processing and store what we have of a puzzle
        //var processedState = self.state.postProcess();
        var processedState = self.state.*;
        var congestionVal = computeCongestion(&processedState, 4, 4, 1);
        // calculate evaluation using computeMapEval
        var slice3x3Val = compute3x3Blocks(self.alloc, &processedState);
        var score = computeMapEval(10, 5, 1, slice3x3Val, congestionVal, processedState.boxes.items.len);
        return score;
    }
    pub fn exploration(self: *Node) f32 {
        const C: f32 = std.math.sqrt(2);
        if (self.parent) |parent| {
            return C * std.math.sqrt(std.math.ln(@intToFloat(f32, parent.visits)) / @intToFloat(f32, self.visits));
        } else {
            return 0;
        }
    }
    pub fn ucb(self: *Node) f32 {
        //if (self.visits == 0) return std.math.f32_max;
        if (self.parent == null) return self.avgScore;
        return self.avgScore + self.exploration();
    }
};
