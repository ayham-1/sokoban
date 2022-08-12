#ifndef MAP_H
#define MAP_H

#include <stdint.h>

#include "consts.h"

typedef struct Map {
	MapArray arr;
	ID highestID;
	char* displayed;
	size_t width;
	size_t height;
	Pos workerPos;
	TextilePos* boxPos;
	size_t s_boxPos; /* the number of items */
	
} Map;

Map* map_init();
void map_deinit(Map* map);
Map* map_clone(Map* map);
uint64_t map_hash(Map* map);
int8_t map_build(Map* map, char* displayed);
int8_t map_build_displayed(Map* map);
void map_set_box_positions(Map* map);
void map_set_worker_position(Map* map);

#endif
