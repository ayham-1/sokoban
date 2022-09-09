const std = @import("std");

pub const texWidth: i32 = 32;
pub const texHeight: i32 = 32;
pub const mapBorder: i32 = 6;

pub const MapRowArray = std.ArrayList(Textile);
pub const MapArray = std.ArrayList(MapRowArray);
pub const TexId = u8;

pub const MapError = error{MapError};
pub const InvalidPos = error{InvalidPos};

pub const Textile = struct { tex: TexType, id: TexId };
pub const TexType = enum(u8) {
    floor = ' ',
    wall = '#',
    dock = '.',
    box = '$',
    boxDocked = 'x',
    worker = '@',
    workerDocked = '2',
    none = '0',
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
            else => {
                return .next;
            },
        };
    }
};

pub const ActType = enum(u5) { up, down, left, right, none };
pub const Pos = struct { x: usize, y: usize };
pub const IdPos = struct { id: u8, pos: Pos };

pub const BoxGoalPair = struct {
    box: Pos,
    goal: Pos,
};
