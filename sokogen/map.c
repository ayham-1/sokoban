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

	for (int8_t i = 0; i < result->arr.s; i++) {
		result->arr.rows[i].s = map->arr.rows[i].s; 
		result->arr.rows[i].cols = (Textile*)malloc(
				sizeof(Textile) * result->arr.rows[i].s);
		memcpy(result->arr.rows[i].cols, map->arr.rows[i].cols,
				sizeof(Textile) * map->arr.rows[i].s);
	}

	return result;
}

int8_t map_build(Map* map, char* displayed) {
	assert(map != NULL);
	assert(displayed != NULL);

	/* clean the map->arr variable */
	for (size_t i = 0; i < map->arr.s; i++)
		free(map->arr.rows[i].cols);
	free(map->arr.rows);
	map->arr.s = 0;

	/* convert char to Textiles */
	MapRow line;
	memset(&line, 0, sizeof(MapRow));
	MapArray result;
	for (size_t i = 0; i < strlen(displayed); i++) {
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

int8_t map_build_displayed(Map* map) {
	free(map->displayed);

	size_t size = 0;
	for (size_t i = 0; i < map->arr.rows->s; i++)
		size += map->arr.rows[i].s;

	char* result = (char*)malloc((sizeof(char) * size) + 2);

	size_t ind = 0;
	for (size_t i = 0; i < map->arr.rows->s; i++) {
		for (size_t j = 0; j < map->arr.rows[i].s; j++) {
			result = strcat(result, (char*)map->arr.rows[i].cols[j].tex);
			ind++;
		}
	}

	return 0;
}

void map_set_box_positions(Map* map) {
	free(map->boxPos);
	map->s_boxPos = 0;

	for (size_t i = 0; i < map->arr.s; i++) {
		for (size_t j = 0; j < map->arr.rows[i].s; j++) {
			if (map->arr.rows[i].cols[j].tex == box 
					|| map->arr.rows[i].cols[j].tex 
					== boxDocked) {
				map->s_boxPos++;
				map->boxPos = realloc(map->boxPos, map->s_boxPos * sizeof(TextilePos));
				Pos pos;
				pos.x = j;
				pos.y = i;

				TextilePos tex; 
				tex.id = map->arr.rows[i].cols[j].id;
				tex.tex = map->arr.rows[i].cols[j].tex;
				tex.pos = pos;
				map->boxPos[map->s_boxPos - 1] = tex;
			}
		}
	}
}
