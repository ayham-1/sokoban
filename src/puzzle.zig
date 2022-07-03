const std = @import("std");
const soko = @import("constants.zig");
const mapzig = @import("map.zig");
const Map = mapzig.Map;

const Allocator = std.mem.Allocator;

pub const Puzzle = struct {
    alloc: Allocator,
    map: Map = undefined,

    workerMovedToTex: soko.TexType = .floor,
    workerMoved: bool = false,

    pub fn init(allocator: Allocator) Puzzle {
        return Puzzle{ .alloc = allocator, .map = Map.init(allocator) };
    }

    pub fn deinit(self: *Puzzle) void {
        self.map.deinit();
    }

    pub fn move(self: *Puzzle, act: soko.ActType) bool {
        if (act == soko.ActType.none) {
            self.workerMoved = false;
            return true;
        }

        const destTex: soko.TexType = self.getTexDirection(self.map.workerPos, act);
        const workerNewPos: soko.Pos = Puzzle.getNewPos(self.map.workerPos, act);

        if (destTex == soko.TexType.floor) {
            self.map.rows.items[workerNewPos.y].items[workerNewPos.x] = .worker;
            self.map.rows.items[self.map.workerPos.y].items[self.map.workerPos.x] = self.workerMovedToTex;
            self.workerMovedToTex = .floor;
            self.map.workerPos = workerNewPos;
        } else if (destTex == .box or destTex == .boxDocked) {
            const boxDestTex: soko.TexType = self.getTexDirection(workerNewPos, act);
            const boxNewPos: soko.Pos = Puzzle.getNewPos(workerNewPos, act);

            self.map.rows.items[boxNewPos.y].items[boxNewPos.x] = switch (boxDestTex) {
                .floor => .box,
                .dock => .boxDocked,
                else => return false,
            };

            self.map.rows.items[workerNewPos.y].items[workerNewPos.x] = switch (destTex) {
                .box => .worker,
                .boxDocked => .workerDocked,
                else => return false,
            };
            self.map.rows.items[self.map.workerPos.y].items[self.map.workerPos.x] = self.workerMovedToTex;

            self.workerMovedToTex = switch (destTex) {
                .box => .floor,
                .boxDocked => .dock,
                else => return false,
            };
            self.map.workerPos = workerNewPos;
        } else if (destTex == .dock) {
            self.map.rows.items[workerNewPos.y].items[workerNewPos.x] = .workerDocked;
            self.map.rows.items[self.map.workerPos.y].items[self.map.workerPos.x] = .floor;
            self.workerMovedToTex = .dock;
            self.map.workerPos = workerNewPos;
        } else {
            self.workerMoved = false;
            return false;
        }
        self.workerMoved = true;
        return true;
    }
    fn getTexDirection(self: Puzzle, pos: soko.Pos, act: soko.ActType) soko.TexType {
        const newPos: soko.Pos = getNewPos(pos, act);
        if (!self.isPosValid(newPos)) {
            return .none;
        } else {
            return self.map.rows.items[newPos.y].items[newPos.x];
        }
    }

    fn isPosValid(self: Puzzle, position: soko.Pos) bool {
        if (position.x <= 0) {
            return false;
        } else if (position.y <= 0) {
            return false;
        } else if (position.y >= self.map.rows.items.len) {
            return false;
        } else if (position.x >= self.map.rows.items[position.y].items.len) {
            return false;
        }
        return true;
    }

    fn getNewPos(oldPos: soko.Pos, act: soko.ActType) soko.Pos {
        return switch (act) {
            .left => .{ .x = oldPos.x - 1, .y = oldPos.y },
            .right => .{ .x = oldPos.x + 1, .y = oldPos.y },
            .up => .{ .x = oldPos.x, .y = oldPos.y - 1 },
            .down => .{ .x = oldPos.x, .y = oldPos.y + 1 },
            .none => oldPos,
        };
    }
};
