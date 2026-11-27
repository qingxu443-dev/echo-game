class_name CharacterSkillRuntime
extends RefCounted

## The entry point for "the active character uses this skill on this target",
## and nothing else.
##
## Four layers, deliberately kept apart:
##
##  - What a skill costs, how far it reaches and how many segments it has comes
##    from SkillDefinition. Changing a number is a data edit.
##  - Where it can be aimed lives in CombatGeometry, which knows about cells and
##    blockers and no design numbers.
##  - What it does lives in SkillEffects, addressed by executor_id, so a new
##    character that reuses an existing mechanic needs no code at all.
##  - Which executor runs which skill is the table below, so "does this skill
##    have an executor?" is a question a test can ask.
##
## Sevrin's kit still runs through SkillExecutor because it predates this runtime;
## SkillEffects wraps it so both characters share one signature and one entry.

const SkillRegistryScript = preload("res://scripts/battle/skill_registry.gd")
const SkillEffectsScript = preload("res://scripts/battle/skill_effects.gd")
const SkillExecutorScript = preload("res://scripts/battle/skill_executor.gd")
const SummonServiceScript = preload("res://scripts/battle/summon_service.gd")
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")
const SkillDefinitionScript = preload("res://scripts/battle/skill_definition.gd")
const TacticalPressureScript = preload("res://scripts/battle/tactical_pressure.gd")
const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")


## Single entry point. Callers press a skill id; whether it is legal, what it
## costs and what it does are all decided further down.
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

	var ward := find_ward_node(battle, target_actor_id)
	if not ward.is_empty():
		TacticalPressureScript.begin_player_action(battle)
		return _attack_ward_node(battle, skill, ward)

	TacticalPressureScript.begin_player_action(battle)
	var ok: bool = _dispatch(battle, skill, target_actor_id)
	if ok and skill.target_mode == SkillDefinitionScript.TARGET_SELF and skill.damage_multiplier > 0.0:
		_splash_ward_nodes_around_caster(battle, skill)
	return ok


static func find_ward_node(battle, target_id: String) -> Dictionary:
	if target_id.is_empty():
		return {}
	for cell in battle.beacons:
		var b: Dictionary = battle.beacons[cell]
		if str(b.get("kind", "")) == "ward_node" and int(b.get("health", 0)) > 0 and str(b.get("id", "")) == target_id:
			return b
	return {}


static func can_aim_ward_node(battle, skill, node_cell: Vector2i) -> bool:
	if battle == null or skill == null or battle.phase != battle.BattlePhase.PLAYER:
		return false
	if skill.target_mode != SkillDefinitionScript.TARGET_ACTOR or skill.damage_multiplier <= 0.0:
		return false
	var caster = battle.get_active_character()
	if caster == null or not caster.is_alive() or not battle.ap.can_spend(skill.ap_cost):
		return false
	var dist: int = GridRulesScript.manhattan_distance(caster.cell, node_cell)
	if dist < skill.min_range or dist > skill.max_range:
		return false
	if StringName(skill.executor_id) == &"sakura_flowing_wind":
		var d: Vector2i = node_cell - caster.cell
		if d.x != 0 and d.y != 0:
			return false
		var step := Vector2i(signi(d.x), signi(d.y))
		var occupied: Dictionary = battle.get_occupied_cells(caster.actor_id)
		for k in range(1, dist):
			var mid: Vector2i = caster.cell + step * k
			if battle.blocked_cells.has(mid) or occupied.has(mid):
				return false
		return true
	if dist > 1 and not GridRulesScript.has_clear_line_of_sight(caster.cell, node_cell, battle.blocked_cells, battle.get_sight_blockers(caster.actor_id)):
		return false
	return true


static func _attack_ward_node(battle, skill, ward: Dictionary) -> bool:
	var node_cell: Vector2i = ward["cell"]
	if not can_aim_ward_node(battle, skill, node_cell):
		return false
	var caster = battle.get_active_character()
	if not battle.ap.spend(skill.ap_cost):
		return false
	if StringName(skill.executor_id) == &"sakura_flowing_wind":
		var d: Vector2i = node_cell - caster.cell
		var dist: int = GridRulesScript.manhattan_distance(caster.cell, node_cell)
		if dist > 1:
			var land: Vector2i = node_cell - Vector2i(signi(d.x), signi(d.y))
			caster.cell = land
			battle._emit_event("actor_moved", caster.actor_id, "", "flowing_wind dest=%s" % str(land))
	var dmg: int = CombatMathScript.calculate_raw_damage(caster.attack, skill.damage_multiplier)
	battle.damage_beacon_at(node_cell, dmg, caster.actor_id, String(skill.skill_id))
	gain_intent_from_action(battle, caster)
	SkillExecutorScript.gain_active_energy(battle, caster.actor_id)
	battle._emit_event("attack_resolved", caster.actor_id, str(ward["id"]), "%s ap=%d" % [String(skill.skill_id), skill.ap_cost])
	battle._check_battle_end()
	return true


static func _splash_ward_nodes_around_caster(battle, skill) -> void:
	var caster = battle.get_active_character()
	if caster == null:
		return
	var dmg: int = CombatMathScript.calculate_raw_damage(caster.attack, skill.damage_multiplier)
	var radius: int = maxi(1, skill.max_range)
	for cell in battle.beacons.keys():
		var b: Dictionary = battle.beacons[cell]
		if str(b.get("kind", "")) != "ward_node" or int(b.get("health", 0)) <= 0:
			continue
		var dx: int = absi(cell.x - caster.cell.x)
		var dy: int = absi(cell.y - caster.cell.y)
		var in_shape: bool = (dx == 0 or dy == 0) and (dx + dy <= radius) if skill.shape == SkillDefinitionScript.SHAPE_CROSS else maxi(dx, dy) <= radius
		if in_shape:
			battle.damage_beacon_at(cell, dmg, caster.actor_id, String(skill.skill_id))


## executor_id -> the function that runs it. A table rather than a match so
## "does this skill have an executor?" is a question the suite can ask: it walks
## the registry and fails on any active skill whose executor is missing. Under a
## match the same mistake produced a button that returned false and said nothing.
static var _executors: Dictionary = {
	&"oathkeeper_judgment_mark": Callable(SkillEffectsScript, "_run_judgment_mark"),
	&"oath_shield": Callable(SkillEffectsScript, "_run_oath_shield"),
	&"absolute_guard": Callable(SkillEffectsScript, "_run_absolute_guard"),
	&"basic_attack": Callable(SkillEffectsScript, "_basic_attack"),
	&"sakura_pierce_blossom": Callable(SkillEffectsScript, "_pierce_blossom"),
	&"sakura_flowing_wind": Callable(SkillEffectsScript, "_flowing_wind"),
	&"sakura_falling_petals": Callable(SkillEffectsScript, "_falling_petals"),
	&"sakura_endless_fragrance": Callable(SkillEffectsScript, "_endless_fragrance"),
}


static func supports(executor_id: StringName) -> bool:
	return _executors.has(executor_id)


static func _dispatch(battle, skill, target_actor_id: String) -> bool:
	var executor_id := StringName(skill.executor_id)
	if not _executors.has(executor_id):
		# Never silently return false: the press would do nothing and the player
		# would have no way to tell a missing executor from a failed condition.
		push_error("CharacterSkillRuntime: no executor registered for '%s' (skill '%s')" % [executor_id, skill.skill_id])
		return false
	return _executors[executor_id].call(battle, skill, target_actor_id)


## Forwarded rather than reimplemented: the target ring and the cast must ask the
## same question, and the answer depends on 极意's footprint, which SkillEffects
## owns.
static func can_aim(battle, skill, target) -> bool:
	return SkillEffectsScript.can_aim(battle, skill, target)


## Forwarded for the turn flow, which grants the movement stack through the same
## per-turn budget every action event uses.
static func gain_intent_from_action(battle, caster, amount: int = SkillEffectsScript.INTENT_PER_ACTION_EVENT, reason: String = "action") -> void:
	SkillEffectsScript.gain_intent_from_action(battle, caster, amount, reason)


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
