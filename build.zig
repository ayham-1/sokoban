const std = @import("std");
const fs = std.fs;

pub const APP_NAME = "sokoban";
const raylibSrc = "src/raylib/raylib/src/";
const bindingSrc = "src/raylib/";
const emscriptenShell = "src/shell/soko.html";
const emscriptenShellJS = "src/shell/soko.js";
const emscriptenShellCSS = "src/shell/soko.css";

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    switch (target.getOsTag()) {
        .wasi, .emscripten => {
            const emscriptenSrc = "src/raylib/emscripten/";
            const webChacheDir = "zig-cache/web/";
            const webOutDir = "zig-out/web/";

            std.log.info("building for emscripten\n", .{});
            if (b.sysroot == null) {
                std.log.err("\n\nUSAGE: Please build with 'zig build -Drelease-small -Dtarget=wasm32-wasi --sysroot \"$EMSDK/upstream/emscripten\"'\n\n", .{});
                return error.SysRootExpected;
            }

            const lib = b.addStaticLibrary(APP_NAME, "src/web.zig");
            lib.addIncludeDir(raylibSrc);

            const emcc_file = switch (b.host.target.os.tag) {
                .windows => "emcc.bat",
                else => "emcc",
            };
            const emar_file = switch (b.host.target.os.tag) {
                .windows => "emar.bat",
                else => "emar",
            };
            const emranlib_file = switch (b.host.target.os.tag) {
                .windows => "emranlib.bat",
                else => "emranlib",
            };

            const emcc_path = try fs.path.join(b.allocator, &.{ b.sysroot.?, emcc_file });
            defer b.allocator.free(emcc_path);
            const emranlib_path = try fs.path.join(b.allocator, &.{ b.sysroot.?, emranlib_file });
            defer b.allocator.free(emranlib_path);
            const emar_path = try fs.path.join(b.allocator, &.{ b.sysroot.?, emar_file });
            defer b.allocator.free(emar_path);
            const include_path = try fs.path.join(b.allocator, &.{ b.sysroot.?, "cache", "sysroot", "include" });
            defer b.allocator.free(include_path);

            fs.cwd().makePath(webChacheDir) catch {};
            fs.cwd().makePath(webOutDir) catch {};

            const warnings = ""; //-Wall

            const rcoreO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "rcore.c", "-o", webChacheDir ++ "rcore.o", "-Os", warnings, "-DPLATFORM_WEB", "-DGRAPHICS_API_OPENGL_ES2" });
            const rshapesO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "rshapes.c", "-o", webChacheDir ++ "rshapes.o", "-Os", warnings, "-DPLATFORM_WEB", "-DGRAPHICS_API_OPENGL_ES2" });
            const rtexturesO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "rtextures.c", "-o", webChacheDir ++ "rtextures.o", "-Os", warnings, "-DPLATFORM_WEB", "-DGRAPHICS_API_OPENGL_ES2" });
            const rtextO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "rtext.c", "-o", webChacheDir ++ "rtext.o", "-Os", warnings, "-DPLATFORM_WEB", "-DGRAPHICS_API_OPENGL_ES2" });
            const rmodelsO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "rmodels.c", "-o", webChacheDir ++ "rmodels.o", "-Os", warnings, "-DPLATFORM_WEB", "-DGRAPHICS_API_OPENGL_ES2" });
            const utilsO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "utils.c", "-o", webChacheDir ++ "utils.o", "-Os", warnings, "-DPLATFORM_WEB" });
            const raudioO = b.addSystemCommand(&.{ emcc_path, "-Os", warnings, "-c", raylibSrc ++ "raudio.c", "-o", webChacheDir ++ "raudio.o", "-Os", warnings, "-DPLATFORM_WEB" });
            const libraylibA = b.addSystemCommand(&.{
                emar_path,
                "rcs",
                webChacheDir ++ "libraylib.a",
                webChacheDir ++ "rcore.o",
                webChacheDir ++ "rshapes.o",
                webChacheDir ++ "rtextures.o",
                webChacheDir ++ "rtext.o",
                webChacheDir ++ "rmodels.o",
                webChacheDir ++ "utils.o",
                webChacheDir ++ "raudio.o",
            });
            const emranlib = b.addSystemCommand(&.{
                emranlib_path,
                webChacheDir ++ "libraylib.a",
            });

            libraylibA.step.dependOn(&rcoreO.step);
            libraylibA.step.dependOn(&rshapesO.step);
            libraylibA.step.dependOn(&rtexturesO.step);
            libraylibA.step.dependOn(&rtextO.step);
            libraylibA.step.dependOn(&rmodelsO.step);
            libraylibA.step.dependOn(&utilsO.step);
            libraylibA.step.dependOn(&raudioO.step);
            emranlib.step.dependOn(&libraylibA.step);

            //only build raylib if not already there
            _ = fs.cwd().statFile(webChacheDir ++ "libraylib.a") catch {
                lib.step.dependOn(&emranlib.step);
            };

            lib.setTarget(target);
            lib.setBuildMode(mode);
            lib.defineCMacro("__EMSCRIPTEN__", null);
            lib.defineCMacro("PLATFORM_WEB", null);
            std.log.info("emscripten include path: {s}", .{include_path});
            lib.addIncludeDir(include_path);
            lib.addIncludeDir(emscriptenSrc);
            lib.addIncludeDir(bindingSrc);
            lib.addIncludeDir(raylibSrc);
            lib.addIncludeDir(raylibSrc ++ "extras/");

            lib.setOutputDir(webChacheDir);
            lib.install();

            const shell = switch (mode) {
                .Debug => emscriptenShell,
                else => emscriptenShell,
            };

            const emcc = b.addSystemCommand(&.{
                emcc_path,
                "-o",
                webOutDir ++ "game.html",

                emscriptenSrc ++ "entry.c",
                bindingSrc ++ "marshal.c",

                webChacheDir ++ "lib" ++ APP_NAME ++ ".a",
                "-I.",
                "-I" ++ raylibSrc,
                "-I" ++ emscriptenSrc,
                "-I" ++ bindingSrc,
                "-L.",
                "-L" ++ webChacheDir,
                "-lraylib",
                "-l" ++ APP_NAME,
                "--shell-file",
                shell,
                "-DPLATFORM_WEB",
                "-sUSE_GLFW=3",
                // "-sWASM=0",
                "-sALLOW_MEMORY_GROWTH=1",
                //"-sTOTAL_MEMORY=1024MB",
                "-sASYNCIFY",
                "-sFORCE_FILESYSTEM=1",
                "-sASSERTIONS=1",
                "--memory-init-file",
                "0",
                "--preload-file",
                "assets",
                "--source-map-base",

                // optimizations
                "-O1",
                "-Os",

                // "-sUSE_PTHREADS=1",
                // "--profiling",
                // "-sTOTAL_STACK=128MB",
                // "-sMALLOC='emmalloc'",
                // "--no-entry",
                "-sEXPORTED_FUNCTIONS=['_malloc','_free','_main', '_emsc_main','_emsc_set_window_size','_updateMap', '_toggleInput']",
                "-sEXPORTED_RUNTIME_METHODS=ccall,cwrap",
            });

            emcc.step.dependOn(&lib.step);

            //b.installFile("src/sokoshell.js", "sokoshell.js");
            b.getInstallStep().dependOn(&emcc.step);
            b.installFile(emscriptenShellJS, "web/sokoshell.js");
            b.installFile(emscriptenShellCSS, "web/sokoshell.css");

            //try fs.cwd().copyFile(emscriptenShell, webOutDir ++ "sokoshell.js", .{});

            //-------------------------------------------------------------------------------------

            std.log.info("\n\nOutput files will be in {s}\n---\ncd {s}\npython -m http.server\n---\n\nbuilding...", .{ webOutDir, webOutDir });
        },
        else => {
            std.log.info("building for desktop\n", .{});
            const exe = b.addExecutable(APP_NAME, "src/desktop.zig");
            exe.setTarget(target);
            exe.setBuildMode(mode);

            const rayBuild = @import("src/raylib/raylib/src/build.zig");
            const raylib = rayBuild.addRaylib(b, target);
            exe.linkLibrary(raylib);
            exe.addIncludeDir(raylibSrc);
            exe.addIncludeDir(raylibSrc ++ "extras/");
            exe.addIncludeDir(bindingSrc);
            exe.addCSourceFile(bindingSrc ++ "marshal.c", &.{});

            switch (raylib.target.getOsTag()) {
                //dunno why but macos target needs sometimes 2 tries to build
                .macos => {
                    exe.linkFramework("Foundation");
                    exe.linkFramework("Cocoa");
                    exe.linkFramework("OpenGL");
                    exe.linkFramework("CoreAudio");
                    exe.linkFramework("CoreVideo");
                    exe.linkFramework("IOKit");
                },
                .linux => {
                    exe.addLibPath("/usr/lib64/");
                    exe.linkSystemLibrary("GL");
                    exe.linkSystemLibrary("rt");
                    exe.linkSystemLibrary("dl");
                    exe.linkSystemLibrary("m");
                    exe.linkSystemLibrary("X11");
                },
                else => {},
            }

            exe.linkLibC();
            exe.install();

            const run_cmd = exe.run();
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| {
                run_cmd.addArgs(args);
            }

            const run_step = b.step("run", "Run the app");
            run_step.dependOn(&run_cmd.step);
        },
    }
}
