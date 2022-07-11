const std = @import("std");
const assert = std.debug.assert;

const soko = @import("constants.zig");
const mapzig = @import("map.zig");
const Map = mapzig.Map;

const Allocator = std.mem.Allocator;

pub const Puzzle = struct {
    alloc: Allocator,
    map: Map = undefined,

    workerMovedToTile: soko.Textile = soko.Textile{ .tex = .floor, .id = std.math.maxInt(u8) },
    workerMoved: bool = false,

    pub fn init(allocator: Allocator, map: Map) Puzzle {
        var puzzle = Puzzle{ .alloc = allocator, .map = map };
        return puzzle;
    }

    pub fn deinit(self: *Puzzle) void {
        //self.map.deinit();
        _ = self;
    }

    pub fn move(self: *Puzzle, act: soko.ActType) !void {
        if (act == soko.ActType.none) {
            self.workerMoved = false;
            return;
        }

        const destTile: soko.Textile = try self.getTexDirection(self.map.workerPos, act);
        const workerNewPos: soko.Pos = try self.getNewPos(self.map.workerPos, act);

        if (destTile.tex == soko.TexType.floor) {
            self.map.rows.items[workerNewPos.y].items[workerNewPos.x] = self.getWorkerTile();
            self.map.rows.items[workerNewPos.y].items[workerNewPos.x].tex = .worker;
            self.map.rows.items[self.map.workerPos.y].items[self.map.workerPos.x] = self.workerMovedToTile;
            self.workerMovedToTile = destTile;
            self.map.workerPos = workerNewPos;
        } else if (destTile.tex == .box or destTile.tex == .boxDocked) {
            const boxDestTile: soko.Textile = try self.getTexDirection(workerNewPos, act);
            const boxNewPos: soko.Pos = try self.getNewPos(workerNewPos, act);

            // switch box's destination with current box location
            self.map.rows.items[boxNewPos.y].items[boxNewPos.x].tex = switch (boxDestTile.tex) {
                .floor => .box,
                .dock => .boxDocked,
                else => return error.InvalidPos,
            };
            self.map.rows.items[boxNewPos.y].items[boxNewPos.x].id = destTile.id; // retain id

            // switch workerNewPos, originally box location, with current workerPos
            self.map.rows.items[workerNewPos.y].items[workerNewPos.x].tex = switch (destTile.tex) {
                .box => .worker,
                .boxDocked => .workerDocked,
                else => return error.InvalidPos,
            };
            self.map.rows.items[workerNewPos.y].items[workerNewPos.x].id = self.getWorkerTile().id; // retain id
            self.map.rows.items[self.map.workerPos.y].items[self.map.workerPos.x] = self.workerMovedToTile;

            self.workerMovedToTile.tex = switch (destTile.tex) {
                .box => .floor,
                .boxDocked => .dock,
                else => return error.InvalidPos,
            };
            self.workerMovedToTile.id = 0; // retain id

            self.map.workerPos = workerNewPos;
        } else if (destTile.tex == .dock) {
            self.map.rows.items[workerNewPos.y].items[workerNewPos.x].tex = .workerDocked;
            self.map.rows.items[self.map.workerPos.y].items[self.map.workerPos.x] = self.workerMovedToTile;
            self.workerMovedToTile = destTile;
            self.map.workerPos = workerNewPos;
        } else {
            self.workerMoved = false;
            return error.InvalidPos;
        }
        self.workerMoved = true;

        return;
    }
    fn getTexDirection(self: Puzzle, pos: soko.Pos, act: soko.ActType) !soko.Textile {
        const newPos: soko.Pos = try self.getNewPos(pos, act);
        return self.map.rows.items[newPos.y].items[newPos.x];
    }

    fn getNewPos(self: Puzzle, oldPos: soko.Pos, act: soko.ActType) !soko.Pos {
        var newPos = oldPos;
        switch (act) {
            .left => {
                if (oldPos.x == 0)
                    return error.InvalidPos;
                newPos = .{ .x = oldPos.x - 1, .y = oldPos.y };
            },
            .right => {
                if (oldPos.x + 1 >= self.map.rows.items[oldPos.y].items.len)
                    return error.InvalidPos;
                newPos = .{ .x = oldPos.x + 1, .y = oldPos.y };
            },
            .up => {
                if (oldPos.y == 0)
                    return error.InvalidPos;
                newPos = .{ .x = oldPos.x, .y = oldPos.y - 1 };
            },
            .down => {
                if (oldPos.y + 1 >= self.map.rows.items.len)
                    return error.InvalidPos;
                newPos = .{ .x = oldPos.x, .y = oldPos.y + 1 };
            },
            .none => {
                newPos = oldPos;
            },
        }
        return newPos;
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
