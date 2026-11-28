class_name SessionValidation
extends RefCounted

## Preflight only: no nodes, RNG changes, bridge updates or file writes.
static func battle_fields_error(data: Dictionary) -> String:
	for entry in [
		[BattleController, "controller", BattleSession.CONTROLLER_CONTAINERS], [RunState, "run_state", []],
		[APBudget, "ap", []], [BattleLedger, "ledger", []], [BattleFxState, "fx", []],
	]:
		var excluded: Array[String] = []
		excluded.assign(entry[2])
		var error := SessionCodec.fields_error(entry[0], data.get(entry[1], {}), excluded)
		if not error.is_empty(): return str(entry[1]) + "." + error
	var view_script: Script = load("res://scripts/ui/battle_view.gd")
	var error := SessionCodec.fields_error(view_script, _select(data.get("view", {}), BattleSession.VIEW_FIELDS))
	if not error.is_empty(): return "view." + error
	for entry in [["actors", BattleActor], ["intents", BattleIntent], ["statuses", BattleStatus]]:
		for row in data.get(entry[0], []):
			if not row is Dictionary: return str(entry[0]) + ": expected Dictionary rows"
			error = SessionCodec.fields_error(entry[1], row)
			if not error.is_empty(): return str(entry[0]) + "." + error
			if entry[0] == "actors":
				for stat in row.get("fragment_bonuses", {}):
					var amount: Variant = row.fragment_bonuses[stat]
					if not stat in FragmentCatalog.STAT_KEYS or not _number(amount) or amount < 0:
						return "fragment_bonuses: invalid captured stat"
	for key in ["level", "camera", "loot_seed", "loot_state", "pressure_sequence"]:
		if not data.get(key, 0) is int: return key + ": expected int"
	if not data.get("spring_mode", false) is bool: return "spring_mode: expected bool"
	if int(data.get("camera", 0)) not in [0, 1, 2, 3]: return "camera: out of range"
	var grid: Variant = data.controller.get("grid_size")
	if not grid is Vector2i: return "grid_size: expected Vector2i"
	for cell in data.controller.get("blocked_cells", {}):
		if not cell is Vector2i or not GridRules.is_inside_bounds(cell, grid): return "blocked_cells: invalid coordinate"
	return _fx_error(data.get("fx", {}))


static func map_ui_error(ui: Variant, template: SpringMapTemplate) -> String:
	if not ui is Dictionary: return "ui: expected Dictionary"
	var script: Script = load("res://scripts/spring/spring_map_view.gd")
	var error := SessionCodec.fields_error(script, _select(ui, PlaySession.MAP_UI))
	if not error.is_empty(): return error
	var cell: Vector2i = ui.get("selected_cell", Vector2i(-1, -1))
	if cell != Vector2i(-1, -1) and not template.is_inside(cell): return "selected_cell: out of range"
	if int(ui.get("shop_tab", 0)) not in [0, 1, 2]: return "shop_tab: out of range"
	if int(ui.get("shop_sell_page", 0)) < 0: return "shop_sell_page: negative"
	return ""


static func _select(values: Dictionary, keys: Array[String]) -> Dictionary:
	var selected := {}
	for key in keys:
		if values.has(key): selected[key] = values[key]
	return selected


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _vector(value: Variant) -> bool:
	return value is Vector2 and is_finite(value.x) and is_finite(value.y)


static func _fx_error(fx: Dictionary) -> String:
	for field in ["actor_visual_pos", "actor_lunge"]:
		for value in fx.get(field, {}).values():
			if not _vector(value): return field + ": expected finite Vector2 values"
	for value in fx.get("actor_hit_flash", {}).values():
		if not _number(value): return "actor_hit_flash: expected finite numbers"
	for hop in fx.get("actor_hop_state", {}).values():
		if not hop is Dictionary or not _vector(hop.get("from")): return "actor_hop_state: invalid origin"
		if not _number(hop.get("age")) or not _number(hop.get("duration")): return "actor_hop_state: invalid clock"
		if hop.age < 0 or hop.duration <= 0: return "actor_hop_state: invalid duration"
	for field in ["floating_popups", "impact_flashes"]:
		for item in fx.get(field, []):
			if not item is Dictionary: return field + ": expected Dictionary rows"
			if not _number(item.get("age")) or not _number(item.get("duration")): return field + ": invalid clock"
			if item.age < 0 or item.duration <= 0 or not item.get("color") is Color: return field + ": invalid effect"
			if field == "floating_popups":
				if not _vector(item.get("pos")) or not item.get("text") is String: return field + ": invalid popup"
			elif not item.get("cell") is Vector2i: return field + ": invalid tile"
	return ""
