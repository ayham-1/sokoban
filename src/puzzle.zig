const std = @import("std");
const assert = std.debug.assert;

const soko = @import("constants.zig");
const mapzig = @import("map.zig");
const Map = mapzig.Map;

const Allocator = std.mem.Allocator;

pub const Puzzle = struct {
    alloc: Allocator,
    map: Map = undefined,

    workerMovedToTile: soko.Textile = soko.Textile{ .tex = .floor, .id = std.math.maxInt(u4) },
    workerMoved: bool = false,

    pub fn init(allocator: Allocator, map: Map) Puzzle {
        var puzzle = Puzzle{ .alloc = allocator, .map = map };
        return puzzle;
    }

    pub fn deinit(self: *Puzzle) void {
        self.map.deinit();
        const builtin = @import("builtin");
        std.log.warn("strip {} ", .{builtin.strip_debug_info});
        std.log.warn("helll", .{});
    }

    pub fn move(self: *Puzzle, act: soko.ActType) bool {
        if (act == soko.ActType.none) {
            self.workerMoved = false;
            return true;
        }

        const destTile: soko.Textile = self.getTexDirection(self.map.workerPos, act);
        const workerNewPos: soko.Pos = Puzzle.getNewPos(self.map.workerPos, act);

        if (destTile.tex == soko.TexType.floor) {
            self.map.rows.items[workerNewPos.y].items[workerNewPos.x] = self.getWorkerTile();
            self.map.rows.items[workerNewPos.y].items[workerNewPos.x].tex = .worker;
            self.map.rows.items[self.map.workerPos.y].items[self.map.workerPos.x] = self.workerMovedToTile;
            self.workerMovedToTile = destTile;
            self.map.workerPos = workerNewPos;
        } else if (destTile.tex == .box or destTile.tex == .boxDocked) {
            const boxDestTile: soko.Textile = self.getTexDirection(workerNewPos, act);
            const boxNewPos: soko.Pos = Puzzle.getNewPos(workerNewPos, act);

            // switch box's destination with current box location
            self.map.rows.items[boxNewPos.y].items[boxNewPos.x].tex = switch (boxDestTile.tex) {
                .floor => .box,
                .dock => .boxDocked,
                else => return false,
            };
            self.map.rows.items[boxNewPos.y].items[boxNewPos.x].id = boxDestTile.id; // retain id

            // switch workerNewPos, originally box location, with current workerPos
            self.map.rows.items[workerNewPos.y].items[workerNewPos.x].tex = switch (destTile.tex) {
                .box => .worker,
                .boxDocked => .workerDocked,
                else => return false,
            };
            self.map.rows.items[workerNewPos.y].items[workerNewPos.x].id = destTile.id; // retain id
            self.map.rows.items[self.map.workerPos.y].items[self.map.workerPos.x] = self.workerMovedToTile;

            self.workerMovedToTile.tex = switch (destTile.tex) {
                .box => .floor,
                .boxDocked => .dock,
                else => return false,
            };
            self.workerMovedToTile.id = destTile.id; // retain id

            self.map.workerPos = workerNewPos;
        } else if (destTile.tex == .dock) {
            self.map.rows.items[workerNewPos.y].items[workerNewPos.x].tex = .workerDocked;
            self.map.rows.items[self.map.workerPos.y].items[self.map.workerPos.x].tex = .floor;
            self.workerMovedToTile = destTile;
            self.map.workerPos = workerNewPos;
        } else {
            self.workerMoved = false;
            return false;
        }
        self.workerMoved = true;
        return true;
    }
    fn getTexDirection(self: Puzzle, pos: soko.Pos, act: soko.ActType) soko.Textile {
        const newPos: soko.Pos = getNewPos(pos, act);
        if (!self.isPosValid(newPos)) {
            return soko.Textile{ .tex = .none, .id = 0 };
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

    pub fn fillBoxPairsWithBoxes(self: *Puzzle, boxes: std.ArrayList(soko.Pos)) void {
        for (boxes.items) |boxPos| {
            self.boxGoalPairs.append(soko.BoxGoalPair{ boxPos, soko.Pos{ .x = std.math.inf_u64, .y = std.math.inf_u64 } });
        }
    }

    fn getWorkerTile(self: *Puzzle) soko.Textile {
        return self.map.rows.items[self.map.workerPos.y].items[self.map.workerPos.x];
    }
};
