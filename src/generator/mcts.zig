const std = @import("std");
const log = @import("../log.zig");
const soko = @import("../constants.zig");
const NodeState = @import("nodestate.zig").NodeState;
const Node = @import("node.zig").Node;

const Allocator = std.mem.Allocator;

pub fn mcts(node: *Node, epoch: i64) *Node {
    var bestNode = node;
    var bestScore: f32 = std.math.f32_min;
    var simulated: *Node = node;

    //var rand = std.rand.DefaultPrng.init(@intCast(u64, std.time.milliTimestamp()));
    var epochsLeft: i64 = epoch;
    var startTime: i64 = std.time.timestamp();
    var totalExploitOverExplore: f64 = 0;

    while (epochsLeft > 0) {
        defer epochsLeft -= 1;

        var timestamp = std.time.nanoTimestamp();

        var selected = node.select();
        selected.expand() catch unreachable;

        if (selected.children.items.len == 0) {
            selected.backPropagate(selected) catch unreachable;
            selected.removeFromParent();
            simulated = selected;
        } else {
            for (selected.children.items) |child| {
                simulated = child.clone() catch unreachable;
                simulated.state.simulate();
                child.backPropagate(simulated) catch unreachable;
            }
        }

        if (simulated.totalEvaluation > bestScore) {
            bestScore = simulated.totalEvaluation;
            bestNode = simulated;
        }

        var timeTaken = std.time.nanoTimestamp() - timestamp;

        var exploitationOverExploration = node.avgScore / node.exploration();
        totalExploitOverExplore += exploitationOverExploration;

        log.info("iter#{}: time: {}ns, explore/exploit: {d:.3}", .{
            epoch - epochsLeft,
            timeTaken,
            exploitationOverExploration,
        });
    }
    log.info("avg. time: {}s, avg. explore/exploit: {}, best score: {d:.3}", .{
        @divFloor(std.time.timestamp() - startTime, epoch),
        @divFloor(totalExploitOverExplore, @intToFloat(f32, epoch)),
        bestScore,
    });

    return bestNode;
}
