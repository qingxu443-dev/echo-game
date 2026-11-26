extends "res://tests/framework/test_case.gd"

const LootCatalogScript = preload("res://scripts/battle/loot_catalog.gd")


func _run() -> void:
	# The roster is explicit data now: every sheet must be valid and unique, or
	# a typo in one .tres silently ships a broken roll.
	_check(LootCatalogScript.item_count() == 13, "roster exposes thirteen loot items")
	_check(LootCatalogScript.all_definitions_valid(), "every loot sheet is valid and ids are unique")

	var seen_kinds: Dictionary = {}
	_check(LootCatalogScript.get_item(&"__missing__").is_empty(), "unknown ids resolve to an empty item")
	for kind in [LootCatalogScript.KIND_WEAPON, LootCatalogScript.KIND_ARMOR, LootCatalogScript.KIND_CONSUMABLE, LootCatalogScript.KIND_SKILL_UPGRADE]:
		seen_kinds[kind] = false
	var probe_ids: Array[StringName] = [
		&"weapon_oath_greatsword", &"armor_iron_bulwark",
		&"item_dusk_potion", &"upg_shatter_slam",
	]
	for item_id in probe_ids:
		var item: Dictionary = LootCatalogScript.get_item(item_id)
		_check(not item.is_empty(), "%s resolves from its sheet" % str(item_id))
		_check(item["id"] == item_id, "%s keeps its id through the dictionary contract" % str(item_id))
		_check(item.has("enemy_buff_zh") and item.has("enemy_attack") and item.has("enemy_shield") and item.has("enemy_heal") and item.has("enemy_charge"), "%s carries the full enemy-steal payload" % str(item_id))
		seen_kinds[item["kind"]] = true
	_check(seen_kinds[LootCatalogScript.KIND_WEAPON] and seen_kinds[LootCatalogScript.KIND_ARMOR], "weapon and armor sheets survive the contract")
	_check(seen_kinds[LootCatalogScript.KIND_CONSUMABLE] and seen_kinds[LootCatalogScript.KIND_SKILL_UPGRADE], "consumable and skill-upgrade sheets survive the contract")

	var slam: Dictionary = LootCatalogScript.get_item(&"upg_shatter_slam")
	_check(slam["mod_id"] == &"shatter_slam", "skill-upgrade sheets keep their run mod id")
	var blade: Dictionary = LootCatalogScript.get_item(&"weapon_dusk_blade")
	_check(int(blade["attack"]) == 340 and int(blade["defense"]) == -60, "weapon stat lines come from the sheet")

	# Seeded rolls are reproducible: same seed, same sequence - this is what a
	# drop complaint replay will lean on.
	LootCatalogScript.seed_rng(424242)
	var first: Array[StringName] = []
	for i in range(6):
		first.append(LootCatalogScript.roll_random_item()["id"])
	LootCatalogScript.seed_rng(424242)
	var second: Array[StringName] = []
	for i in range(6):
		second.append(LootCatalogScript.roll_random_item()["id"])
	_check(first == second, "the same seed replays the same drop sequence")
	_check(LootCatalogScript.current_seed() == 424242, "the catalog reports the seed in force")

	# Two different seeds should not produce identical long sequences (13 items
	# over 6 draws - a collision would mean the seed is being ignored).
	LootCatalogScript.seed_rng(7)
	var third: Array[StringName] = []
	for i in range(6):
		third.append(LootCatalogScript.roll_random_item()["id"])
	_check(not (first == third), "a different seed produces a different sequence")

	# The default seed stays fixed for headless runs.
	LootCatalogScript.seed_rng(0)
	_check(LootCatalogScript.current_seed() == 0, "the default headless seed is zero")

	_report()
