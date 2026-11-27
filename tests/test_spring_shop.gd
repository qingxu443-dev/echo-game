extends "res://tests/framework/test_case.gd"

## 春日行商 (设计汇总 2026-11-26 §7).
##
## Pinned: six guaranteed slots, stock locked after the first roll, bought goods
## never return (not even after a paid refresh), refresh fees climb, every trade is
## atomic, selling pays independently of buying, one service per shop, and the whole
## thing survives a save round-trip.

const LootCatalogScript = preload("res://scripts/battle/loot_catalog.gd")


func _run() -> void:
	_test_stock_shape()
	_test_stock_is_locked()
	_test_buy_is_atomic()
	_test_bought_goods_never_return()
	_test_refresh_fee_climbs()
	_test_sell_pays_and_removes()
	_test_sell_refuses_progress()
	_test_service_is_one_shot()
	_test_price_modifier_applies()
	_test_save_round_trip()
	_test_deterministic_stock()


func _fresh_run(seed_value: int = 21) -> SpringRun:
	var run := SpringRun.begin(seed_value)
	run.add_coins(500)
	run.add_supplies(10)
	return run


func _test_stock_shape() -> void:
	var shop := SpringShop.create(1234)
	_check(shop.stock.size() == SpringShop.SLOT_COUNT, "the shop opens six slots")
	var seen: Dictionary = {}
	var has_supply: bool = false
	for entry in shop.stock:
		var entry_id: String = str(entry["id"])
		_check(not seen.has(entry_id), "slot %d holds a distinct item (%s)" % [int(entry["slot"]), entry_id])
		seen[entry_id] = true
		_check(int(entry["price"]) > 0, "%s carries a price" % entry_id)
		_check(int(entry["remaining"]) > 0, "%s starts with stock" % entry_id)
		if str(entry["category"]) == "supply":
			has_supply = true
	_check(has_supply, "the supply slot is always filled (§7.1)")

	# The guaranteed categories: one supply, one consumable, one upgrade, one gear.
	var categories: Dictionary = {}
	for entry in shop.stock:
		categories[str(entry["category"])] = int(categories.get(str(entry["category"]), 0)) + 1
	_check(int(categories.get("supply", 0)) == 1, "exactly one supply slot")
	_check(int(categories.get("consumable", 0)) >= 1, "at least one combat consumable")
	_check(int(categories.get("upgrade", 0)) >= 1, "at least one passive collectible")
	_check(int(categories.get("gear", 0)) >= 1, "at least one piece of gear")


func _test_stock_is_locked() -> void:
	# §7.2: leaving and coming back must show the same goods, not a fresh roll.
	var run := _fresh_run()
	var shop: SpringShop = run.enter_shop()
	var first_ids: Array[String] = []
	for entry in shop.stock:
		first_ids.append(str(entry["id"]))
	run.leave_shop()
	var again: SpringShop = run.enter_shop()
	var second_ids: Array[String] = []
	for entry in again.stock:
		second_ids.append(str(entry["id"]))
	_check(first_ids == second_ids, "re-entering keeps the same stock")
	_check(again == shop, "re-entering returns the same shop object")


func _test_buy_is_atomic() -> void:
	var run := _fresh_run()
	var shop: SpringShop = run.enter_shop()
	var entry: Dictionary = shop.stock[0]
	var price: int = int(entry["price"])
	var remaining: int = int(entry["remaining"])
	var coins_before: int = run.coins

	var result: Dictionary = shop.buy(0, run)
	_check(bool(result["ok"]), "the first purchase goes through")
	_check(run.coins == coins_before - price, "the purchase costs its price")
	_check(int(shop.stock[0]["remaining"]) == remaining - 1, "the shelf loses one unit")
	_check(shop.purchases.size() == 1, "the purchase is recorded")

	# Too poor: nothing moves.
	var poor := _fresh_run()
	poor.coins = 0
	var poor_shop: SpringShop = poor.enter_shop()
	var poor_stock: Array = poor_shop.stock.duplicate(true)
	var denied: Dictionary = poor_shop.buy(0, poor)
	_check(not bool(denied["ok"]), "an empty purse cannot buy")
	_check(poor.coins == 0, "a refused purchase charges nothing")
	_check(poor_shop.stock == poor_stock, "a refused purchase leaves the shelf untouched")
	_check(poor_shop.purchases.is_empty(), "a refused purchase is not recorded")


func _test_bought_goods_never_return() -> void:
	var run := _fresh_run()
	run.add_coins(5000)
	var shop: SpringShop = run.enter_shop()
	var bought_id: String = str(shop.stock[1]["id"])
	# Empty that slot.
	var guard: int = 0
	while int(shop.stock[1]["remaining"]) > 0 and guard < 8:
		shop.buy(1, run)
		guard += 1
	_check(shop.sold_out.has(bought_id), "a sold-out item is remembered")
	shop.refresh(run)
	var reappeared: bool = false
	for entry in shop.stock:
		if str(entry["id"]) == bought_id:
			reappeared = true
	_check(not reappeared, "a refresh never re-offers a bought item (§7.2)")

	# A partly-bought bundle must not be topped back up by a refresh, or buying one
	# supply and refreshing would refill the shelf for free.
	var partial := _fresh_run()
	partial.add_coins(5000)
	var partial_shop: SpringShop = partial.enter_shop()
	var bundle_index: int = -1
	for index in range(partial_shop.stock.size()):
		if str(partial_shop.stock[index]["category"]) == "supply":
			bundle_index = index
	_check(bundle_index >= 0, "a supply bundle is on the shelf")
	partial_shop.buy(bundle_index, partial)
	_check(int(partial_shop.stock[bundle_index]["remaining"]) == 1, "one bundle of two was bought")
	partial_shop.refresh(partial)
	var bundle_back: bool = false
	var bundle_remaining: int = 0
	for entry in partial_shop.stock:
		if str(entry["category"]) == "supply":
			bundle_back = true
			bundle_remaining = int(entry["remaining"])
	_check(not bundle_back, "a refresh does not restock a partly-bought bundle")
	_check(bundle_remaining == 0, "no supply slot is re-created after a purchase")


func _test_refresh_fee_climbs() -> void:
	var run := _fresh_run()
	run.add_coins(5000)
	var shop: SpringShop = run.enter_shop()
	_check(shop.refresh_cost() == SpringShop.REFRESH_FEES[0], "the first refresh costs the first fee")
	var coins_before: int = run.coins
	var result: Dictionary = shop.refresh(run)
	_check(bool(result["ok"]), "a paid refresh goes through")
	_check(run.coins == coins_before - SpringShop.REFRESH_FEES[0], "the refresh charges the first fee")
	_check(shop.refresh_cost() == SpringShop.REFRESH_FEES[1], "the second refresh costs more")
	_check(shop.refresh_count == 1, "the refresh is counted")

	var poor := _fresh_run()
	poor.coins = 1
	var poor_shop: SpringShop = poor.enter_shop()
	_check(not bool(poor_shop.refresh(poor)["ok"]), "a refresh without coins is refused")
	_check(poor_shop.refresh_count == 0, "a refused refresh is not counted")


func _test_sell_pays_and_removes() -> void:
	var run := _fresh_run()
	var sword: Dictionary = LootCatalogScript.get_item(&"weapon_oath_greatsword")
	run.add_battle_item(sword)
	var shop: SpringShop = run.enter_shop()
	var coins_before: int = run.coins
	var expected: int = SpringShop.sell_price(sword)
	var stock_before: int = shop.stock.size()

	var result: Dictionary = shop.sell(run, 0)
	_check(bool(result["ok"]), "the sword sells")
	_check(run.coins == coins_before + expected, "selling pays the sell price")
	_check(run.battle_backpack().is_empty(), "the sold item leaves the backpack")
	_check(shop.stock.size() == stock_before, "selling does not restock the shelves (§7.4)")
	_check(shop.sales.size() == 1, "the sale is recorded")
	_check(not bool(shop.sell(run, 0)["ok"]), "selling an empty slot is refused")

	# Sell price is below buy price, so there is no arbitrage.
	var greatsword_price: int = int(SpringShop.BASE_PRICE["gear"])
	_check(expected < greatsword_price, "selling pays less than buying")


func _test_sell_refuses_progress() -> void:
	# §7.4: story items and progress are not for sale. A collectible never enters
	# the backpack, so an index that points at nothing must be refused.
	var run := _fresh_run()
	var shop: SpringShop = run.enter_shop()
	_check(not bool(shop.sell(run, 0)["ok"]), "an empty backpack has nothing to sell")
	_check(not bool(shop.sell(run, 99)["ok"]), "an out-of-range sale is refused")
	_check(run.coins == 500, "a refused sale changes nothing")


func _test_service_is_one_shot() -> void:
	var run := _fresh_run()
	run.hero_health = 1000
	var shop: SpringShop = run.enter_shop()
	var coins_before: int = run.coins
	var first: Dictionary = shop.use_service(SpringShop.SERVICE_REST, run)
	_check(bool(first["ok"]), "the rest service works")
	_check(run.coins == coins_before - SpringShop.SERVICE_REST_COST, "the service costs its price")
	_check(run.hero_health > 1000, "the service restores health")
	var second: Dictionary = shop.use_service(SpringShop.SERVICE_REST, run)
	_check(not bool(second["ok"]), "the same service cannot be bought twice")

	var full := _fresh_run()
	full.hero_health = full.effective_max_health()
	var full_shop: SpringShop = full.enter_shop()
	_check(not bool(full_shop.use_service(SpringShop.SERVICE_REST, full)["ok"]), "a full-health hero cannot rest")
	_check(full.coins == 500, "a refused service charges nothing")


func _test_price_modifier_applies() -> void:
	var run := _fresh_run()
	run.apply_shop_price_modifier(0.5, "test")
	var shop: SpringShop = run.enter_shop()
	_check(is_equal_approx(shop.price_multiplier, 0.5), "the modifier reaches the shop")
	for entry in shop.stock:
		var category: String = str(entry["category"])
		if SpringShop.BASE_PRICE.has(category):
			var expected: int = int(round(float(SpringShop.BASE_PRICE[category]) * 0.5))
			_check(int(entry["price"]) == expected, "%s is priced at half" % str(entry["id"]))


func _test_save_round_trip() -> void:
	var run := _fresh_run()
	run.add_coins(1000)
	var shop: SpringShop = run.enter_shop()
	shop.buy(0, run)
	shop.refresh(run)
	var saved_stock: Array = shop.stock.duplicate(true)
	var saved_purchases: int = shop.purchases.size()

	var data: Dictionary = run.to_dict()
	var restored: SpringRun = SpringRun.from_dict(data)
	_check(restored != null, "the run restores")
	if restored == null:
		return
	_check(restored.shop != null, "the shop restores with the run")
	_check(restored.shop.stock == saved_stock, "the stock and remaining counts survive the save")
	_check(restored.shop.purchases.size() == saved_purchases, "purchase records survive the save")
	_check(restored.shop.refresh_count == shop.refresh_count, "the refresh count survives the save")
	_check(restored.coins == run.coins, "the purse survives the save")

	# A restored shop still refuses to re-offer what was bought.
	var sold_ids: Array[String] = shop.sold_out.duplicate()
	restored.shop.refresh(restored)
	for entry in restored.shop.stock:
		_check(not sold_ids.has(str(entry["id"])), "a restored shop does not re-offer %s" % str(entry["id"]))


func _test_deterministic_stock() -> void:
	# Two runs with the same seed and no purchases must open the same shelves.
	var first: SpringShop = SpringShop.create(777)
	var second: SpringShop = SpringShop.create(777)
	var first_ids: Array[String] = []
	var second_ids: Array[String] = []
	for entry in first.stock:
		first_ids.append(str(entry["id"]))
	for entry in second.stock:
		second_ids.append(str(entry["id"]))
	_check(first_ids == second_ids, "the same seed rolls the same stock")
	_check(first.price_multiplier == second.price_multiplier, "the same seed carries the same multiplier")
