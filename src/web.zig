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
    try game.start(gameMap);
    defer game.stop();

    updateMapView();

    emsdk.emscripten_set_main_loop(gameLoop, 0, 1);

    return 0;
}

export fn gameLoop() callconv(.C) void {
    if (game.won) {
        emsdk.emscripten_run_script(winPromptScript);
        emsdk.emscripten_cancel_main_loop();
        game.stop();
    }

    game.loop(ray.GetFrameTime());

    if (game.workerMoved) {
        log.warn("ran", .{});
        updateMapView();
    }
}

fn updateMapView() void {
    game.buildDisplayedMap() catch {
        emsdk.emscripten_run_script(invalidMapScript);
        emsdk.emscripten_cancel_main_loop();
        return;
    };

    var gameMapScript = std.ArrayList(u8).init(alloc);
    gameMapScript.appendSlice(mapViewScript) catch unreachable;
    gameMapScript.appendSlice(game.mapDisplayed.items) catch unreachable;
    gameMapScript.append('\'') catch unreachable;
    gameMapScript.appendSlice(".replace(/<br>/gi, \"\\r\\n\");") catch unreachable;
    gameMapScript.append('\x00') catch unreachable;
    log.warn("{s}", .{gameMapScript.items});
    emsdk.emscripten_run_script(gameMapScript.items.ptr);
}

const winPromptScript =
    \\document.getElementById("winStatus").style.display = "block";
;

const invalidMapScript =
    \\alert("It appears you don't have a valid puzzle map!");
;

const mapViewScript =
    \\document.getElementById("mapView").innerHTML = '
;
