class_name SpringShop
extends RefCounted

## 春日行商 (设计汇总 2026-11-26 §7): buy / sell / service.
##
## What the document fixes and this file therefore treats as rules:
##   - stock is rolled once and then locked; leaving and re-entering keeps the
##     same goods and the same remaining counts (§7.2);
##   - bought goods never come back, not even after a paid refresh (§7.2);
##   - refresh costs grow with the number of refreshes in this shop (§7.2);
##   - an economic event only touches the *next* shop, applied once on arrival
##     (§7.3 / §10.4);
##   - every trade is atomic: money and goods move together or not at all (§7.4).
##
## What the document leaves open, and what is therefore a draft in one table:
## the six-slot layout, the base prices, the refresh fees (the document's
## 15/25/40/60/85 are explicitly examples) and the sell rate.
##
## One deliberate departure: the document asks for a "季节商品" slot whose spring
## direction is recovery. Spring has exactly one healing item, so a dedicated slot
## would sit empty half the time; the slot is folded into the consumable/gear
## pools instead. Recorded in PROJECT_STATUS.md.

const LootCatalogScript = preload("res://scripts/battle/loot_catalog.gd")

const SLOT_COUNT: int = 6
const SUPPLY_BUNDLE: int = 3

## The document's example ladder, not a confirmed price list.
const REFRESH_FEES: Array[int] = [15, 25, 40, 60, 85]

const BASE_PRICE := {
	"supply": 18,
	"consumable": 40,
	"upgrade": 70,
	"gear": 90,
}

## Sell prices are computed independently of buy prices (§7.4) so there is no
## buy-low / sell-high loop.
const SELL_RATE := 0.5

const SERVICE_REST: String = "rest"
const SERVICE_REST_COST: int = 30
const SERVICE_REST_FRACTION: float = 0.25

## Slot plan: the guaranteed categories first, then two wildcard slots.
const SLOT_PLAN: Array[String] = ["supply", "consumable", "upgrade", "gear", "random", "random"]

var seed_value: int = 0
## Price multiplier handed down by economic events. 1.0 means "no event".
var price_multiplier: float = 1.0
var stock: Array[Dictionary] = []
## Item ids bought here. Kept so a refresh cannot re-offer them.
var sold_out: Array[String] = []
var purchases: Array[Dictionary] = []
var sales: Array[Dictionary] = []
var services_done: Array[String] = []
var refresh_count: int = 0


static func create(p_seed: int, p_multiplier: float = 1.0) -> SpringShop:
	var shop := SpringShop.new()
	shop.seed_value = p_seed
	shop.price_multiplier = p_multiplier
	shop.refresh_count = 0
	shop._roll_stock()
	return shop


static func from_dict(data: Dictionary) -> SpringShop:
	var shop := SpringShop.new()
	shop.seed_value = int(data.get("seed", 0))
	shop.price_multiplier = float(data.get("price_multiplier", 1.0))
	shop.refresh_count = int(data.get("refresh_count", 0))
	for entry in data.get("stock", []):
		shop.stock.append((entry as Dictionary).duplicate(true))
	for item_id in data.get("sold_out", []):
		shop.sold_out.append(str(item_id))
	for entry in data.get("purchases", []):
		shop.purchases.append((entry as Dictionary).duplicate(true))
	for entry in data.get("sales", []):
		shop.sales.append((entry as Dictionary).duplicate(true))
	for service in data.get("services_done", []):
		shop.services_done.append(str(service))
	return shop


func to_dict() -> Dictionary:
	return {
		"seed": seed_value,
		"price_multiplier": price_multiplier,
		"refresh_count": refresh_count,
		"stock": stock.duplicate(true),
		"sold_out": sold_out.duplicate(),
		"purchases": purchases.duplicate(true),
		"sales": sales.duplicate(true),
		"services_done": services_done.duplicate(),
	}


# --- stock -------------------------------------------------------------------

## Rolls the six slots. Guaranteed categories first; a category with no candidate
## falls back to the full pool, per §7.1.
func _roll_stock() -> void:
	stock.clear()
	var rng := RandomNumberGenerator.new()
	# Each refresh is a different roll but still reproducible from the save.
	rng.seed = hash("%d|%d" % [seed_value, refresh_count])
	# Anything already bought here is off the shelves for good (§7.2). Without
	# this, a refresh would top a partly-bought bundle back up to full.
	var used: Array[String] = sold_out.duplicate()
	for record in purchases:
		var bought_id: String = str(record.get("id", ""))
		if not bought_id.is_empty() and not used.has(bought_id):
			used.append(bought_id)

	for index in range(SLOT_COUNT):
		var category: String = SLOT_PLAN[index]
		if category == "random":
			category = _pick_category(rng)
		var entry := _make_entry(category, rng, used)
		if entry.is_empty():
			entry = _make_entry(_pick_category(rng), rng, used)
		if entry.is_empty():
			continue
		entry["slot"] = index
		stock.append(entry)
		used.append(str(entry["id"]))


func _pick_category(rng: RandomNumberGenerator) -> String:
	var categories: Array[String] = ["consumable", "upgrade", "gear", "supply"]
	return categories[rng.randi_range(0, categories.size() - 1)]


func _make_entry(category: String, rng: RandomNumberGenerator, used: Array[String]) -> Dictionary:
	if category == "supply":
		# Bought-out supplies do not come back on a refresh (§7.2), so a shop that
		# has already sold both bundles simply has no supply slot.
		if used.has("supply_bundle"):
			return {}
		return {
			"id": "supply_bundle",
			"category": "supply",
			"name": "补给 ×%d" % SUPPLY_BUNDLE,
			"desc": "全队共享的补给，用于恢复、事件与交易。",
			"price": _price("supply"),
			"remaining": 2,
			"item": {},
		}

	var pool := _pool_for(category)
	if pool.is_empty():
		return {}
	var candidates: Array[Dictionary] = []
	for item in pool:
		if used.has(str(item["id"])):
			continue
		candidates.append(item)
	if candidates.is_empty():
		return {}
	var picked: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	var kind: String = str(picked.get("kind", ""))
	var rarity: String = "consumable" if kind == "consumable" else ("upgrade" if kind == "skill_upgrade" else "gear")
	return {
		"id": str(picked["id"]),
		"category": rarity,
		"name": str(picked.get("name", "")),
		"desc": str(picked.get("desc", "")),
		"price": _price(rarity),
		"remaining": 1 if rarity != "consumable" else 2,
		"item": picked.duplicate(true),
	}


func _pool_for(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item_id in _catalog_ids():
		var item: Dictionary = LootCatalogScript.get_item(item_id)
		if item.is_empty():
			continue
		var kind: String = str(item.get("kind", ""))
		match category:
			"consumable":
				if kind == LootCatalogScript.KIND_CONSUMABLE:
					result.append(item)
			"upgrade":
				if kind == LootCatalogScript.KIND_SKILL_UPGRADE:
					result.append(item)
			"gear":
				if kind == LootCatalogScript.KIND_WEAPON or kind == LootCatalogScript.KIND_ARMOR:
					result.append(item)
	return result


## LootCatalog keeps its sheets private; its public surface is get_item() over
## known ids, so the ids are listed here rather than reaching into the catalog.
static func _catalog_ids() -> Array[StringName]:
	return [
		&"weapon_oath_greatsword", &"weapon_echo_halberd", &"weapon_dusk_blade",
		&"armor_iron_bulwark", &"armor_echo_mantle", &"armor_warden_plate",
		&"item_dusk_potion", &"item_echo_hourglass", &"item_vow_talisman",
		&"upg_heavy_push", &"upg_shatter_slam", &"upg_shock_shield", &"upg_wide_verdict",
	]


func _price(category: String) -> int:
	var base: int = int(BASE_PRICE.get(category, 50))
	return maxi(1, int(round(float(base) * price_multiplier)))


# --- buying ------------------------------------------------------------------

func can_buy(index: int, run) -> bool:
	if index < 0 or index >= stock.size():
		return false
	var entry: Dictionary = stock[index]
	if int(entry.get("remaining", 0)) <= 0:
		return false
	return run.coins >= int(entry.get("price", 0))


## Atomic: the coins leave and the goods arrive together, or nothing happens.
func buy(index: int, run) -> Dictionary:
	var result := {"ok": false, "message": ""}
	if index < 0 or index >= stock.size():
		result["message"] = "没有这件商品。"
		return result
	var entry: Dictionary = stock[index]
	if int(entry.get("remaining", 0)) <= 0:
		result["message"] = "这件已经卖光了。"
		return result
	var price: int = int(entry.get("price", 0))
	if not run.spend_coins(price):
		result["message"] = "花钿不足：需要 %d，现有 %d。" % [price, run.coins]
		return result

	entry["remaining"] = int(entry["remaining"]) - 1
	stock[index] = entry
	_deliver(entry, run)

	var record := {
		"id": str(entry["id"]),
		"name": str(entry["name"]),
		"price": price,
		"slot": int(entry.get("slot", index)),
	}
	purchases.append(record)
	if int(entry["remaining"]) <= 0 and not sold_out.has(str(entry["id"])):
		sold_out.append(str(entry["id"]))
	result["ok"] = true
	result["message"] = "买下了「%s」。" % str(entry["name"])
	return result


func _deliver(entry: Dictionary, run) -> void:
	if str(entry.get("category", "")) == "supply":
		run.add_supplies(SUPPLY_BUNDLE)
		return
	var item: Dictionary = entry.get("item", {})
	if not item.is_empty():
		run.add_battle_item(item)


# --- selling -----------------------------------------------------------------

## What the player may sell: the gear and consumables sitting in the battle
## backpack. Relics, memory pages and collectibles are progress, and §7.4 says
## story-critical items are not for sale.
func sellable_index(run, index: int) -> bool:
	var bag: Array = run.battle_backpack()
	if index < 0 or index >= bag.size():
		return false
	var item: Dictionary = bag[index]
	var kind: String = str(item.get("kind", ""))
	return kind == LootCatalogScript.KIND_WEAPON \
		or kind == LootCatalogScript.KIND_ARMOR \
		or kind == LootCatalogScript.KIND_CONSUMABLE \
		or kind == LootCatalogScript.KIND_SKILL_UPGRADE


static func sell_price(item: Dictionary) -> int:
	var kind: String = str(item.get("kind", ""))
	var category: String = "gear"
	if kind == LootCatalogScript.KIND_CONSUMABLE:
		category = "consumable"
	elif kind == LootCatalogScript.KIND_SKILL_UPGRADE:
		category = "upgrade"
	var base: int = int(BASE_PRICE.get(category, 50))
	return maxi(1, int(round(float(base) * SELL_RATE)))


## Atomic, like buying. Sold items do not return to the shop's shelves (§7.4).
func sell(run, index: int) -> Dictionary:
	var result := {"ok": false, "message": ""}
	if not sellable_index(run, index):
		result["message"] = "这件不能出售。"
		return result
	var bag: Array = run.battle_backpack()
	var item: Dictionary = bag[index]
	var price: int = sell_price(item)
	if not run.remove_battle_item(index):
		result["message"] = "背包里没有这件东西。"
		return result
	run.add_coins(price)
	sales.append({"id": str(item.get("id", "")), "name": str(item.get("name", "")), "price": price})
	result["ok"] = true
	result["message"] = "卖掉「%s」，得到 %d 花钿。" % [str(item.get("name", "")), price]
	return result


# --- refresh -----------------------------------------------------------------

func refresh_cost() -> int:
	var index: int = mini(refresh_count, REFRESH_FEES.size() - 1)
	return REFRESH_FEES[index]


func can_refresh(run) -> bool:
	return run.coins >= refresh_cost()


## Paid re-roll. Bought goods stay bought: `sold_out` is carried into the new roll.
func refresh(run) -> Dictionary:
	var result := {"ok": false, "message": ""}
	var cost: int = refresh_cost()
	if not run.spend_coins(cost):
		result["message"] = "花钿不足：刷新需要 %d。" % cost
		return result
	refresh_count += 1
	_roll_stock()
	result["ok"] = true
	result["message"] = "花 %d 花钿换了新货。" % cost
	return result


# --- services ----------------------------------------------------------------

func can_use_service(service_id: String, run) -> bool:
	if service_id != SERVICE_REST:
		return false
	if services_done.has(service_id):
		return false
	if run.hero_health >= run.hero_max_health:
		return false
	return run.coins >= SERVICE_REST_COST


## One service per shop (§7.2 keeps "已完成服务" across visits). The rest is
## capped at max health, and the coin leaves only if there is health to restore.
func use_service(service_id: String, run) -> Dictionary:
	var result := {"ok": false, "message": ""}
	if service_id != SERVICE_REST:
		result["message"] = "没有这项服务。"
		return result
	if services_done.has(service_id):
		result["message"] = "这项服务已经用过了。"
		return result
	if run.hero_health >= run.hero_max_health:
		result["message"] = "生命已满，不需要疗养。"
		return result
	if not run.spend_coins(SERVICE_REST_COST):
		result["message"] = "花钿不足：疗养需要 %d。" % SERVICE_REST_COST
		return result
	var healed: int = run.heal_fraction(SERVICE_REST_FRACTION)
	services_done.append(service_id)
	result["ok"] = true
	result["message"] = "疗养完毕，回复 %d 点生命。" % healed
	return result


static func service_label(service_id: String) -> String:
	if service_id == SERVICE_REST:
		return "疗养（%d 花钿 · 回复 %d%% 生命）" % [SERVICE_REST_COST, int(SERVICE_REST_FRACTION * 100.0)]
	return service_id

