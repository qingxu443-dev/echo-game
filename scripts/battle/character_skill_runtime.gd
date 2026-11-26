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
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")

## Sakura's mark (design plan §20) and resource (§19).
const PETAL_MARK: StringName = &"sakura_petal_mark"
const PETAL_MARK_TURNS: int = 3

## §19: at most three stacks per turn from action events; the turn-start stack is
## outside that budget.
const INTENT_PER_ACTION_EVENT: int = 1
const INTENT_ACTION_BUDGET: int = 3

## §21: echo return is 50% of attack, or 65% under a Falling Petals empowerment.
const ECHO_RETURN_MULTIPLIER: float = 0.5
## §19-23 极意. Being at full intent strengthens the next active skill (流风 or
## 落英) and consumes every stack. A normal attack and the ultimate neither spend
## nor clear it.
const EXTREME_FOLLOW_UP_MULTIPLIER: float = 0.4   # §22 second strike
const EXTREME_ECHO_MULTIPLIER: float = 0.65       # §21 / §23 boosted echo return
## §23 says 落英's area "expands" at 极意 without giving a number. One extra cell
## each way is this implementation's reading, and it is recorded as open rather
## than settled - the footprint is data, so changing it is an edit.
const EXTREME_SHAPE_WIDTH_BONUS: int = 1
const EXTREME_SHAPE_DEPTH_BONUS: int = 1

## §22: the dash is at most two cells. Separate from the skill's targeting range
## (three), which is how far away the enemy may be picked.
const FLOWING_WIND_DASH_STEPS: int = 2

## §24: ultimate cost, and how much each blade-intent stack lifts the finisher.
const ULTIMATE_FINISHER_PER_STACK: float = 0.05
const ULTIMATE_FINISHER_FULL_BONUS: float = 0.20


## Single entry point for "the active character uses this skill on this target".
static func request(battle, skill_id: StringName, target_actor_id: String) -> bool:
	# Summons are player-side support actions rather than character skills, so they
	# live in their own catalog. The bar names them "summon:<id>" so one entry point
	# can serve every summon without a branch per summon.
	var summon_prefix := "summon:"
	if String(skill_id).begins_with(summon_prefix):
		var summon_id := StringName(String(skill_id).substr(summon_prefix.length()))
		return SummonServiceScript.request(battle, summon_id, target_actor_id)

	var skill := SkillRegistryScript.get_skill(skill_id)
	if skill == null or skill.is_passive:
		return false
	# A character may only use skills their own sheet lists. Without this, asking
	# for Sevrin's blade while Sakura is active resolves his numbers against her
	# stats, and the UI is the only thing that would have prevented it.
	if not _owns_skill(battle, skill_id):
		return false

	# Self-target skills are pressed, not aimed: the caller passes no target, so
	# the active character is the target.
	if target_actor_id.is_empty() and (skill.target_mode == SkillDefinitionScript.TARGET_SELF or skill.target_mode == SkillDefinitionScript.TARGET_SELF_AND_ALLY):
		var caster = battle.get_active_character()
		if caster != null:
			target_actor_id = caster.actor_id

	return _dispatch(battle, skill, target_actor_id)


## executor_id -> the function that runs it. A table rather than a match so
## "does this skill have an executor?" is a question the suite can ask: it walks
## the registry and fails on any active skill whose executor is missing. Under a
## match the same mistake produced a button that returned false and said nothing.
##
## Every entry takes (battle, skill, target_actor_id); Sevrin's three are wrapped
## below because SkillExecutor predates this shape.
static var _executors: Dictionary = {
	&"oathkeeper_judgment_mark": Callable(CharacterSkillRuntime, "_run_judgment_mark"),
	&"oath_shield": Callable(CharacterSkillRuntime, "_run_oath_shield"),
	&"absolute_guard": Callable(CharacterSkillRuntime, "_run_absolute_guard"),
	&"basic_attack": Callable(CharacterSkillRuntime, "_basic_attack"),
	&"sakura_pierce_blossom": Callable(CharacterSkillRuntime, "_pierce_blossom"),
	&"sakura_flowing_wind": Callable(CharacterSkillRuntime, "_flowing_wind"),
	&"sakura_falling_petals": Callable(CharacterSkillRuntime, "_falling_petals"),
	&"sakura_endless_fragrance": Callable(CharacterSkillRuntime, "_endless_fragrance"),
}


static func supports(executor_id: StringName) -> bool:
	return _executors.has(executor_id)


## The executors resolve the caster as the commanded character themselves, so
## there is one rule in one place rather than a parameter every call has to
## remember to pass correctly.
static func _dispatch(battle, skill, target_actor_id: String) -> bool:
	var executor_id := StringName(skill.executor_id)
	if not _executors.has(executor_id):
		# Never silently return false: the press would do nothing and the player
		# would have no way to tell a missing executor from a failed condition.
		push_error("CharacterSkillRuntime: no executor registered for '%s' (skill '%s')" % [executor_id, skill.skill_id])
		return false
	return _executors[executor_id].call(battle, skill, target_actor_id)


# --- Sevrin's three, wrapped so every executor shares one signature -----------

static func _run_judgment_mark(battle, _skill, target_actor_id: String) -> bool:
	return SkillExecutorScript.judgment_mark_v2(battle, target_actor_id)


static func _run_oath_shield(battle, _skill, target_actor_id: String) -> bool:
	return SkillExecutorScript.oath_shield(battle, target_actor_id)


static func _run_absolute_guard(battle, _skill, _target_actor_id: String) -> bool:
	return SkillExecutorScript.absolute_guard(battle)


## Shared normal attack: adjacent single target, damage only. Characters with an
## extra rider (Sakura's mark) use their own executor instead.
static func _basic_attack(battle, skill, target_actor_id: String) -> bool:
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

	var kills: int = _apply_segments(battle, caster, skill, [target], String(skill.skill_id))
	gain_intent_from_action(battle, caster)
	_credit_kills(battle, kills)
	# §47 待决 9 option A: a normal attack is an active action, so it pays the
	# §13 per-turn ultimate energy like every skill does. The per-turn cap lives
	# in gain_active_energy, so this cannot be farmed by attacking repeatedly.
	SkillExecutorScript.gain_active_energy(battle, caster.actor_id)
	battle._emit_event("attack_resolved", caster.actor_id, target_actor_id, "%s ap=%d" % [String(skill.skill_id), skill.ap_cost])
	battle._check_battle_end()
	return true


# --- Sakura ------------------------------------------------------------------

## §18 穿花: adjacent single target, applies the mark, then echo return may fire.
static func _pierce_blossom(battle, skill, target_actor_id: String) -> bool:
	var caster = battle.get_active_character()
	if not _can_cast(battle, caster, skill):
		return false
	var target = battle.actors.get(target_actor_id)
	if target == null or target.team != "enemy":
		return false
	if not can_aim(battle, skill, target):
		return false
	if not battle.ap.spend(skill.ap_cost):
		return false

	# §20: a target that was not already marked only gets the mark - the first
	# application must not also fire the follow-up.
	var was_marked: bool = battle.statuses.has_status(target.actor_id, PETAL_MARK)
	var kills: int = _apply_segments(battle, caster, skill, [target], "sakura_pierce_blossom")
	# A dead target cannot carry a mark: damage clears its statuses, so marking it
	# afterwards leaves one on a corpse for three enemy phases.
	if target.is_alive():
		_apply_petal_mark(battle, caster, target)
	# §19/§30 order: the action's own stack, then kills, then the echo return.
	gain_intent_from_action(battle, caster)
	_credit_kills(battle, kills)
	# §13 applies to every character's successful active action. This branch used
	# to be the one skill that skipped it, so Pierce Blossom paid no ultimate
	# energy while the dash and the rectangle did - same rule, different result
	# depending on which button was pressed.
	SkillExecutorScript.gain_active_energy(battle, caster.actor_id)
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

	# Range and lane both come from can_aim, the same predicate the target ring
	# calls. Writing them out twice is how the ring ended up promising a dash the
	# cast refused whenever a wall stood between.
	if not can_aim(battle, skill, target):
		return false

	var landing: Vector2i = _dash_landing(battle, caster, target)
	if landing == caster.cell and GridRulesScript.manhattan_distance(caster.cell, target.cell) != 1:
		return false
	if not battle.ap.spend(skill.ap_cost):
		return false

	# Captured before any settlement: the bar is spent by this action, but the
	# stacks this action earns must survive, so consumption happens first and the
	# gain afterwards (§19).
	var extreme: bool = _is_extreme(caster)
	var from_cell: Vector2i = caster.cell
	caster.cell = landing
	battle._emit_event("actor_moved", caster.actor_id, "", str(landing))

	var adjacent: bool = GridRulesScript.manhattan_distance(caster.cell, target.cell) == 1
	var was_marked: bool = adjacent and battle.statuses.has_status(target.actor_id, PETAL_MARK)
	var kills: int = 0
	if adjacent:
		kills += _apply_segments(battle, caster, skill, [target], "sakura_flowing_wind")
		if target.is_alive():
			_apply_petal_mark(battle, caster, target)
		# §22 极意: a second strike at 40% against the same target. The plan allows
		# a new direction and a new target, but picking one is a second aiming
		# step the interface does not offer yet, so this strike reuses the target.
		if extreme and target.is_alive():
			if _apply_one_hit(battle, caster, target, EXTREME_FOLLOW_UP_MULTIPLIER, "sakura_flowing_wind_extreme"):
				kills += 1
	if extreme:
		_consume_extreme(battle, caster)
	gain_intent_from_action(battle, caster)
	_credit_kills(battle, kills)
	# §13: a successful active action grants one ultimate energy per turn, for
	# every character. The dash resolves even without a strike, so the grant
	# follows the action rather than the hit.
	SkillExecutorScript.gain_active_energy(battle, caster.actor_id)
	if adjacent and was_marked:
		_check_echo_return(battle, caster, target)
	battle._emit_event("skill_resolved", caster.actor_id, target_actor_id, "skill=sakura_flowing_wind ap=1 from=%s to=%s" % [str(from_cell), str(landing)])
	battle._check_battle_end()
	return true


## §23 落英: a rectangle in front of the caster - three cells wide and two deep
## by owner decision on 2026-11-25, replacing the undecided fan. Three segments of
## 30% each; the mark lands on hit, and targets already marked take a follow-up.
static func _falling_petals(battle, skill, target_actor_id: String) -> bool:
	var caster = battle.get_active_character()
	if not _can_cast(battle, caster, skill):
		return false
	var target = battle.actors.get(target_actor_id)
	if target == null or target.team != "enemy" or not target.is_alive():
		return false

	# 落英 had no range gate and no sight gate at all: the rectangle only checked
	# bounds, so a wall between Sakura and the enemy did not matter and the cast
	# still landed. One predicate now covers the ring and the cast.
	if not can_aim(battle, skill, target):
		return false

	var direction: Vector2i = _direction_toward(caster.cell, target.cell)
	if direction == Vector2i.ZERO:
		return false
	var extreme: bool = _is_extreme(caster)
	# §23 极意: the area expands. The bonus is a constant beside the mechanic
	# rather than a data field because the plan gives no number to put in data.
	var width: int = skill.shape_width + (EXTREME_SHAPE_WIDTH_BONUS if extreme else 0)
	var depth: int = skill.shape_depth + (EXTREME_SHAPE_DEPTH_BONUS if extreme else 0)
	var cells: Dictionary = _rectangle_cells(battle, caster.cell, direction, width, depth)
	var targets: Array = _actors_in_cells(battle, cells)
	if targets.is_empty():
		return false
	if not battle.ap.spend(skill.ap_cost):
		return false

	var was_marked: Dictionary = {}
	for actor in targets:
		was_marked[actor.actor_id] = battle.statuses.has_status(actor.actor_id, PETAL_MARK)

	var kills: int = _apply_segments(battle, caster, skill, targets, "sakura_falling_petals")
	for actor in targets:
		if actor.is_alive():
			_apply_petal_mark(battle, caster, actor)
	if extreme:
		_consume_extreme(battle, caster)
	gain_intent_from_action(battle, caster)
	_credit_kills(battle, kills)
	# §13: same per-turn ultimate-energy grant as every other active action.
	SkillExecutorScript.gain_active_energy(battle, caster.actor_id)
	# §21 / §23: 极意 raises the echo return against already-marked targets.
	var echo_multiplier: float = EXTREME_ECHO_MULTIPLIER if extreme else ECHO_RETURN_MULTIPLIER
	for actor in targets:
		if actor.is_alive() and bool(was_marked.get(actor.actor_id, false)):
			_check_echo_return(battle, caster, actor, echo_multiplier)
	battle._emit_event("skill_resolved", caster.actor_id, target_actor_id, "skill=sakura_falling_petals cells=%d targets=%d extreme=%s" % [cells.size(), targets.size(), str(extreme)])
	battle._check_battle_end()
	return true


## The orthogonal direction the cast is aimed at; ties go to the larger axis.
static func _direction_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var delta: Vector2i = to - from
	if delta == Vector2i.ZERO:
		return Vector2i.ZERO
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))


## Rectangular footprint in front of the caster. With an even width the cast axis
## is the first column rather than the middle, because a two-wide block cannot be
## centred on a single line - documented so the asymmetry is deliberate.
static func _rectangle_cells(battle, origin: Vector2i, direction: Vector2i, width: int, depth: int) -> Dictionary:
	var cells: Dictionary = {}
	var perpendicular := Vector2i(direction.y, direction.x)
	var start: int = -int((width - 1) / 2)
	for step in range(1, depth + 1):
		var row_origin: Vector2i = origin + direction * step
		for offset in range(start, start + width):
			var cell: Vector2i = row_origin + perpendicular * offset
			if GridRulesScript.is_inside_bounds(cell, battle.grid_size):
				cells[cell] = true
	return cells


## §24 无尽芳华: cross around the caster, three 20% cuts and a 40% finisher that
## each blade-intent stack lifts by 5%, plus 20% at full stacks.
static func _endless_fragrance(battle, skill, _target_actor_id: String = "") -> bool:
	var caster = battle.get_active_character()
	if not _can_cast(battle, caster, skill):
		return false
	# Releasing an ultimate spends the whole pool; the pool's size is a character
	# property, so Sakura and Sevrin can differ without touching this branch.
	var energy_cost: int = caster.ultimate_energy_max
	if caster.ultimate_energy < energy_cost:
		return false
	var targets := _cross_targets(battle, caster, skill.max_range)
	if targets.is_empty():
		return false
	if not battle.ap.spend(skill.ap_cost):
		return false
	if not caster.spend_ultimate_energy(energy_cost):
		battle.ap.refund(skill.ap_cost)
		return false

	var multipliers := _ultimate_multipliers(skill, caster)
	var last_index: int = multipliers.size() - 1
	var kills: int = 0
	for hit_index in range(multipliers.size()):
		for target in targets:
			if not target.is_alive():
				continue
			var raw_damage: int = CombatMathScript.calculate_raw_damage(caster.attack, multipliers[hit_index])
			var action_id := "sakura_endless_fragrance_finisher" if hit_index == last_index else "sakura_endless_fragrance"
			battle._apply_damage(target.actor_id, raw_damage, caster.actor_id, action_id, String(skill.damage_type))
			# Only the hit that lands the killing blow counts, so a target already
			# dead from an earlier segment is not counted again.
			if not target.is_alive():
				kills += 1
	gain_intent_from_action(battle, caster)
	_credit_kills(battle, kills)
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

## Whether the aim itself is legal: range and line of sight, before AP, energy or
## resource are considered. The target ring and the cast both call this, so the
## highlight can never promise a shot the controller then refuses - and a skill
## that forgets one of the two checks cannot silently pass it.
##
## Three aim shapes, because they are genuinely different:
##  - A rectangle (FAN) is aimed by direction, not at a point. A three-wide row
##    cannot sit on a single line, so only its centre lane has to be clear.
##  - A dash needs a straight orthogonal lane: the landing walk steps along one
##    axis, so a diagonal target three cells out would spend the AP and stop two
##    cells short of striking anything.
##  - Everything else needs a clear straight line to the target (45 degrees
##    included). Adjacent targets skip it - nothing can stand in between.
static func can_aim(battle, skill, target) -> bool:
	var caster = battle.get_active_character()
	if caster == null or target == null or not target.is_alive():
		return false
	var distance: int = GridRulesScript.manhattan_distance(caster.cell, target.cell)
	if distance < skill.min_range or distance > skill.max_range:
		return false
	if skill.shape == SkillDefinitionScript.SHAPE_FAN:
		# Same footprint the cast will use, so the ring cannot promise an expanded
		# rectangle whose lane is actually blocked.
		var shape_depth: int = skill.shape_depth + (EXTREME_SHAPE_DEPTH_BONUS if _is_extreme(caster) else 0)
		return _centre_lane_clear(battle, caster, target, shape_depth)
	if distance <= 1:
		return true
	if String(skill.executor_id) == "sakura_flowing_wind":
		return GridRulesScript.has_clear_orthogonal_line(
			caster.cell, target.cell, battle.blocked_cells, battle.get_occupied_cells(caster.actor_id))
	return GridRulesScript.has_clear_line_of_sight(
		caster.cell, target.cell, battle.blocked_cells, battle.get_occupied_cells(caster.actor_id))


## A rectangle is cast through the cell in front of the caster, so only that lane
## has to be open. Checking every hit cell instead would refuse the whole skill
## whenever one corner sat behind a wall, and a three-wide block has no single
## line to begin with.
static func _centre_lane_clear(battle, caster, target, depth: int) -> bool:
	var direction: Vector2i = _direction_toward(caster.cell, target.cell)
	if direction == Vector2i.ZERO:
		return false
	for step in range(1, depth + 1):
		var cell: Vector2i = caster.cell + direction * step
		if not GridRulesScript.is_inside_bounds(cell, battle.grid_size):
			break
		if battle.blocked_cells.has(cell):
			return false
	return true


## Whether the active character's sheet lists this skill. Ownership is data, so a
## character cannot borrow another kit by naming its skill id.
static func _owns_skill(battle, skill_id: StringName) -> bool:
	var caster = battle.get_active_character()
	if caster == null:
		return false
	var sheet = CharacterCatalogScript.get_definition(String(caster.character_id))
	if sheet == null:
		return false
	return sheet.skill_ids.has(skill_id)


static func _living_enemies(battle) -> int:
	var living: int = 0
	for actor in battle.actors.values():
		if actor.team == "enemy" and actor.is_alive():
			living += 1
	return living


## §19: one stack per enemy defeated, inside the same per-turn action budget as
## movement and attacks. Called between the damage and the echo return, because
## §30 orders the defeat step before the echo step.
static func _credit_kills(battle, kills: int) -> void:
	var caster = battle.get_active_character()
	if caster == null or not caster.has_resource() or kills <= 0:
		return
	gain_intent_from_action(battle, caster, kills, "kill")


## §19: 极意 is simply the full-intent state, so there is no separate flag to keep
## in sync with the resource.
static func _is_extreme(caster) -> bool:
	return caster != null and caster.has_resource() and caster.is_resource_full()


## §19: using an enhanced active skill consumes the whole bar. Called before the
## normal gain of this action, so the stacks earned by the action itself survive.
static func _consume_extreme(battle, caster) -> void:
	var consumed: int = caster.resource_current
	if consumed <= 0:
		return
	caster.spend_resource(consumed)
	battle._emit_event("resource_consumed", caster.actor_id, caster.actor_id, "resource=%s value=%d reason=extreme" % [String(caster.resource_id), consumed])


static func _can_cast(battle, caster, skill) -> bool:
	if caster == null or not caster.is_alive():
		return false
	if battle.phase != battle.BattlePhase.PLAYER:
		return false
	if not battle.ap.can_spend(skill.ap_cost):
		return false
	return true


## One segment per entry in hit_multipliers, or damage_multiplier split evenly.
static func _apply_segments(battle, caster, skill, targets: Array, action_id: String) -> int:
	var multipliers: Array[float] = []
	if not skill.hit_multipliers.is_empty():
		multipliers = skill.hit_multipliers.duplicate()
	elif skill.damage_multiplier > 0.0:
		for _i in range(maxi(1, skill.hits)):
			multipliers.append(skill.damage_multiplier / float(maxi(1, skill.hits)))
	var kills: int = 0
	for multiplier in multipliers:
		for target in targets:
			if not target.is_alive():
				continue
			if _apply_one_hit(battle, caster, target, multiplier, action_id, String(skill.damage_type)):
				kills += 1
	return kills


## One segment at an explicit multiplier, for hits that are not part of the
## skill's own segment list (极意's follow-up strike). Returns whether this hit
## killed the target, so the caller can order the kill credit before the echo
## return the way §30 lists them.
static func _apply_one_hit(battle, caster, target, multiplier: float, action_id: String, damage_type: String = "physical") -> bool:
	if not target.is_alive():
		return false
	var raw_damage: int = CombatMathScript.calculate_raw_damage(caster.attack, multiplier)
	battle._apply_damage(target.actor_id, raw_damage, caster.actor_id, action_id, damage_type)
	return not target.is_alive()


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
	return _actors_in_cells(battle, cells)


static func _actors_in_cells(battle, cells: Dictionary) -> Array:
	var targets: Array = []
	for actor_id in battle.actors:
		var actor = battle.actors[actor_id]
		if actor.team == "enemy" and actor.is_alive() and cells.has(actor.cell):
			targets.append(actor)
	return targets


## Walk toward the target until blocked or adjacent, at most max_range steps.
static func _dash_landing(battle, caster, target) -> Vector2i:
	var cursor: Vector2i = caster.cell
	var steps: int = FLOWING_WIND_DASH_STEPS
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
## Returns whether the follow-up landed the killing blow, so the caller can
## assert on it; the kill stack itself is paid here, because a defeat is a defeat
## whichever step produced it.
static func _check_echo_return(battle, caster, target, multiplier: float = ECHO_RETURN_MULTIPLIER) -> bool:
	if not target.is_alive():
		return false
	if not battle.statuses.has_status(target.actor_id, PETAL_MARK):
		return false
	if GridRulesScript.manhattan_distance(caster.cell, target.cell) != 1:
		return false
	var raw_damage: int = CombatMathScript.calculate_raw_damage(caster.attack, multiplier)
	battle._apply_damage(target.actor_id, raw_damage, caster.actor_id, "sakura_echo_return", "physical")
	var killed: bool = not target.is_alive()

	# §19 / §30: a defeat inside the echo step is still a defeat, so its stack is
	# paid before the first-echo stack - and both share the per-turn budget, which
	# is why the echo stack can still come up empty after this.
	if killed:
		_credit_kills(battle, 1)

	# §19: the first echo return of a turn is worth one more stack.
	if int(battle.echo_return_gain_turn.get(caster.actor_id, -1)) != battle.turn_number:
		battle.echo_return_gain_turn[caster.actor_id] = battle.turn_number
		gain_intent_from_action(battle, caster)
	battle._emit_event("counter_resolved", caster.actor_id, target.actor_id, "skill=sakura_echo_return multiplier=%.2f raw=%d killed=%s" % [multiplier, raw_damage, str(killed)])
	return killed


## §19: action events share a three-stack budget per turn; the turn-start stack
## is granted separately by the flow.
static func gain_intent_from_action(battle, caster, amount: int = INTENT_PER_ACTION_EVENT, reason: String = "action") -> void:
	if caster == null or not caster.has_resource():
		return
	if int(battle.resource_gain_turn.get(caster.actor_id, -1)) != battle.turn_number:
		battle.resource_gain_turn[caster.actor_id] = battle.turn_number
		battle.resource_gain_count[caster.actor_id] = 0
	var used: int = int(battle.resource_gain_count.get(caster.actor_id, 0))
	if used >= INTENT_ACTION_BUDGET:
		return
	var granted: int = mini(amount, INTENT_ACTION_BUDGET - used)
	var before: int = caster.resource_current
	caster.gain_resource(granted)
	battle.resource_gain_count[caster.actor_id] = used + granted
	# The budget is spent by the attempt, but a full bar absorbs the stack - so the
	# event only fires when the number actually moved. Reporting "gained" for a
	# grant the ceiling swallowed made a capped kill look like it had paid.
	if caster.resource_current == before:
		return
	battle._emit_event("resource_gained", caster.actor_id, caster.actor_id, "resource=%s reason=%s value=%d" % [String(caster.resource_id), reason, caster.resource_current])
