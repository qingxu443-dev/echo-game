class_name BattleFlow
extends RefCounted

## Turn boundaries, encounter setup and termination.
##
## Everything that decides "whose turn is it, is the fight over, what gets reset"
## lives here. The phase enum and the battle_finished signal stay on the
## controller because tests and the view read them from there.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const BattleActorScript = preload("res://scripts/actors/battle_actor.gd")
const BattleIntentScript = preload("res://scripts/battle/battle_intent.gd")
const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")
const IntentPlannerScript = preload("res://scripts/battle/intent_planner.gd")
const IntentResolverScript = preload("res://scripts/battle/intent_resolver.gd")
const HazardFieldScript = preload("res://scripts/battle/hazard_field.gd")
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")
const LootCatalogScript = preload("res://scripts/battle/loot_catalog.gd")
const TacticalPressureScript = preload("res://scripts/battle/tactical_pressure.gd")


## Validates the whole setup before touching live state: a rejected call must
## leave the previous encounter exactly as it was.
static func start_encounter(
	battle,
	player_cell: Vector2i,
	enemy_cells: Array[Vector2i],
	obstacles: Array[Vector2i] = [],
	enemy_archetypes: Array[String] = [],
	character_ids: Array[String] = [],
	ally_cells: Array[Vector2i] = [],
	chest_items: Array[StringName] = [],
	ward_nodes: int = 0,
	deploy_zone_cells: Array[Vector2i] = [],
	defer_start: bool = false,
	enemy_stat_multiplier: float = 1.0
) -> bool:
	if battle.grid_size.x <= 0 or battle.grid_size.y <= 0 or battle.team_ap <= 0:
		return false
	if enemy_stat_multiplier <= 0.0:
		return false
	if not GridRulesScript.is_inside_bounds(player_cell, battle.grid_size):
		return false
	if enemy_cells.is_empty():
		return false
	if not enemy_archetypes.is_empty() and enemy_archetypes.size() != enemy_cells.size():
		return false
	for archetype in enemy_archetypes:
		if not EnemyCatalogScript.has_definition(archetype):
			return false

	# Deployed characters come from data. character_ids[0] takes player_cell and
	# every later one takes ally_cells[i - 1], so a roster and its cells must
	# agree in length before anything is spawned.
	var roster: Array[String] = []
	roster.append_array(character_ids)
	if roster.is_empty():
		roster.append(CharacterCatalogScript.default_id())
	if roster.size() != ally_cells.size() + 1:
		return false
	for character_id in roster:
		if not CharacterCatalogScript.has_definition(character_id):
			return false

	var spawn_cells: Array[Vector2i] = [player_cell]
	spawn_cells.append_array(ally_cells)
	var seen_cells: Dictionary = {}
	for cell in spawn_cells:
		if not GridRulesScript.is_inside_bounds(cell, battle.grid_size) or seen_cells.has(cell):
			return false
		seen_cells[cell] = true

	var candidate_blockers: Dictionary = {}
	for cell in obstacles:
		if not GridRulesScript.is_inside_bounds(cell, battle.grid_size):
			return false
		candidate_blockers[cell] = true
	for cell in spawn_cells:
		if candidate_blockers.has(cell):
			return false

	var candidate_enemy_cells: Dictionary = {}
	for cell in enemy_cells:
		if not GridRulesScript.is_inside_bounds(cell, battle.grid_size) or seen_cells.has(cell):
			return false
		if candidate_blockers.has(cell) or candidate_enemy_cells.has(cell):
			return false
		candidate_enemy_cells[cell] = true

	battle.ap.maximum = battle.team_ap
	battle.actors.clear()
	battle.beacons.clear()
	battle.dropped_loot.clear()
	battle.statuses.clear_all()
	battle.ledger.reset_for_encounter()
	TacticalPressureScript.reset_turn_tolerance(battle)
	battle.blocked_cells = candidate_blockers
	battle.intents.clear()
	battle.event_sequence = 0
	battle.turn_number = 0
	battle.battle_result = ""
	battle.damage_dealt = 0
	battle.damage_taken = 0
	battle.enemies_defeated = 0
	battle.hazards.clear()
	battle.deploy_zone = deploy_zone_cells.duplicate() if not deploy_zone_cells.is_empty() else default_deploy_zone(battle)
	battle.deploy_order.clear()
	battle.deploy_index = 0

	for index in range(roster.size()):
		var character_id: String = roster[index]
		var sheet: CharacterDefinition = CharacterCatalogScript.get_definition(character_id)
		var unit = BattleActorScript.new(character_id, "player", spawn_cells[index], sheet.max_health, String(sheet.character_id), sheet.attack, sheet.defense, sheet.magic_resistance)
		unit.character_id = sheet.character_id
		unit.glyph = sheet.glyph
		unit.display_name_zh = sheet.display_name_zh
		unit.role_label_zh = sheet.role_label_zh
		unit.resource_id = sheet.resource_id
		unit.resource_name_zh = sheet.resource_name_zh
		unit.resource_max = sheet.resource_max
		unit.ultimate_energy_max = maxi(1, sheet.ultimate_energy_max)
		unit.resource_current = 0
		if index == 0 and battle.run_state != null:
			battle.run_state.apply_to_actor(unit)
		battle.actors[character_id] = unit
		if index == 0:
			battle.active_character_id = roster[0]
		# §11.1 deploys the roster in order, one cell each.
		battle.deploy_order.append(character_id)
	for index in range(enemy_cells.size()):
		var cell: Vector2i = enemy_cells[index]
		var archetype := EnemyCatalogScript.DEFAULT_ARCHETYPE if enemy_archetypes.is_empty() else enemy_archetypes[index]
		var enemy_id := "%s_%02d" % [archetype, index]
		var profile: EnemyDefinition = EnemyCatalogScript.get_definition(archetype)
		var enemy_unit = EnemyActorFactory.create(profile, enemy_id, cell)
		# Boss encounters can scale the four core sheet stats without changing
		# signature-skill damage, which remains authored independently in the sheet.
		if not is_equal_approx(enemy_stat_multiplier, 1.0):
			enemy_unit.max_health = roundi(float(profile.health) * enemy_stat_multiplier)
			enemy_unit.health = enemy_unit.max_health
			enemy_unit.attack = roundi(float(profile.attack) * enemy_stat_multiplier)
			enemy_unit.defense = roundi(float(profile.defense) * enemy_stat_multiplier)
			enemy_unit.magic_resistance = roundi(float(profile.magic_resistance) * enemy_stat_multiplier)
		# Start encounter with full charge so turn 1 immediately showcases each enemy's signature threat
		enemy_unit.skill_charge = 3
		TacticalPressureScript.init_enemy_pressure(enemy_unit)
		battle.actors[enemy_id] = enemy_unit

	# Spawn 2 Relic Beacons as stationary defense objectives on the board
	_spawn_default_beacons(battle, spawn_cells, enemy_cells, candidate_blockers, chest_items)
	# After the chests, so a node never lands on one and the fight still has the
	# loot the player expects.
	if ward_nodes > 0:
		battle.spawn_ward_nodes(ward_nodes)

	# §11.1: the board, the enemies, the obstacles and the chests are all placed
	# before deployment, and the deployment phase itself spends no AP, advances no
	# turn and lets no enemy act. So the only thing "defer" changes is that the
	# first player turn waits for request_begin_battle().
	if defer_start:
		battle.phase = battle.BattlePhase.DEPLOY
		battle.turn_number = 0
		battle.ap.reset()
		battle._emit_event("deployment_started", "", "", "zone=%d roster=%d" % [battle.deploy_zone.size(), battle.deploy_order.size()])
		return true
	battle.phase = battle.BattlePhase.PLAYER
	begin_player_turn(battle)
	return true


static func _spawn_default_beacons(
	battle,
	spawn_cells: Array[Vector2i],
	enemy_cells: Array[Vector2i],
	blockers: Dictionary,
	fixed_items: Array[StringName] = []
) -> void:
	var preferred: Array[Vector2i] = [
		Vector2i(1, 5),
		Vector2i(3, 1),
		Vector2i(2, 6),
		Vector2i(5, 2),
		Vector2i(1, 2),
		Vector2i(4, 1),
	]
	var used: Dictionary = {}
	for c in spawn_cells:
		used[c] = true
	for c in enemy_cells:
		used[c] = true
	for c in blockers:
		used[c] = true
	var owned_mods: Array[StringName] = []
	var excluded_upgrades: Array[StringName] = []
	if battle.run_state != null:
		owned_mods = battle.run_state.mods.duplicate()
		for bag_item in battle.run_state.backpack:
			if str(bag_item.get("kind", "")) == LootCatalogScript.KIND_SKILL_UPGRADE:
				excluded_upgrades.append(StringName(str(bag_item.get("id", ""))))
	var roster: Array[String] = battle.deploy_order.duplicate()
	var placed: int = 0
	for c in preferred:
		if placed >= 2:
			break
		if not GridRulesScript.is_inside_bounds(c, battle.grid_size) or used.has(c):
			continue
		placed += 1
		used[c] = true
		var loot: Dictionary = {}
		if placed <= fixed_items.size():
			var fixed_id: StringName = fixed_items[placed - 1]
			loot = LootCatalogScript.get_item(fixed_id)
			if loot.is_empty():
				push_error("LevelCatalog: unknown chest item id '%s', falling back to a random roll" % str(fixed_id))
			elif not LootCatalogScript.is_item_usable_by_roster(loot, roster):
				loot = {}
		if loot.is_empty():
			loot = LootCatalogScript.roll_item_for_roster(roster, owned_mods, excluded_upgrades)
		if str(loot.get("kind", "")) == LootCatalogScript.KIND_SKILL_UPGRADE:
			excluded_upgrades.append(StringName(str(loot.get("id", ""))))
		battle.beacons[c] = {
			"id": "beacon_%02d" % placed,
			"cell": c,
			"health": 2,
			"max_health": 2,
			"opened": false,
			# A chest is a solid box: it blocks both movement and sight, unlike the
			# 结界 nodes, which §15.2 limits to movement.
			"blocks_sight": true,
			"loot": loot,
		}


static func start_enemy_phase_stepped(battle) -> bool:
	if battle.phase != battle.BattlePhase.PLAYER:
		return false
	expire_oath_shields_for_current_turn(battle)
	var expired_statuses: int = battle.statuses.expire_all_boundary(&"player_phase_end")
	if expired_statuses > 0:
		battle._emit_event("statuses_expired", "", "", "boundary=player_phase_end count=%d" % expired_statuses)
	battle.ap.clear()
	TacticalPressureScript.reset_turn_tolerance(battle)
	battle.phase = battle.BattlePhase.ENEMY
	battle._emit_event("turn_ended", battle.active_character_id, "", "turn=%d" % battle.turn_number)
	return true


static func resolve_next_enemy_intent(battle) -> bool:
	return IntentResolverScript.resolve_one_active(battle)


static func finish_enemy_phase_stepped(battle) -> void:
	IntentResolverScript.finish_phase(battle)


## §11.1 部署区. The document leaves the shape open ("部署区形状可变化"), so the
## default is stated in one place - the southern three rows, the edge the hero
## already enters from - and a level that wants another shape passes its own
## cells through `EncounterDefinition.deploy_cells`.
const DEFAULT_DEPLOY_ROWS: int = 3


static func default_deploy_zone(battle) -> Array[Vector2i]:
	var zone: Array[Vector2i] = []
	var start_row: int = maxi(0, battle.grid_size.y - DEFAULT_DEPLOY_ROWS)
	for y in range(start_row, battle.grid_size.y):
		for x in range(battle.grid_size.x):
			zone.append(Vector2i(x, y))
	return zone


## Places the next character waiting for deployment, or slides the last one
## already placed. §11.1 lets the player adjust before confirming, and with a
## one-character roster "the last one placed" is the same character, so a second
## tap simply relocates them.
static func request_deploy(battle, cell: Vector2i) -> bool:
	if battle.phase != battle.BattlePhase.DEPLOY:
		return false
	if battle.deploy_order.is_empty():
		return false
	if not battle.deploy_zone.has(cell):
		battle._emit_event("action_rejected", "", "", "outside_deploy_zone cell=%s" % str(cell))
		return false
	if battle.blocked_cells.has(cell):
		battle._emit_event("action_rejected", "", "", "deploy_on_obstacle cell=%s" % str(cell))
		return false
	var pending: bool = battle.deploy_index < battle.deploy_order.size()
	var actor_id: String = battle.deploy_order[battle.deploy_index] if pending else battle.deploy_order[battle.deploy_order.size() - 1]
	var occupant: String = _actor_at(battle, cell)
	if not occupant.is_empty() and occupant != actor_id:
		battle._emit_event("action_rejected", actor_id, occupant, "deploy_cell_taken cell=%s" % str(cell))
		return false
	var actor = battle.actors[actor_id]
	if actor == null or actor.team != "player":
		return false
	actor.cell = cell
	if pending:
		battle.deploy_index += 1
	battle._emit_event("actor_deployed", actor_id, "", "cell=%s placed=%d/%d" % [str(cell), battle.deploy_index, battle.deploy_order.size()])
	return true


## §11.1 "点击确认部署后才正式开始战斗". Only after the whole roster is placed:
## starting with a character still off the board would be a battle the player
## cannot act in.
static func request_begin_battle(battle) -> bool:
	if battle.phase != battle.BattlePhase.DEPLOY:
		return false
	if battle.deploy_index < battle.deploy_order.size():
		battle._emit_event("action_rejected", "", "", "deployment_incomplete %d/%d" % [battle.deploy_index, battle.deploy_order.size()])
		return false
	# Everything that "fires at battle start" - resource gain, ultimate energy,
	# relic procs - lives inside begin_player_turn, so deferring that call is what
	# keeps them out of deployment without a second list of exceptions.
	battle.phase = battle.BattlePhase.PLAYER
	begin_player_turn(battle)
	battle._emit_event("battle_started", battle.active_character_id, "", "turn=%d" % battle.turn_number)
	return true


static func _actor_at(battle, cell: Vector2i) -> String:
	# Use the battle's single occupancy authority so actors, relic chests and
	# ward nodes all reserve their cells. Undeployed party members are removed
	# from the temporary view because their initial cells are not placements.
	var occupied: Dictionary = battle.get_occupied_cells()
	for pending_index in range(battle.deploy_index, battle.deploy_order.size()):
		var pending_id: String = battle.deploy_order[pending_index]
		var pending_actor = battle.actors.get(pending_id)
		if pending_actor != null and str(occupied.get(pending_actor.cell, "")) == pending_id:
			occupied.erase(pending_actor.cell)
	return str(occupied.get(cell, ""))


static func end_player_turn(battle) -> bool:
	if battle.phase != battle.BattlePhase.PLAYER:
		return false
	expire_oath_shields_for_current_turn(battle)
	var expired_statuses: int = battle.statuses.expire_all_boundary(&"player_phase_end")
	if expired_statuses > 0:
		battle._emit_event("statuses_expired", "", "", "boundary=player_phase_end count=%d" % expired_statuses)
	battle.ap.clear()
	TacticalPressureScript.reset_turn_tolerance(battle)
	battle.phase = battle.BattlePhase.ENEMY
	battle._emit_event("turn_ended", battle.active_character_id, "", "turn=%d" % battle.turn_number)
	IntentResolverScript.resolve_phase(battle)
	return true


static func expire_oath_shields_for_current_turn(battle) -> void:
	var expired_ids: Array[String] = []
	for actor_id in battle.ledger.oath_shield_expiry_turn.keys():
		if int(battle.ledger.oath_shield_expiry_turn[actor_id]) <= battle.turn_number:
			expired_ids.append(String(actor_id))
	for actor_id in expired_ids:
		if battle.actors.has(actor_id):
			var actor = battle.actors[actor_id]
			var removed: int = actor.shield
			actor.shield = 0
			battle._emit_event("oath_shield_expired", actor_id, actor_id, "removed=%d turn=%d" % [removed, battle.turn_number])
		battle.ledger.oath_shield_expiry_turn.erase(actor_id)


## Temp shields from 结界守护 (§15.2) live on the actor. Swept at the start of a
## player turn, the same boundary the player's oath shield uses, so both kinds of
## shield expire where the player expects them to.
static func _expire_enemy_stance_shields(battle) -> void:
	for actor_id in battle.actors:
		var actor = battle.actors[actor_id]
		if actor.team != "enemy" or actor.shield_expiry_turn < 0:
			continue
		if battle.turn_number < actor.shield_expiry_turn:
			continue
		var removed: int = actor.shield
		actor.shield = 0
		actor.shield_expiry_turn = -1
		if removed > 0:
			battle._emit_event("enemy_shield_expired", String(actor_id), String(actor_id), "removed=%d turn=%d" % [removed, battle.turn_number])


static func begin_player_turn(battle) -> void:
	var expired_statuses: int = battle.statuses.expire_all_boundary(&"player_phase_start")
	if expired_statuses > 0:
		battle._emit_event("statuses_expired", "", "", "boundary=player_phase_start count=%d" % expired_statuses)
	battle.turn_number += 1
	_expire_enemy_stance_shields(battle)
	# Ground hazards run on the same player-turn clock: sweep the lapsed ones
	# first, then bill whoever is still standing on a live tile. Doing it in the
	# other order would charge for a tile that expires this very turn.
	HazardFieldScript.expire(battle)
	if HazardFieldScript.tick_player_turn_start(battle) > 0:
		battle._check_battle_end()
		if battle.phase == battle.BattlePhase.FINISHED:
			return
	battle.ledger.reset_for_player_turn()
	TacticalPressureScript.reset_turn_tolerance(battle)
	for actor_id in battle.actors.keys():
		var player_actor = battle.actors[actor_id]
		if player_actor.team != "player" or not player_actor.is_alive():
			continue
		var energy_before: int = player_actor.ultimate_energy
		player_actor.gain_ultimate_energy(1)
		if player_actor.ultimate_energy != energy_before:
			battle._emit_event("ultimate_energy_gained", String(actor_id), String(actor_id), "source=player_turn_start energy=%d" % player_actor.ultimate_energy)
	# §19: one stack at turn start, outside the per-turn action budget.
	for actor_id in battle.actors:
		var member = battle.actors[actor_id]
		if member.team == "player" and member.is_alive() and member.has_resource():
			member.gain_resource(1)
	battle.ap.reset()
	battle.phase = battle.BattlePhase.PLAYER
	# The commanded member may have gone down during the enemy phase. Hand command
	# to the first one still standing, otherwise the turn starts on a character
	# who cannot act and nothing on screen says why.
	var active = battle.get_active_character()
	if active == null or not active.is_alive():
		for actor_id in battle.actors:
			var member = battle.actors[actor_id]
			if member.team == "player" and member.is_alive():
				battle.active_character_id = String(actor_id)
				break
	battle.intents = IntentPlannerScript.plan(battle)
	# Emitted after the handover above, so the id is the member who actually
	# holds command for this turn - the view rebuilds the bar from this event.
	battle._emit_event("player_turn_started", battle.active_character_id, "", "turn=%d" % battle.turn_number)


static func check_battle_end(battle) -> void:
	if battle.phase == battle.BattlePhase.FINISHED:
		return
	# §12: defeat only when the whole party is down. A single downed member is
	# still revivable while anyone else stands. Any party counts - naming Sevrin
	# here meant a party without him could never lose.
	var party_size := 0
	var living_party := 0
	for actor in battle.actors.values():
		if actor.team != "player":
			continue
		party_size += 1
		if actor.is_alive():
			living_party += 1
	if party_size > 0 and living_party == 0:
		finish_battle(battle, "defeat")
		return
	var living_enemies := 0
	for actor in battle.actors.values():
		if actor.team == "enemy" and actor.is_alive():
			living_enemies += 1
	if living_enemies == 0:
		finish_battle(battle, "victory")


static func finish_battle(battle, result: String) -> void:
	if battle.phase == battle.BattlePhase.FINISHED:
		return
	battle.phase = battle.BattlePhase.FINISHED
	battle.battle_result = result
	for intent in battle.intents:
		if intent.state == BattleIntentScript.IntentState.ACTIVE:
			intent.cancel("battle_finished")
	var removed_statuses: int = battle.statuses.clear_all()
	if removed_statuses > 0:
		battle._emit_event("statuses_cleared", "", "", "reason=battle_finished count=%d" % removed_statuses)
	battle.battle_finished.emit(result)
	battle._emit_event("battle_" + result, "", "", result)
