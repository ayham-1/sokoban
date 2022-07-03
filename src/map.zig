const std = @import("std");
const soko = @import("constants.zig");

const Allocator = std.mem.Allocator;

pub const Map = struct {
    alloc: Allocator,
    rows: soko.MapArray,
    displayed: std.ArrayList(u8),
    sizeWidth: i32 = 0,
    sizeHeight: i32 = 0,
    workerPos: soko.Pos = undefined,

    pub fn init(allocator: Allocator) Map {
        return Map{
            .alloc = allocator,
            .rows = soko.MapArray.init(allocator),
            .displayed = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Map) void {
        for (self.rows.items) |row| {
            row.deinit();
        }
        self.rows.deinit();
        self.displayed.deinit();
    }

    pub fn buildDisplayed(alloc: Allocator, rows: soko.MapArray) !std.ArrayList(u8) {
        var result = std.ArrayList(u8).init(alloc);

        for (rows.items) |row| {
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
        return result;
    }

    pub fn build(self: *Map, givenMap: []u8) !void {
        var result = soko.MapArray.init(self.alloc);
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
};
