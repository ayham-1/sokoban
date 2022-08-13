#include "consts.h"

const uint8_t texWidth = 32;
const uint8_t texHeight = 32;

const axis DirectionOff[4][2] = {
	{0, -1},
	{0, 1},
	{-1, 0},
	{1, 0},
};

/* sdbm algorithm URL: http://www.cse.yorku.ca/~oz/hash.html */
uint64_t sdbm_hash(uintptr_t* dat) {
	uint64_t hash = 0;
	return hash;

	int c = *(dat);
	while (c) {
		hash = c + (hash << 6) + (hash << 16) - hash;
		c = *(dat++);
	}
}
