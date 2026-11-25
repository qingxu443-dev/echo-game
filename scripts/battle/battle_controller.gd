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
const AreaEffectCollectionScript = preload("res://scripts/battle/battle_area_effect_collection.gd")
const BattleFlowScript = preload("res://scripts/battle/battle_flow.gd")
const SkillExecutorScript = preload("res://scripts/battle/skill_executor.gd")
const SummonServiceScript = preload("res://scripts/battle/summon_service.gd")
const DamagePipelineScript = preload("res://scripts/battle/damage_pipeline.gd")
const IntentResolverScript = preload("res://scripts/battle/intent_resolver.gd")

## Hunter summon: a free support strike on a cooldown. The hunter is not a
## battlefield unit -- it appears next to the chosen enemy, strikes once and is
## gone, so it never occupies a cell, never appears in the intent order and can
## never be targeted. Values are prototype baselines pending playtesting.
const HUNTER_SUMMON_ATTACK: int = 1400
const HUNTER_SUMMON_MULTIPLIER: float = 0.9
const HUNTER_SUMMON_COOLDOWN_TURNS: int = 2

enum BattlePhase { PLAYER, ENEMY, FINISHED }

@export var grid_size: Vector2i = Vector2i(8, 8)
@export var player_ap: int = 3

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
## Turn number the hunter summon was last used on. -1 means "not yet used".
var summon_last_used_turn: int = -1
var statuses: BattleStatusCollection = StatusCollectionScript.new()
var area_effects: BattleAreaEffectCollection = AreaEffectCollectionScript.new()
## actor_id -> player turn number after which the oath shield expires.
var oath_shield_expiry_turn: Dictionary = {}
## Enemy intent IDs already counted by Oath Vow; prevents multi-hit actions stacking repeatedly.
var oath_vow_triggered_intents: Dictionary = {}
## Intent IDs whose public attack action successfully hit Sevrin during Absolute Guard.
var absolute_guard_hit_intents: Dictionary = {}
## Enemy actor IDs that have already been countered during the current player turn.
var absolute_guard_countered_enemies: Dictionary = {}


func _ready() -> void:
	ap = APBudgetScript.new(player_ap)


# --- encounter ---------------------------------------------------------------

func start_encounter(
	player_cell: Vector2i,
	enemy_cells: Array[Vector2i],
	obstacles: Array[Vector2i] = [],
	enemy_archetypes: Array[String] = []
) -> bool:
	return BattleFlowScript.start_encounter(self, player_cell, enemy_cells, obstacles, enemy_archetypes)


func end_player_turn() -> bool:
	return BattleFlowScript.end_player_turn(self)


# --- read-only queries -------------------------------------------------------

func get_occupied_cells(exclude_actor_id: String = "") -> Dictionary:
	var occupied: Dictionary = {}
	for actor_id in actors:
		var actor = actors[actor_id]
		if actor_id != exclude_actor_id and actor.is_alive():
			occupied[actor.cell] = actor_id
	return occupied


func get_actor(actor_id: String):
	return actors.get(actor_id)


func get_oath_vow_stacks(actor_id: String = "sevrin") -> int:
	var vow = statuses.get_status(actor_id, &"oath_vow")
	return 0 if vow == null else vow.stacks


func get_oathkeeper_marked_target() -> String:
	return SkillExecutorScript.marked_target(self)


# --- player actions ----------------------------------------------------------

func request_player_move(path: Array[Vector2i]) -> bool:
	if phase != BattlePhase.PLAYER or not actors.has("sevrin"):
		return false
	var player = actors["sevrin"]
	if not player.is_alive() or not ap.can_spend(1):
		return false
	if not GridRulesScript.is_path_legal(player.cell, path, grid_size, blocked_cells, get_occupied_cells("sevrin"), 2):
		_emit_event("action_rejected", "sevrin", "", "invalid_move")
		return false
	if not ap.spend(1):
		return false
	player.cell = path[path.size() - 1]
	SkillExecutorScript.gain_active_energy(self, "sevrin")
	_emit_event("actor_moved", "sevrin", "", str(player.cell))
	_check_battle_end()
	return true


func request_absolute_guard() -> bool:
	return SkillExecutorScript.absolute_guard(self)


func request_oath_shield(target_actor_id: String) -> bool:
	return SkillExecutorScript.oath_shield(self, target_actor_id)


func request_oathkeeper_judgment_mark(target_actor_id: String) -> bool:
	return SkillExecutorScript.judgment_mark_v2(self, target_actor_id)


func request_player_attack(target_actor_id: String, damage_multiplier: float = 1.0) -> bool:
	return SkillExecutorScript.player_attack(self, target_actor_id, damage_multiplier)


func request_oathguard_stance(caster_actor_id: String = "sevrin") -> bool:
	return SkillExecutorScript.oathguard_stance(self, caster_actor_id)


func request_echo_counter(caster_actor_id: String = "sevrin") -> bool:
	return SkillExecutorScript.echo_counter(self, caster_actor_id)


func request_watchwall() -> bool:
	return SkillExecutorScript.watchwall(self)


func request_judgment_mark(target_actor_id: String) -> bool:
	return SkillExecutorScript.judgment_mark(self, target_actor_id)


func request_oath_severance(target_actor_id: String) -> bool:
	return SkillExecutorScript.oath_severance(self, target_actor_id)


# --- hunter summon -----------------------------------------------------------

func summon_cooldown_remaining() -> int:
	return SummonServiceScript.cooldown_remaining(self)


func can_summon(target_actor_id: String = "") -> bool:
	return SummonServiceScript.can_summon(self, target_actor_id)


func request_hunter_summon(target_actor_id: String) -> bool:
	return SummonServiceScript.request(self, target_actor_id)


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
