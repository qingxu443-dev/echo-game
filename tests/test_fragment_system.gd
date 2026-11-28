extends "res://tests/framework/test_case.gd"

const Catalog = preload("res://scripts/fragments/fragment_catalog.gd")
const Store = preload("res://scripts/fragments/fragment_store.gd")
const Advisor = preload("res://scripts/fragments/fragment_build_advisor.gd")
const BattleControllerScript = preload("res://scripts/battle/battle_controller.gd")
const DamagePipelineScript = preload("res://scripts/battle/damage_pipeline.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")
const BattleActorScript = preload("res://scripts/actors/battle_actor.gd")
const RosterOverlayScript = preload("res://scripts/ui/roster_manager_overlay.gd")
const FragmentCenterPanelScript = preload("res://scripts/ui/fragment_center_panel.gd")


func _run() -> void:
	_test_fixed_module_generation()
	_test_medium_pool_contains_all_pairs()
	_test_fixed_large_distribution()
	_test_inventory_slots_capacity_and_transfer()
	_test_advisor_uses_character_capabilities()
	_test_equipped_modules_apply_to_battle()
	_test_roster_overlay_fragment_center()


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _test_fixed_module_generation() -> void:
	var rng := _rng(1001)
	var small := Catalog.create_small(rng)
	_check(Catalog.validate_module(small), "a small module is valid")
	_check(small.attributes.size() == 1, "a small module has exactly one fixed attribute")
	var small_stat := str(small.attributes.keys()[0])
	_check(Catalog.STAT_KEYS.has(small_stat), "a small module chooses from the seven-stat pool")
	_check(is_equal_approx(float(small.attributes[small_stat]), float(Catalog.VALUES[Catalog.SIZE_SMALL][small_stat])), "small-module values match the first test library")

	var medium := Catalog.create_medium(rng)
	_check(Catalog.validate_module(medium), "a medium module is valid")
	_check(medium.attributes.size() == 2, "a medium module has exactly two attributes")
	var medium_keys: Array = medium.attributes.keys()
	_check(medium_keys[0] != medium_keys[1], "a medium module never repeats its attribute")
	var medium_values_match := true
	for stat in medium_keys:
		medium_values_match = medium_values_match and is_equal_approx(float(medium.attributes[stat]), float(Catalog.VALUES[Catalog.SIZE_MEDIUM][str(stat)]))
	_check(medium_values_match, "both medium attributes use their fixed values")

	var large := Catalog.create_large("attack", rng)
	_check(Catalog.validate_module(large), "a large module is valid")
	_check(large.main_stat == "attack", "a large module keeps the player-selected main stat")
	_check(large.sub_stat != large.main_stat, "a large module's random sub stat differs from its main stat")
	_check(is_equal_approx(float(large.attributes.attack), 7.0), "a large main stat uses the main-stat value")
	_check(is_equal_approx(float(large.attributes[large.sub_stat]), float(Catalog.VALUES[Catalog.SIZE_LARGE_SUB][large.sub_stat])), "a large sub stat uses the sub-stat value")
	_check(Catalog.create_large("unknown", rng).is_empty(), "invalid large main stats are rejected")
	_check(not Catalog.validate_module({"instance_id": "broken", "size": "small", "capacity": 1, "attributes": {"attack": 999.0}, "main_stat": "attack"}), "forged values are rejected by module validation")


func _test_medium_pool_contains_all_pairs() -> void:
	var seen := {}
	for seed_value in range(400):
		var medium := Catalog.create_medium(_rng(seed_value))
		var keys := PackedStringArray()
		for key in medium.attributes.keys():
			keys.append(str(key))
		keys.sort()
		seen["|".join(keys)] = true
	_check(seen.size() == 21, "the medium generator can produce all 21 unique two-stat pairs")


func _test_fixed_large_distribution() -> void:
	var modules := Catalog.create_fixed_large_bundle(_rng(3003))
	_check(modules.size() == 10, "the specified large-module reward creates ten modules")
	var expected := {"attack": 2, "health": 2, "defense": 1, "crit_rate": 1, "crit_damage": 1, "magic_resistance": 1, "healing_efficiency": 2}
	var actual := {}
	var valid := true
	for module in modules:
		valid = valid and Catalog.validate_module(module)
		var stat := str(module.main_stat)
		actual[stat] = int(actual.get(stat, 0)) + 1
		valid = valid and module.sub_stat != module.main_stat
	_check(valid, "all fixed large modules have valid and distinct main/sub stats")
	_check(actual == expected, "the fixed main-stat distribution is 2/2/1/1/1/1/2")


func _test_inventory_slots_capacity_and_transfer() -> void:
	var path := "user://fragment_inventory_test_%d.json" % OS.get_process_id()
	var store = Store.load_store(path)
	var rng := _rng(4004)
	var modules: Array[Dictionary] = []
	for index in range(6):
		modules.append(Catalog.create_large("health", rng))
	_check(store.add_modules(modules), "the inventory accepts independent duplicate-type instances")
	_check(store.install("sevrin", 0, str(modules[0].instance_id)).ok, "a module can be installed in a character slot")
	_check(not store.install("sakura", 0, str(modules[0].instance_id)).ok, "one instance cannot be equipped by two characters")
	_check(not store.install("sevrin", 1, str(modules[0].instance_id)).ok, "one instance cannot occupy two slots on the same character")
	_check(store.install("sevrin", 1, str(modules[1].instance_id)).ok, "different instances of the same module type may be equipped together")
	_check(store.install("sevrin", 2, str(modules[2].instance_id)).ok, "a third large module fits within the capacity budget")
	_check(store.install("sevrin", 3, str(modules[3].instance_id)).ok, "a fourth large module fills capacity exactly")
	_check(store.equipped_capacity("sevrin") == 12, "four large modules consume all 12 capacity")
	_check(not store.install("sevrin", 4, str(modules[4].instance_id)).ok, "capacity 12 blocks another module even with open slots")
	_check(store.available_modules("sakura").size() == 2, "modules equipped by another character are unavailable")
	_check(store.uninstall("sevrin", 0).ok, "uninstalling a module is allowed")
	_check(store.install("sakura", 0, str(modules[0].instance_id)).ok, "an uninstalled module can be transferred")
	_check(store.validate_equipment(), "slot and ownership constraints remain valid")
	_check(store.save(), "the module inventory persists")
	var loaded = Store.load_store(path)
	_check(loaded != null and loaded.modules.size() == 6, "the saved inventory round-trips")
	_check(loaded.equipped_ids("sakura").has(str(modules[0].instance_id)), "the transferred module owner persists")
	DirAccess.remove_absolute(path)


func _test_advisor_uses_character_capabilities() -> void:
	var path := "user://fragment_advisor_test_%d.json" % OS.get_process_id()
	var store = Store.load_store(path)
	var rng := _rng(5005)
	var modules: Array[Dictionary] = [
		Catalog.create_small(rng, "adv_small_1"),
		Catalog.create_small(rng, "adv_small_2"),
		Catalog.create_large("attack", rng, "adv_large_1"),
		Catalog.create_large("health", rng, "adv_large_2"),
	]
	_check(store.add_modules(modules), "advisor test inventory is seeded")
	var attack := Advisor.recommend(store, "sevrin", Advisor.DIRECTION_ATTACK)
	_check(attack.ok and attack.instance_ids.size() <= 6 and attack.capacity <= 12, "attack advice returns one feasible loadout")
	var defense := Advisor.recommend(store, "sakura", Advisor.DIRECTION_DEFENSE)
	_check(defense.ok and defense.capacity <= 12, "defense advice evaluates the selected character")
	_check(not Advisor.directions_for_character("sevrin").has(Advisor.DIRECTION_SUPPORT), "a character without healing cannot select treatment support")
	_check(not Advisor.directions_for_character("sakura").has(Advisor.DIRECTION_SUPPORT), "the second current character also has no healing kit")
	var empty_store = Store.load_store(path + ".empty")
	var empty := Advisor.recommend(empty_store, "sevrin", Advisor.DIRECTION_ATTACK)
	_check(empty.ok and empty.instance_ids.is_empty() and empty.already_optimal, "an empty inventory does not fill slots with zero-value modules")
	DirAccess.remove_absolute(path)


func _test_equipped_modules_apply_to_battle() -> void:
	var path := "user://fragment_battle_test_%d.json" % OS.get_process_id()
	var store = Store.load_store(path)
	var rng := _rng(6006)
	var attack_module := {
		"instance_id": "battle_attack_4",
		"size": Catalog.SIZE_SMALL,
		"capacity": 1,
		"main_stat": "attack",
		"sub_stat": "",
		"attributes": {"attack": 4.0},
		"created_seed": 6006,
	}
	var crit_module := {
		"instance_id": "battle_crit_1",
		"size": Catalog.SIZE_LARGE,
		"capacity": 3,
		"main_stat": "crit_rate",
		"sub_stat": "health",
		"attributes": {"crit_rate": 2.5, "health": 1.0},
		"created_seed": 6007,
	}
	var battle_modules: Array[Dictionary] = [attack_module, crit_module]
	_check(store.add_modules(battle_modules), "battle test modules are added")
	_check(store.install("sevrin", 0, str(attack_module.instance_id)).ok, "attack module is equipped")
	_check(store.install("sevrin", 1, str(crit_module.instance_id)).ok, "critical module is equipped")
	_check(store.save(), "battle test loadout is saved")
	Store.default_path_override = path
	var battle = BattleControllerScript.new()
	battle.run_state = RunState.new()
	battle.run_state.reset()
	root.add_child(battle)
	var no_obstacles: Array[Vector2i] = []
	var no_enemy_archetypes: Array[String] = []
	var no_deployment_cells: Array[Vector2i] = []
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)], no_obstacles, no_enemy_archetypes, ["sevrin"], no_deployment_cells)
	var actor = battle.get_actor("sevrin")
	_check(actor.attack == roundi(650.0 * (1.0 + float(attack_module.attributes.attack) / 100.0)), "equipped attack percentage modifies the spawned character")
	_check(is_equal_approx(actor.crit_rate, float(crit_module.attributes.crit_rate)), "equipped critical-rate modules reach combat runtime")
	actor.health = 1000
	battle.run_state.add_to_backpack({"id": &"fragment_probe_armor", "kind": "armor", "name": "复验护甲", "attack": 100, "max_health": 400})
	battle.run_state.equip_from_backpack(0, actor)
	_check(actor.attack == 780, "equipping armor retains the captured 4% fragment attack bonus")
	_check(actor.max_health == 3636 and actor.health == 1404, "equipment HP changes retain the captured 1% fragment multiplier")
	battle.run_state.unequip_slot("armor", actor)
	_check(actor.attack == 676, "unequipping returns to fragment-scaled attack instead of removing the module")
	_check(actor.max_health == 3232 and actor.health == 1000, "unequipping scaled HP is symmetric")
	var fields: Dictionary = SessionCodec.decode(JSON.parse_string(JSON.stringify(SessionCodec.encode(SessionCodec.fields(actor)))))
	var restored := BattleActor.new("sevrin", "player", Vector2i.ZERO, 3600)
	SessionCodec.apply_fields(restored, fields)
	_check(restored.fragment_bonuses == actor.fragment_bonuses, "fragment composition survives the actual JSON codec")
	var restored_state := RunState.new()
	restored_state.reset()
	restored_state.add_to_backpack({"id": &"resume_armor", "kind": "armor", "name": "续行护甲", "attack": 100})
	restored_state.equip_from_backpack(0, restored)
	_check(restored.attack == 1300, "post-resume equipment uses the saved fragment composition")
	actor.crit_rate = 100.0
	actor.crit_damage = 200.0
	var enemy = battle.get_actor("vanguard_00")
	var before: int = enemy.health
	DamagePipelineScript.apply(battle, "vanguard_00", 100, "sevrin", "fragment_crit_test", "physical")
	var expected := CombatMathScript.calculate_damage(200, enemy.defense, battle.attenuation_k)
	_check(before - enemy.health == expected, "a guaranteed critical strike applies its multiplier before mitigation")
	actor.healing_efficiency = 10.0
	_check(actor.scaled_healing_amount(100) == 110, "healing efficiency scales skill healing amounts")
	battle.queue_free()
	Store.default_path_override = ""
	DirAccess.remove_absolute(path)


func _test_roster_overlay_fragment_center() -> void:
	var overlay = RosterOverlayScript.new()
	root.add_child(overlay)
	overlay.size = Vector2(1280, 720)
	await process_frame
	overlay.open_characters()
	_check(overlay.current_mode == "characters", "the merged roster overlay remains the character detail entry")
	overlay.open_fragments("dest_lee")
	await process_frame
	_check(overlay.current_mode == "fragments" and overlay.selected_character_id == "dest_lee", "the fragment center opens with the selected character")
	var fragment_panel = _find_script_node(overlay, FragmentCenterPanelScript)
	_check(fragment_panel != null, "the roster overlay embeds the independent fragment center panel")
	if fragment_panel != null:
		_check(fragment_panel.store != null, "the fragment center reads the persistent inventory")
	overlay.queue_free()
	await process_frame


func _find_script_node(node: Node, script: Script):
	if node.get_script() == script:
		return node
	for child in node.get_children():
		var found = _find_script_node(child, script)
		if found != null:
			return found
	return null
