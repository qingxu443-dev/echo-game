class_name SpringSaveValidation
extends RefCounted

const SECTIONS := [
	"exploration", "hidden", "resources", "hero", "battle_carry",
	"event_choices", "pending_event", "event_log", "price", "shop", "route_plan", "party_vitals",
]


static func invalid_field(data: Dictionary) -> String:
	for key in SECTIONS:
		if not data.get(key, {}) is Dictionary:
			return key
	for key in ["version", "template_id", "seed", "battles_won"]:
		if not _whole_number(data.get(key, 0)):
			return key
	for key in ["collectibles", "reward_choices"]:
		if not _list_of(data.get(key, []), TYPE_STRING):
			return key

	if not _is_text(data.get("random_event", "")):
		return "random_event"
	for choice in data.get("reward_choices", []):
		if not SpringCollectibleCatalog.has_collectible(StringName(choice)):
			return "reward_choices"
	var exploration: Dictionary = data.get("exploration", {})
	if exploration.has("position") and not _point(exploration["position"]):
		return "exploration.position"
	var stamina = exploration.get("stamina", 0)
	if not _whole_number(stamina) or stamina < 0 or stamina > ExplorationState.STAMINA_MAX:
		return "exploration.stamina"
	if not _list_of(exploration.get("completed", []), TYPE_STRING):
		return "exploration.completed"

	var hidden: Dictionary = data.get("hidden", {})
	var hidden_cell = hidden.get("cell", [0, 0])
	if not _point(hidden_cell, not bool(hidden.get("revealed", false))):
		return "hidden.cell"

	var resources: Dictionary = data.get("resources", {})
	for key in ["coins", "supplies", "dew_cap", "memory_pages"]:
		var amount = resources.get(key, 0)
		if not _whole_number(amount) or amount < 0:
			return "resources." + key
	var dew = resources.get("dew", {})
	if not dew is Dictionary or not _list_of(resources.get("relics", []), TYPE_STRING):
		return "resources.dew / relics"
	var dew_total := 0.0
	for key in ["spring", "summer", "autumn", "winter"]:
		var amount = dew.get(key, 0)
		if not _whole_number(amount) or amount < 0:
			return "resources.dew." + key
		dew_total += amount
	if dew_total > resources.get("dew_cap", 0):
		return "resources.dew_cap"

	var party_ids: Array = data.get("party_character_ids", [])
	if party_ids.size() > 3 or party_ids.size() != party_ids.duplicate().size():
		return "party_character_ids"
	var party_vitals: Dictionary = data.get("party_vitals", {})
	for character_id in party_vitals:
		var vitals: Variant = party_vitals[character_id]
		if not vitals is Dictionary:
			return "party_vitals." + str(character_id)
		var hp = vitals.get("health", 0)
		var max_hp = vitals.get("max_health", 0)
		if not _whole_number(hp) or not _whole_number(max_hp) or hp < 0 or max_hp <= 0 or hp > max_hp:
			return "party_vitals." + str(character_id)

	var hero: Dictionary = data.get("hero", {})
	for key in ["health", "bonus_max_health", "carry_max_health"]:
		if not _whole_number(hero.get(key, 0)) or hero.get(key, 0) < 0:
			return "hero." + key
	var carry: Dictionary = data.get("battle_carry", {})
	if not _list_of(carry.get("backpack", []), TYPE_DICTIONARY) or not _list_of(carry.get("mods", []), TYPE_STRING):
		return "battle_carry.backpack / mods"
	for key in ["equipped_weapon", "equipped_armor"]:
		if not carry.get(key, {}) is Dictionary:
			return "battle_carry." + key

	var pending: Dictionary = data.get("pending_event", {})
	if not pending.is_empty():
		if not _is_text(pending.get("place")) or not pending.get("result") is Dictionary:
			return "pending_event"
		var outcome: Dictionary = pending["result"]
		if not _list_of(outcome.get("log", []), TYPE_STRING) or not _is_text(outcome.get("battle", "")):
			return "pending_event.result"
		var encounter := StringName(outcome.get("battle", ""))
		if encounter != &"" and not SpringEncounterCatalog.has_encounter(encounter):
			return "pending_event.result.battle"

	var shop: Dictionary = data.get("shop", {})
	for key in ["stock", "sales", "purchases"]:
		if not _list_of(shop.get(key, []), TYPE_DICTIONARY):
			return "shop." + key
	for key in ["sold_out", "services_done"]:
		if not _list_of(shop.get(key, []), TYPE_STRING):
			return "shop." + key
	var price: Dictionary = data.get("price", {})
	if not _list_of(price.get("notes", []), TYPE_STRING):
		return "price.notes"
	if not _positive_number(price.get("multiplier", 1.0)) or not _positive_number(shop.get("price_multiplier", 1.0)):
		return "price.multiplier / shop.price_multiplier"
	for key in ["seed", "refresh_count"]:
		if not _whole_number(shop.get(key, 0)):
			return "shop." + key

	var route: Dictionary = data.get("route_plan", {})
	var waypoints = route.get("waypoints", [])
	var cursor = route.get("cursor", 0)
	if not waypoints is Array or not _whole_number(cursor) or cursor < 0 or cursor > waypoints.size():
		return "route_plan"
	for waypoint in waypoints:
		if not _point(waypoint):
			return "route_plan.waypoints"
	return ""


static func _point(value: Variant, allow_unset: bool = false) -> bool:
	if not value is Array or value.size() != 2:
		return false
	if not _whole_number(value[0]) or not _whole_number(value[1]):
		return false
	if allow_unset and value[0] == 0 and value[1] == 0:
		return true
	return value[0] >= 1 and value[0] <= SpringMapTemplate.SIZE and value[1] >= 1 and value[1] <= SpringMapTemplate.SIZE


static func _whole_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and absf(value) < 9.223372036854775e18 and value == floorf(value))


static func _positive_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value > 0


static func _list_of(value: Variant, element_type: int) -> bool:
	if not value is Array:
		return false
	for element in value:
		if element_type == TYPE_STRING and _is_text(element):
			continue
		if typeof(element) != element_type:
			return false
	return true


static func _is_text(value: Variant) -> bool:
	return value is String or value is StringName
