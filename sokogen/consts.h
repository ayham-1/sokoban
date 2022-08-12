#ifndef CONSTS_H
#define CONSTS_H

#include <stddef.h>
#include <stdint.h>

extern const int8_t texWidth;
extern const int8_t texHeight;

typedef struct Pos {
	size_t x; 
	size_t y; 
} Pos;

typedef size_t ID;

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

typedef struct TextilePos {
	ID id;
	TexType tex;
	Pos pos;
} TextilePos;

typedef struct MapRow {
	Textile* cols;
	size_t s;
} MapRow;

typedef struct MapArray {
	MapRow* rows;
	size_t s;
} MapArray;



typedef struct BGPair {
	Pos box;
	Pos goal;
} BGPair;

typedef enum Direction {
	up = 0, down = 1, left = 2, right = 3
} Direction;

extern const int8_t DirectionOff[4][2];

#endif
