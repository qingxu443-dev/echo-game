class_name HazardField
extends RefCounted

## Ground hazards: 凋零 (§15.1 樱落领域) and 残春 (§15.3 春痕绽放).
##
## Both share one rule set the document states once and then repeats for each:
## the tile hurts whoever enters it or stays on it, at most once per character per
## player turn, never blocks movement or line of sight, never stacks, and expires
## after a fixed number of whole turns. Two kinds, one table, one clock.
##
## The clock is `battle.turn_number`, which increments at the START of a player
## turn. A hazard laid during the enemy phase of turn T carries
## `expires_turn = T + 2`, so it survives the player turns T+1 and T+2 and is
## swept before the stay-damage tick of turn T+3 - exactly two whole turns.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")

const KIND_BLIGHT: String = "blight"
const KIND_LINGERING_SPRING: String = "lingering_spring"

## Display names live here rather than in the UI so the event log, the board and
## the HUD all call the same tile the same thing.
const KIND_LABELS: Dictionary = {
	KIND_BLIGHT: "凋零",
	KIND_LINGERING_SPRING: "残春",
}


static func is_known_kind(kind: String) -> bool:
	return KIND_LABELS.has(kind)


static func label_of(kind: String) -> String:
	return String(KIND_LABELS.get(kind, kind))


## Lays hazards on `cells`. Returns how many tiles were actually placed: a cell
## that already carries a hazard is left untouched (the document forbids both
## clearing and stacking), as is an obstacle or an out-of-bounds cell.
static func spawn(
	battle,
	cells: Array,
	kind: String,
	damage: int,
	owner_id: String,
	duration_turns: int,
	damage_type: String = "physical"
) -> int:
	if not is_known_kind(kind):
		return 0
	var placed := 0
	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		if not GridRulesScript.is_inside_bounds(cell, battle.grid_size):
			continue
		if battle.blocked_cells.has(cell):
			continue
		if battle.hazards.has(cell):
			continue
		battle.hazards[cell] = {
			"kind": kind,
			"cell": cell,
			"damage": maxi(0, damage),
			"damage_type": damage_type,
			"owner_id": owner_id,
			"expires_turn": battle.turn_number + maxi(1, duration_turns),
		}
		placed += 1
	if placed > 0:
		battle._emit_event(
			"hazard_spawned", owner_id, "",
			"kind=%s cells=%d damage=%d expires=%d" % [kind, placed, maxi(0, damage), battle.turn_number + maxi(1, duration_turns)]
		)
	return placed


## Sweeps expired tiles. Called at the START of a player turn, before the
## stay-damage tick, so the turn a hazard lapses is a turn it stops hurting.
static func expire(battle) -> int:
	var expired_cells: Array[Vector2i] = []
	for cell in battle.hazards:
		if battle.turn_number > int(battle.hazards[cell].get("expires_turn", 0)):
			expired_cells.append(cell)
	for cell in expired_cells:
		battle.hazards.erase(cell)
	if not expired_cells.is_empty():
		battle._emit_event("hazard_expired", "", "", "cells=%d turn=%d" % [expired_cells.size(), battle.turn_number])
	return expired_cells.size()


## The one place a character takes hazard damage. "Enters" and "stays" both land
## here, and the per-turn ledger makes the second call in the same turn a no-op -
## the document allows at most one trigger per character per player turn, not one
## per tile and not one per way of getting there.
static func trigger_for(battle, actor) -> int:
	if actor == null or not actor.is_alive():
		return 0
	var hazard: Dictionary = battle.hazards.get(actor.cell, {})
	if hazard.is_empty():
		return 0
	if int(battle.hazard_trigger_turn.get(actor.actor_id, -1)) == battle.turn_number:
		return 0
	var damage: int = int(hazard.get("damage", 0))
	if damage <= 0:
		return 0
	battle.hazard_trigger_turn[actor.actor_id] = battle.turn_number
	var kind: String = str(hazard.get("kind", ""))
	var damage_type: String = str(hazard.get("damage_type", "physical"))
	# Not a public intent: the telegraph already resolved as its own hit, and the
	# ground under the character is a separate source. `is_public_intent` drives
	# oath-vow accumulation, which belongs to telegraphed enemy actions only.
	battle._apply_damage(
		String(actor.actor_id), damage, str(hazard.get("owner_id", "")),
		"hazard_" + kind, damage_type, false, ""
	)
	battle._emit_event(
		"hazard_triggered", str(hazard.get("owner_id", "")), String(actor.actor_id),
		"kind=%s cell=%s damage=%d" % [kind, str(actor.cell), damage]
	)
	return damage


## Stay damage for everyone standing on a tile at the start of their turn.
static func tick_player_turn_start(battle) -> int:
	var total := 0
	for actor_id in battle.actors:
		var actor = battle.actors[actor_id]
		if actor.team != "player":
			continue
		total += trigger_for(battle, actor)
	return total


static func cells_of_kind(battle, kind: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in battle.hazards:
		if str(battle.hazards[cell].get("kind", "")) == kind:
			cells.append(cell)
	return cells


static func damage_at(battle, cell: Vector2i) -> int:
	var hazard: Dictionary = battle.hazards.get(cell, {})
	return int(hazard.get("damage", 0))
