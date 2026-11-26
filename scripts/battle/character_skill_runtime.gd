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

	return _dispatch(battle, skill, target_actor_id)


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
