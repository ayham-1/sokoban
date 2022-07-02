const std = @import("std");
const log = @import("log.zig");
const raylib = @import("./raylib/raylib.zig");
const soko = @import("constants.zig");

const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
var zalloc = ZecsiAllocator{};
var alloc = zalloc.allocator();

const puzzle = @import("puzzle.zig");

var screenWidth: i32 = undefined;
var screenHeight: i32 = undefined;
var texFloor: raylib.Texture2D = undefined;
var texWall: raylib.Texture2D = undefined;
var texDock: raylib.Texture2D = undefined;
var texBox: raylib.Texture2D = undefined;
var texBoxDocked: raylib.Texture2D = undefined;
var texWorker: raylib.Texture2D = undefined;
var texWorkerDocked: raylib.Texture2D = undefined;

pub var mapDisplayed: std.ArrayList(u8) = undefined;
var map: std.ArrayList(std.ArrayList(soko.TexType)) = undefined;
var mapSizeWidth: i32 = undefined;
var mapSizeHeight: i32 = undefined;

var workerPos: soko.Pos = undefined;
var workerMovedToTex: soko.TexType = .floor;
pub var workerMoved: bool = false;
pub var workerInputStopped: bool = false;

pub var won: bool = false;

pub fn start(givenMap: []u8) !void {
    map = try buildMap(givenMap);

    screenWidth = (mapSizeWidth * soko.texWidth) + 2 * soko.mapBorder;
    screenHeight = (mapSizeHeight * soko.texHeight) + 2 * soko.mapBorder;

    raylib.InitWindow(screenWidth, screenHeight, "sokoban");

    const builtin = @import("builtin");
    if (builtin.os.tag != .wasi) {
        raylib.SetTargetFPS(21);
    }

    texFloor = raylib.LoadTexture("assets/floor.png");
    texWall = raylib.LoadTexture("assets/wall.png");
    texDock = raylib.LoadTexture("assets/dock.png");
    texBox = raylib.LoadTexture("assets/box.png");
    texBoxDocked = raylib.LoadTexture("assets/box-docked.png");
    texWorker = raylib.LoadTexture("assets/worker.png");
    texWorkerDocked = raylib.LoadTexture("assets/worker-docked.png");
}

pub fn stop() void {
    for (map.items) |row| {
        row.deinit();
    }
    map.deinit();
    mapDisplayed.deinit();

    if (zalloc.deinit()) {
        log.err("memory leaks detected!", .{});
    }

    raylib.UnloadTexture(texFloor);
    raylib.UnloadTexture(texWall);
    raylib.UnloadTexture(texDock);
    raylib.UnloadTexture(texBox);
    raylib.UnloadTexture(texBoxDocked);
    raylib.UnloadTexture(texWorker);
    raylib.UnloadTexture(texWorkerDocked);

    raylib.CloseWindow();
}

pub fn loop(dt: f32) void {
    _ = dt;
    if (won) return;

    // Update
    if (!workerInputStopped and map.items.len != 0) {
        won = checkWin();

        var moveResult: bool = true;
        if (raylib.IsKeyPressed(.KEY_D)) {
            moveResult = move(soko.ActType.right);
        } else if (raylib.IsKeyPressed(.KEY_A)) {
            moveResult = move(soko.ActType.left);
        } else if (raylib.IsKeyPressed(.KEY_W)) {
            moveResult = move(soko.ActType.up);
        } else if (raylib.IsKeyPressed(.KEY_S)) {
            moveResult = move(soko.ActType.down);
        } else {
            moveResult = move(soko.ActType.none);
        }

        if (!moveResult) {
            log.warn("Can't move there!", .{});
        }
    }

    //Draw
    {
        raylib.BeginDrawing();
        defer raylib.EndDrawing();
        raylib.ClearBackground(raylib.BLACK);

        if (map.items.len == 0) {
            drawTextCenter("EMPTY PUZZLE", raylib.RED);
        }

        for (map.items) |row, i| {
            columned: for (row.items) |texType, j| {
                // find coords value of current box
                var x: i32 = soko.mapBorder + @intCast(i32, j) * soko.texWidth;
                var y: i32 = soko.mapBorder + @intCast(i32, i) * soko.texHeight;

                const texPtr = switch (texType) {
                    .floor => &texFloor,
                    .wall => &texWall,
                    .dock => &texDock,
                    .box => &texBox,
                    .boxDocked => &texBoxDocked,
                    .worker => &texWorker,
                    .workerDocked => &texWorkerDocked,
                    .none => {
                        continue :columned;
                    },
                    .next => {
                        break :columned;
                    },
                };

                raylib.DrawTexture(texPtr.*, x, y, raylib.WHITE);
            }
        }
        if (won) {
            log.info("PUZZLE SOLVED!", .{});
            drawTextCenter("PUZZLE SOLVED!", raylib.YELLOW);
        }
    }
}

fn checkWin() bool {
    if (map.items.len == 0) return false;
    for (map.items) |row| {
        for (row.items) |texType| {
            if (texType == .dock) return false;
            if (texType == .workerDocked) return false;
        }
    }
    return true;
}

fn move(act: soko.ActType) bool {
    if (act == soko.ActType.none) {
        workerMoved = false;
        return true;
    }

    const destTex: soko.TexType = getTexDirection(workerPos, act);
    const workerNewPos: soko.Pos = getNewPos(workerPos, act);

    if (destTex == soko.TexType.floor) {
        map.items[workerNewPos.y].items[workerNewPos.x] = .worker;
        map.items[workerPos.y].items[workerPos.x] = workerMovedToTex;
        workerMovedToTex = .floor;
        workerPos = workerNewPos;
    } else if (destTex == .box or destTex == .boxDocked) {
        const boxDestTex: soko.TexType = getTexDirection(workerNewPos, act);
        const boxNewPos: soko.Pos = getNewPos(workerNewPos, act);

        map.items[boxNewPos.y].items[boxNewPos.x] = switch (boxDestTex) {
            .floor => .box,
            .dock => .boxDocked,
            else => return false,
        };

        map.items[workerNewPos.y].items[workerNewPos.x] = switch (destTex) {
            .box => .worker,
            .boxDocked => .workerDocked,
            else => return false,
        };
        map.items[workerPos.y].items[workerPos.x] = workerMovedToTex;

        workerMovedToTex = switch (destTex) {
            .box => .floor,
            .boxDocked => .dock,
            else => return false,
        };
        workerPos = workerNewPos;
    } else if (destTex == .dock) {
        map.items[workerNewPos.y].items[workerNewPos.x] = .workerDocked;
        map.items[workerPos.y].items[workerPos.x] = .floor;
        workerMovedToTex = .dock;
        workerPos = workerNewPos;
    } else {
        workerMoved = false;
        return false;
    }
    workerMoved = true;
    return true;
}

fn getTexDirection(pos: soko.Pos, act: soko.ActType) soko.TexType {
    const newPos: soko.Pos = getNewPos(pos, act);
    if (!isPosValid(newPos)) {
        return .none;
    } else {
        return map.items[newPos.y].items[newPos.x];
    }
}

fn isPosValid(position: soko.Pos) bool {
    if (position.x <= 0) {
        return false;
    } else if (position.y <= 0) {
        return false;
    } else if (position.y >= map.items.len) {
        return false;
    } else if (position.x >= map.items[position.y].items.len) {
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

pub fn buildDisplayedMap() !void {
    mapDisplayed.deinit();
    var result = std.ArrayList(u8).init(alloc);

    for (map.items) |row| {
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
    mapDisplayed = result;
}

fn buildMap(givenMap: []u8) !std.ArrayList(std.ArrayList(soko.TexType)) {
    var result = std.ArrayList(std.ArrayList(soko.TexType)).init(alloc);
    var line = std.ArrayList(soko.TexType).init(alloc);
    defer line.deinit();

    if (givenMap.len == 0) return result;

    for (givenMap) |item| {
        const itemEnumed = try soko.TexType.convert(item);
        if (itemEnumed == soko.TexType.next) {
            var added_line = std.ArrayList(soko.TexType).init(alloc);
            try added_line.appendSlice(line.items);
            try result.append(added_line);

            line.deinit();
            line = std.ArrayList(soko.TexType).init(alloc);
        } else {
            try line.append(itemEnumed);
        }

        if (itemEnumed == .worker or itemEnumed == .workerDocked) {
            workerPos.x = line.items.len - 1;
            workerPos.y = result.items.len;
        }
    }

    mapSizeHeight = @intCast(i32, result.items.len);
    if (mapSizeHeight != 0) {
        mapSizeWidth = 0;
        for (result.items) |row| {
            if (row.items.len > mapSizeWidth) mapSizeWidth = @intCast(i32, row.items.len);
        }
    } else {
        mapSizeWidth = 6;
        mapSizeHeight = 2;
    }

    // make sure window is sized properly
    screenWidth = (mapSizeWidth * soko.texWidth) + 2 * soko.mapBorder;
    screenHeight = (mapSizeHeight * soko.texHeight) + 2 * soko.mapBorder;

    if (raylib.IsWindowReady()) raylib.SetWindowSize(screenWidth, screenHeight);

    return result;
}

fn drawTextCenter(str: [*:0]const u8, color: raylib.Color) void {
    raylib.BeginDrawing();
    defer raylib.EndDrawing();

    var textSize = raylib.MeasureTextEx(raylib.GetFontDefault(), str, 23, 2.0);
    var textWidth: i32 = @divFloor(textSize.int().x, 2);
    var textHeight: i32 = @divFloor(textSize.int().y, 2);
    var textLocationX: i32 = @divFloor(screenWidth, 2) - textWidth;
    var textLocationY: i32 = @divFloor(screenHeight, 2) - textHeight;

    raylib.DrawText(str, textLocationX, textLocationY, 23, color);
}

pub fn updateMap(givenMap: []u8) !void {
    map = try buildMap(givenMap);
}
