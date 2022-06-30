const std = @import("std");
const log = @import("log.zig");
const raylib = @import("./raylib/raylib.zig");

const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
var zalloc = ZecsiAllocator{};
//var zalloc = std.heap.GeneralPurposeAllocator(.{}){};
var alloc = zalloc.allocator();

const texWidth: i32 = 32;
const texHeight: i32 = 32;
const mapBorder: i32 = 6;

const TexType = enum(u8) {
    floor = '.',
    wall = 'w',
    dock = 'd',
    box = 'b',
    boxDocked = 'x',
    worker = 'p',
    workerDocked = 'X',
    none = '#',
    next = '\n',
};

const ActType = enum(u5) { up, down, left, right, none };
const Pos = struct { x: usize, y: usize };

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
var map: std.ArrayList(std.ArrayList(TexType)) = undefined;
var mapSizeWidth: i32 = undefined;
var mapSizeHeight: i32 = undefined;

var workerPos: Pos = undefined;
var workerMovedToTex: TexType = .floor;
pub var workerMoved: bool = false;

pub var won: bool = false;

pub fn start(givenMap: []u8) !void {
    map = try buildMap(givenMap);

    screenWidth = (mapSizeWidth * texWidth) + 2 * mapBorder;
    screenHeight = (mapSizeHeight * texHeight) + 2 * mapBorder;

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

    // Update
    if (!won) {
        won = checkWin();

        var moveResult: bool = true;
        if (raylib.IsKeyPressed(.KEY_D) or raylib.IsKeyPressed(.KEY_RIGHT)) {
            moveResult = move(ActType.right);
        } else if (raylib.IsKeyPressed(.KEY_A) or raylib.IsKeyPressed(.KEY_LEFT)) {
            moveResult = move(ActType.left);
        } else if (raylib.IsKeyPressed(.KEY_W) or raylib.IsKeyPressed(.KEY_UP)) {
            moveResult = move(ActType.up);
        } else if (raylib.IsKeyPressed(.KEY_S) or raylib.IsKeyPressed(.KEY_DOWN)) {
            moveResult = move(ActType.down);
        } else {
            moveResult = move(ActType.none);
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

        for (map.items) |row, i| {
            columned: for (row.items) |texType, j| {
                // find coords value of current box
                var x: i32 = mapBorder + @intCast(i32, j) * texWidth;
                var y: i32 = mapBorder + @intCast(i32, i) * texHeight;

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

            raylib.BeginDrawing();
            defer raylib.EndDrawing();

            var textSize = raylib.MeasureTextEx(raylib.GetFontDefault(), "PUZZLE SOLVED!", 23, 2.0);
            var textWidth: i32 = @divFloor(textSize.int().x, 2);
            var textHeight: i32 = @divFloor(textSize.int().y, 2);
            var textLocationX: i32 = @divFloor(screenWidth, 2) - textWidth;
            var textLocationY: i32 = @divFloor(screenHeight, 2) - textHeight;

            raylib.DrawText("PUZZLE SOLVED!", textLocationX, textLocationY, 23, raylib.WHITE);
        }
    }
}

fn checkWin() bool {
    for (map.items) |row| {
        for (row.items) |texType| {
            if (texType == .dock) return false;
        }
    }
    return true;
}

fn move(act: ActType) bool {
    if (act == ActType.none) {
        workerMoved = false;
        return true;
    }

    const destTex: TexType = getTexDirection(workerPos, act);
    const workerNewPos: Pos = getNewPos(workerPos, act);

    if (destTex == TexType.floor) {
        map.items[workerNewPos.y].items[workerNewPos.x] = .worker;
        map.items[workerPos.y].items[workerPos.x] = workerMovedToTex;
        workerMovedToTex = .floor;
        workerPos = workerNewPos;
    } else if (destTex == .box or destTex == .boxDocked) {
        const boxDestTex: TexType = getTexDirection(workerNewPos, act);
        const boxNewPos: Pos = getNewPos(workerNewPos, act);

        map.items[boxNewPos.y].items[boxNewPos.x] = switch (boxDestTex) {
            .floor => .box,
            .dock => .boxDocked,
            else => {
                return false;
            },
        };

        map.items[workerNewPos.y].items[workerNewPos.x] = switch (destTex) {
            .box => .worker,
            .boxDocked => .workerDocked,
            else => unreachable,
        };
        map.items[workerPos.y].items[workerPos.x] = workerMovedToTex;

        workerMovedToTex = switch (destTex) {
            .box => .floor,
            .boxDocked => .dock,
            else => unreachable,
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

fn getTexDirection(pos: Pos, act: ActType) TexType {
    const newPos: Pos = getNewPos(pos, act);
    if (!isPosValid(newPos)) {
        return .none;
    } else {
        return map.items[newPos.y].items[newPos.x];
    }
}

fn isPosValid(position: Pos) bool {
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

fn getNewPos(oldPos: Pos, act: ActType) Pos {
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

fn buildMap(givenMap: []u8) !std.ArrayList(std.ArrayList(TexType)) {
    var result = std.ArrayList(std.ArrayList(TexType)).init(alloc);
    var line = std.ArrayList(TexType).init(alloc);
    defer line.deinit();

    for (givenMap) |item| {
        const itemEnumed = @intToEnum(TexType, item);
        if (itemEnumed == TexType.next) {
            var added_line = std.ArrayList(TexType).init(alloc);
            try added_line.appendSlice(line.items);
            try result.append(added_line);

            line.deinit();
            line = std.ArrayList(TexType).init(alloc);
        } else {
            try line.append(itemEnumed);
        }

        if (itemEnumed == .worker or itemEnumed == .workerDocked) {
            workerPos.x = line.items.len - 1;
            workerPos.y = result.items.len;
        }
    }

    mapSizeWidth = @intCast(i32, result.items[0].items.len);
    mapSizeHeight = @intCast(i32, result.items.len);
    return result;
}
