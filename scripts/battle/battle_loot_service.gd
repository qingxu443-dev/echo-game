class_name BattleLootService
extends RefCounted

## Encounter-local chest benefits and equipment transfers. BattleController owns
## the actor/object tables and events; this collaborator has no static state or
## knowledge of exploration, persistent rewards, or UI.

static func grant_chest_buff_to_enemy(battle, source_actor_id: String, chest: Dictionary) -> void:
	var loot: Dictionary = chest.get("loot", {})
	if loot.is_empty():
		return
	var recipient = battle.get_actor(source_actor_id)
	if recipient == null or recipient.team != "enemy" or not recipient.is_alive():
		for aid in battle.actors:
			var a = battle.actors[aid]
			if a.team == "enemy" and a.is_alive():
				recipient = a
				break
	if recipient == null:
		return

	var kind: String = str(loot.get("kind", ""))
	var item_name: String = str(loot.get("name", "宝箱物品"))
	# Enemy variants use the catalogue's enemy_* fields and the existing doubled
	# chest benefit. Player equipment fields are not reused for enemy balancing.
	recipient.attack = maxi(1, recipient.attack + int(loot.get("enemy_attack", 0)) * 2)
	var add_shield: int = int(loot.get("enemy_shield", 0)) * 2
	if add_shield > 0:
		recipient.shield = mini(recipient.max_health, recipient.shield + add_shield)
	var add_heal: int = int(loot.get("enemy_heal", 0)) * 2
	if add_heal > 0:
		recipient.health = mini(recipient.max_health, recipient.health + add_heal)
	if bool(loot.get("enemy_charge", false)) and recipient.skill_charge_max > 0:
		recipient.skill_charge = recipient.skill_charge_max
	var verb: String = "吸收了"
	if kind == "weapon" or kind == "armor":
		recipient.stolen_equipment.append(loot.duplicate(true))
		verb = "装备了"
	elif kind == "consumable":
		verb = "使用了"
	battle._emit_event("chest_stolen_by_enemy", recipient.actor_id, str(chest.get("id", "")), "%s「%s」" % [verb, item_name])


static func drop_enemy_equipment(battle, enemy) -> void:
	if enemy == null or enemy.stolen_equipment.is_empty():
		return
	var cell: Vector2i = enemy.cell
	if not battle.dropped_loot.has(cell):
		battle.dropped_loot[cell] = []
	var names: Array[String] = []
	for item in enemy.stolen_equipment:
		var kind: String = str(item.get("kind", ""))
		if kind == "weapon" or kind == "armor":
			battle.dropped_loot[cell].append(item.duplicate(true))
			names.append(str(item.get("name", "装备")))
	enemy.stolen_equipment.clear()
	if not names.is_empty():
		battle._emit_event("loot_dropped", enemy.actor_id, "", "掉落「%s」" % "、".join(names))


static func pickup_dropped_loot_at(battle, cell: Vector2i) -> Array[Dictionary]:
	if not battle.dropped_loot.has(cell):
		return []
	var items: Array = battle.dropped_loot[cell]
	battle.dropped_loot.erase(cell)
	var picked: Array[Dictionary] = []
	for item in items:
		if battle.run_state != null:
			battle.run_state.add_to_backpack(item)
		picked.append(item)
		battle._emit_event("loot_picked_up", battle.active_character_id, "", str(item.get("name", "装备")))
	return picked


static func collect_remaining_chests(battle) -> Array[Dictionary]:
	var claimed: Array[Dictionary] = []
	for cell in battle.beacons:
		var b: Dictionary = battle.beacons[cell]
		# Ward nodes are never counted as saved chests or awarded as loot.
		if str(b.get("kind", "")) == "ward_node":
			continue
		if int(b.get("health", 0)) > 0 and not bool(b.get("opened", false)):
			b["health"] = 0
			b["opened"] = true
			battle.beacons[cell] = b
			var loot: Dictionary = b.get("loot", {})
			if not loot.is_empty():
				if battle.run_state != null:
					battle.run_state.add_to_backpack(loot)
				claimed.append(loot)
	for drop_cell in battle.dropped_loot.keys():
		for item in battle.dropped_loot[drop_cell]:
			if battle.run_state != null:
				battle.run_state.add_to_backpack(item)
			claimed.append(item)
	battle.dropped_loot.clear()
	return claimed
