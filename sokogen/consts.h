#ifndef CONSTS_H
#define CONSTS_H

#include <stddef.h>

extern const int texWidth;
extern const int texHeight;

typedef unsigned short ID;

typedef enum TexType {
	floor = '.',
	wall = 'w',
	dock = 'd',
	box = 'b',
	boxDocked = 'x',
	worker = 'p',
	workerDocked = 'X',
	none = '#',
	next = '\n'
} TexType;

typedef struct Textile {
	ID id;
	TexType tex;
} Textile;

typedef struct MapRow {
	Textile* cols;
	size_t s;
} MapRow;

typedef struct MapArray {
	MapRow* rows;
	size_t s;
} MapArray;

typedef struct Pos {
	unsigned short x; 
	unsigned short y; 
} Pos;

typedef struct BGPair {
	Pos box;
	Pos goal;
} BGPair;

typedef enum Direction {
	up = 0, down = 1, left = 2, right = 3
} Direction;

extern const short DirectionOff[4][2];

#endif
