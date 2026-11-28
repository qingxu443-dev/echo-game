extends "res://tests/framework/test_case.gd"

## The map <-> battle handshake and what a fight is worth (设计汇总 2026-11-26
## §11.2, §11.3, §14, §15.4, §16.1).
##
## Driven without a scene: the map writes `pending`, the battle would read it, and
## these tests write `last_result` directly and let `settle` apply it. What is
## pinned: health carries both ways, a fight keeps the map position and the
## remaining stamina, a win pays for surviving chests, a loss finishes the node
## but leaves the run alive once, an elite win offers three distinct candidates,
## and a boss win closes 春之境.

const BridgeScript = preload("res://scripts/spring/spring_battle_bridge.gd")
const RegionProgressionScript = preload("res://scripts/spring/spring_region_progression.gd")
const RunStateScript = preload("res://scripts/battle/run_state.gd")
const CollectibleCatalogScript = preload("res://scripts/spring/spring_collectible_catalog.gd")
const CharacterCatalogScript = preload("res://scripts/battle/character_catalog.gd")
const ControllerScript = preload("res://scripts/battle/battle_controller.gd")


func _run() -> void:
	_test_prepare_refuses_unknown()
	_test_normal_battle_drops_collectibles()
	_test_active_collectibles_stack_and_use()
	_test_relics_are_unique_and_raise_dew_capacity()
	_test_payload_maps_vitals_and_relics()
	_test_victory_settles()
	_test_defeat_finishes_the_node()
	_test_continue_is_one_shot()
	_test_elite_offers_three()
	_test_boss_closes_the_region()
	_test_region_unlock_persistence()
	_test_save_keeps_the_fight_results()
	_test_baseline_matches_the_hero_sheet()
	_test_the_spring_hero_fights_as_herself()


func _fresh_run(seed_value: int = 5) -> SpringRun:
	BridgeScript.clear_pending()
	BridgeScript.last_result = {}
	var run := SpringRun.begin(seed_value)
	run.add_coins(100)
	run.add_supplies(10)
	run.hero_health = run.effective_max_health()
	return run


func _result(overrides: Dictionary) -> Dictionary:
	var result := {
		"result": "victory",
		"kind": BridgeScript.KIND_BATTLE,
		"place": "battle_1",
		# 樱的档案是 1800 血（§2 把她定为这个模式的主角）。
		"hero_health": 1200,
		"hero_max_health": 1800,
		"carry": {"mods": [], "equipped_weapon": {}, "equipped_armor": {}, "backpack": []},
		"chests_saved": 0,
		"loot": [],
		"seed": 5,
	}
	for key in overrides:
		result[key] = overrides[key]
	return result


func _test_normal_battle_drops_collectibles() -> void:
	var run := _fresh_run()
	BridgeScript.last_result = _result({"kind": BridgeScript.KIND_BATTLE, "place": "battle_1"})
	var outcome: Dictionary = BridgeScript.settle(run)
	var total_owned: int = run.collectibles.size()
	for count in run.collectible_consumables.values():
		total_owned += int(count)
	_check(total_owned == 1, "an ordinary victory grants one random common collectible")
	_check(str(outcome.get("message", "")).contains("藏品"), "the ordinary reward is reported to the player")
	for collectible_id in run.collectibles:
		_check(CollectibleCatalogScript.rarity_of(collectible_id) == CollectibleCatalogScript.RARITY_COMMON, "ordinary drops stay common")


func _test_active_collectibles_stack_and_use() -> void:
	var run := _fresh_run()
	var supplies_before: int = run.supplies
	_check(run.grant_collectible(&"col_field_ration"), "an active ration can be acquired")
	_check(run.grant_collectible(&"col_field_ration"), "active consumables may stack")
	_check(int(run.collectible_consumables.get("col_field_ration", 0)) == 2, "the active stack records both copies")
	_check(run.supplies == supplies_before, "an active consumable does not trigger on acquisition")
	var used: Dictionary = run.use_collectible(&"col_field_ration")
	_check(bool(used.get("ok", false)), "the player can actively use a ration")
	_check(run.supplies == supplies_before + 2, "using the ration grants its supplies")
	_check(int(run.collectible_consumables.get("col_field_ration", 0)) == 1, "using consumes exactly one copy")

	run.hero_health = 1000
	run.grant_collectible(&"col_medicinal_pouch")
	var healed: Dictionary = run.use_collectible(&"col_medicinal_pouch")
	_check(bool(healed.get("ok", false)) and run.hero_health == 1300, "the medical pouch heals when used")
	_check(not run.collectible_consumables.has("col_medicinal_pouch"), "a used medical pouch is consumed")
	var full_health: int = run.hero_health
	run.grant_collectible(&"col_medicinal_pouch")
	run.hero_health = run.effective_max_health()
	var refused: Dictionary = run.use_collectible(&"col_medicinal_pouch")
	_check(not bool(refused.get("ok", false)), "a full-health use is refused")
	_check(int(run.collectible_consumables.get("col_medicinal_pouch", 0)) == 1, "a refused use does not consume the item")


func _test_relics_are_unique_and_raise_dew_capacity() -> void:
	var run := _fresh_run()
	_check(run.add_relic(&"relic_homeward_bell"), "a valid relic can be acquired")
	_check(not run.add_relic(&"relic_homeward_bell"), "a relic cannot be duplicated")
	_check(not run.add_relic(&"relic_unknown"), "unknown relic ids are rejected")
	_check(run.effective_dew_cap() == run.dew_cap + 2, "the homeward bell raises shared dew capacity by two")
	_check(run.add_dew("spring", 2), "the relic's added capacity can be filled")
	_check(not run.add_dew("winter", 1), "dew cannot exceed the relic-adjusted shared cap")


func _test_prepare_refuses_unknown() -> void:
	var run := _fresh_run()
	_check(not BridgeScript.prepare(run, &"B999", &"battle_1"), "an unknown encounter cannot be prepared")
	_check(not BridgeScript.has_pending(), "a refused preparation writes nothing")
	_check(BridgeScript.prepare(run, &"B001", &"battle_1", BridgeScript.KIND_BATTLE), "a known encounter prepares")
	_check(BridgeScript.has_pending(), "preparing fills the handshake")
	_check(str(BridgeScript.pending["encounter"]) == "B001", "the handshake names the fight")
	_check(str(BridgeScript.pending["place"]) == "battle_1", "the handshake remembers the place")
	BridgeScript.clear_pending()


func _test_payload_maps_vitals_and_relics() -> void:
	var run := _fresh_run()
	run.add_relic(&"relic_spring_charm")
	run.add_relic(&"relic_old_hairpin")
	run.hero_health = 2000
	BridgeScript.prepare(run, &"B001", &"battle_1")

	var state := RunStateScript.new()
	BridgeScript.apply_payload(state, BridgeScript.pending)
	_check(state.hero_health == 2000, "the hero's current health crosses into the battle")
	_check(state.effective_max_health() == SpringRun.HERO_BASE_MAX_HEALTH + 300, "the relic raises the battle ceiling")
	_check(state.effective_attack() == SpringRun.HERO_BASE_ATTACK + 80, "the relic raises the battle attack")
	BridgeScript.clear_pending()

	# Damage taken in battle comes back to the run.
	var carried := _fresh_run()
	carried.hero_health = 3300
	BridgeScript.last_result = _result({"hero_health": 1200, "place": "battle_2"})
	BridgeScript.settle(carried)
	_check(carried.hero_health == 1200, "health after the fight is the run's health")


func _test_victory_settles() -> void:
	var run := _fresh_run()
	var stamina_before: int = run.exploration.stamina
	var coins_before: int = run.coins
	var position_before: Vector2i = run.exploration.position
	BridgeScript.last_result = _result({"chests_saved": 3})

	var outcome: Dictionary = BridgeScript.settle(run)
	_check(not BridgeScript.has_result(), "settling consumes the result")
	_check(run.exploration.completed.has(&"battle_1"), "a win finishes the node")
	_check(run.battles_won == 1, "the win is counted")
	_check(run.coins == coins_before + 3 * BridgeScript.CHEST_COINS, "three surviving chests pay 30 coins")
	_check(run.exploration.stamina == stamina_before, "a fight costs no exploration stamina (§11.2)")
	_check(run.exploration.position == position_before, "a fight returns to the same cell (§11.2)")
	_check(str(outcome["message"]).contains("战斗胜利"), "the outcome says the fight was won")
	_check(run.hero_health == 1200, "the win carries the hero's health back")


func _test_defeat_finishes_the_node() -> void:
	var run := _fresh_run()
	BridgeScript.last_result = _result({"result": "defeat", "hero_health": 1, "chests_saved": 0})
	var outcome: Dictionary = BridgeScript.settle(run)
	_check(run.exploration.completed.has(&"battle_1"), "a lost node is marked done, not retryable (§11.3)")
	_check(run.battles_won == 0, "a loss does not count as a win")
	_check(run.coins == 100, "a loss pays nothing")
	_check(not bool(outcome.get("finished_run", false)), "the first loss leaves the run alive")
	_check(not run.exploration.finished, "the run is not over yet")
	var restored := SpringRun.from_dict(run.to_dict())
	_check(restored.revive_prompt and not restored.revive_used, "a restored defeat still requires the continuation decision")
	_check(str(outcome["message"]).contains("补给"), "the outcome points at the continuation")


func _test_continue_is_one_shot() -> void:
	var run := _fresh_run()
	run.hero_health = 1
	var supplies_before: int = run.supplies
	var outcome: Dictionary = BridgeScript.continue_run(run)
	_check(bool(outcome["ok"]), "the first continuation works")
	_check(run.supplies == supplies_before - BridgeScript.CONTINUE_SUPPLY_COST, "it costs three supplies")
	_check(run.hero_health == int(round(float(run.effective_max_health()) * BridgeScript.CONTINUE_HEALTH_FRACTION)),
		"it restores exactly 30% of max health")
	_check(run.revive_used, "the area's continuation is spent")

	run.hero_health = 1
	var second: Dictionary = BridgeScript.continue_run(run)
	_check(not bool(second["ok"]), "a second continuation in the same area is refused")
	_check(run.hero_health == 1, "a refused continuation heals nothing")

	# Too poor: refused and nothing is deducted.
	var poor := _fresh_run()
	poor.supplies = 1
	poor.hero_health = 1
	var denied: Dictionary = BridgeScript.continue_run(poor)
	_check(not bool(denied["ok"]), "an empty larder cannot continue")
	_check(poor.supplies == 1, "a refused continuation charges nothing")
	_check(not poor.revive_used, "a refused continuation does not spend the area's one use")


func _test_elite_offers_three() -> void:
	var run := _fresh_run()
	BridgeScript.last_result = _result({"kind": BridgeScript.KIND_ELITE, "place": "elite"})
	var outcome: Dictionary = BridgeScript.settle(run)
	var choices: Array = outcome["reward_choices"]
	_check(choices.size() == 3, "an elite win offers three candidates (§14)")
	var seen: Dictionary = {}
	for choice in choices:
		_check(not seen.has(String(choice)), "candidate %s appears once" % String(choice))
		seen[String(choice)] = true
		_check(CollectibleCatalogScript.has_collectible(choice), "candidate %s is a real collectible" % String(choice))
		_check(CollectibleCatalogScript.rarity_of(choice) != CollectibleCatalogScript.RARITY_EPIC,
			"candidate %s is not epic (§14)" % String(choice))
	_check(run.collectibles.is_empty(), "the choice is not granted until the player picks")
	var restored := SpringRun.from_dict(run.to_dict())
	_check(restored.reward_choices == choices, "reloading preserves the exact unclaimed elite choices")

	# Owning everything leaves no candidates rather than duplicates.
	var loaded := _fresh_run()
	for collectible_id in CollectibleCatalogScript.candidates_for("elite"):
		loaded.grant_collectible(StringName(collectible_id))
	var exhausted: Array = BridgeScript.roll_reward_choices(loaded, "elite", 3, 5)
	_check(exhausted.is_empty(), "a fully collected pool yields no candidates")


func _test_boss_closes_the_region() -> void:
	var run := _fresh_run()
	run.exploration.stamina = 4
	run.exploration.mark_completed(&"battle_1")
	BridgeScript.last_result = _result({"kind": BridgeScript.KIND_BOSS, "place": "boss"})
	var outcome: Dictionary = BridgeScript.settle(run)
	var transition: Dictionary = outcome.get("region_transition", {})
	_check(run.exploration.completed.has(&"boss"), "the boss node is finished")
	_check(run.exploration.finished, "beating the boss ends 春之境 (§3)")
	_check(run.exploration.finish_reason == "cleared", "a boss victory is a clear, not a defeat")
	_check(run.exploration.stamina == 0, "remaining exploration stamina is discarded at the floor boundary")
	_check(not run.exploration.can_interact(), "the player cannot keep exploring after the boss")
	_check(not run.exploration.can_move_to(run.exploration.position + Vector2i.RIGHT), "the finished floor rejects further movement")
	_check(bool(outcome["finished_run"]), "the outcome reports the current exploration as finished")
	_check(String(transition.get("from_region", "")) == "spring", "the transition starts from 春之境")
	_check(String(transition.get("next_region", "")) == "summer", "the next floor is 夏之境")
	_check(String(transition.get("status", "")) == "locked", "夏之境 remains locked in this build")
	_check(not bool(transition.get("can_enter", true)), "the locked next floor cannot be entered")
	_check(str(outcome["message"]).contains("夏之境") and str(outcome["message"]).contains("尚未解锁"),
		"the player-facing result explains why the next floor cannot open")
	_check(run.collectibles.size() <= 1, "the boss pays at most one passive collectible")
	_check(run.relics.size() == 1, "the boss guarantees one unique relic while the pool remains")

	# An unlocked next region is not a completed adventure: the current floor
	# closes, while the map receives an explicit scene-transition request.
	var available_run := _fresh_run()
	available_run.exploration.stamina = 3
	var available_result := _result({"kind": BridgeScript.KIND_BOSS, "place": "boss"})
	var available_outcome: Dictionary = BridgeScript.settle_result(available_run, available_result, [&"spring", &"summer"], true)
	var available_transition: Dictionary = available_outcome.get("region_transition", {})
	_check(bool(available_transition.get("can_enter", false)), "an unlocked region with an available scene can be entered")
	_check(str(available_transition.get("status", "")) == "available", "the transition distinguishes an enterable region")
	_check(available_run.exploration.finished and available_run.exploration.stamina == 0, "the spring floor closes and discards its stamina before handoff")
	_check(not bool(available_outcome.get("finished_run", true)), "entering the next region does not mark the whole adventure complete")
	_check(str(available_transition.get("scene_path", "")).ends_with("summer_map.tscn"), "the transition carries the next region scene path")

	# The boss pool may include the epic, the elite pool may not.
	var boss_candidates: Array[String] = CollectibleCatalogScript.candidates_for("boss")
	var has_epic: bool = false
	for candidate_id in boss_candidates:
		if CollectibleCatalogScript.rarity_of(StringName(candidate_id)) == CollectibleCatalogScript.RARITY_EPIC:
			has_epic = true
	_check(has_epic, "the boss pool reaches epic (§15.4)")



func _test_region_unlock_persistence() -> void:
	var test_path := "user://test_region_progression.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	var initial: Array[StringName] = RegionProgressionScript.get_unlocked_region_ids(test_path)
	_check(initial.has(&"spring") and not initial.has(&"summer"), "a fresh profile unlocks spring only")
	_check(RegionProgressionScript.unlock_region(&"summer", test_path), "a valid region unlock is persisted")
	var restored: Array[StringName] = RegionProgressionScript.get_unlocked_region_ids(test_path)
	_check(restored.has(&"summer"), "the summer unlock survives reloading progression data")
	var no_scene: Dictionary = RegionProgressionScript.resolve_next(&"spring", restored, false)
	_check(str(no_scene.get("status", "")) == "content_unavailable" and not bool(no_scene.get("can_enter", true)), "an unlocked region without a scene fails closed")
	_check(not RegionProgressionScript.unlock_region(&"unknown", test_path), "unknown region ids cannot be unlocked")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))


func _test_save_keeps_the_fight_results() -> void:
	var run := _fresh_run()
	run.hero_health = 1300
	run.grant_collectible(&"col_petal_purse")
	run.grant_collectible(&"col_field_ration")
	run.add_relic(&"relic_homeward_bell")
	run.battles_won = 2
	run.exploration.mark_completed(&"battle_1")
	run.battle_carry["mods"] = ["heavy_push"]
	run.add_battle_item({"id": &"weapon_oath_greatsword", "kind": "weapon", "name": "誓约重剑"})

	var restored: SpringRun = SpringRun.from_dict(run.to_dict())
	_check(restored != null, "a run with content restores")
	if restored == null:
		return
	_check(restored.hero_health == 1300, "health survives the save")
	_check(restored.has_collectible(&"col_petal_purse"), "passive collectibles survive the save")
	_check(int(restored.collectible_consumables.get("col_field_ration", 0)) == 1, "active consumable stacks survive the save")
	_check(restored.relics.has(&"relic_homeward_bell") and restored.effective_dew_cap() == 2, "relics and their capacity bonus survive the save")
	_check(restored.battles_won == 2, "the win count survives the save")
	_check(restored.exploration.completed.has(&"battle_1"), "finished nodes survive the save")
	_check(restored.battle_carry["mods"] == ["heavy_push"], "the battle carry survives the save")
	_check(restored.battle_carry["backpack"].size() == 1, "the backpack survives the save")


## SpringRun duplicates the hero's four stats because it must not depend on the
## battle layer (§4). Duplication drifts, so this pins the copy to the sheet:
## changing one without the other fails here rather than in a balance bug.
func _test_baseline_matches_the_hero_sheet() -> void:
	var sheet = CharacterCatalogScript.get_definition(SpringRun.HERO_CHARACTER_ID)
	_check(sheet != null, "the spring run names a character sheet that exists")
	if sheet == null:
		return
	_check(SpringRun.HERO_BASE_MAX_HEALTH == sheet.max_health, "baseline health matches the sheet", "%d vs %d" % [SpringRun.HERO_BASE_MAX_HEALTH, sheet.max_health])
	_check(SpringRun.HERO_BASE_ATTACK == sheet.attack, "baseline attack matches the sheet", "%d vs %d" % [SpringRun.HERO_BASE_ATTACK, sheet.attack])
	_check(SpringRun.HERO_BASE_DEFENSE == sheet.defense, "baseline defense matches the sheet", "%d vs %d" % [SpringRun.HERO_BASE_DEFENSE, sheet.defense])
	_check(SpringRun.HERO_BASE_MAGIC_RESISTANCE == sheet.magic_resistance, "baseline resistance matches the sheet", "%d vs %d" % [SpringRun.HERO_BASE_MAGIC_RESISTANCE, sheet.magic_resistance])


## §2: 樱 is the lead of this mode. Before this change the spring run built its
## encounter with the *default* character, so the mode was played as 瑟弗林 with
## her 3600 HP and oath kit while the narrative kept calling the lead 樱.
func _test_the_spring_hero_fights_as_herself() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var placed := battle.start_encounter(
		Vector2i(3, 6), [Vector2i(3, 5)], [], ["petal_warrior"], [String(SpringRun.HERO_CHARACTER_ID)]
	)
	_check(placed, "a spring encounter accepts the spring hero")
	var hero = battle.get_active_character()
	_check(hero != null and hero.character_id == &"sakura", "the deployed hero is 樱", "id=%s" % (String(hero.character_id) if hero != null else "none"))
	_check(hero.max_health == 1800, "she fights with her own health pool", "max=%d" % hero.max_health)

	# Her kit, not Sevrin's: 穿花 is a 樱 skill and must resolve; 誓刃 is not hers
	# and must be refused even though the executor exists.
	battle.ap.reset()
	var enemy = battle.get_actor("petal_warrior_00")
	enemy.cell = hero.cell + Vector2i(0, -1)
	var before: int = enemy.health
	_check(battle.request_skill(&"sakura_pierce_blossom", enemy.actor_id), "樱 can use 穿花")
	_check(enemy.health < before, "穿花 lands damage", "before=%d after=%d" % [before, enemy.health])
	_check(not battle.request_skill(&"oathblade", enemy.actor_id), "she cannot borrow 瑟弗林's 誓刃")
	battle.queue_free()
