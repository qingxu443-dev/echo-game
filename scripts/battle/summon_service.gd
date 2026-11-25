class_name SummonService
extends RefCounted

## The hunter summon: a free support strike on a cooldown.
##
## The hunter is not a battlefield unit. It appears next to the chosen enemy,
## strikes once and is gone, so it never occupies a cell, never appears in the
## intent order and can never be targeted. That falls out of the design rather
## than being enforced: enemy intent generation only ever locks onto "sevrin".
##
## Numbers stay on the controller (HUNTER_SUMMON_ATTACK and friends) so callers
## and tests keep reading them from one place.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")


## Remaining turns until the hunter can be summoned again. 0 means ready.
static func cooldown_remaining(battle) -> int:
	if battle.summon_last_used_turn < 0:
		return 0
	return maxi(0, battle.HUNTER_SUMMON_COOLDOWN_TURNS - (battle.turn_number - battle.summon_last_used_turn))


static func can_summon(battle, target_actor_id: String = "") -> bool:
	var actors = battle.actors
	if battle.phase != battle.BattlePhase.PLAYER or not actors.has("sevrin"):
		return false
	if not actors["sevrin"].is_alive() or cooldown_remaining(battle) > 0:
		return false
	if target_actor_id.is_empty():
		return true
	if not actors.has(target_actor_id):
		return false
	var target = actors[target_actor_id]
	if not target.is_alive() or target.team != "enemy":
		return false
	return not is_cell_missing(find_hunter_cell(battle, target))


## The hunter strikes once and leaves. No AP is spent, no unit is created and
## nothing is added to the intent order.
static func request(battle, target_actor_id: String) -> bool:
	if not can_summon(battle, target_actor_id):
		return false
	var target = battle.actors[target_actor_id]
	var hunter_cell: Vector2i = find_hunter_cell(battle, target)
	if is_cell_missing(hunter_cell):
		return false
	var damage: int = CombatMathScript.calculate_raw_damage(battle.HUNTER_SUMMON_ATTACK, battle.HUNTER_SUMMON_MULTIPLIER)
	battle.summon_last_used_turn = battle.turn_number
	battle._emit_event(
		"hunter_summoned",
		"hunter",
		target_actor_id,
		"cell=%s target=%s cooldown=%d" % [str(hunter_cell), target_actor_id, battle.HUNTER_SUMMON_COOLDOWN_TURNS]
	)
	battle._apply_damage(target_actor_id, damage, "hunter", "hunter_summon", "physical")
	SkillExecutor.gain_active_energy(battle, "sevrin")
	battle._emit_event("skill_resolved", "hunter", target_actor_id, "skill=hunter_summon raw=%d cell=%s" % [damage, str(hunter_cell)])
	battle._check_battle_end()
	return true


## First free orthogonal neighbour of the target, in a fixed order so the
## appearance cell is deterministic. Vector2i(-1, -1) means no room.
static func find_hunter_cell(battle, target) -> Vector2i:
	var offsets: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var occupied: Dictionary = battle.get_occupied_cells()
	for offset in offsets:
		var cell: Vector2i = target.cell + offset
		if not GridRulesScript.is_inside_bounds(cell, battle.grid_size):
			continue
		if battle.blocked_cells.has(cell) or occupied.has(cell):
			continue
		return cell
	return Vector2i(-1, -1)


static func is_cell_missing(cell: Vector2i) -> bool:
	return cell.x < 0 or cell.y < 0
