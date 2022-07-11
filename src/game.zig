const std = @import("std");
const log = @import("log.zig");
const raylib = @import("./raylib/raylib.zig");
const soko = @import("constants.zig");

const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
var zalloc = ZecsiAllocator{};
var alloc = zalloc.allocator();

const Map = @import("map.zig").Map;
const Puzzle = @import("puzzle.zig").Puzzle;
pub var puzzle: Puzzle = undefined;

var screenWidth: i32 = undefined;
var screenHeight: i32 = undefined;
var texFloor: raylib.Texture2D = undefined;
var texWall: raylib.Texture2D = undefined;
var texDock: raylib.Texture2D = undefined;
var texBox: raylib.Texture2D = undefined;
var texBoxDocked: raylib.Texture2D = undefined;
var texWorker: raylib.Texture2D = undefined;
var texWorkerDocked: raylib.Texture2D = undefined;

pub var workerInputStopped: bool = false;

pub var won: bool = false;

pub fn start(givenMap: Map) !void {
    puzzle = Puzzle.init(alloc, givenMap);

    screenWidth = (puzzle.map.sizeWidth * soko.texWidth) + 2 * soko.mapBorder;
    screenHeight = (puzzle.map.sizeHeight * soko.texHeight) + 2 * soko.mapBorder;

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
    puzzle.deinit();
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
    if (!workerInputStopped and puzzle.map.rows.items.len != 0) {
        won = checkWin();

        var act: soko.ActType = soko.ActType.none;
        if (raylib.IsKeyPressed(.KEY_D)) {
            act = soko.ActType.right;
        } else if (raylib.IsKeyPressed(.KEY_A)) {
            act = soko.ActType.left;
        } else if (raylib.IsKeyPressed(.KEY_W)) {
            act = soko.ActType.up;
        } else if (raylib.IsKeyPressed(.KEY_S)) {
            act = soko.ActType.down;
        } else {
            act = soko.ActType.none;
        }
        puzzle.move(act) catch {
            log.warn("Can't move there!", .{});
        };
    }

    //Draw
    {
        raylib.BeginDrawing();
        defer raylib.EndDrawing();
        raylib.ClearBackground(raylib.BLACK);

        if (puzzle.map.rows.items.len == 0) {
            drawTextCenter("EMPTY PUZZLE", raylib.RED);
        }

        for (puzzle.map.rows.items) |row, i| {
            columned: for (row.items) |texType, j| {
                // find coords value of current box
                var x: i32 = soko.mapBorder + @intCast(i32, j) * soko.texWidth;
                var y: i32 = soko.mapBorder + @intCast(i32, i) * soko.texHeight;

                const texPtr = switch (texType.tex) {
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
    if (puzzle.map.rows.items.len == 0) return false;
    for (puzzle.map.rows.items) |row| {
        for (row.items) |texType| {
            if (texType.tex == .dock) return false;
            if (texType.tex == .workerDocked) return false;
            if (texType.tex == .box) return false;
        }
    }
    return true;
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
    try puzzle.map.buildMap(givenMap);

    // make sure window is sized properly
    screenWidth = (puzzle.sizeWidth * soko.texWidth) + 2 * soko.mapBorder;
    screenHeight = (puzzle.sizeHeight * soko.texHeight) + 2 * soko.mapBorder;

    if (raylib.IsWindowReady()) raylib.SetWindowSize(screenWidth, screenHeight);
}
