class_name SummonService
extends RefCounted

## Player-side summons: a support strike on a cooldown.
##
## A summon is not a battlefield unit. It appears next to the chosen enemy,
## strikes once and is gone, so it never occupies a cell, never appears in the
## intent order and can never be targeted. That falls out of the design rather
## than being enforced: enemy intents only ever lock onto a party member.
##
## Everything numeric comes from SummonDefinition; this file only knows the rules
## - who may be aimed at, where the summon appears, and the cooldown clock.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")
const SummonCatalogScript = preload("res://scripts/battle/summon_catalog.gd")
const SkillExecutorScript = preload("res://scripts/battle/skill_executor.gd")


## Remaining turns before this summon is ready again. 0 means ready.
static func cooldown_remaining(battle, summon_id: StringName = SummonCatalogScript.DEFAULT_ID) -> int:
	var definition := SummonCatalogScript.get_definition(summon_id)
	if definition == null:
		return 0
	var last_used: int = int(battle.summon_last_used_turn.get(String(summon_id), -1))
	if last_used < 0:
		return 0
	return maxi(0, definition.cooldown_turns - (battle.turn_number - last_used))


static func can_summon(battle, summon_id: StringName, target_actor_id: String = "") -> bool:
	var definition := SummonCatalogScript.get_definition(summon_id)
	if definition == null:
		return false
	if battle.phase != battle.BattlePhase.PLAYER:
		return false
	var summoner = battle.get_active_character()
	if summoner == null or not summoner.is_alive():
		return false
	if cooldown_remaining(battle, summon_id) > 0:
		return false
	if not battle.ap.can_spend(definition.ap_cost):
		return false
	if target_actor_id.is_empty():
		return true

	var target = battle.actors.get(target_actor_id)
	if target == null or not target.is_alive() or target.team != "enemy":
		return false
	return not is_cell_missing(find_hunter_cell(battle, target))


## The summon strikes once and leaves. Appearance is presentation only: no unit
## is created, nothing enters the intent order, and AP is charged per the data.
static func request(battle, summon_id: StringName, target_actor_id: String) -> bool:
	var definition := SummonCatalogScript.get_definition(summon_id)
	if definition == null or not can_summon(battle, summon_id, target_actor_id):
		return false

	var target = battle.actors[target_actor_id]
	var summon_cell: Vector2i = find_hunter_cell(battle, target)
	if is_cell_missing(summon_cell):
		return false
	if definition.ap_cost > 0 and not battle.ap.spend(definition.ap_cost):
		return false

	var damage: int = CombatMathScript.calculate_raw_damage(definition.attack, definition.damage_multiplier)
	battle.summon_last_used_turn[String(summon_id)] = battle.turn_number
	battle._emit_event(
		"hunter_summoned",
		String(summon_id),
		target_actor_id,
		"cell=%s target=%s cooldown=%d" % [str(summon_cell), target_actor_id, definition.cooldown_turns]
	)
	battle._apply_damage(target_actor_id, damage, String(summon_id), String(summon_id), "physical")
	SkillExecutorScript.gain_active_energy(battle, battle.active_character_id)
	battle._emit_event("skill_resolved", String(summon_id), target_actor_id, "skill=%s raw=%d cell=%s" % [String(summon_id), damage, str(summon_cell)])
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
