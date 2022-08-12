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
	result->map = (Map*)malloc(sizeof(Map));
	result->playerReach = NULL;

	return result;
}

void snode_deinit(NodeState* snode) {
	while (snode->s_nextActions) {
		free(snode->nextActions[snode->s_nextActions - 1]);
		snode->s_nextActions--;
	}
	free(snode->nextActions);

	map_deinit(snode->map);
	free(snode->playerReach);

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

	result->s_playerReach = snode->s_playerReach;
	result->playerReach = (Textile*)malloc(sizeof(Textile) * result->s_playerReach);
	memcpy(result->playerReach, snode->playerReach, sizeof(Textile) * result->s_playerReach);

	return result;
}

uint64_t snode_hash(NodeState* snode) {
	uint64_t hash = 0;

	hash += sdbm_hash((unsigned char*)snode->action);
	for (int i = 0; i < snode->s_nextActions; i++)
		hash += sdbm_hash((unsigned char*)snode->nextActions[i]);
	hash += sdbm_hash((unsigned char*)snode->s_nextActions);

	hash += sdbm_hash((unsigned char*)snode->playerReach);
	hash += sdbm_hash((unsigned char*)snode->s_playerReach);

	hash += map_hash(snode->map);

	return hash;
}
