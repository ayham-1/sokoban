const std = @import("std");
const log = @import("../log.zig");
const soko = @import("../constants.zig");
const NodeState = @import("nodestate.zig").NodeState;
const Node = @import("node.zig").Node;

const Allocator = std.mem.Allocator;

pub fn mcts(node: *Node, epoch: i64, percentChild: f16) *Node {
    var bestNode = node;
    var bestScore: f32 = std.math.f32_min;
    var simulated = node;

    var epochsLeft: i64 = epoch;
    var startTime: i64 = std.time.timestamp();
    var totalExploitOverExplore: f64 = 0;
    while (epochsLeft > 0) {
        defer epochsLeft -= 1;

        var timestamp = std.time.nanoTimestamp();

        var selected = node.select();
        var childrenCount: usize = @floatToInt(usize, (percentChild * @intToFloat(f16, (selected.children.items.len))));
        selected.expand() catch unreachable;

        var rand = std.rand.DefaultPrng.init(@intCast(u64, std.time.milliTimestamp()));
        var counter: usize = 0;
        while (counter <= childrenCount) {
            defer counter += 1;
            if (selected.children.items.len == 0) {
                selected.state.simulate();
                selected.evalBackProp() catch unreachable;
                simulated = selected.clone() catch unreachable;
                selected.removeFromParent();
                break;
            } else {
                const num = rand.random().intRangeAtMost(usize, 0, selected.children.items.len - 1);
                var child = selected.children.items[num].clone() catch unreachable;
                child.state.simulate();
                child.evalBackProp() catch unreachable;
                simulated = child;
            }

            if (simulated.totalEvaluation > bestScore) {
                bestScore = simulated.totalEvaluation;
                bestNode = simulated;
            }
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
