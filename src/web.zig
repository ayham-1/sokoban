const std = @import("std");
const fmt = std.fmt;
const emsdk = @cImport({
    @cDefine("__EMSCRIPTEN__", "1");
    @cDefine("PLATFORM_WEB", "1");
    @cInclude("emscripten/emscripten.h");
});
const log = @import("log.zig");
const game = @import("game.zig");
const ZecsiAllocator = @import("allocator.zig").ZecsiAllocator;
const ray = @import("raylib/raylib.zig");
const Map = @import("map.zig").Map;

var zalloc = ZecsiAllocator{};
var alloc = zalloc.allocator();

////special entry point for Emscripten build, called from src/marshall/emscripten_entry.c
export fn emsc_main() callconv(.C) c_int {
    return safeMain() catch |err| {
        log.err("ERROR: {?}", .{err});
        return 1;
    };
}

export fn emsc_set_window_size(width: c_int, height: c_int) callconv(.C) void {
    ray.SetWindowSize(@intCast(i32, width), @intCast(i32, height));
}

fn safeMain() !c_int {
    var testMap =
        \\#www#www#wwwwww#
        \\w...w...w......w
        \\w.p.b.d........w
        \\w.bdw..bw......w
        \\wwwwwwwwwwwwwww#
        \\
    ;

    var gameMap = try alloc.alloc(u8, testMap.len);
    std.mem.copy(u8, gameMap, testMap);
    var map = Map.init(alloc);
    try map.build(gameMap);
    try game.start(map);
    defer game.stop();
    defer alloc.free(gameMap);

    updateMapView();

    emsdk.emscripten_set_main_loop(gameLoop, 0, 1);

    return 0;
}

export fn gameLoop() callconv(.C) void {
    if (game.won) emsdk.emscripten_run_script(winPromptScript);

    game.loop(ray.GetFrameTime());

    if (game.puzzle.workerMoved) {
        updateMapView();
    }
}

fn updateMapView() void {
    game.puzzle.map.buildDisplayed() catch {
        emsdk.emscripten_run_script(invalidMapScript);
        //emsdk.emscripten_cancel_main_loop();
        return;
    };

    var gameMapScript = std.ArrayList(u8).init(alloc);
    gameMapScript.appendSlice(mapViewScript) catch unreachable;
    gameMapScript.appendSlice(game.puzzle.map.displayed.items) catch unreachable;
    gameMapScript.appendSlice("`") catch unreachable;
    gameMapScript.append(';') catch unreachable;
    gameMapScript.append('\x00') catch unreachable;

    emsdk.emscripten_run_script(gameMapScript.items.ptr);

    //emsc_set_window_size(game.puzzle.map.sizeWidth * game.);
}

export fn updateMap() void {
    var givenMap = emsdk.emscripten_run_script_string(getMapView);
    var givenMapSize = @intCast(usize, emsdk.emscripten_run_script_int(getMapViewSize));

    game.updateMap(givenMap[0..givenMapSize]) catch {
        emsdk.emscripten_run_script(invalidMapScript);
        updateMapView();
    };
}

export fn toggleInput() void {
    game.workerInputStopped = !game.workerInputStopped;
}

const winPromptScript =
    \\document.getElementById("winStatus").style.display = "block";
;

const invalidMapScript =
    \\alert("Make sure you enter valid puzzle tiles!");
;

const mapViewScript =
    \\document.getElementById("mapView").value = `
;
const mapViewCleanScript =
    \\document.getElementById("mapView").innerHTML;
;

const getMapView =
    \\document.getElementById("mapView").value.replace(/\r\n/gi, "\n");
;

const getMapViewSize =
    \\document.getElementById("mapView").value.length;
;
