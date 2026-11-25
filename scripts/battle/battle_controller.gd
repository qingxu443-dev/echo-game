class_name BattleController
extends Node

## Authoritative battle state, and the only entry point the UI is allowed to use.
##
## The rules themselves live in focused collaborators; this file owns the state
## they operate on and forwards to them. The public surface (request_*, getters,
## the phase enum and the signals) is unchanged from the pre-split version, which
## is what lets the whole test suite verify the split without edits.
##
##   BattleFlow        turn boundaries, encounter setup, termination
##   IntentPlanner     enemy intent generation
##   IntentResolver    enemy intent execution
##   SkillExecutor     player skill validation and resolution
##   SummonService     hunter summon
##   DamagePipeline    damage resolution and everything that reacts to a hit

signal battle_event(event: Dictionary)
signal battle_finished(result: String)

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const APBudgetScript = preload("res://scripts/battle/ap_budget.gd")
const StatusCollectionScript = preload("res://scripts/battle/battle_status_collection.gd")
const BattleFlowScript = preload("res://scripts/battle/battle_flow.gd")
const SkillExecutorScript = preload("res://scripts/battle/skill_executor.gd")
const SummonServiceScript = preload("res://scripts/battle/summon_service.gd")
const DamagePipelineScript = preload("res://scripts/battle/damage_pipeline.gd")
const IntentResolverScript = preload("res://scripts/battle/intent_resolver.gd")
const CharacterSkillRuntimeScript = preload("res://scripts/battle/character_skill_runtime.gd")
const SummonCatalogScript = preload("res://scripts/battle/summon_catalog.gd")

## Maximum straight-line steps for one player move action. The UI reads this
## constant so the movement-range rule has a single source of truth.
const PLAYER_MOVE_MAX_STEPS: int = 2

enum BattlePhase { PLAYER, ENEMY, FINISHED }

@export var grid_size: Vector2i = Vector2i(8, 8)
## Team-wide AP pool (design plan §4): five points shared by the whole party per
## player turn, not five per character. One ledger, drawn down by whichever
## character acts. Unspent points are discarded at end of turn.
@export var team_ap: int = 5

var phase: BattlePhase = BattlePhase.FINISHED
var ap: APBudget
var actors: Dictionary = {}
var blocked_cells: Dictionary = {}
var intents: Array = []
var event_sequence: int = 0
var turn_number: int = 0
var battle_result: String = ""
## Settlement tallies for the end-of-battle panel. Reset on every encounter.
var damage_dealt: int = 0
var damage_taken: int = 0
var enemies_defeated: int = 0
## summon_id -> the player turn it was last used on. Absent means "never used".
var summon_last_used_turn: Dictionary = {}
var statuses: BattleStatusCollection = StatusCollectionScript.new()
## actor_id -> player turn number after which the oath shield expires.
var oath_shield_expiry_turn: Dictionary = {}
## Enemy intent IDs already counted by Oath Vow; prevents multi-hit actions stacking repeatedly.
var oath_vow_triggered_intents: Dictionary = {}
## Intent IDs whose public attack action successfully hit Sevrin during Absolute Guard.
var absolute_guard_hit_intents: Dictionary = {}
## Enemy actor IDs that have already been countered during the current player turn.
var absolute_guard_countered_enemies: Dictionary = {}
## Which party member the player is currently commanding. Skills resolve their
## caster from here, so adding a character never means hardcoding an actor id.
var active_character_id: String = "sevrin"
## Per-character bookkeeping for class resources: which turn the action budget was
## last reset, how much of it is spent, and whether the first echo return of the
## turn has already paid out.
var resource_gain_turn: Dictionary = {}
var resource_gain_count: Dictionary = {}
var echo_return_gain_turn: Dictionary = {}


func _ready() -> void:
	ap = APBudgetScript.new(team_ap)


# --- encounter ---------------------------------------------------------------

func start_encounter(
	player_cell: Vector2i,
	enemy_cells: Array[Vector2i],
	obstacles: Array[Vector2i] = [],
	enemy_archetypes: Array[String] = [],
	character_ids: Array[String] = [],
	ally_cells: Array[Vector2i] = []
) -> bool:
	return BattleFlowScript.start_encounter(self, player_cell, enemy_cells, obstacles, enemy_archetypes, character_ids, ally_cells)


func end_player_turn() -> bool:
	return BattleFlowScript.end_player_turn(self)


# --- read-only queries -------------------------------------------------------

func get_occupied_cells(exclude_actor_id: String = "") -> Dictionary:
	var occupied: Dictionary = {}
	for actor_id in actors:
		var actor = actors[actor_id]
		# §12: a downed body still holds its cell, so it blocks movement.
		if actor_id != exclude_actor_id and actor.blocks_cell():
			occupied[actor.cell] = actor_id
	return occupied


func get_actor(actor_id: String):
	return actors.get(actor_id)


func get_active_character():
	return actors.get(active_character_id)


## Switch command to another living party member. Costs nothing: the AP pool is
## shared, so switching is a free choice about who spends it.
func set_active_character(character_id: String) -> bool:
	if not actors.has(character_id):
		return false
	var candidate = actors[character_id]
	if candidate.team != "player" or not candidate.is_alive():
		return false
	active_character_id = character_id
	return true


## Living, non-downed party members in a stable order, for the switch control.
## Which party member enemies aim at. The character the player is commanding,
## falling back to the first living one. Kept explicit so a party does not need
## enemies hardcoded to a single actor id.
func get_defender():
	var active = actors.get(active_character_id)
	if active != null and active.team == "player" and active.is_alive():
		return active
	for actor_id in actors:
		var actor = actors[actor_id]
		if actor.team == "player" and actor.is_alive():
			return actor
	return null


func get_switchable_characters() -> Array[String]:
	var ids: Array[String] = []
	for actor_id in actors:
		var actor = actors[actor_id]
		if actor.team == "player" and actor.is_alive():
			ids.append(String(actor_id))
	return ids


func get_oath_vow_stacks(actor_id: String = "sevrin") -> int:
	var vow = statuses.get_status(actor_id, &"oath_vow")
	return 0 if vow == null else vow.stacks


func get_oathkeeper_marked_target() -> String:
	return SkillExecutorScript.marked_target(self)


# --- player actions ----------------------------------------------------------

func request_player_move(path: Array[Vector2i]) -> bool:
	# The active character moves, not Sevrin: the view builds the candidate path
	# from whoever is being commanded, so validating from a fixed actor id made
	# every move by anyone else fail the adjacency check on the first step.
	var mover = get_active_character()
	if phase != BattlePhase.PLAYER or mover == null:
		return false
	if not mover.is_alive() or not ap.can_spend(1):
		return false
	if not GridRulesScript.is_path_legal(mover.cell, path, grid_size, blocked_cells, get_occupied_cells(mover.actor_id), PLAYER_MOVE_MAX_STEPS):
		_emit_event("action_rejected", mover.actor_id, "", "invalid_move")
		return false
	if not ap.spend(1):
		return false
	mover.cell = path[path.size() - 1]
	SkillExecutorScript.gain_active_energy(self, mover.actor_id)
	CharacterSkillRuntimeScript.gain_intent_from_action(self, mover)
	_emit_event("actor_moved", mover.actor_id, "", str(mover.cell))
	_check_battle_end()
	return true


func request_absolute_guard() -> bool:
	return SkillExecutorScript.absolute_guard(self)


func request_oath_shield(target_actor_id: String) -> bool:
	return SkillExecutorScript.oath_shield(self, target_actor_id)


func request_oathkeeper_judgment_mark(target_actor_id: String) -> bool:
	return SkillExecutorScript.judgment_mark_v2(self, target_actor_id)


## Single entry point for the active character. Adding a character adds data and,
## only if it invents a new mechanic, one branch in CharacterSkillRuntime.
func request_skill(skill_id: StringName, target_actor_id: String = "") -> bool:
	return CharacterSkillRuntimeScript.request(self, skill_id, target_actor_id)


# --- hunter summon -----------------------------------------------------------

func summon_cooldown_remaining(summon_id: StringName = SummonCatalogScript.DEFAULT_ID) -> int:
	return SummonServiceScript.cooldown_remaining(self, summon_id)


func can_summon(target_actor_id: String = "", summon_id: StringName = SummonCatalogScript.DEFAULT_ID) -> bool:
	return SummonServiceScript.can_summon(self, summon_id, target_actor_id)


func request_hunter_summon(target_actor_id: String) -> bool:
	return SummonServiceScript.request(self, SummonCatalogScript.DEFAULT_ID, target_actor_id)


# --- internal surface used by the collaborators and by tests ------------------

func _apply_damage(
	target_actor_id: String,
	amount: int,
	source_actor_id: String,
	action_id: String,
	damage_type: String = "physical",
	is_public_intent: bool = false,
	resolving_intent_id: String = ""
) -> void:
	DamagePipelineScript.apply(self, target_actor_id, amount, source_actor_id, action_id, damage_type, is_public_intent, resolving_intent_id)


func _begin_player_turn() -> void:
	BattleFlowScript.begin_player_turn(self)


func _expire_oath_shields_for_current_turn() -> void:
	BattleFlowScript.expire_oath_shields_for_current_turn(self)


func _check_battle_end() -> void:
	BattleFlowScript.check_battle_end(self)


func _finish_battle(result: String) -> void:
	BattleFlowScript.finish_battle(self, result)


func _redirect_single_target_intent_to_sevrin(intent) -> void:
	IntentResolverScript.redirect_to_sevrin(self, intent)


func _resolve_absolute_guard_counter(intent) -> void:
	IntentResolverScript.absolute_guard_counter(self, intent)


func _emit_event(event_type: String, actor_id: String, target_id: String, detail: String) -> void:
	event_sequence += 1
	battle_event.emit({
		"sequence": event_sequence,
		"turn": turn_number,
		"type": event_type,
		"actor_id": actor_id,
		"target_id": target_id,
		"detail": detail
	})
