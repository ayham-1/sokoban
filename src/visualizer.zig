const std = @import("std");
const log = @import("log.zig");
const raylib = @import("./raylib/raylib.zig");
const soko = @import("constants.zig");
const Gen = @import("generator.zig");
const Node = Gen.Node;
const NodeActionSet = Gen.NodeActionSet;
const Map = @import("map.zig").Map;

const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
var zalloc = ZecsiAllocator{};
var alloc = zalloc.allocator();

var seed: u64 = undefined;
var rnd: std.rand.Xoshiro256 = undefined;
var font: raylib.Font = undefined;

const screenWidth = 1000;
const screenHeight = 600;

const levelSize = 8;
var boxCount: usize = 3;
var parentNode: *Node = undefined;
var parentNodeVis: *NodeVis = undefined;

var fontSize: f32 = 24;

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

    Gen.generatedPuzzles = std.ArrayList(Gen.GeneratedPuzzle).init(alloc);
    parentNode = Node.initAsParent(alloc, map, boxCount);
}

pub fn main() !void {
    init();
    if (std.os.argv.len > 1) {
        var iterateTimes: usize = try std.fmt.parseInt(usize, try std.fmt.allocPrint(alloc, "{s}", .{std.os.argv[1]}), 10);
        while (iterateTimes > 0) {
            try parentNode.iterate();
            iterateTimes -= 1;
            log.info("epochs left: {}", .{iterateTimes});
        }
    }
    raylib.InitWindow(screenWidth, screenHeight, "Sokoban Puzzle Generator Visualizer");
    raylib.SetConfigFlags(.FLAG_WINDOW_RESIZABLE);
    raylib.SetTargetFPS(60);

    //font = raylib.LoadFont("assets/font.ttf");
    //defer raylib.UnloadFont(font);
    font = raylib.GetFontDefault();

    var camera2D = raylib.Camera2D{
        .offset = raylib.Vector2.zero(),
        .target = raylib.Vector2.zero(),
        .rotation = 0.0,
        .zoom = 1.0,
    };

    var prevMousePos: raylib.Vector2 = raylib.GetMousePosition();

    defer raylib.CloseWindow();

    while (!raylib.WindowShouldClose()) {
        // draw
        {
            raylib.BeginDrawing();
            raylib.ClearBackground(raylib.BLACK);
            raylib.DrawFPS(2, 2);
            raylib.BeginMode2D(camera2D);
            defer raylib.EndMode2D();
            defer raylib.EndDrawing();

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            parentNodeVis = NodeVis.init(arena.allocator(), parentNode);
            parentNodeVis.positionTree(0.25, 0.25);
            drawCard(parentNodeVis, 0);
            //arena.deinit();
        }

        // update
        {
            var mouseWheelDelta = raylib.GetMouseWheelMove();
            var newZoom = camera2D.zoom + mouseWheelDelta * 0.05;
            if (newZoom <= 0)
                newZoom = 0.01;
            camera2D.zoom = newZoom;

            var mousePos = raylib.GetMousePosition();
            var delta = raylib.Vector2Subtract(prevMousePos, mousePos);
            prevMousePos = mousePos;

            if (raylib.IsMouseButtonDown(.MOUSE_BUTTON_LEFT))
                camera2D.target = raylib.GetScreenToWorld2D(raylib.Vector2Add(camera2D.offset, delta), camera2D);

            if (raylib.IsKeyPressed(.KEY_SPACE)) {
                parentNode.iterate() catch unreachable;
            }

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
    }

    log.warn("mem leaks: {}", .{zalloc.deinit()}); // TODO IMPL TREE DEINIT
}

// Uses John Q. Walker II tree positioning algorithm, article from 1989.
const unitSize = 2;
const siblingSeparation = unitSize * 2;
const subTreeSeparation = siblingSeparation * 1.2;
const levelSeparation: f32 = unitSize * 1.5;

var prevNodeAlloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var prevNodeList = std.AutoArrayHashMap(usize, *NodeVis).init(prevNodeAlloc.allocator());

var xTopAdj: f32 = 0;
var yTopAdj: f32 = 0;
// all coords values are of multiples of unitSize, which is computed later on
// the program execution, when actually drawing the card, ref. drawCard()
const NodeVis = struct {
    alloc: std.mem.Allocator,
    absoluteX: f32 = 0,
    absoluteY: f32 = 0,

    localX: usize = 0,
    mod: f32 = 0, // cardWidth multiple to offset current card along the X axis
    prelim: f32 = 0,

    parent: ?*NodeVis,
    children: std.ArrayList(*NodeVis),
    node: *Node,
    leftNeighbor: ?*NodeVis = null,

    pub fn init(selfAlloc: std.mem.Allocator, tree: *Node) *@This() {
        var parent = NodeVis.initNode(selfAlloc, tree, null);
        parent.initializeLocalX(0);
        return parent;
    }

    pub fn positionTree(self: *NodeVis, rootX: f32, rootY: f32) void {
        prevNodeList.clearAndFree();
        self.firstWalk(0);

        xTopAdj = rootX - self.prelim;
        yTopAdj = rootY;

        self.secondWalk(0, 0);
    }

    fn initializeLocalX(self: *NodeVis, childNum: usize) void {
        var localChildNum: usize = 0;
        for (self.children.items) |child| {
            child.initializeLocalX(localChildNum);
            localChildNum += 1;
        }
        self.localX = childNum;
    }

    fn firstWalk(self: *NodeVis, level: usize) void {
        self.leftNeighbor = prevNodeList.get(level) orelse null;
        prevNodeList.put(level, self) catch unreachable;
        self.mod = 0;

        if (self.children.items.len == 0) {
            if (self.localX != 0) {
                if (self.parent) |parent| {
                    self.prelim =
                        parent.children.items[self.localX - 1].prelim +
                        siblingSeparation +
                        unitSize; // mean node -> (unitSize * 2) / 2
                } else {
                    unreachable;
                }
            } else {
                self.prelim = 0;
            }
        } else {
            var leftMost: *NodeVis = self.children.items[0];
            leftMost.firstWalk(level + 1);

            var rightMost: *NodeVis = self.children.items[0];
            while (rightMost.hasRightSibling()) {
                rightMost = rightMost.parent.?.children.items[rightMost.localX + 1];
                rightMost.firstWalk(level + 1);
            }

            var midPoint = (leftMost.prelim + rightMost.prelim) / 2;
            if (self.localX != 0) {
                self.prelim =
                    self.parent.?.children.items[self.localX - 1].prelim +
                    siblingSeparation +
                    unitSize; // mean node -> (unitSize * 2) / 2
                self.mod = self.prelim - midPoint;
                self.apportion(level);
            } else {
                self.prelim = midPoint;
            }
        }
    }

    fn secondWalk(self: *NodeVis, level: usize, modSum: f32) void {
        var xTemp = xTopAdj + self.prelim + modSum;
        var yTemp = yTopAdj + (@intToFloat(f32, level) * levelSeparation);

        self.absoluteX = xTemp;
        self.absoluteY = yTemp;

        if (self.children.items.len != 0)
            self.children.items[0].secondWalk(level + 1, modSum + self.mod);

        if (self.hasRightSibling())
            self.parent.?.children.items[self.localX + 1].secondWalk(level, modSum);
    }

    fn apportion(self: *NodeVis, level: usize) void {
        var leftMost: ?*NodeVis = self.children.items[0];
        var neighbor: ?*NodeVis = leftMost.?.leftNeighbor orelse prevNodeList.get(level + 1) orelse null;

        var compareDepth: usize = 1;
        while (leftMost != null and neighbor != null) {
            var leftModSum: f32 = 0;
            var rightModSum: f32 = 0;
            var ancestorLeftMost = leftMost;
            var ancestorNeighbor = neighbor;

            var i: usize = 0;
            while (i < compareDepth) {
                defer i += 1;
                ancestorLeftMost = ancestorLeftMost.?.parent.?;
                ancestorNeighbor = ancestorNeighbor.?.parent.?;
                rightModSum += ancestorLeftMost.?.mod;
                leftModSum += ancestorNeighbor.?.mod;
            }

            var moveDistance: f32 =
                neighbor.?.prelim +
                leftModSum +
                subTreeSeparation +
                unitSize -
                (leftMost.?.prelim + rightModSum);

            if (moveDistance > 0) {
                // count interior sibling subtrees in leftSiblings (diff than
                // article, here localX property is used)
                var tempPtr: ?*NodeVis = self;
                var leftSiblings: usize = 0;
                while (tempPtr != null and tempPtr != ancestorNeighbor) {
                    leftSiblings += 1;
                    tempPtr = if (tempPtr.?.localX != 0)
                        tempPtr.?.parent.?.children.items[tempPtr.?.localX - 1]
                    else
                        null;
                }

                if (tempPtr != null) { // check
                    var portion = moveDistance / @intToFloat(f32, leftSiblings);
                    tempPtr = self;
                    while (tempPtr != null and tempPtr != ancestorNeighbor) {
                        tempPtr.?.*.prelim += moveDistance;
                        tempPtr.?.*.mod += moveDistance;
                        moveDistance -= portion;
                        tempPtr = if (tempPtr.?.localX != 0)
                            tempPtr.?.parent.?.children.items[tempPtr.?.localX - 1]
                        else
                            null;
                    }
                } else {
                    return;
                }
            }

            compareDepth += 1;
            if (leftMost.?.children.items.len == 0) {
                leftMost = self.getLeftMost(0, compareDepth);
            } else {
                leftMost = leftMost.?.children.items[0];
            }
            if (leftMost != null) {
                neighbor = leftMost.?.leftNeighbor;
            }
        }
    }

    fn getLeftMost(self: *NodeVis, level: usize, depth: usize) ?*NodeVis {
        if (level >= depth) {
            return self;
        } else if (self.children.items.len == 0) {
            return null;
        } else {
            var rightMost = self.children.items[0];
            var leftMost = rightMost.getLeftMost(level + 1, depth);
            while (leftMost == null and rightMost.hasRightSibling()) {
                rightMost = rightMost.parent.?.children.items[rightMost.localX + 1];
                leftMost = rightMost.getLeftMost(level + 1, depth);
            }
            return leftMost;
        }
    }

    fn hasRightSibling(self: *NodeVis) bool {
        if (self.parent) |parent|
            if (self.localX + 1 < parent.children.items.len)
                return true;
        return false;
    }

    // deinit with arena allocator
    fn initNode(selfAlloc: std.mem.Allocator, tree: *Node, parent: ?*NodeVis) *@This() {
        var nodeVis = NodeVis{
            .alloc = selfAlloc,
            .node = tree,
            .parent = parent,
            .children = std.ArrayList(*NodeVis).init(selfAlloc),
        };
        var allocNodeVis: *NodeVis = alloc.create(NodeVis) catch unreachable;
        allocNodeVis.* = nodeVis;
        allocNodeVis.initNodes(tree);
        return allocNodeVis;
    }

    pub fn appendChild(self: *NodeVis, node: *Node) !void {
        var newNode = NodeVis.initNode(self.alloc, node, self);
        try self.children.append(newNode);
    }

    fn initNodes(self: *@This(), node: *Node) void {
        for (node.children.items) |child|
            self.appendChild(child) catch unreachable;
    }
};

var highestEval: f32 = 0;
pub fn drawCard(nodeVis: *NodeVis, nodeNum: usize) void {
    var cardWidth: i32 = ((levelSize + 8) * (@floatToInt(i32, fontSize) + 1)) + 8;
    var cardHeight: i32 = ((@intCast(i32, levelSize) + 8) * (@floatToInt(i32, fontSize))) + 8;
    var node = nodeVis.node.*;

    for (nodeVis.children.items) |child|
        drawCard(child, child.localX);

    var cardX: i32 = @floatToInt(i32, (nodeVis.absoluteX / 2) * @intToFloat(f32, cardWidth));
    var cardY: i32 = @floatToInt(i32, (nodeVis.absoluteY / 2) * @intToFloat(f32, cardHeight));
    var cardXCenter: i32 = cardX + @divFloor(cardWidth, 2);
    var currentYProgress: i32 = cardY + 3;

    // link this node with our parent
    if (nodeVis.parent) |parent| {
        var parentCardX: i32 = @floatToInt(i32, (parent.absoluteX / 2) * @intToFloat(f32, cardWidth));
        var parentCardY: i32 = @floatToInt(i32, (parent.absoluteY / 2) * @intToFloat(f32, cardHeight));
        var parentCardXCenter: i32 = parentCardX + @divFloor(cardWidth, 2);
        var parentCardYBottom: i32 = parentCardY + cardHeight;
        raylib.DrawLine(cardXCenter, cardY, parentCardXCenter, parentCardYBottom, raylib.BLUE);
    }

    // Draw Card outlines
    var rectLine = raylib.Rectangle{
        .x = @intToFloat(f32, cardX),
        .y = @intToFloat(f32, cardY),
        .width = @intToFloat(f32, cardWidth),
        .height = @intToFloat(f32, cardHeight),
    };
    if (node.parent != null and node.totalEvaluation > highestEval) highestEval = node.totalEvaluation;
    raylib.DrawRectangleLinesEx(rectLine, 5, raylib.RED);

    if (node.action == NodeActionSet.evaluateLevel)
        raylib.DrawRectangleLinesEx(rectLine, 5, raylib.GREEN);

    // draw title
    var nodeTitle = std.ArrayList(u8).init(std.heap.c_allocator);
    defer nodeTitle.deinit();
    nodeTitle.appendSlice("Node ") catch unreachable;
    nodeTitle.appendSlice(std.fmt.allocPrint(std.heap.c_allocator, "{d}", .{nodeNum}) catch unreachable) catch unreachable;
    nodeTitle.append(0) catch unreachable;
    var titleText = @ptrCast([*:0]const u8, nodeTitle.items);
    var titleX = cardXCenter - @divFloor(raylib.MeasureText(titleText, @floatToInt(i32, fontSize)), 2);
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
    //log.warn("node: {d}\n{s}\n{*}", .{ nodeNum, node.map.displayed.items, node.map.displayed.items });
    map.appendSlice(node.map.displayed.items) catch unreachable;
    map.append(0) catch unreachable;
    var mapText = @ptrCast([*:0]const u8, map.items);
    var mapX = cardXCenter - @divFloor(raylib.MeasureText(mapText, @floatToInt(i32, fontSize)), 2);
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
    currentYProgress += 6 + @floatToInt(i32, fontSize);

    // draw self.totalEvaluation
    var totEval = std.ArrayList(u8).init(std.heap.c_allocator);
    defer totEval.deinit();
    totEval.appendSlice("self.totalEvaluation = ") catch unreachable;
    totEval.appendSlice(std.fmt.allocPrint(std.heap.c_allocator, "{d}", .{node.totalEvaluation}) catch unreachable) catch unreachable;
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
    currentYProgress += 6 + @floatToInt(i32, fontSize);

    // draw self.action
    var action = std.ArrayList(u8).init(std.heap.c_allocator);
    defer action.deinit();
    action.appendSlice("self.action = ") catch unreachable;
    switch (node.action) {
        .root => action.appendSlice("rootNode") catch unreachable,
        .deleteWall => action.appendSlice("deleteWall") catch unreachable,
        .placeBox => action.appendSlice("placeBox") catch unreachable,
        .freezeLevel => action.appendSlice("freezeLevel") catch unreachable,
        .moveAgent => action.appendSlice("moveAgent") catch unreachable,
        .evaluateLevel => action.appendSlice("evaluateLevel") catch unreachable,
    }
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
