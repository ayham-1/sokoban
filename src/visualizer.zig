const std = @import("std");
const log = @import("log.zig");
const raylib = @import("./raylib/raylib.zig");
const soko = @import("constants.zig");
const Node = @import("generator.zig").Node;
const Map = @import("map.zig").Map;

const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
var zalloc = ZecsiAllocator{};
var alloc = zalloc.allocator();

var levelSize: usize = 5;
var boxCount: usize = 3;
var seed: u64 = undefined;
var rnd: std.rand.Xoshiro256 = undefined;
var parentNode: *Node = undefined;
var font: raylib.Font = undefined;

const screenWidth = 800;
const screenHeight = 600;

fn init() void {
    std.os.getrandom(std.mem.asBytes(&seed)) catch unreachable;
    rnd = std.rand.DefaultPrng.init(seed);

    var map: *Map = alloc.create(Map) catch unreachable;
    map.* = Map.init(alloc);

    var i: usize = 0;
    var j: usize = 0;
    while (i < levelSize) {
        defer i += 1;
        j = 0;
        var newRow: soko.MapRowArray = soko.MapRowArray.init(alloc);
        while (j < levelSize) {
            defer j += 1;
            newRow.append(soko.Textile{ .id = map.highestId, .tex = soko.TexType.wall }) catch unreachable;
            map.highestId += 1;
        }
        map.rows.append(newRow) catch unreachable;
    }

    // plob worker in a random place
    var workerX = rnd.random().intRangeAtMost(usize, 1, levelSize - 2);
    var workerY = rnd.random().intRangeAtMost(usize, 1, levelSize - 2);

    map.rows.items[workerY].items[workerX].tex = .worker;
    map.setWorkerPos();

    map.buildDisplayed() catch unreachable;
    map.sizeHeight = @intCast(i32, levelSize);
    map.sizeWidth = @intCast(i32, levelSize);

    parentNode = Node.initAsParent(alloc, map, boxCount);
}

pub fn main() !void {
    init();
    raylib.InitWindow(screenWidth, screenHeight, "Sokoban Puzzle Generator Visualizer");
    raylib.SetConfigFlags(.FLAG_WINDOW_RESIZABLE);
    raylib.SetTargetFPS(60);

    font = raylib.LoadFont("assets/font.otf");
    defer raylib.UnloadFont(font);

    var camera2D = raylib.Camera2D{
        .offset = raylib.Vector2.zero(),
        .target = raylib.Vector2.zero(),
        .rotation = 0.0,
        .zoom = 1.0,
    };

    defer raylib.CloseWindow();

    while (!raylib.WindowShouldClose()) {
        raylib.BeginDrawing();
        raylib.BeginMode2D(camera2D);
        defer raylib.EndMode2D();
        defer raylib.EndDrawing();
        raylib.ClearBackground(raylib.BLACK);

        visualize(parentNode, 0, 0);

        // update
        if (raylib.IsMouseButtonPressed(.MOUSE_BUTTON_LEFT) or raylib.IsKeyPressed(.KEY_SPACE))
            parentNode.iterate() catch unreachable;

        if (raylib.IsKeyDown(.KEY_Z))
            camera2D.zoom += 0.01;
        if (raylib.IsKeyDown(.KEY_X))
            camera2D.zoom -= 0.01;

        if (raylib.IsKeyDown(.KEY_A))
            camera2D.offset.x += 10;
        if (raylib.IsKeyDown(.KEY_D))
            camera2D.offset.x -= 10;
        if (raylib.IsKeyDown(.KEY_W))
            camera2D.offset.y += 10;
        if (raylib.IsKeyDown(.KEY_S))
            camera2D.offset.y -= 10;
        if (raylib.IsKeyPressed(.KEY_R)) {
            camera2D.offset.setZero();
            camera2D.zoom = 1.0;
        }
    }

    log.warn("mem leaks: {}", .{zalloc.deinit()}); // TODO IMPL TREE DEINIT
}

pub fn visualize(node: *Node, nodeNum: usize, nodeChildNum: usize) void {
    var childNum: usize = 0;
    for (node.children.items) |child| {
        visualize(child, nodeNum + 1, childNum);
        childNum += 1;
    }
    log.warn("node: {*}", .{node});
    const fontSize = 14;

    var cardWidth: i32 = ((@intCast(i32, levelSize) + 8) * (fontSize + 1)) + 8;
    var cardHeight: i32 = ((@intCast(i32, levelSize) + 8) * (fontSize)) + 8;
    var cardX: i32 = 20 + (@intCast(i32, nodeChildNum) * (cardWidth + 15));
    var cardY: i32 = 20 + (@intCast(i32, nodeNum) * (cardHeight + 15));
    var cardXCenter: i32 = cardX + @divFloor(cardWidth, 2);
    var currentYProgress: i32 = cardY + 3;

    var rectLine = raylib.Rectangle{
        .x = @intToFloat(f32, cardX),
        .y = @intToFloat(f32, cardY),
        .width = @intToFloat(f32, cardWidth),
        .height = @intToFloat(f32, cardHeight),
    };
    raylib.DrawRectangleLinesEx(rectLine, 3, raylib.WHITE);

    // draw title
    var nodeTitle = std.ArrayList(u8).init(std.heap.c_allocator);
    defer nodeTitle.deinit();
    nodeTitle.appendSlice("Node ") catch unreachable;
    nodeTitle.appendSlice(std.fmt.allocPrint(std.heap.c_allocator, "{d}", .{nodeNum}) catch unreachable) catch unreachable;
    nodeTitle.append(0) catch unreachable;
    var titleText = @ptrCast([*:0]const u8, nodeTitle.items);
    var titleX = cardXCenter - @divFloor(raylib.MeasureText(titleText, fontSize), 2);
    raylib.DrawTextEx(
        font,
        titleText,
        raylib.Vector2{ .x = @intToFloat(f32, titleX), .y = @intToFloat(f32, currentYProgress) },
        fontSize,
        2,
        raylib.WHITE,
    );
    currentYProgress += raylib.GetFontDefault().baseSize + 6;

    // draw displayed map
    var map = std.ArrayList(u8).init(std.heap.c_allocator);
    defer map.deinit();
    node.map.buildDisplayed() catch unreachable;
    log.warn("node: {d}\n{s}\n{*}", .{ nodeNum, node.map.displayed.items, node.map.displayed.items });
    map.appendSlice(node.map.displayed.items) catch unreachable;
    map.append(0) catch unreachable;
    var mapText = @ptrCast([*:0]const u8, map.items);
    var mapX = cardXCenter - @divFloor(raylib.MeasureText(mapText, fontSize), 2);
    raylib.DrawTextEx(
        font,
        mapText,
        raylib.Vector2{ .x = @intToFloat(f32, mapX), .y = @intToFloat(f32, currentYProgress) },
        fontSize,
        2,
        raylib.WHITE,
    );
    currentYProgress +=
        (@floatToInt(
        i32,
        raylib.MeasureTextEx(font, mapText, fontSize, @intToFloat(f32, 2)).y,
    )) - 20;

    // draw self.visits
    var visits = std.ArrayList(u8).init(std.heap.c_allocator);
    defer visits.deinit();
    visits.appendSlice("self.visits = ") catch unreachable;
    visits.appendSlice(std.fmt.allocPrint(std.heap.c_allocator, "{d}", .{node.visits}) catch unreachable) catch unreachable;
    visits.append(0) catch unreachable;
    var visitsText = @ptrCast([*:0]const u8, visits.items);
    var visitsX = cardXCenter - @floatToInt(i32, @divFloor(raylib.MeasureTextEx(font, visitsText, fontSize, 2).x, 2));
    raylib.DrawTextEx(
        font,
        visitsText,
        raylib.Vector2{ .x = @intToFloat(f32, visitsX), .y = @intToFloat(f32, currentYProgress + 6) },
        fontSize,
        2,
        raylib.WHITE,
    );
    currentYProgress += 6 + fontSize;

    // draw self.totalEvaluation
    var totEval = std.ArrayList(u8).init(std.heap.c_allocator);
    defer totEval.deinit();
    totEval.appendSlice("self.totalEvaluation = ") catch unreachable;
    totEval.appendSlice(std.fmt.allocPrint(std.heap.c_allocator, "{d}", .{node.visits}) catch unreachable) catch unreachable;
    totEval.append(0) catch unreachable;
    var totEvalText = @ptrCast([*:0]const u8, totEval.items);
    var totEvalX = cardXCenter - @floatToInt(i32, @divFloor(raylib.MeasureTextEx(font, totEvalText, fontSize, 2).x, 2));
    raylib.DrawTextEx(
        font,
        totEvalText,
        raylib.Vector2{ .x = @intToFloat(f32, totEvalX), .y = @intToFloat(f32, currentYProgress + 6) },
        fontSize,
        2,
        raylib.WHITE,
    );
    currentYProgress += 6 + fontSize;

    // draw self.action
    var action = std.ArrayList(u8).init(std.heap.c_allocator);
    defer action.deinit();
    action.appendSlice("self.action = ") catch unreachable;
    action.appendSlice(std.fmt.allocPrint(std.heap.c_allocator, "{}", .{@enumToInt(node.action)}) catch unreachable) catch unreachable;
    action.append(0) catch unreachable;
    var actionText = @ptrCast([*:0]const u8, action.items);
    var actionX = cardXCenter - @floatToInt(i32, @divFloor(raylib.MeasureTextEx(font, actionText, fontSize, 2).x, 2));
    raylib.DrawTextEx(
        font,
        actionText,
        raylib.Vector2{ .x = @intToFloat(f32, actionX), .y = @intToFloat(f32, currentYProgress + 6) },
        fontSize,
        2,
        raylib.WHITE,
    );
}
