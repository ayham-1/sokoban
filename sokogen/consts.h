#ifndef CONSTS_H
#define CONSTS_H

#include <stddef.h>
#include <stdint.h>

typedef size_t ID;
typedef int8_t axis;

extern const uint8_t texWidth;
extern const uint8_t texHeight;

typedef struct Pos {
	axis x; 
	axis y; 
} Pos;


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
	Textile* tile;
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

extern const axis DirectionOff[4][2];

/* sdbm algorithm URL: http://www.cse.yorku.ca/~oz/hash.html */
uint64_t sdbm_hash(uint8_t* dat);

#endif
