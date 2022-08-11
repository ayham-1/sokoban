#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include "map.h"

Map* map_init() {
	Map* result = (Map*)malloc(sizeof(Map));
	memset(result, 0, sizeof(Map));

	result->arr.s++;
	result->arr.rows = (MapRow*)calloc(result->arr.s, sizeof(MapRow));

	return result;
}

void map_deinit(Map* map) {
	if (map->arr.rows) free(map->arr.rows);
	if (map->displayed) free(map->displayed);

	free(map);
	map = NULL;
}

Map* map_clone(Map* map) {
	Map* result = (Map*)malloc(sizeof(Map));
	memcpy(result, map, sizeof(Map));

	result->arr.s = map->arr.s;
	result->arr.rows = (MapRow*)malloc(sizeof(MapRow) * result->arr.s);

	for (int i = 0; i < result->arr.s; i++) {
		result->arr.rows[i].s = map->arr.rows[i].s; 
		result->arr.rows[i].cols = (Textile*)malloc(
				sizeof(Textile) * result->arr.rows[i].s);
		memcpy(result->arr.rows[i].cols, map->arr.rows[i].cols,
				sizeof(Textile) * map->arr.rows[i].s);
	}

	return result;
}

int map_build(Map* map, char* displayed) {
	assert(map != NULL);
	assert(displayed != NULL);

	/* clean the map->arr variable */
	for (int i = 0; i < map->arr.s; i++)
		free(map->arr.rows[i].cols);
	free(map->arr.rows);
	map->arr.s = 0;


	/* convert char to Textiles */
	MapRow line;
	memset(&line, 0, sizeof(MapRow));
	MapArray result;
	for (int i = 0; i < strlen(displayed); i++) {
		TexType tex = displayed[i];
		if (tex == next) {
			/* copy line */
			MapRow copied_line;
			copied_line.s = line.s;
			copied_line.cols = (Textile*)malloc(
					sizeof(Textile) * line.s);
			memcpy(copied_line.cols, line.cols, 
					sizeof(Textile) * line.s);

			/* realloc and append */
			result.s++;
			result.rows = (MapRow*)realloc(result.rows, 
					sizeof(MapRow) * result.s);
			result.rows[result.s - 1] = copied_line;

			/* dealloc line */
			free(line.cols);
			line.s = 0;
		} else {
			/* make new tile */
			Textile tile;
			tile.id = map->highestID;
			map->highestID++;
			tile.tex = tex;

			/* realloc and append */
			line.s++;
			line.cols = (Textile*)realloc(line.cols, 
					sizeof(Textile) * line.s);
			line.cols[line.s - 1] =  tile;
		}

		if (tex == worker && tex == workerDocked) {
			map->workerPos.x = line.s - 1;
			map->workerPos.y = result.s;
		}
	}
	free(line.cols);

	map->height = result.s;
	if (map->height != 0) map->width = result.rows[0].s;
	if (map->width || map->height) {
		map->width = 6;
		map->height = 2;
	}

	map->arr = result;
	return 0;
}
