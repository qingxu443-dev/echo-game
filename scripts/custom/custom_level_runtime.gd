class_name CustomLevelRuntime
extends RefCounted


static func start(view: Node, design: CustomLevelData) -> bool:
	var level := design.encounter()
	if level == null: return false
	var battle: BattleController = view.controller
	battle.grid_size = design.size()
	battle.team_ap = int(design.data.ap)
	var hero: Dictionary = design.data.heroes[0]
	view.run_state.reset(int(hero.health), int(hero.attack), int(hero.defense), int(hero.magic_resistance))
	if not battle.start_encounter(level.player_cell, level.enemy_cells, level.obstacles, level.enemy_archetypes, level.character_ids, level.ally_cells, [], 0, [], true): return false
	battle.beacons.clear()
	for index in range(design.data.chests.size()):
		var cell := CustomLevelData.point(design.data.chests[index])
		battle.beacons[cell] = {"id": "custom_chest_%02d" % index, "cell": cell, "health": 2, "max_health": 2, "opened": false, "blocks_sight": true, "loot": LootCatalog.roll_item_for_roster(level.character_ids)}
	for unit in design.data.heroes:
		_apply(battle.get_actor(str(unit.id)), unit)
		if battle.single_active_party: PartyLoadout.adopt_actor(battle, battle.get_actor(str(unit.id)))
	for index in range(design.data.enemies.size()):
		var unit: Dictionary = design.data.enemies[index]
		_apply(battle.get_actor("%s_%02d" % [unit.id, index]), unit)
	battle.deploy_index = battle.deploy_order.size()
	if not battle.request_begin_battle(): return false
	# Initial energy/resource values are author choices, applied after turn hooks.
	for unit in design.data.heroes:
		var actor: BattleActor = battle.get_actor(str(unit.id))
		actor.ultimate_energy = int(unit.get("ultimate_energy", 0))
		actor.resource_current = int(unit.get("resource_current", 0))
	battle.ledger.rewards_settled = true
	UiPalette.board_grid_size = battle.grid_size
	if battle.single_active_party: PartyLoadout.select_role(battle, battle.active_character_id)
	else: view.run_state.sync_from_actor(battle.get_active_character())
	return true


static func _apply(actor: BattleActor, unit: Dictionary) -> void:
	actor.max_health = int(unit.health)
	actor.health = actor.max_health
	for key in ["attack", "defense", "magic_resistance", "shield", "move_steps", "skill_damage", "skill_charge", "skill_charge_max", "armor_layers"]:
		if unit.has(key): actor.set(key, int(unit[key]))
	if unit.has("armor_layers"): actor.armor_max = int(unit.armor_layers)
