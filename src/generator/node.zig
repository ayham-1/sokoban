//! Module defining Node
//!
//! Node represents a complete state in a sokoban generation run. Complete in
//! the sense of state representation. Does *NOT* necessarily mean a complete
//! puzzle.
//!
//! Meant to be used with another module for controlling MCTS phases.
//!
//! Implementation inspired from Oliviers Lemer's implmentation.

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

pub const Node = struct {
    alloc: Allocator,
    parent: ?*Node = null,

    children: std.ArrayList(*Node),
    state: *NodeState,

    visits: usize = 1,
    totalEvaluation: f32 = 0,

    // shared between all nodes,
    // never clone
    visitedHashes: std.ArrayList(i64),

    pub fn init(alloc: Allocator, state: *NodeState) *Node {
        var node = Node{
            .alloc = alloc,
            .children = std.ArrayList(*Node).init(alloc),
            .state = state,
            .visitedHashes = std.ArrayList(i64).init(alloc),
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
            .visitedHashes = self.visitedHashes,
        };

        var allocNode: *Node = try self.alloc.create(Node);
        allocNode.* = node;
        return allocNode;
    }

    pub fn appendChild(self: *Node, state: *NodeState) void {
        var node = Node{
            .alloc = self.alloc,
            .children = std.ArrayList(*Node).init(self.alloc),
            .state = state,
            .visitedHashes = self.visitedHashes,
        };
        var allocNode: *Node = self.alloc.create(Node) catch unreachable;
        allocNode.* = node;
        self.children.append(allocNode) catch unreachable;
    }

    pub fn evalBackProp(self: *Node) !void {
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

    pub fn expand(self: *Node) !void {
        for (self.state.nextActions.items) |action| {
            var clonedState = try self.state.clone();
            defer clonedState.deinit();
            action.func(clonedState, action.params);

            // make sure we don't revisit
            var childHash = clonedState.hash();
            for (self.visitedHashes.items) |hash| {
                if (hash == childHash)
                    return;
            }

            self.appendChild(clonedState);
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
        var parent = self.parent.?;
        for (parent.children.items) |parentChild, i| {
            if (parentChild == self) {
                _ = parent.children.swapRemove(i);
                if (parent.children.items.len > 0) {
                    parent.children.resize(parent.children.items.len - 1) catch unreachable;
                } else {
                    parent.children.clearAndFree();
                }
            }
        }
        //self.deinit();
    }

    fn evaluationFunction(self: *Node) !f32 {
        // do post processing and store what we have of a puzzle
        var processedState = self.state.postProcess();

        var congestionVal = computeCongestion(&processedState, 4, 4, 0.5);

        // calculate evaluation using computeMapEval
        var slice3x3Val = compute3x3Blocks(self.alloc, &processedState);
        var score = computeMapEval(10, 5, 0.5, slice3x3Val, congestionVal, processedState.boxes.items.len);

        return score;
    }

    pub fn exploitation(self: *Node) f32 {
        return (self.evaluationFunction() catch unreachable) * ((self.parent orelse self).totalEvaluation / @intToFloat(f32, self.visits));
    }

    pub fn exploration(self: *Node) f32 {
        const C: f32 = std.math.sqrt(2);

        return C * std.math.sqrt(std.math.ln(@intToFloat(f32, (self.parent orelse self).visits)) / @intToFloat(f32, self.visits));
    }

    pub fn ucb(self: *Node) f32 {
        if (self.visits == 0) return std.math.f32_max;
        return self.exploitation() + self.exploration();
    }
};
