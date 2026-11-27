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
const RunStateScript = preload("res://scripts/battle/run_state.gd")
const CollectibleCatalogScript = preload("res://scripts/spring/spring_collectible_catalog.gd")


func _run() -> void:
	_test_prepare_refuses_unknown()
	_test_payload_maps_vitals_and_relics()
	_test_victory_settles()
	_test_defeat_finishes_the_node()
	_test_continue_is_one_shot()
	_test_elite_offers_three()
	_test_boss_closes_the_region()
	_test_save_keeps_the_fight_results()


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
		"hero_health": 2400,
		"hero_max_health": 3600,
		"carry": {"mods": [], "equipped_weapon": {}, "equipped_armor": {}, "backpack": []},
		"chests_saved": 0,
		"loot": [],
		"seed": 5,
	}
	for key in overrides:
		result[key] = overrides[key]
	return result


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
	_check(run.hero_health == 2400, "the win carries the hero's health back")


func _test_defeat_finishes_the_node() -> void:
	var run := _fresh_run()
	BridgeScript.last_result = _result({"result": "defeat", "hero_health": 1, "chests_saved": 0})
	var outcome: Dictionary = BridgeScript.settle(run)
	_check(run.exploration.completed.has(&"battle_1"), "a lost node is marked done, not retryable (§11.3)")
	_check(run.battles_won == 0, "a loss does not count as a win")
	_check(run.coins == 100, "a loss pays nothing")
	_check(not bool(outcome.get("finished_run", false)), "the first loss leaves the run alive")
	_check(not run.exploration.finished, "the run is not over yet")
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

	# Owning everything leaves no candidates rather than duplicates.
	var loaded := _fresh_run()
	for collectible_id in CollectibleCatalogScript.candidates_for("elite"):
		loaded.grant_collectible(StringName(collectible_id))
	var exhausted: Array = BridgeScript.roll_reward_choices(loaded, "elite", 3, 5)
	_check(exhausted.is_empty(), "a fully collected pool yields no candidates")


func _test_boss_closes_the_region() -> void:
	var run := _fresh_run()
	run.exploration.mark_completed(&"battle_1")
	BridgeScript.last_result = _result({"kind": BridgeScript.KIND_BOSS, "place": "boss"})
	var outcome: Dictionary = BridgeScript.settle(run)
	_check(run.exploration.completed.has(&"boss"), "the boss node is finished")
	_check(run.exploration.finished, "beating the boss ends 春之境 (§3)")
	_check(bool(outcome["finished_run"]), "the outcome reports the run as finished")
	_check(run.collectibles.size() <= 1, "the boss pays at most one collectible")

	# The boss pool may include the epic, the elite pool may not.
	var boss_candidates: Array[String] = CollectibleCatalogScript.candidates_for("boss")
	var has_epic: bool = false
	for candidate_id in boss_candidates:
		if CollectibleCatalogScript.rarity_of(StringName(candidate_id)) == CollectibleCatalogScript.RARITY_EPIC:
			has_epic = true
	_check(has_epic, "the boss pool reaches epic (§15.4)")


func _test_save_keeps_the_fight_results() -> void:
	var run := _fresh_run()
	run.hero_health = 2600
	run.grant_collectible(&"col_petal_purse")
	run.battles_won = 2
	run.exploration.mark_completed(&"battle_1")
	run.battle_carry["mods"] = ["heavy_push"]
	run.add_battle_item({"id": &"weapon_oath_greatsword", "kind": "weapon", "name": "誓约重剑"})

	var restored: SpringRun = SpringRun.from_dict(run.to_dict())
	_check(restored != null, "a run with content restores")
	if restored == null:
		return
	_check(restored.hero_health == 2600, "health survives the save")
	_check(restored.has_collectible(&"col_petal_purse"), "collectibles survive the save")
	_check(restored.battles_won == 2, "the win count survives the save")
	_check(restored.exploration.completed.has(&"battle_1"), "finished nodes survive the save")
	_check(restored.battle_carry["mods"] == ["heavy_push"], "the battle carry survives the save")
	_check(restored.battle_carry["backpack"].size() == 1, "the backpack survives the save")
