const std = @import("std");
const log = @import("../log.zig");
const soko = @import("../constants.zig");
const NodeState = @import("nodestate.zig").NodeState;
const Node = @import("node.zig").Node;

const Allocator = std.mem.Allocator;

pub fn mcts(node: *Node, epoch: i64) *Node {
    var bestNode = node;
    var bestScore: f32 = std.math.f32_min;

    var epochsLeft: i64 = epoch;
    var startTime: i64 = std.time.timestamp();
    var totalExploitOverExplore: f64 = 0;
    while (epochsLeft > 0) {
        defer epochsLeft -= 1;

        var timestamp = std.time.nanoTimestamp();

        var selected = node.select();
        if (selected.parent) |_| {
            selected.state.simulate();
            if (selected.visits == 0) {
                selected.state.simulate();
                selected.evalBackProp() catch unreachable;
            } else {
                selected.expand() catch unreachable;
                selected.evalBackProp() catch unreachable;
            }
        } else {
            selected.expand() catch unreachable;
            selected.state.simulate();
            selected.evalBackProp() catch unreachable;
        }

        if (selected.totalEvaluation > bestScore) {
            bestScore = selected.totalEvaluation;
            bestNode = selected;
        }

        var timeTaken = std.time.nanoTimestamp() - timestamp;

        var exploitationOverExploration = node.exploitation() / node.exploration();
        totalExploitOverExplore += exploitationOverExploration;

        log.info("iter#{}: time: {}ns, explore/exploit: {d:.3}, evaluated: {}", .{
            epoch - epochsLeft,
            timeTaken,
            exploitationOverExploration,
            selected.state.evaluated,
        });
    }
    log.info("avg. time: {}s, avg. explore/exploit: {}, best score: {d:.3}", .{
        @divFloor(std.time.timestamp() - startTime, epoch),
        @divFloor(totalExploitOverExplore, @intToFloat(f32, epoch)),
        bestScore,
    });

    return bestNode;
}
