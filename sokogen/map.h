#ifndef MAP_H
#define MAP_H

#include "consts.h"

typedef struct Map {
	MapArray arr;
	ID highestID;
	char* displayed;
	size_t width;
	size_t height;
	Pos workerPos;
	BGPair* boxPos;
	
} Map;

Map* map_init();
void map_deinit(Map* map);
Map* map_clone(Map* map);
int map_build(Map* map, char* displayed);
int map_build_displayed(Map* map);
void map_set_box_positions(Map* map);
void map_set_worker_position(Map* map);


#endif
