const std = @import("std");
const log = @import("log.zig");
const raylib = @import("./raylib/raylib.zig");

const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
var zalloc = ZecsiAllocator{};

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
    non = '#',
    next = '\n',
};

const ActType = enum(u4) { up, down, left, right };

var screenWidth: i32 = undefined;
var screenHeight: i32 = undefined;
var texFloor: raylib.Texture2D = undefined;
var texWall: raylib.Texture2D = undefined;
var texDock: raylib.Texture2D = undefined;
var texBox: raylib.Texture2D = undefined;
var texBoxDocked: raylib.Texture2D = undefined;
var texWorker: raylib.Texture2D = undefined;
var texWorkerDocked: raylib.Texture2D = undefined;

var alloc = zalloc.allocator();
var map: std.ArrayList(std.ArrayList(TexType)) = undefined;
var mapSizeWidth: i32 = undefined;
var mapSizeHeight: i32 = undefined;

const Pos = struct { x: usize, y: usize };

var workerPos: Pos = undefined;

pub fn start(givenMap: []u8) !void {
    map = try buildMap(givenMap);

    screenWidth = (mapSizeWidth * texWidth) + 2 * mapBorder;
    screenHeight = (mapSizeHeight * texHeight) + 2 * mapBorder;

    raylib.SetConfigFlags(.FLAG_MSAA_4X_HINT);
    raylib.InitWindow(screenWidth, screenHeight, "sokoban");
    raylib.SetTargetFPS(16);

    texFloor = raylib.LoadTexture("assets/floor.png");
    texWall = raylib.LoadTexture("assets/wall.png");
    texDock = raylib.LoadTexture("assets/dock.png");
    texBox = raylib.LoadTexture("assets/box.png");
    texBoxDocked = raylib.LoadTexture("assets/box-docked.png");
    texWorker = raylib.LoadTexture("assets/worker.png");
    texWorkerDocked = raylib.LoadTexture("assets/worker-docked.png");
}

pub fn stop() void {
    raylib.UnloadTexture(texFloor);
    raylib.UnloadTexture(texWall);
    raylib.UnloadTexture(texDock);
    raylib.UnloadTexture(texBox);
    raylib.UnloadTexture(texBoxDocked);
    raylib.UnloadTexture(texWorker);
    raylib.UnloadTexture(texWorkerDocked);

    raylib.CloseWindow();
    if (zalloc.deinit()) {
        log.err("memory leaks detected!", .{});
    }
}

pub fn loop(dt: f32) void {
    _ = dt;

    // Update
    {
        var act: ActType = undefined;
        if (raylib.IsKeyPressed(.KEY_D) or raylib.IsKeyPressed(.KEY_RIGHT)) {
            act = ActType.right;
        } else if (raylib.IsKeyPressed(.KEY_A) or raylib.IsKeyPressed(.KEY_LEFT)) {
            act = ActType.left;
        } else if (raylib.IsKeyPressed(.KEY_W) or raylib.IsKeyPressed(.KEY_UP)) {
            act = ActType.up;
        } else if (raylib.IsKeyPressed(.KEY_S) or raylib.IsKeyPressed(.KEY_DOWN)) {
            act = ActType.down;
        }

        if (act != undefined and !move(act)) {
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
                    .non => {
                        continue :columned;
                    },
                    .next => {
                        break :columned;
                    },
                };

                raylib.DrawTexture(texPtr.*, x, y, raylib.WHITE);
            }
        }
    }
}

pub fn move(act: ActType) bool {
    const destTex: TexType = getTexDirection(act);
    const workerNewPos: Pos = getWorkerNewPos(act);
    if (destTex == TexType.floor or destTex == TexType.box or destTex == TexType.boxDocked) {
        log.warn("{}", .{workerNewPos});
        map.items[workerNewPos.x].items[workerNewPos.y] = TexType.worker;
        map.items[workerPos.y].items[workerPos.x] = TexType.floor;
        workerPos = workerNewPos;
        return true;
    } else {
        return false;
    }
}

fn getTexDirection(act: ActType) TexType {
    const workerNewPos: Pos = getWorkerNewPos(act);
    if (!isWorkerPosValid(workerNewPos)) {
        return TexType.non;
    } else {
        return map.items[workerNewPos.y].items[workerNewPos.x - 1];
    }
}

fn isWorkerPosValid(position: Pos) bool {
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

fn getWorkerNewPos(act: ActType) Pos {
    return switch (act) {
        .left => .{ .x = workerPos.x - 1, .y = workerPos.y },
        .right => .{ .x = workerPos.x + 1, .y = workerPos.y },
        .up => .{ .x = workerPos.x, .y = workerPos.y - 1 },
        .down => .{ .x = workerPos.x, .y = workerPos.y + 1 },
    };
}

pub fn buildMap(givenMap: []u8) !std.ArrayList(std.ArrayList(TexType)) {
    var result = std.ArrayList(std.ArrayList(TexType)).init(alloc);
    var line = std.ArrayList(TexType).init(alloc);

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

        if (itemEnumed == TexType.worker or itemEnumed == TexType.workerDocked) {
            workerPos.x = line.items.len;
            workerPos.y = result.items.len;
        }
    }

    mapSizeWidth = @intCast(i32, result.items[0].items.len);
    mapSizeHeight = @intCast(i32, result.items.len);
    return result;
}
