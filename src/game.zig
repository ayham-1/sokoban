const std = @import("std");
const log = @import("log.zig");
const raylib = @import("./raylib/raylib.zig");

const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
var zalloc = ZecsiAllocator{};

const screenWidth = 600;
const screenHeight = 400;

pub fn start() void {
    var alloc = zalloc.allocator();
    _ = alloc;
    raylib.SetConfigFlags(.FLAG_MSAA_4X_HINT);
    raylib.InitWindow(screenWidth, screenHeight, "sokoban");
    raylib.SetTargetFPS(60);
}

pub fn stop() void {
    raylib.CloseWindow();
    if (zalloc.deinit()) {
        log.err("memory leaks detected!", .{});
    }
}

pub fn loop(dt: f32) void {
    _ = dt;

    //Draw
    {
        raylib.BeginDrawing();
        defer raylib.EndDrawing();

        raylib.ClearBackground(raylib.BLACK);
    }
}
