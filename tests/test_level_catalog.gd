extends "res://tests/framework/test_case.gd"

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const LevelCatalogScript = preload("res://scripts/battle/level_catalog.gd")
const LootCatalogScript = preload("res://scripts/battle/loot_catalog.gd")


func _run() -> void:
	var levels: Array[EncounterDefinition] = LevelCatalogScript.create_prototype_levels()

	_check(levels.size() == 3, "catalog exposes three prototype levels")
	_check(LevelCatalogScript.level_count() == levels.size(), "level_count matches the catalog")

	var seen_ids: Dictionary = {}
	for index in range(levels.size()):
		var level: EncounterDefinition = levels[index]
		_check(level.is_valid(), "level %d passes definition validation" % index)
		_check(level.describe_layout_error() == "", "level %d has a self-consistent layout" % index)
		_check(not seen_ids.has(level.level_id), "level %d uses a unique level id" % index)
		seen_ids[level.level_id] = true
		_check(not level.display_name_zh.strip_edges().is_empty(), "level %d has a display name" % index)
		_check(not level.tactical_hint_zh.strip_edges().is_empty(), "level %d teaches a tactical lesson" % index)

	_check(levels[0].level_id == &"lesson_charge", "first level is the charged-strike lesson")
	_check(levels[1].level_id == &"lesson_lane", "second level is the firing-lane lesson")
	_check(levels[2].level_id == &"lesson_mixed", "third level is the mixed roster")

	# Level 1 introduces the Relic Chests with a vanguard + marksman pair,
	# pins its chest rewards so the tutorial always delivers the lesson it
	# promises, and places a wall next to the vanguard so the first knockback
	# slam is teachable.
	var battle_one = ControllerScript.new()
	root.add_child(battle_one)
	var level_one: EncounterDefinition = levels[0]
	_check(battle_one.start_encounter(level_one.player_cell, level_one.enemy_cells, level_one.obstacles, level_one.enemy_archetypes, level_one.character_ids, [], level_one.chest_items), "level 1 is accepted by the controller with its teaching chest contents")
	_check(battle_one.intents.size() == level_one.enemy_cells.size(), "level 1 telegraphs one intent per enemy")
	_check(battle_one.blocked_cells.has(Vector2i(5, 3)), "level 1 places the knockback-teaching wall beside the vanguard column")
	var chest_item_ids: Array[StringName] = []
	for cell in battle_one.beacons:
		chest_item_ids.append(battle_one.beacons[cell]["loot"]["id"])
	_check(chest_item_ids.has(&"upg_shatter_slam") and chest_item_ids.has(&"armor_iron_bulwark"), "level 1 chests carry the pinned teaching items")
	var unpinned: bool = true
	for item_id in level_one.chest_items:
		if LootCatalogScript.get_item(item_id).is_empty():
			unpinned = false
	_check(unpinned, "every pinned chest id exists in the loot catalog")
	_check(level_one.obstacles.has(Vector2i(5, 3)) and level_one.enemy_cells.has(Vector2i(4, 3)), "the teaching wall is orthogonally adjacent to the vanguard spawn")
	battle_one.queue_free()

	# Level 2 introduces 3-way crossfire with vanguard, marksman, and area controller.
	var battle_two = ControllerScript.new()
	root.add_child(battle_two)
	var level_two: EncounterDefinition = levels[1]
	_check(battle_two.start_encounter(level_two.player_cell, level_two.enemy_cells, level_two.obstacles, level_two.enemy_archetypes), "level 2 is accepted by the controller")
	_check(battle_two.intents.size() == level_two.enemy_cells.size(), "level 2 telegraphs one intent per enemy")
	battle_two.queue_free()

	# Level 3 mixes all three archetypes.
	var battle_three = ControllerScript.new()
	root.add_child(battle_three)
	var level_three: EncounterDefinition = levels[2]
	_check(battle_three.start_encounter(level_three.player_cell, level_three.enemy_cells, level_three.obstacles, level_three.enemy_archetypes), "level 3 is accepted by the controller")
	_check(battle_three.intents.size() == 3, "level 3 telegraphs one intent per enemy")
	_check(battle_three.blocked_cells.size() == level_three.obstacles.size(), "level 3 applies its obstacle layout")
	battle_three.queue_free()

	# Authoring guards reject the mistakes a level author is most likely to make.
	var broken: EncounterDefinition = levels[0].duplicate()
	broken.enemy_cells = [Vector2i(2, 2), Vector2i(2, 2)]
	broken.enemy_archetypes = ["vanguard", "vanguard"]
	_check(broken.describe_layout_error() != "", "duplicate enemy cells are reported")
	var overlapping: EncounterDefinition = levels[0].duplicate()
	overlapping.enemy_cells = [levels[0].player_cell]
	overlapping.enemy_archetypes = ["vanguard"]
	_check(overlapping.describe_layout_error() != "", "enemy on the player cell is reported")
	var unknown: EncounterDefinition = levels[0].duplicate()
	unknown.enemy_archetypes = ["sorcerer"]
	_check(not unknown.is_valid(), "unknown archetype fails definition validation")

	_report()
