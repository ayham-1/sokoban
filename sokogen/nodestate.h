#ifndef NODESTATE_H
#define NODESTATE_H

#include <stdint.h>

#include "consts.h"
#include "map.h"

typedef struct NodeState NodeState;

typedef struct Action Action;
typedef struct ActionArgs ActionArgs;
typedef void (*ActionFn)(NodeState*, ActionArgs);

typedef enum ActionType {
	PLACE_BOX, PLACE_FLOOR, PLACE_PLAYER, MOVE_BOX, EVALUATE
} ActionType;

struct NodeState {
	ActionType action;
	Action** nextActions;
	size_t s_nextActions;

	Map* map;
	Map* freezedMap;

	Textile* playerReach;
	size_t s_playerReach;

	BGPair* boxGoal;
	size_t s_boxGoal;
};

NodeState* snode_init(uint8_t width, uint8_t height);
void snode_deinit(NodeState* snode);
NodeState* snode_clone(NodeState* snode);
uint64_t snode_hash(NodeState* snode);
void snode_post_process(NodeState* snode);
void snode_simulate(NodeState* snode);
void snode_action_place_box(NodeState* snode, ActionArgs args);
void snode_action_place_floor(NodeState* snode, ActionArgs args);
void snode_action_place_player(NodeState* snode, ActionArgs args);
void snode_action_move_box(NodeState* snode, ActionArgs args);
void snode_action_evaluate(NodeState* snode, ActionArgs args);
void snode_get_reach_from(NodeState* snode, Pos pos);
Pos snode_move_pos(NodeState* snode, Direction direction);
void snode_append_box_moves(NodeState* snode);

struct ActionArgs {
	Pos pos;
	size_t boxID;
	Direction direction;
};

struct Action {
	ActionArgs args;
	ActionFn fn;
};

#endif
