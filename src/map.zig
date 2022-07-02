const std = @import("std");
const soko = @import("constants.zig");

const Allocator = std.mem.Allocator;

pub const Map = struct {
    alloc: Allocator,
    sizeWidth: i32 = 0,
    sizeHeight: i32 = 0,
    displayed: std.ArrayList(u8),
    rows: soko.Map,

    workerPos: soko.Pos = undefined,
    workerMovedToTex: soko.TexType = .floor,
    workerMoved: bool = false,

    pub fn init(allocator: Allocator) Map {
        return Map{ .alloc = allocator, .rows = soko.Map.init(allocator), .displayed = std.ArrayList(u8).init(allocator) };
    }

    pub fn deinit(self: *Map) void {
        for (self.rows.items) |row| {
            row.deinit();
        }
        self.rows.deinit();
        self.displayed.deinit();
        std.log.warn("helllo", .{});
    }

    pub fn buildDisplayedMap(self: *Map) !void {
        self.displayed.deinit();
        var result = std.ArrayList(u8).init(self.alloc);

        for (self.rows.items) |row| {
            for (row.items) |item| {
                try result.append(@enumToInt(item));
            }
            const builtin = @import("builtin");
            if (builtin.os.tag == .wasi) {
                try result.appendSlice("<br>");
            } else {
                try result.append('\n');
            }
        }
        self.displayed = result;
    }

    pub fn buildMap(self: *Map, givenMap: []u8) !void {
        var result = soko.Map.init(self.alloc);
        var line = std.ArrayList(soko.TexType).init(self.alloc);
        defer line.deinit();

        if (givenMap.len == 0) return;

        for (givenMap) |item| {
            const itemEnumed = try soko.TexType.convert(item);
            if (itemEnumed == soko.TexType.next) {
                var added_line = std.ArrayList(soko.TexType).init(self.alloc);
                try added_line.appendSlice(line.items);
                try result.append(added_line);

                line.deinit();
                line = std.ArrayList(soko.TexType).init(self.alloc);
            } else {
                try line.append(itemEnumed);
            }

            if (itemEnumed == .worker or itemEnumed == .workerDocked) {
                self.workerPos.x = line.items.len - 1;
                self.workerPos.y = result.items.len;
            }
        }

        self.sizeHeight = @intCast(i32, result.items.len);
        if (self.sizeHeight != 0) {
            self.sizeWidth = 0;
            for (result.items) |row| {
                if (row.items.len > self.sizeWidth) self.sizeWidth = @intCast(i32, row.items.len);
            }
        } else {
            self.sizeWidth = 6;
            self.sizeHeight = 2;
        }

        self.rows.deinit();
        self.rows = result;
    }

    pub fn move(self: *Map, act: soko.ActType) bool {
        if (act == soko.ActType.none) {
            self.workerMoved = false;
            return true;
        }

        const destTex: soko.TexType = self.getTexDirection(self.workerPos, act);
        const workerNewPos: soko.Pos = Map.getNewPos(self.workerPos, act);

        if (destTex == soko.TexType.floor) {
            self.rows.items[workerNewPos.y].items[workerNewPos.x] = .worker;
            self.rows.items[self.workerPos.y].items[self.workerPos.x] = self.workerMovedToTex;
            self.workerMovedToTex = .floor;
            self.workerPos = workerNewPos;
        } else if (destTex == .box or destTex == .boxDocked) {
            const boxDestTex: soko.TexType = self.getTexDirection(workerNewPos, act);
            const boxNewPos: soko.Pos = Map.getNewPos(workerNewPos, act);

            self.rows.items[boxNewPos.y].items[boxNewPos.x] = switch (boxDestTex) {
                .floor => .box,
                .dock => .boxDocked,
                else => return false,
            };

            self.rows.items[workerNewPos.y].items[workerNewPos.x] = switch (destTex) {
                .box => .worker,
                .boxDocked => .workerDocked,
                else => return false,
            };
            self.rows.items[self.workerPos.y].items[self.workerPos.x] = self.workerMovedToTex;

            self.workerMovedToTex = switch (destTex) {
                .box => .floor,
                .boxDocked => .dock,
                else => return false,
            };
            self.workerPos = workerNewPos;
        } else if (destTex == .dock) {
            self.rows.items[workerNewPos.y].items[workerNewPos.x] = .workerDocked;
            self.rows.items[self.workerPos.y].items[self.workerPos.x] = .floor;
            self.workerMovedToTex = .dock;
            self.workerPos = workerNewPos;
        } else {
            self.workerMoved = false;
            return false;
        }
        self.workerMoved = true;
        return true;
    }
    fn getTexDirection(self: Map, pos: soko.Pos, act: soko.ActType) soko.TexType {
        const newPos: soko.Pos = getNewPos(pos, act);
        if (!self.isPosValid(newPos)) {
            return .none;
        } else {
            return self.rows.items[newPos.y].items[newPos.x];
        }
    }

    fn isPosValid(self: Map, position: soko.Pos) bool {
        if (position.x <= 0) {
            return false;
        } else if (position.y <= 0) {
            return false;
        } else if (position.y >= self.rows.items.len) {
            return false;
        } else if (position.x >= self.rows.items[position.y].items.len) {
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
