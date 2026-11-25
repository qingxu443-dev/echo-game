class_name CharacterSkillRuntime
extends RefCounted

## Runs skill definitions for any character, driven by their data.
##
## Two layers, deliberately kept apart:
##
##  - What a skill costs, how far it reaches, how many segments it has and how
##    each segment scales all come from SkillDefinition. Changing a number is a
##    data edit.
##  - Novel mechanics (Sakura's blade intent, petal mark, echo return) need code.
##    They are addressed by effect_id, so a new character that reuses an existing
##    mechanic needs no code at all, and one that invents a mechanic adds one
##    branch here.
##
## Sevrin's kit still runs through SkillExecutor because it predates this runtime;
## request() forwards to it by effect_id so both characters share one entry point.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")
const SkillRegistryScript = preload("res://scripts/battle/skill_registry.gd")
const SkillExecutorScript = preload("res://scripts/battle/skill_executor.gd")
const SummonServiceScript = preload("res://scripts/battle/summon_service.gd")
const CharacterScript = preload("res://scripts/battle/character_definition.gd")
const SkillDefinitionScript = preload("res://scripts/battle/skill_definition.gd")

## Sakura's mark (design plan §20) and resource (§19).
const PETAL_MARK: StringName = &"sakura_petal_mark"
const PETAL_MARK_TURNS: int = 3

## §19: at most three stacks per turn from action events; the turn-start stack is
## outside that budget.
const INTENT_PER_ACTION_EVENT: int = 1
const INTENT_ACTION_BUDGET: int = 3

## §21: echo return is 50% of attack, or 65% under a Falling Petals empowerment.
const ECHO_RETURN_MULTIPLIER: float = 0.5

## §24: ultimate cost, and how much each blade-intent stack lifts the finisher.
const ULTIMATE_ENERGY_COST: int = 5
const ULTIMATE_FINISHER_PER_STACK: float = 0.05
const ULTIMATE_FINISHER_FULL_BONUS: float = 0.20


## Single entry point for "the active character uses this skill on this target".
static func request(battle, skill_id: StringName, target_actor_id: String) -> bool:
	# The hunter summon is a player-side support action rather than a character
	# skill, so it is not in any sheet or catalog. It takes this one branch.
	if skill_id == &"hunter_summon":
		return SummonServiceScript.request(battle, target_actor_id)

	var skill := SkillRegistryScript.get_skill(skill_id)
	if skill == null or skill.is_passive:
		return false

	# Self-target skills are pressed, not aimed: the caller passes no target, so
	# the active character is the target.
	if target_actor_id.is_empty() and (skill.target_mode == SkillDefinitionScript.TARGET_SELF or skill.target_mode == SkillDefinitionScript.TARGET_SELF_AND_ALLY):
		var caster = battle.get_active_character()
		if caster != null:
			target_actor_id = caster.actor_id

	match String(skill.executor_id):
		"oathkeeper_judgment_mark":
			return SkillExecutorScript.judgment_mark_v2(battle, target_actor_id)
		"oath_shield":
			return SkillExecutorScript.oath_shield(battle, target_actor_id)
		"absolute_guard":
			return SkillExecutorScript.absolute_guard(battle)
		"sakura_pierce_blossom":
			return _pierce_blossom(battle, skill, target_actor_id)
		"sakura_flowing_wind":
			return _flowing_wind(battle, skill, target_actor_id)
		"sakura_endless_fragrance":
			return _endless_fragrance(battle, skill)
	return false


# --- Sakura ------------------------------------------------------------------

## §18 穿花: adjacent single target, applies the mark, then echo return may fire.
static func _pierce_blossom(battle, skill, target_actor_id: String) -> bool:
	var caster = battle.get_active_character()
	if not _can_cast(battle, caster, skill):
		return false
	var target = battle.actors.get(target_actor_id)
	if target == null or target.team != "enemy" or not target.is_alive():
		return false
	if GridRulesScript.manhattan_distance(caster.cell, target.cell) != 1:
		return false
	if not battle.ap.spend(skill.ap_cost):
		return false

	# §20: a target that was not already marked only gets the mark - the first
	# application must not also fire the follow-up.
	var was_marked: bool = battle.statuses.has_status(target.actor_id, PETAL_MARK)
	_apply_segments(battle, caster, skill, [target], "sakura_pierce_blossom")
	_apply_petal_mark(battle, caster, target)
	gain_intent_from_action(battle, caster)
	if was_marked:
		_check_echo_return(battle, caster, target)
	battle._emit_event("skill_resolved", caster.actor_id, target_actor_id, "skill=sakura_pierce_blossom ap=1")
	battle._check_battle_end()
	return true


## §22 流风: dash up to two cells toward the target, then strike it if adjacent.
static func _flowing_wind(battle, skill, target_actor_id: String) -> bool:
	var caster = battle.get_active_character()
	if not _can_cast(battle, caster, skill):
		return false
	var target = battle.actors.get(target_actor_id)
	if target == null or target.team != "enemy" or not target.is_alive():
		return false

	var aligned: bool = caster.cell.x == target.cell.x or caster.cell.y == target.cell.y
	if not aligned and GridRulesScript.manhattan_distance(caster.cell, target.cell) > skill.max_range:
		return false
	if not GridRulesScript.has_clear_orthogonal_line(caster.cell, target.cell, battle.blocked_cells, battle.get_occupied_cells(caster.actor_id)):
		return false

	var landing: Vector2i = _dash_landing(battle, caster, target)
	if landing == caster.cell and GridRulesScript.manhattan_distance(caster.cell, target.cell) != 1:
		return false
	if not battle.ap.spend(skill.ap_cost):
		return false

	var from_cell: Vector2i = caster.cell
	caster.cell = landing
	battle._emit_event("actor_moved", caster.actor_id, "", str(landing))
	gain_intent_from_action(battle, caster)

	if GridRulesScript.manhattan_distance(caster.cell, target.cell) == 1:
		var was_marked: bool = battle.statuses.has_status(target.actor_id, PETAL_MARK)
		_apply_segments(battle, caster, skill, [target], "sakura_flowing_wind")
		_apply_petal_mark(battle, caster, target)
		if was_marked:
			_check_echo_return(battle, caster, target)
	battle._emit_event("skill_resolved", caster.actor_id, target_actor_id, "skill=sakura_flowing_wind ap=1 from=%s to=%s" % [str(from_cell), str(landing)])
	battle._check_battle_end()
	return true


## §24 无尽芳华: cross around the caster, three 20% cuts and a 40% finisher that
## each blade-intent stack lifts by 5%, plus 20% at full stacks.
static func _endless_fragrance(battle, skill) -> bool:
	var caster = battle.get_active_character()
	if not _can_cast(battle, caster, skill):
		return false
	if caster.ultimate_energy < ULTIMATE_ENERGY_COST:
		return false
	var targets := _cross_targets(battle, caster, skill.max_range)
	if targets.is_empty():
		return false
	if not battle.ap.spend(skill.ap_cost):
		return false
	if not caster.spend_ultimate_energy(ULTIMATE_ENERGY_COST):
		battle.ap.refund(skill.ap_cost)
		return false

	var multipliers := _ultimate_multipliers(skill, caster)
	var last_index: int = multipliers.size() - 1
	for hit_index in range(multipliers.size()):
		for target in targets:
			if not target.is_alive():
				continue
			var raw_damage: int = CombatMathScript.calculate_raw_damage(caster.attack, multipliers[hit_index])
			var action_id := "sakura_endless_fragrance_finisher" if hit_index == last_index else "sakura_endless_fragrance"
			battle._apply_damage(target.actor_id, raw_damage, caster.actor_id, action_id, String(skill.damage_type))
	gain_intent_from_action(battle, caster)
	battle._emit_event("skill_resolved", caster.actor_id, "", "skill=sakura_endless_fragrance hits=%d targets=%d" % [multipliers.size(), targets.size()])
	battle._check_battle_end()
	return true


## Per-segment multipliers, with the finisher scaled by current blade intent.
static func _ultimate_multipliers(skill, caster) -> Array[float]:
	var multipliers: Array[float] = []
	if skill.hit_multipliers.is_empty():
		return multipliers
	var stacks: int = caster.resource_current
	var finisher_bonus: float = ULTIMATE_FINISHER_PER_STACK * float(stacks)
	if caster.is_resource_full():
		finisher_bonus += ULTIMATE_FINISHER_FULL_BONUS
	for index in range(skill.hit_multipliers.size()):
		var value: float = skill.hit_multipliers[index]
		if index == skill.hit_multipliers.size() - 1:
			value += finisher_bonus
		multipliers.append(value)
	return multipliers


# --- shared helpers ----------------------------------------------------------

static func _can_cast(battle, caster, skill) -> bool:
	if caster == null or not caster.is_alive():
		return false
	if battle.phase != battle.BattlePhase.PLAYER:
		return false
	if not battle.ap.can_spend(skill.ap_cost):
		return false
	return true


## One segment per entry in hit_multipliers, or damage_multiplier split evenly.
static func _apply_segments(battle, caster, skill, targets: Array, action_id: String) -> void:
	var multipliers: Array[float] = []
	if not skill.hit_multipliers.is_empty():
		multipliers = skill.hit_multipliers.duplicate()
	elif skill.damage_multiplier > 0.0:
		for _i in range(maxi(1, skill.hits)):
			multipliers.append(skill.damage_multiplier / float(maxi(1, skill.hits)))
	for multiplier in multipliers:
		for target in targets:
			if not target.is_alive():
				continue
			var raw_damage: int = CombatMathScript.calculate_raw_damage(caster.attack, multiplier)
			battle._apply_damage(target.actor_id, raw_damage, caster.actor_id, action_id, String(skill.damage_type))


## Cells two steps out in each orthogonal direction, kept on the board.
static func _cross_targets(battle, caster, reach: int) -> Array:
	var targets: Array = []
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var cells: Dictionary = {}
	for direction in directions:
		for step in range(1, reach + 1):
			var cell: Vector2i = caster.cell + direction * step
			if not GridRulesScript.is_inside_bounds(cell, battle.grid_size):
				break
			cells[cell] = true
	for actor_id in battle.actors:
		var actor = battle.actors[actor_id]
		if actor.team == "enemy" and actor.is_alive() and cells.has(actor.cell):
			targets.append(actor)
	return targets


## Walk toward the target until blocked or adjacent, at most max_range steps.
static func _dash_landing(battle, caster, target) -> Vector2i:
	var cursor: Vector2i = caster.cell
	var steps: int = 2
	var occupied: Dictionary = battle.get_occupied_cells(caster.actor_id)
	for _i in range(steps):
		var next := cursor
		if target.cell.x != cursor.x:
			next.x += signi(target.cell.x - cursor.x)
		elif target.cell.y != cursor.y:
			next.y += signi(target.cell.y - cursor.y)
		if next == cursor:
			break
		if GridRulesScript.manhattan_distance(next, target.cell) < 1:
			break
		if not GridRulesScript.is_inside_bounds(next, battle.grid_size):
			break
		if battle.blocked_cells.has(next) or occupied.has(next):
			break
		cursor = next
	return cursor


static func _apply_petal_mark(battle, caster, target) -> void:
	battle.statuses.apply_status(PETAL_MARK, caster.actor_id, target.actor_id, 1, 1, -1, &"", &"refresh")
	var status = battle.statuses.get_status(target.actor_id, PETAL_MARK)
	if status != null:
		status.enemy_turns_remaining = PETAL_MARK_TURNS
	battle._emit_event("status_applied", caster.actor_id, target.actor_id, "status=sakura_petal_mark turns=%d" % PETAL_MARK_TURNS)


## §21: an adjacent marked target takes one automatic follow-up per action.
static func _check_echo_return(battle, caster, target) -> void:
	if not target.is_alive():
		return
	if not battle.statuses.has_status(target.actor_id, PETAL_MARK):
		return
	if GridRulesScript.manhattan_distance(caster.cell, target.cell) != 1:
		return
	var raw_damage: int = CombatMathScript.calculate_raw_damage(caster.attack, ECHO_RETURN_MULTIPLIER)
	battle._apply_damage(target.actor_id, raw_damage, caster.actor_id, "sakura_echo_return", "physical")

	# §19: the first echo return of a turn is worth one more stack.
	if int(battle.echo_return_gain_turn.get(caster.actor_id, -1)) != battle.turn_number:
		battle.echo_return_gain_turn[caster.actor_id] = battle.turn_number
		gain_intent_from_action(battle, caster)
	battle._emit_event("counter_resolved", caster.actor_id, target.actor_id, "skill=sakura_echo_return raw=%d" % raw_damage)


## §19: action events share a three-stack budget per turn; the turn-start stack
## is granted separately by the flow.
static func gain_intent_from_action(battle, caster, amount: int = INTENT_PER_ACTION_EVENT) -> void:
	if caster == null or not caster.has_resource():
		return
	if int(battle.resource_gain_turn.get(caster.actor_id, -1)) != battle.turn_number:
		battle.resource_gain_turn[caster.actor_id] = battle.turn_number
		battle.resource_gain_count[caster.actor_id] = 0
	var used: int = int(battle.resource_gain_count.get(caster.actor_id, 0))
	if used >= INTENT_ACTION_BUDGET:
		return
	var granted: int = mini(amount, INTENT_ACTION_BUDGET - used)
	caster.gain_resource(granted)
	battle.resource_gain_count[caster.actor_id] = used + granted
	battle._emit_event("resource_gained", caster.actor_id, caster.actor_id, "resource=%s value=%d" % [String(caster.resource_id), caster.resource_current])
