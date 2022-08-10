#ifndef CONSTS_H
#define CONSTS_H

#include <stddef.h>

const int texWidth = 32;
const int texHeight = 32;

typedef unsigned short ID;

typedef enum TexTypes {
	floor = '.',
	wall = 'w',
	dock = 'd',
	box = 'b',
	boxDocked = 'x',
	worker = 'p',
	workerDocked = 'X',
	none = '#',
	next = '\n',
} TexType;

typedef struct Textiles {
	ID id;
	TexType tex;
} Textile;

typedef struct MapRows {
	Textile* row;
	size_t s;
} MapRow;

typedef struct Positions {
	unsigned short x; 
	unsigned short y; 
} Pos;

typedef struct BoxGoalPair {
	Pos box;
	Pos goal;
} BGPair;

typedef enum Directions {
	up = 0, down = 1, left = 2, right = 3
} Direction;

const short DirectionOff[4][2] = {
	{0, -1},
	{0, 1},
	{-1, 0},
	{1, 0},
};

#endif
