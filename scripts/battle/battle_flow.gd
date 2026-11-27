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
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")
const LootCatalogScript = preload("res://scripts/battle/loot_catalog.gd")


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
	chest_items: Array[StringName] = []
) -> bool:
	if battle.grid_size.x <= 0 or battle.grid_size.y <= 0 or battle.team_ap <= 0:
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
	battle.oath_shield_expiry_turn.clear()
	battle.oath_shield_revived.clear()
	battle.resource_gain_turn.clear()
	battle.resource_gain_count.clear()
	battle.echo_return_gain_turn.clear()
	battle.oath_vow_triggered_intents.clear()
	battle.absolute_guard_hit_intents.clear()
	battle.absolute_guard_countered_enemies.clear()
	battle.blocked_cells = candidate_blockers
	battle.intents.clear()
	battle.event_sequence = 0
	battle.turn_number = 0
	battle.battle_result = ""
	battle.summon_last_used_turn.clear()
	battle.damage_dealt = 0
	battle.damage_taken = 0
	battle.enemies_defeated = 0

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
	battle.active_character_id = roster[0]
	battle.free_move_used_turn = -1
	for index in range(enemy_cells.size()):
		var cell: Vector2i = enemy_cells[index]
		var archetype := EnemyCatalogScript.DEFAULT_ARCHETYPE if enemy_archetypes.is_empty() else enemy_archetypes[index]
		var enemy_id := "%s_%02d" % [archetype, index]
		var profile: EnemyDefinition = EnemyCatalogScript.get_definition(archetype)
		var enemy_unit = BattleActorScript.new(enemy_id, "enemy", cell, profile.health, archetype, profile.attack, profile.defense, profile.magic_resistance)
		enemy_unit.glyph = profile.glyph
		enemy_unit.skill_charge_max = 3
		enemy_unit.move_steps = profile.move_steps
		enemy_unit.tier = profile.tier
		enemy_unit.ward_shield = profile.ward_shield
		# Start encounter with full charge so turn 1 immediately showcases each enemy's signature threat
		enemy_unit.skill_charge = 3
		battle.actors[enemy_id] = enemy_unit

	# Spawn 2 Relic Beacons as stationary defense objectives (Into-the-Breach style)
	_spawn_default_beacons(battle, spawn_cells, enemy_cells, candidate_blockers, chest_items)

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
				loot = LootCatalogScript.roll_random_item()
		else:
			loot = LootCatalogScript.roll_random_item()
		battle.beacons[c] = {
			"id": "beacon_%02d" % placed,
			"cell": c,
			"health": 2000,
			"max_health": 2000,
			"opened": false,
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
	battle.phase = battle.BattlePhase.ENEMY
	battle._emit_event("turn_ended", battle.active_character_id, "", "turn=%d" % battle.turn_number)
	return true


static func resolve_next_enemy_intent(battle) -> bool:
	return IntentResolverScript.resolve_one_active(battle)


static func finish_enemy_phase_stepped(battle) -> void:
	IntentResolverScript.finish_phase(battle)


static func end_player_turn(battle) -> bool:
	if battle.phase != battle.BattlePhase.PLAYER:
		return false
	expire_oath_shields_for_current_turn(battle)
	var expired_statuses: int = battle.statuses.expire_all_boundary(&"player_phase_end")
	if expired_statuses > 0:
		battle._emit_event("statuses_expired", "", "", "boundary=player_phase_end count=%d" % expired_statuses)
	battle.ap.clear()
	battle.phase = battle.BattlePhase.ENEMY
	battle._emit_event("turn_ended", battle.active_character_id, "", "turn=%d" % battle.turn_number)
	IntentResolverScript.resolve_phase(battle)
	return true


static func expire_oath_shields_for_current_turn(battle) -> void:
	var expired_ids: Array[String] = []
	for actor_id in battle.oath_shield_expiry_turn.keys():
		if int(battle.oath_shield_expiry_turn[actor_id]) <= battle.turn_number:
			expired_ids.append(String(actor_id))
	for actor_id in expired_ids:
		if battle.actors.has(actor_id):
			var actor = battle.actors[actor_id]
			var removed: int = actor.shield
			actor.shield = 0
			battle._emit_event("oath_shield_expired", actor_id, actor_id, "removed=%d turn=%d" % [removed, battle.turn_number])
		battle.oath_shield_expiry_turn.erase(actor_id)


static func begin_player_turn(battle) -> void:
	var expired_statuses: int = battle.statuses.expire_all_boundary(&"player_phase_start")
	if expired_statuses > 0:
		battle._emit_event("statuses_expired", "", "", "boundary=player_phase_start count=%d" % expired_statuses)
	battle.turn_number += 1
	battle.absolute_guard_countered_enemies.clear()
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
