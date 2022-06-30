#!/bin/sh

zig build -Drelease-safe=true -Drelease-small=false -Drelease-fast=false -Dtarget=wasm32-wasi --sysroot ~/.local/src/emsdk/upstream/emscripten && python -m http.server --directory zig-out/web/
