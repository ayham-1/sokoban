#!/bin/sh

zig build -Dtarget=wasm32-wasi --sysroot ~/.local/src/emsdk/upstream/emscripten

python -m http.server --directory zig-out/web/
