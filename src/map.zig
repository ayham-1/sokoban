const std = @import("std");
const soko = @import("constants.zig");

const Allocator = std.mem.Allocator;

pub const Map = struct {
    alloc: Allocator,
    rows: soko.MapArray,
    highestId: soko.TexId = 1,
    displayed: std.ArrayList(u8) = undefined,
    sizeWidth: i32 = 0,
    sizeHeight: i32 = 0,
    workerPos: soko.Pos = undefined,
    boxPos: std.AutoArrayHashMap(soko.TexId, soko.Pos),

    pub fn init(alloc: Allocator) Map {
        var map = Map{
            .alloc = alloc,
            .rows = soko.MapArray.init(alloc),
            .displayed = std.ArrayList(u8).init(alloc),
            .boxPos = std.AutoArrayHashMap(soko.TexId, soko.Pos).init(alloc),
        };

        // find worker pos
        map.setWorkerPos();
        map.setBoxPositions();
        return map;
    }

    pub fn deinit(self: *Map) void {
        for (self.rows.items) |row| {
            row.deinit();
        }
        self.rows.deinit();
        self.displayed.deinit();
    }

    // TODO: consider renaming to getDisplayed()
    pub fn buildDisplayed(self: *Map) !void {
        self.displayed.clearAndFree();

        for (self.rows.items) |row| {
            for (row.items) |item| {
                try self.displayed.append(@enumToInt(item.tex));
            }
            const builtin = @import("builtin");
            if (builtin.os.tag == .wasi) {
                try self.displayed.appendSlice("\r\n");
            } else {
                try self.displayed.append('\n');
            }
        }
    }

    pub fn build(self: *Map, givenMap: []const u8) !void {
        var result = soko.MapArray.init(self.alloc);
        var line = soko.MapRowArray.init(self.alloc);
        defer line.deinit();

        if (givenMap.len == 0) return;

        for (givenMap) |item| {
            const itemEnumed = try soko.TexType.convert(item);
            if (itemEnumed == soko.TexType.next) {
                var added_line = soko.MapRowArray.init(self.alloc);
                try added_line.appendSlice(line.items);
                try result.append(added_line);

                line.deinit();
                line = std.ArrayList(soko.Textile).init(self.alloc);
            } else {
                try line.append(soko.Textile{ .tex = itemEnumed, .id = self.highestId });
                self.highestId += 1;
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

    fn setBoxPositions(self: *Map) void {
        self.boxPos.clearAndFree();
        for (self.rows.items) |row, i| {
            for (row.items) |item, j| {
                switch (item.tex) {
                    .box, .boxDocked => self.boxPos.put(item.id, soko.Pos{ .x = j, .y = i }) catch unreachable,
                    else => {},
                }
            }
        }
    }

    pub fn setWorkerPos(self: *Map) void {
        for (self.rows.items) |row, i| {
            for (row.items) |item, j| {
                if (item.tex == .worker) {
                    self.workerPos = soko.Pos{ .x = j, .y = i };
                }
            }
        }
    }

    pub fn clone(self: *Map) !*Map {
        const cloned: *Map = try self.alloc.create(Map);
        cloned.alloc = self.alloc;
        cloned.highestId = self.highestId;
        cloned.sizeHeight = self.sizeHeight;
        cloned.sizeWidth = self.sizeWidth;
        cloned.rows = soko.MapArray.init(self.alloc); // contains rows
        for (self.rows.items) |*row| {
            try cloned.rows.append(try row.clone());
        }
        cloned.displayed = try self.displayed.clone();
        cloned.boxPos = try self.boxPos.clone();
        cloned.setWorkerPos();
        return cloned;
    }
};
