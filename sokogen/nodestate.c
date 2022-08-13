#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <sys/types.h>

#include "nodestate.h"

NodeState* snode_init(uint8_t width, uint8_t height) {
	/* seed rand */
	time_t t;
	srand((unsigned) time(&t));

	/* plot random floor tile */
	size_t x = rand() % (width - 1);
	size_t y = rand() % (height - 1);
	Pos pos;
	pos.x = x;
	pos.y = y;

	Action* floorAct  = (Action*)malloc(sizeof(Action));
	(*floorAct) = (Action) {
		.fn = snode_action_place_floor,
		.args = {
			.boxID = 0,
			.pos = pos,
			.direction = 0,
		}
	};

	/* alloc new NodeState */
	NodeState* result = (NodeState*)malloc(sizeof(NodeState));
	result->action = PLACE_BOX;
	result->nextActions = (Action**)malloc(sizeof(Action*));
	result->nextActions[0] = floorAct;
	result->s_nextActions = 1;
	result->map = map_init();
	result->freezedMap = NULL;
	result->playerReach = NULL;
	result->s_playerReach = 0;
	result->boxGoal = NULL;
	result->s_boxGoal = 0;

	return result;
}

void snode_deinit(NodeState* snode) {
	while (snode->s_nextActions) {
		free(snode->nextActions[snode->s_nextActions - 1]);
		snode->s_nextActions--;
	}
	free(snode->nextActions);

	map_deinit(snode->map);
	map_deinit(snode->freezedMap);
	free(snode->playerReach);
	free(snode->boxGoal);
	free(snode);
}

NodeState* snode_clone(NodeState* snode) {
	NodeState* result = (NodeState*)malloc(sizeof(NodeState));
	result->action = snode->action;

	result->s_nextActions = snode->s_nextActions;
	result->nextActions = (Action**)malloc(sizeof(Action*) * result->s_nextActions);
	for (int i = 0; i < snode->s_nextActions; i++) {
		Action* newAction = (Action*)malloc(sizeof(Action));
		(*newAction) = (*snode->nextActions[i]);
		result->nextActions[i] = newAction;
	}

	result->map = map_clone(snode->map);
	result->freezedMap = map_clone(snode->freezedMap);

	result->s_playerReach = snode->s_playerReach;
	result->playerReach = (Textile*)malloc(sizeof(Textile) * result->s_playerReach);
	memcpy(result->playerReach, snode->playerReach, sizeof(Textile) * result->s_playerReach);

	result->s_boxGoal = snode->s_boxGoal;
	result->boxGoal = (BGPair*)malloc(sizeof(BGPair) * result->s_boxGoal);
	memcpy(result->boxGoal, snode->boxGoal, sizeof(BGPair) * result->s_boxGoal);

	return result;
}

uint64_t snode_hash(NodeState* snode) {
	uint64_t hash = 0;

	hash += sdbm_hash((uint8_t*)snode->action);
	for (int i = 0; i < snode->s_nextActions; i++)
		hash += sdbm_hash((uint8_t*)snode->nextActions[i]);
	hash += sdbm_hash((uint8_t*)snode->s_nextActions);

	hash += sdbm_hash((uint8_t*)snode->playerReach);
	hash += sdbm_hash((uint8_t*)snode->s_playerReach);

	hash += sdbm_hash((uint8_t*)snode->boxGoal);
	hash += sdbm_hash((uint8_t*)snode->s_boxGoal);

	hash += map_hash(snode->map);

	return hash;
}

void snode_post_process(NodeState* snode) {
	if (snode->freezedMap == NULL) return;

	/* 
	 * convert all boxes that are moves 1 or less times into obstacles
	   convert all boxes that moved more than 1 time into goals (docks)
	   */
	for (int i = 0; i < snode->s_boxGoal; i++) {
		BGPair paired = snode->boxGoal[i];

		axis b_x = paired.box.x;
		axis b_y = paired.box.y;

		axis g_x = paired.goal.x;
		axis g_y = paired.goal.y;

		if (abs(b_x - g_x) <= 1 && abs(b_y - g_y) <= 1)
			snode->freezedMap->arr.rows[b_y].cols[b_x].tex = wall;
		else
			snode->freezedMap->arr.rows[g_y].cols[g_x].tex = dock;
	}

}
