const std = @import("std");

pub const texWidth: i32 = 32;
pub const texHeight: i32 = 32;
pub const mapBorder: i32 = 6;

pub const MapRowArray = std.ArrayList(Textile);
pub const MapArray = std.ArrayList(MapRowArray);

pub const MapError = error{MapError};

pub const Textile = struct { tex: TexType, id: u8 };
pub const TexType = enum(u8) {
    floor = '.',
    wall = 'w',
    dock = 'd',
    box = 'b',
    boxDocked = 'x',
    worker = 'p',
    workerDocked = 'X',
    none = '#',
    next = '\n',

    // solves the problem of @intToEnum() having undefined behavior.
    // TODO: maybe better syntax?
    pub fn convert(number: u8) MapError!TexType {
        return switch (number) {
            @enumToInt(TexType.floor) => .floor,
            @enumToInt(TexType.wall) => .wall,
            @enumToInt(TexType.dock) => .dock,
            @enumToInt(TexType.box) => .box,
            @enumToInt(TexType.boxDocked) => .boxDocked,
            @enumToInt(TexType.worker) => .worker,
            @enumToInt(TexType.workerDocked) => .workerDocked,
            @enumToInt(TexType.none) => .none,
            @enumToInt(TexType.next) => .next,
            else => error.MapError,
        };
    }
};

pub const ActType = enum(u5) { up, down, left, right, none };
pub const Pos = struct { x: usize, y: usize };

pub const BoxGoalPair = struct {
    box: Pos,
    goal: Pos,
};
