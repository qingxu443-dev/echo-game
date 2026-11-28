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
const HazardFieldScript = preload("res://scripts/battle/hazard_field.gd")
const IntentResolverScript = preload("res://scripts/battle/intent_resolver.gd")
const CharacterSkillRuntimeScript = preload("res://scripts/battle/character_skill_runtime.gd")
const BattleIntentScript = preload("res://scripts/battle/battle_intent.gd")
const SummonCatalogScript = preload("res://scripts/battle/summon_catalog.gd")
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")
const SkillRegistryScript = preload("res://scripts/battle/skill_registry.gd")
const RunStateScript = preload("res://scripts/battle/run_state.gd")

## Maximum straight-line steps for one player move action. The UI reads this
## constant so the movement-range rule has a single source of truth.
const PLAYER_MOVE_MAX_STEPS: int = 2

## DEPLOY is appended rather than prepended so the three existing constants keep
## their values: a few tests and save-ish payloads compare them by number.
enum BattlePhase { PLAYER, ENEMY, FINISHED, DEPLOY }

@export var grid_size: Vector2i = Vector2i(8, 8)
## Team-wide AP pool (design plan §4): five points shared by the whole party per
## player turn, not five per character. One ledger, drawn down by whichever
## character acts. Unspent points are discarded at end of turn.
@export var team_ap: int = 3

var phase: BattlePhase = BattlePhase.FINISHED
var ap: APBudget
var actors: Dictionary = {}
var blocked_cells: Dictionary = {}
## Destructible Relic Chests: cell -> {"id", "cell", "health", "max_health", "opened", "loot"}
var beacons: Dictionary = {}
## Equipment dropped onto tiles when an enemy carrying stolen gear dies: cell -> Array[Dictionary]
var dropped_loot: Dictionary = {}
## Ground hazards (凋零 / 残春): cell -> {"kind", "cell", "damage", "damage_type",
## "owner_id", "expires_turn"}. They never hold a cell - movement and line of
## sight read `blocked_cells`, not this table - so a hazard can only ever hurt.
var hazards: Dictionary = {}
## 11.1 部署阶段: the cells the player may place characters on, the roster order
## they are placed in, and how many have been placed. Empty when the encounter
## skips deployment.
var deploy_zone: Array[Vector2i] = []
var deploy_order: Array[String] = []
var deploy_index: int = 0
var intents: Array = []
var event_sequence: int = 0
var turn_number: int = 0
var battle_result: String = ""
## Settlement tallies for the end-of-battle panel. Reset on every encounter.
var damage_dealt: int = 0
var damage_taken: int = 0
var enemies_defeated: int = 0
var statuses: BattleStatusCollection = StatusCollectionScript.new()
## Transient synchronous state for Dest Lee multi-hit and death-ember batches.
var dest_lee_batch_depth: int = 0
var dest_lee_death_queue: Array[Dictionary] = []
var dest_lee_chain_active: bool = false
var dest_lee_chain_hit_targets: Dictionary = {}
## Which party member the player is currently commanding. Skills resolve their
## caster from here, so adding a character never means hardcoding an actor id.
var active_character_id: String = ""
## 单场战斗的机制记账（护盾 / 誓约 / 绝对防御 / 职业资源 / 召唤 / 地格 / 免费移动）。
## 字段与键语义见 BattleLedger；controller 自身不再平铺这些字典。
var ledger: BattleLedger = BattleLedger.new()
## Optional roguelite RunState attached by BattleView (persists HP & mods across levels).
var run_state: RunStateScript = null


func _ready() -> void:
	ap = APBudgetScript.new(team_ap)
	ap.on_spend = Callable(self, "_on_ap_spent")


func _on_ap_spent(amount: int) -> void:
	if phase != BattlePhase.PLAYER or amount <= 0:
		return
	for actor_id in actors:
		var unit = actors[actor_id]
		if unit.team != "enemy" or not unit.is_alive() or unit.skill_charge_max <= 0:
			continue
		var before: int = unit.skill_charge
		unit.skill_charge = mini(unit.skill_charge_max, unit.skill_charge + amount)
		if unit.skill_charge != before:
			_emit_event("enemy_skill_charged", String(actor_id), "", "charge=%d/%d" % [unit.skill_charge, unit.skill_charge_max])


# --- encounter ---------------------------------------------------------------

func start_encounter(
	player_cell: Vector2i,
	enemy_cells: Array[Vector2i],
	obstacles: Array[Vector2i] = [],
	enemy_archetypes: Array[String] = [],
	character_ids: Array[String] = [],
	ally_cells: Array[Vector2i] = [],
	chest_items: Array[StringName] = [],
	ward_nodes: int = 0,
	deploy_zone_cells: Array[Vector2i] = [],
	defer_start: bool = false, enemy_stat_multiplier: float = 1.0
) -> bool:
	return BattleFlowScript.start_encounter(self, player_cell, enemy_cells, obstacles, enemy_archetypes, character_ids, ally_cells, chest_items, ward_nodes, deploy_zone_cells, defer_start, enemy_stat_multiplier)


func end_player_turn() -> bool:
	return BattleFlowScript.end_player_turn(self)


# --- 11.1 deployment ---------------------------------------------------------

func is_deploy_cell(cell: Vector2i) -> bool:
	return deploy_zone.has(cell)


func all_deployed() -> bool:
	return not deploy_order.is_empty() and deploy_index >= deploy_order.size()


## Places the next undeployed character on `cell`, or slides the last placed one
## there: §11.1 allows adjusting before confirming.
func request_deploy(cell: Vector2i) -> bool:
	return BattleFlowScript.request_deploy(self, cell)


## §11.1 "点击确认部署后才正式开始战斗".
func request_begin_battle() -> bool:
	return BattleFlowScript.request_begin_battle(self)


# --- read-only queries -------------------------------------------------------

## Cells that block line of sight. Split from `get_occupied_cells` because
## §15.2 says the 春之结界 nodes "阻挡移动但不阻挡视线": they hold their cell, so
## nobody can walk through, but an archer can still shoot across one. Everything
## else that holds a cell - actors, walls, relic chests - blocks both.
func get_sight_blockers(exclude_actor_id: String = "") -> Dictionary:
	var blockers: Dictionary = blocked_cells.duplicate()
	for actor_id in actors:
		var actor = actors[actor_id]
		if actor_id != exclude_actor_id and actor.blocks_cell():
			blockers[actor.cell] = actor_id
	for b_cell in beacons:
		var b: Dictionary = beacons[b_cell]
		if int(b.get("health", 0)) > 0 and bool(b.get("blocks_sight", true)):
			blockers[b_cell] = str(b["id"])
	return blockers


func get_occupied_cells(exclude_actor_id: String = "") -> Dictionary:
	var occupied: Dictionary = {}
	for actor_id in actors:
		var actor = actors[actor_id]
		# §12: a downed body still holds its cell, so it blocks movement.
		if actor_id != exclude_actor_id and actor.blocks_cell():
			occupied[actor.cell] = actor_id
	for b_cell in beacons:
		var b: Dictionary = beacons[b_cell]
		if int(b.get("health", 0)) > 0:
			occupied[b_cell] = str(b["id"])
	return occupied


func alive_beacons() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for b_cell in beacons:
		var b: Dictionary = beacons[b_cell]
		if int(b.get("health", 0)) > 0:
			list.append(b)
	return list


func damage_beacon_at(cell: Vector2i, amount: int, source_actor_id: String, action_id: String, use_amount_for_chests: bool = false) -> bool:
	if not beacons.has(cell):
		return false
	var b: Dictionary = beacons[cell]
	if int(b.get("health", 0)) <= 0:
		return false
	var dmg: int = maxi(1, amount) if use_amount_for_chests or str(b.get("kind", "")) == "ward_node" else 1
	b["health"] = maxi(0, int(b["health"]) - dmg)
	beacons[cell] = b
	_emit_event("beacon_damaged", source_actor_id, str(b["id"]), "action=%s cell=%s applied=%d health=%d" % [action_id, str(cell), dmg, int(b["health"])])
	if int(b["health"]) <= 0:
		_emit_event("beacon_destroyed", source_actor_id, str(b["id"]), "cell=%s" % str(cell))
		# 春之结界 (§15.2): breaking a node permanently cancels the defense it
		# lent its boss. The bonus is tracked on the node, not recomputed from a
		# node count, so two destroyed nodes cannot subtract three times.
		var ward_defense: int = int(b.get("ward_defense", 0))
		if ward_defense > 0:
			var owner_id := str(b.get("owner_id", ""))
			var owner = get_actor(owner_id)
			if owner != null:
				owner.defense = maxi(0, owner.defense - ward_defense)
				preload("res://scripts/battle/tactical_pressure.gd").on_ward_node_destroyed(self, owner_id)
				_emit_event("ward_defense_lost", owner_id, str(b["id"]), "defense=%d" % owner.defense)
		var breaker = get_actor(source_actor_id)
		if breaker != null and breaker.team == "player":
			# Player slammed an enemy into the chest and cracked it open -> drop loot on the tile!
			var loot: Dictionary = b.get("loot", {})
			if not loot.is_empty():
				if not dropped_loot.has(cell):
					dropped_loot[cell] = []
				dropped_loot[cell].append(loot.duplicate(true))
				_emit_event("loot_dropped", source_actor_id, str(b["id"]), "撞开掉落「%s」" % str(loot.get("name", "战利品")))
		else:
			_grant_chest_buff_to_enemy(source_actor_id, b)
	return true


## §15.2 春之结界: two destructible nodes beside the boss. Each one holds a cell
## (so it blocks movement - the beacon table is the only cell-holding object the
## battle layer has) and lends its boss `WARD_NODE_DEFENSE` while it stands.
## Nodes never act, never drop loot, and are not re-spawned after destruction.
const WARD_NODE_HEALTH: int = 700
const WARD_NODE_DEFENSE: int = 80

func spawn_ward_nodes(count: int = 2, health: int = WARD_NODE_HEALTH, defense_bonus: int = WARD_NODE_DEFENSE) -> int:
	var boss = null
	for actor_id in actors:
		var candidate = actors[actor_id]
		if candidate.team == "enemy" and candidate.is_alive() and int(candidate.tier) == 2:
			boss = candidate
			break
	if boss == null:
		return 0
	var occupied: Dictionary = get_occupied_cells()
	var candidates: Array[Vector2i] = [
		boss.cell + Vector2i(-2, 0), boss.cell + Vector2i(2, 0), boss.cell + Vector2i(-1, -1), boss.cell + Vector2i(1, -1),
		boss.cell + Vector2i(-2, 1), boss.cell + Vector2i(2, 1), boss.cell + Vector2i.LEFT, boss.cell + Vector2i.RIGHT,
		boss.cell + Vector2i.UP, boss.cell + Vector2i.DOWN,
	]
	var placed: int = 0
	for cell in candidates:
		if placed >= count:
			break
		if not GridRulesScript.is_inside_bounds(cell, grid_size):
			continue
		if blocked_cells.has(cell) or occupied.has(cell) or beacons.has(cell):
			continue
		beacons[cell] = {
			"id": "ward_node_%02d" % placed,
			"cell": cell,
			"health": health,
			"max_health": health,
			"opened": false,
			"loot": {},
			"kind": "ward_node",
			# §15.2: the node blocks movement but not sight.
			"blocks_sight": false,
			# The boss must not treat its own nodes as objectives.
			"enemy_objective": false,
			"ward_defense": defense_bonus,
			"owner_id": boss.actor_id,
		}
		boss.defense += defense_bonus
		placed += 1
		_emit_event("ward_node_spawned", boss.actor_id, "ward_node_%02d" % (placed - 1), "cell=%s defense=%d" % [str(cell), boss.defense])
	return placed


func _grant_chest_buff_to_enemy(source_actor_id: String, chest: Dictionary) -> void:
	var loot: Dictionary = chest.get("loot", {})
	if loot.is_empty():
		return
	var recipient = get_actor(source_actor_id)
	if recipient == null or recipient.team != "enemy" or not recipient.is_alive():
		for aid in actors:
			var a = actors[aid]
			if a.team == "enemy" and a.is_alive():
				recipient = a
				break
	if recipient == null:
		return

	var kind: String = str(loot.get("kind", ""))
	var item_name: String = str(loot.get("name", "宝箱物品"))
	# The catalogue's enemy_* columns are the single authority for what a
	# chest gives an enemy (the catalogue is where numbers live, not a code
	# path). The player-side stats are deliberately not reused: the enemy
	# variants are tuned separately - armor becomes shield, the dusk blade
	# loses its defense penalty, and each upgrade carries its own numbers.
	recipient.attack = maxi(1, recipient.attack + int(loot.get("enemy_attack", 0)) * 2)
	var add_shield: int = int(loot.get("enemy_shield", 0)) * 2
	if add_shield > 0:
		recipient.shield = mini(recipient.max_health, recipient.shield + add_shield)
	var add_heal: int = int(loot.get("enemy_heal", 0)) * 2
	if add_heal > 0:
		recipient.health = mini(recipient.max_health, recipient.health + add_heal)
	if bool(loot.get("enemy_charge", false)) and recipient.skill_charge_max > 0:
		recipient.skill_charge = recipient.skill_charge_max
	var verb: String = "吸收了"
	if kind == "weapon" or kind == "armor":
		# Equipped pieces drop back onto the ground when the wearer dies.
		recipient.stolen_equipment.append(loot.duplicate(true))
		verb = "装备了"
	elif kind == "consumable":
		verb = "使用了"
	_emit_event("chest_stolen_by_enemy", recipient.actor_id, str(chest.get("id", "")), "%s「%s」" % [verb, item_name])


## Only weapon/armor equipment drops onto the ground when an enemy is defeated.
func drop_enemy_equipment(enemy) -> void:
	if enemy == null or enemy.stolen_equipment.is_empty():
		return
	var cell: Vector2i = enemy.cell
	if not dropped_loot.has(cell):
		dropped_loot[cell] = []
	var names: Array[String] = []
	for item in enemy.stolen_equipment:
		var kind: String = str(item.get("kind", ""))
		if kind == "weapon" or kind == "armor":
			dropped_loot[cell].append(item.duplicate(true))
			names.append(str(item.get("name", "装备")))
	enemy.stolen_equipment.clear()
	if not names.is_empty():
		_emit_event("loot_dropped", enemy.actor_id, "", "掉落「%s」" % "、".join(names))


func pickup_dropped_loot_at(cell: Vector2i) -> Array[Dictionary]:
	if not dropped_loot.has(cell):
		return []
	var items: Array = dropped_loot[cell]
	dropped_loot.erase(cell)
	var picked: Array[Dictionary] = []
	for item in items:
		if run_state != null:
			run_state.add_to_backpack(item)
		picked.append(item)
		_emit_event("loot_picked_up", active_character_id, "", str(item.get("name", "装备")))
	return picked


## Collect any intact chests and uncollected ground equipment on victory.
func collect_remaining_chests() -> Array[Dictionary]:
	var claimed: Array[Dictionary] = []
	for cell in beacons:
		var b: Dictionary = beacons[cell]
		# 结界节点 are not chests: they carry no loot and must not be reported as
		# "saved" in the settlement summary.
		if str(b.get("kind", "")) == "ward_node":
			continue
		if int(b.get("health", 0)) > 0 and not bool(b.get("opened", false)):
			b["health"] = 0
			b["opened"] = true
			beacons[cell] = b
			var loot: Dictionary = b.get("loot", {})
			if not loot.is_empty():
				if run_state != null:
					run_state.add_to_backpack(loot)
				claimed.append(loot)
	for drop_cell in dropped_loot.keys():
		for item in dropped_loot[drop_cell]:
			if run_state != null:
				run_state.add_to_backpack(item)
			claimed.append(item)
	dropped_loot.clear()
	return claimed


func start_enemy_phase_stepped() -> bool:
	return BattleFlowScript.start_enemy_phase_stepped(self)


func resolve_next_enemy_intent() -> bool:
	return BattleFlowScript.resolve_next_enemy_intent(self)


func finish_enemy_phase_stepped() -> void:
	BattleFlowScript.finish_enemy_phase_stepped(self)


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


## Living, non-downed party members in a stable order, for the switch control.
func get_switchable_characters() -> Array[String]:
	var ids: Array[String] = []
	for actor_id in actors:
		var actor = actors[actor_id]
		if actor.team == "player" and actor.is_alive():
			ids.append(String(actor_id))
	return ids


func get_oath_vow_stacks(actor_id: String = "") -> int:
	# Defaulting to the commanded character rather than a fixed id: with a party,
	# "whose vow" must never be inferred from who the prototype used to have.
	var target_id: String = actor_id if not actor_id.is_empty() else active_character_id
	var vow = statuses.get_status(target_id, &"oath_vow")
	return 0 if vow == null else vow.stacks


## Whether a unit carries a given passive. Used where a mechanic belongs to the
## character rather than to the status: Oath Vow accumulation follows the unit
## that actually has the passive, so a character without it never accumulates.
func has_passive(actor_id: String, passive_id: StringName) -> bool:
	if not actors.has(actor_id):
		return false
	var unit = actors[actor_id]
	if unit.team != "player" or unit.character_id == &"":
		return false
	var definition = CharacterCatalogScript.get_definition(String(unit.character_id))
	if definition == null:
		return false
	for skill_id in definition.skill_ids:
		if skill_id != passive_id:
			continue
		var skill = SkillRegistryScript.get_skill(skill_id)
		return skill != null and skill.is_passive
	return false


## Whoever currently holds the Absolute Guard stance. The status is the authority,
## not a character id, so the taunt works for any unit that can cast it.
func get_absolute_guardian() -> String:
	for actor_id in actors:
		var actor = actors[actor_id]
		if actor.team == "player" and actor.is_alive() and statuses.has_status(String(actor_id), &"absolute_guard"):
			return String(actor_id)
	return ""


func get_oathkeeper_marked_target() -> String:
	return SkillExecutorScript.marked_target(self)


# --- player actions ----------------------------------------------------------

func request_player_move(path: Array[Vector2i]) -> bool:
	var mover = get_active_character()
	if phase != BattlePhase.PLAYER or mover == null:
		return false
	var free_stride: bool = run_state != null and run_state.has_mod(&"echo_stride") and ledger.free_move_used_turn != turn_number
	var move_cost: int = 0 if free_stride else 1
	if not mover.is_alive() or not ap.can_spend(move_cost):
		return false
	if not GridRulesScript.is_path_legal(mover.cell, path, grid_size, blocked_cells, get_occupied_cells(mover.actor_id), PLAYER_MOVE_MAX_STEPS):
		_emit_event("action_rejected", mover.actor_id, "", "invalid_move")
		return false
	if move_cost > 0 and not ap.spend(move_cost):
		return false
	if free_stride:
		ledger.free_move_used_turn = turn_number
	mover.cell = path[path.size() - 1]
	pickup_dropped_loot_at(mover.cell)
	# 凋零 / 残春 punish walking onto a tile, on top of whatever the player spent
	# to get here. `trigger_for` owns the once-per-turn rule, so a two-step move
	# across two hazard tiles still hurts exactly once.
	HazardFieldScript.trigger_for(self, mover)
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
func request_skill(skill_id: StringName, target_actor_id: String = "", target_cell: Vector2i = Vector2i(-1, -1)) -> bool:
	return CharacterSkillRuntimeScript.request(self, skill_id, target_actor_id, target_cell)


## §14 樱华蓄斩: break a telegraphed charged strike that the sheet marks as
## interruptible. Control is expressed as this call - a dash that slams into the
## swordsman, a knockback that moves him - and the charge bar pays for it, so the
## elite needs three more AP of pressure before it can wind up again. Returns
## false when there was nothing to interrupt, so callers can log a plain hit.
func interrupt_enemy_charge(actor_id: String, reason: String) -> bool:
	if actor_id.is_empty():
		return false
	for intent in intents:
		if intent.source_actor_id != actor_id or intent.state != BattleIntentScript.IntentState.ACTIVE:
			continue
		if not intent.interruptible:
			continue
		intent.cancel("interrupted")
		var source = actors.get(actor_id)
		if source != null and source.skill_charge_max > 0:
			source.skill_charge = 0
		_emit_event("enemy_skill_interrupted", actor_id, "", "action=%s reason=%s" % [intent.action_id, reason])
		return true
	return false


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


## Kept as a thin facade because the controller test drives the taunt through it.
## The target is the current Absolute Guard holder, not a fixed character.
func _redirect_single_target_intent_to_guardian(intent) -> void:
	IntentResolverScript.redirect_to_guardian(self, intent, get_absolute_guardian())


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
