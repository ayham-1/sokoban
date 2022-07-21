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
const log = @import("../log.zig");
const soko = @import("../constants.zig");
const Map = @import("../map.zig").Map;
const Puzzle = @import("../puzzle.zig").Puzzle;
const mcts = @import("mcts.zig").mcts;

const Node = @import("node.zig").Node;
const NodeState = @import("nodestate.zig").NodeState;

const Allocator = std.mem.Allocator;

pub fn get(alloc: Allocator, width: u8, height: u8, iter: i64) void {
    var parentState = NodeState.init(alloc, width, height);
    var parentNode = Node.init(alloc, parentState);
    parentNode.expand() catch unreachable;
    parentNode.state.simulate();
    log.warn("{}", .{parentNode.state.nextActions.items.len});

    var bestNode: *Node = mcts(parentNode, iter, 0.75);

    log.info("score: {d:.3}", .{bestNode.totalEvaluation / @intToFloat(f32, bestNode.visits)});

    //return bestState;
}
