extends "res://tests/framework/test_case.gd"

## 春之境 events (设计汇总 2026-11-26 §10.2, §10.4).
##
## The document fixes the ten events, their options and the direction of each
## option's effect; the amounts are drafts. So these assertions pin behaviour, not
## numbers: an option the player cannot pay for is refused without touching
## anything, a chosen option resolves exactly once, risk is seeded (the same
## choice on the same run always lands the same way), an economic event prices the
## next shop, and no event can take the run down to zero health.

const CatalogScript = preload("res://scripts/spring/spring_event_catalog.gd")
const EncounterCatalogScript = preload("res://scripts/spring/spring_encounter_catalog.gd")
const CollectibleCatalogScript = preload("res://scripts/spring/spring_collectible_catalog.gd")


func _run() -> void:
	_test_pool_shape()
	_test_every_option_resolves_when_affordable()
	_test_unaffordable_option_touches_nothing()
	_test_named_effects_land_where_the_document_says()
	_test_economic_events_price_the_next_shop()
	_test_health_floor_is_one()
	_test_repeat_resolution_is_identical()
	_test_battles_are_real_encounters()
	_test_collectibles_never_duplicate()
	_test_reveal_is_reported()
	_test_feast_of_hidden_hoard()


func _fresh_run(seed_value: int = 7) -> SpringRun:
	var run := SpringRun.begin(seed_value)
	run.add_coins(1000)
	run.add_supplies(20)
	run.dew_cap = 20
	run.hero_health = run.effective_max_health()
	return run


func _test_pool_shape() -> void:
	_check(CatalogScript.EVENTS.size() == 11, "the pool holds the ten document events plus the hidden hoard")
	for event_id in CatalogScript.EVENTS:
		var key := StringName(event_id)
		_check(not CatalogScript.title_of(key).is_empty(), "%s has a title" % event_id)
		_check(not CatalogScript.body_of(key).is_empty(), "%s has body text" % event_id)
		_check(CatalogScript.option_count(key) >= 2, "%s offers at least two options" % event_id)
		var risk: String = CatalogScript.risk_of(key)
		_check([CatalogScript.RISK_SAFE, CatalogScript.RISK_UNKNOWN, CatalogScript.RISK_DANGER, CatalogScript.RISK_HIGH].has(risk),
			"%s carries one of the four risk labels" % event_id)
	for event_id in CatalogScript.RANDOM_POOL:
		_check(CatalogScript.has_event(StringName(event_id)), "the random pool only names known events (%s)" % event_id)


func _test_every_option_resolves_when_affordable() -> void:
	for event_id in CatalogScript.EVENTS:
		var key := StringName(event_id)
		for index in range(CatalogScript.option_count(key)):
			var run := _fresh_run()
			# The collector's "trade one in" needs a collectible in hand; a rich
			# purse is not enough for that one, so hand it one first.
			if not run.collectibles.is_empty() or run.collectibles.size() == 0:
				run.grant_collectible(&"col_petal_purse")
			if not CatalogScript.can_afford(run, key, index):
				_check(false, "%s option %d should be affordable on a stocked run" % [event_id, index])
				continue
			var result: Dictionary = CatalogScript.resolve(run, key, index)
			_check(bool(result["ok"]), "%s option %d resolves" % [event_id, index])
			_check(not (result["log"] as Array).is_empty(), "%s option %d says what happened" % [event_id, index])
			_check(run.hero_health >= 1, "%s option %d never kills the hero" % [event_id, index])


func _test_unaffordable_option_touches_nothing() -> void:
	var run := _fresh_run()
	run.coins = 5
	var before := {"coins": run.coins, "supplies": run.supplies, "pages": run.memory_pages}
	_check(not CatalogScript.can_afford(run, &"unworshipped_shrine", 0), "an empty purse cannot buy the shrine offering")
	var result: Dictionary = CatalogScript.resolve(run, &"unworshipped_shrine", 0)
	_check(not bool(result["ok"]), "the shrine refuses the choice")
	_check(run.coins == before["coins"] and run.supplies == before["supplies"] and run.memory_pages == before["pages"],
		"a refused choice changes nothing")
	_check(CatalogScript.resolve(run, &"unworshipped_shrine", 99).is_empty() == false, "an out-of-range option still returns a result")
	_check(not bool(CatalogScript.resolve(run, &"unworshipped_shrine", 99)["ok"]), "an out-of-range option resolves to nothing")


func _test_named_effects_land_where_the_document_says() -> void:
	# 神龛: pay 20 coins, gain one page.
	var run := _fresh_run()
	var coins_before: int = run.coins
	var pages_before: int = run.memory_pages
	CatalogScript.resolve(run, &"unworshipped_shrine", 0)
	_check(run.coins == coins_before - 20, "the shrine offering costs 20 coins")
	_check(run.memory_pages == pages_before + 1, "the shrine offering grants a page")

	# 失落的旅人: asking for payment pays coins and nothing else.
	run = _fresh_run()
	coins_before = run.coins
	CatalogScript.resolve(run, &"lost_traveler", 1)
	_check(run.coins == coins_before + 25, "the traveller pays 25 for the errand")

	# 无人的营地: resting costs supplies and restores health.
	run = _fresh_run()
	run.hero_health = 1000
	var supplies_before: int = run.supplies
	CatalogScript.resolve(run, &"empty_camp", 0)
	_check(run.supplies == supplies_before - 2, "resting costs two supplies")
	_check(run.hero_health > 1000, "resting restores health")

	# 没有寄出的信: reading pays two pages, burning one.
	run = _fresh_run()
	pages_before = run.memory_pages
	CatalogScript.resolve(run, &"unsent_letter", 0)
	_check(run.memory_pages == pages_before + 2, "reading the letter grants two pages")
	run = _fresh_run()
	pages_before = run.memory_pages
	CatalogScript.resolve(run, &"unsent_letter", 2)
	_check(run.memory_pages == pages_before + 1, "burning the letter grants one page")


func _test_economic_events_price_the_next_shop() -> void:
	var run := _fresh_run()
	CatalogScript.resolve(run, &"old_contract", 0)
	_check(is_equal_approx(run.shop_price_multiplier, 0.80), "signing the old contract prices the next shop at 80%")
	run = _fresh_run()
	CatalogScript.resolve(run, &"old_contract", 2)
	_check(is_equal_approx(run.shop_price_multiplier, 1.20), "tearing it up raises the next shop to 120%")
	# The modifier multiplies rather than replaces.
	run = _fresh_run()
	CatalogScript.resolve(run, &"stranded_caravan", 0)
	CatalogScript.resolve(run, &"old_contract", 0)
	_check(is_equal_approx(run.shop_price_multiplier, 0.85 * 0.80), "two economic events compound")

	# Entering a shop spends the effect; leaving does not bring it back.
	var base_price: int = SpringShop.BASE_PRICE["gear"]
	run = _fresh_run()
	CatalogScript.resolve(run, &"old_contract", 0)
	var shop: SpringShop = run.enter_shop()
	_check(is_equal_approx(shop.price_multiplier, 0.80), "the shop opened with the event's price")
	var discounted: bool = false
	for entry in shop.stock:
		if str(entry["category"]) == "gear":
			discounted = int(entry["price"]) == int(round(float(base_price) * 0.80))
	_check(discounted, "gear on the shelf is priced at the discount")
	run.leave_shop()
	_check(is_equal_approx(run.shop_price_multiplier, 1.0), "leaving clears the pending modifier")


func _test_health_floor_is_one() -> void:
	# The rule lives on the run, so pin it there.
	var run := _fresh_run()
	run.hero_health = 100
	run.damage_hero(300)
	_check(run.hero_health == 1, "event damage stops at one point of health")

	# And the shrine's "take the offering" path must respect it on every seed.
	for seed_value in range(0, 24):
		var seeded := _fresh_run(seed_value)
		seeded.hero_health = 120
		CatalogScript.resolve(seeded, &"unworshipped_shrine", 2)
		if seeded.hero_health < 120:
			_check(seeded.hero_health == 1, "seed %d stops the shrine's curse at one point" % seed_value)
		_check(seeded.hero_health >= 1, "seed %d leaves the hero alive" % seed_value)


func _test_repeat_resolution_is_identical() -> void:
	# Risk rolls are seeded from (run seed, event, option), so replaying the same
	# choice on the same run must land the same way.
	var cases := [["sealed_chest", 1], ["empty_camp", 1], ["unworshipped_shrine", 2]]
	for pair in cases:
		var event_id: String = str(pair[0])
		var option_index: int = int(pair[1])
		var first := _fresh_run(11)
		var second := _fresh_run(11)
		var first_result: Dictionary = CatalogScript.resolve(first, StringName(event_id), option_index)
		var second_result: Dictionary = CatalogScript.resolve(second, StringName(event_id), option_index)
		_check(first_result["log"] == second_result["log"], "%s rolls identically on the same seed" % event_id)
		_check(first.hero_health == second.hero_health, "%s leaves the same health on the same seed" % event_id)
		_check(first.coins == second.coins, "%s leaves the same purse on the same seed" % event_id)


func _test_battles_are_real_encounters() -> void:
	var run := _fresh_run()
	var result: Dictionary = CatalogScript.resolve(run, &"forest_noise", 0)
	_check(String(result["battle"]) == "B007", "investigating the noise starts B007")
	_check(EncounterCatalogScript.has_encounter(StringName(str(result["battle"]))), "the ambush id is a real encounter")

	# Every battle an event can start - including one nested under a risk roll -
	# must exist in the encounter catalog, or the ambush opens an empty board.
	for event_id in CatalogScript.EVENTS:
		var battles: Array[String] = []
		_collect_battles(CatalogScript.EVENTS[event_id]["options"], battles)
		for battle_id in battles:
			_check(EncounterCatalogScript.has_encounter(StringName(battle_id)),
				"%s starts a real encounter (%s)" % [event_id, battle_id])


func _collect_battles(options: Array, out: Array[String]) -> void:
	for option in options:
		for effect in option.get("effects", []):
			_collect_battles_from_effect(effect, out)


func _collect_battles_from_effect(effect: Dictionary, out: Array[String]) -> void:
	if str(effect.get("kind", "")) == CatalogScript.EFFECT_BATTLE:
		out.append(str(effect.get("encounter", "")))
	for nested in effect.get("effects", []):
		_collect_battles_from_effect(nested, out)


func _test_collectibles_never_duplicate() -> void:
	var run := _fresh_run()
	var satchel: Dictionary = CatalogScript.resolve(run, &"lost_traveler", 2)
	_check(bool(satchel["ok"]), "the traveller's satchel resolves")
	var satchel_total: int = run.collectibles.size()
	for count in run.collectible_consumables.values():
		satchel_total += int(count)
	_check(satchel_total == 1, "the satchel yields exactly one collectible")
	if not run.collectibles.is_empty():
		var owned: StringName = run.collectibles[0]
		_check(not run.grant_collectible(owned), "the same passive collectible cannot be granted twice")
	else:
		var active_id := StringName(run.collectible_consumables.keys()[0])
		_check(run.grant_collectible(active_id), "an active consumable can be acquired more than once")
		_check(int(run.collectible_consumables[String(active_id)]) == 2, "the second active copy stacks")

	# Exhausting the pool must not hand out a duplicate; it reports &"" instead.
	var exhausted := _fresh_run()
	for collectible_id in CollectibleCatalogScript.candidates_for("event"):
		exhausted.grant_collectible(StringName(collectible_id))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	_check(exhausted.grant_random_collectible(rng) == &"", "an exhausted pool yields nothing rather than a duplicate")

	# Elite draws never contain the epic (§14).
	for candidate_id in CollectibleCatalogScript.candidates_for("elite"):
		_check(CollectibleCatalogScript.rarity_of(StringName(candidate_id)) != CollectibleCatalogScript.RARITY_EPIC,
			"elite rewards never include %s" % candidate_id)


func _test_reveal_is_reported() -> void:
	var revealed: bool = false
	# 石门之后 option 1 always reveals, whatever the roll says about the trap.
	var run := _fresh_run()
	var result: Dictionary = CatalogScript.resolve(run, &"beyond_stone_door", 1)
	revealed = bool(result.get("reveal_hidden", false))
	_check(revealed, "forcing the stone door always reveals the hidden place")
	_check(run.pending_hidden_reveal == false, "the event itself does not touch the map")


func _test_feast_of_hidden_hoard() -> void:
	var run := _fresh_run()
	var coins_before: int = run.coins
	var result: Dictionary = CatalogScript.resolve(run, &"hidden_hoard", 0)
	_check(bool(result["ok"]), "the hidden hoard opens")
	_check(run.coins >= coins_before + 40, "the hoard pays 40 coins plus any immediate coin collectible")
	var total_collectibles: int = run.collectibles.size()
	for count in run.collectible_consumables.values():
		total_collectibles += int(count)
	_check(total_collectibles == 1, "the hoard yields one collectible")
	_check(run.relics.size() == 1, "the hidden hoard also grants one unique relic")
	if not run.collectibles.is_empty():
		var gained: StringName = run.collectibles[0]
		match String(gained):
			"col_dried_ration":
				_check(run.supplies >= 23, "passive supply collectibles apply when obtained")
			"col_memory_scrap":
				_check(run.memory_pages >= 2, "passive page collectibles apply when obtained")
			"col_spring_vial":
				_check(run.dew_total() >= 3, "passive dew collectibles apply when obtained")
			"col_old_map":
				_check(run.pending_hidden_reveal, "passive map collectibles apply when obtained")
			"col_petal_purse":
				_check(run.coins >= coins_before + 100, "passive coin collectibles apply when obtained")
	else:
		_check(not run.collectible_consumables.is_empty(), "active collectibles are stored for later use")
