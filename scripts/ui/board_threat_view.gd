class_name BoardThreatView
extends RefCounted

## The threat layer of the 2.5D board: enemy attack telegraphs, hazard tiles,
## hover-focused intent inspection, turn-order badges, directional move arrows,
## reactive-melee / intercept caution zones, stacked damage labels and event callouts.

const IntentScript = preload("res://scripts/battle/battle_intent.gd")
const IntentPlannerScript = preload("res://scripts/battle/intent_planner.gd")
const P = preload("res://scripts/ui/theme_palette.gd")
const ThreatTiles = preload("res://scripts/ui/board_threat_tiles.gd")
const HazardFieldScript = preload("res://scripts/battle/hazard_field.gd")
const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")

const ORDER_CIRCLES: Array[String] = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨"]


static func draw(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	draw_hazard_tiles(canvas, controller, fx_state)
	draw_formation_links(canvas, controller, fx_state)
	draw_telegraphs(canvas, controller, fx_state)
	draw_impact_flashes(canvas, fx_state)
	draw_telegraph_labels(canvas, controller, fx_state)
	draw_popups(canvas, fx_state)
	draw_danger_vignette(canvas, controller, fx_state)


static func _order_symbol(idx: int) -> String:
	return ORDER_CIRCLES[idx] if idx >= 0 and idx < ORDER_CIRCLES.size() else str(idx + 1)


static func _active_intents(controller) -> Array:
	var list: Array = []
	for intent in controller.intents:
		if intent.state == IntentScript.IntentState.ACTIVE:
			list.append(intent)
	return list


## Returns the enemy actor ids currently focused by mouse hover (empty = show all).
static func _focused_source_ids(controller, fx_state: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if not fx_state.has("hover_cell"):
		return out
	var hc: Vector2i = fx_state["hover_cell"]
	if not P.is_inside_board(hc, controller.grid_size):
		return out
	for actor_id in controller.actors:
		var a = controller.actors[actor_id]
		if a.team == "enemy" and a.is_alive() and a.cell == hc:
			out[String(actor_id)] = true
			return out
	for intent in _active_intents(controller):
		if ThreatTiles.cells_for(controller, intent).has(hc) or intent.move_path.has(hc):
			out[intent.source_actor_id] = true
		elif TacticalPressure.is_reactive_cell(controller, intent, hc):
			out[intent.source_actor_id] = true
	return out


static func is_actor_focused(controller, fx_state: Dictionary, actor_id: String) -> bool:
	var focused := _focused_source_ids(controller, fx_state)
	return focused.has(actor_id)


## Compact turn-order badge shown above an enemy (e.g. "①" or "①②" for boss combo).
static func intent_order_badge(controller, actor_id: String) -> String:
	var active := _active_intents(controller)
	var parts: Array[String] = []
	for i in range(active.size()):
		if active[i].source_actor_id == actor_id and active[i].action_id != "wait":
			parts.append(_order_symbol(i))
	return "".join(parts)


static func _draw_ward_node_tethers(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	var t: float = float(fx_state.get("time", 0.0))
	var pulse: float = 0.65 + 0.35 * sin(t * 3.0)
	for b_cell in controller.beacons:
		var node: Dictionary = controller.beacons[b_cell]
		if str(node.get("kind", "")) != "ward_node" or int(node.get("health", 0)) <= 0:
			continue
		var owner_id: String = str(node.get("owner_id", ""))
		var owner = controller.get_actor(owner_id) if not owner_id.is_empty() else null
		if owner == null or not owner.is_alive():
			continue
		var p0 := P.cell_center(b_cell)
		var p1 := P.cell_center(owner.cell)
		canvas.draw_line(p0, p1, Color(0.37, 0.85, 0.69, 0.22 * pulse), 7.0, true)
		canvas.draw_dashed_line(p0, p1, Color(0.56, 0.94, 0.81, 0.78 * pulse), 2.2, 6.0)
		for k in range(2):
			var u := fposmod(t * 0.55 + float(k) * 0.5, 1.0)
			canvas.draw_circle(p0.lerp(p1, u), 4.0, Color(0.85, 1.0, 0.95, 0.92))


static func draw_formation_links(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	_draw_ward_node_tethers(canvas, controller, fx_state)
	if _focused_source_ids(controller, fx_state).is_empty(): return
	var formation: Dictionary = IntentPlannerScript.analyze_formation(controller)
	if formation.is_empty():
		return
	var t: float = float(fx_state.get("time", 0.0))
	var pulse: float = 0.55 + 0.35 * sin(t * 2.4)
	var form_id: String = str(formation.get("id", ""))
	var base_col := Color(0.92, 0.72, 0.42)
	if form_id == "pincer_lockdown":
		base_col = Color(0.92, 0.44, 0.38)
	elif form_id == "crossfire_net":
		base_col = Color(0.62, 0.76, 0.98)
	var line_col := Color(base_col.r, base_col.g, base_col.b, 0.42 * pulse)
	var glow_col := Color(base_col.r, base_col.g, base_col.b, 0.16 * pulse)
	for link in formation.get("links", []):
		var a = controller.get_actor(str(link.get("from", "")))
		var b = controller.get_actor(str(link.get("to", "")))
		if a == null or b == null or not a.is_alive() or not b.is_alive():
			continue
		var p0 := P.cell_center(a.cell)
		var p1 := P.cell_center(b.cell)
		if form_id == "crossfire_net":
			canvas.draw_dashed_line(p0, p1, line_col, 2.0, 6.0)
		else:
			canvas.draw_line(p0, p1, glow_col, 6.0, true)
			canvas.draw_line(p0, p1, line_col, 2.0, true)
		var mid := p0.lerp(p1, 0.5)
		var r := 4.5
		canvas.draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -r), mid + Vector2(r, 0), mid + Vector2(0, r), mid + Vector2(-r, 0)]), Color(base_col.r, base_col.g, base_col.b, 0.72 * pulse))


# --- ground hazards (凋零 / 残春) ---------------------------------------------

static func draw_hazard_tiles(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	if controller.hazards.is_empty():
		return
	var t: float = float(fx_state.get("time", 0.0))
	var pulse: float = 0.72 + 0.28 * sin(t * 2.0)
	for cell in controller.hazards:
		var hazard: Dictionary = controller.hazards[cell]
		match str(hazard.get("kind", "")):
			HazardFieldScript.KIND_BLIGHT:
				_draw_blight_tile(canvas, cell, pulse)
			HazardFieldScript.KIND_LINGERING_SPRING:
				_draw_lingering_tile(canvas, cell, pulse)


static func _draw_blight_tile(canvas: CanvasItem, cell: Vector2i, pulse: float) -> void:
	var diamond := P.cell_diamond(cell, 5.0)
	canvas.draw_colored_polygon(diamond, Color(P.HAZARD_BLIGHT_FILL.r, P.HAZARD_BLIGHT_FILL.g, P.HAZARD_BLIGHT_FILL.b, P.HAZARD_BLIGHT_FILL.a * pulse))
	P.draw_polyline_closed(canvas, diamond, Color(P.HAZARD_BLIGHT_LINE.r, P.HAZARD_BLIGHT_LINE.g, P.HAZARD_BLIGHT_LINE.b, 0.55 + 0.25 * pulse), 1.6)
	var center := P.cell_center(cell)
	for angle in [-0.9, 0.2, 1.5]:
		var dir := Vector2(cos(angle), sin(angle))
		canvas.draw_line(center - dir * 12.0, center + dir * 17.0, Color(P.HAZARD_BLIGHT_LINE.r, P.HAZARD_BLIGHT_LINE.g, P.HAZARD_BLIGHT_LINE.b, 0.85), 2.0, true)


static func _draw_lingering_tile(canvas: CanvasItem, cell: Vector2i, pulse: float) -> void:
	var diamond := P.cell_diamond(cell, 7.0)
	canvas.draw_colored_polygon(diamond, Color(P.HAZARD_SPRING_FILL.r, P.HAZARD_SPRING_FILL.g, P.HAZARD_SPRING_FILL.b, P.HAZARD_SPRING_FILL.a * pulse))
	P.draw_polyline_closed(canvas, diamond, Color(P.HAZARD_SPRING_LINE.r, P.HAZARD_SPRING_LINE.g, P.HAZARD_SPRING_LINE.b, 0.50 + 0.25 * pulse), 1.4)
	var center := P.cell_center(cell)
	for offset in [Vector2(-13, -3), Vector2(7, 8), Vector2(15, -8), Vector2(-4, 10)]:
		canvas.draw_circle(center + offset, 3.6, Color(P.HAZARD_SPRING_LINE.r, P.HAZARD_SPRING_LINE.g, P.HAZARD_SPRING_LINE.b, 0.92))


# --- telegraphs & reactive/intercept caution zones ----------------------------

static func _reactive_cells_for_intent(controller, intent) -> Array[Vector2i]:
	return TacticalPressure.reactive_cells(controller, intent)


static func draw_telegraphs(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	ThreatTiles.draw(canvas, controller, float(fx_state.get("time", 0.0)))
	var cautions := caution_tiles(controller, fx_state)
	for cell in cautions:
		_draw_caution_tile(canvas, cell, Color(1.0, 0.62, 0.16), cautions[cell])
	var focused := _focused_source_ids(controller, fx_state)
	var has_focus := not focused.is_empty()
	var active := _active_intents(controller)

	for i in range(active.size()):
		var intent = active[i]
		var source = controller.get_actor(intent.source_actor_id)
		var is_focus: bool = (not has_focus) or focused.has(intent.source_actor_id)
		var dim: float = 1.0 if is_focus else 0.22
		var path_cells: Array = intent.move_path if not intent.move_path.is_empty() else (intent.affected_cells if intent.action_id == "pursuit" else [])
		if not path_cells.is_empty() and source != null and source.is_alive():
			_draw_move_arrow_chain(canvas, source.cell, path_cells, dim, is_focus and has_focus)
		var target_cells := ThreatTiles.cells_for(controller, intent)
		var aim_cell: Vector2i = target_cells[0] if intent.target_mode == IntentScript.TargetMode.ACTOR_LOCKED and not target_cells.is_empty() else intent.target_cell
		var origin_cell: Vector2i = intent.move_path[intent.move_path.size() - 1] if not intent.move_path.is_empty() else (source.cell if source != null else Vector2i.ZERO)

		if not has_focus or not is_focus: continue
		match intent.action_id:
			"ground_pulse", "echo_bolt":
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(origin_cell) + Vector2(0.0, -34.0), P.cell_center(aim_cell), P.TELEGRAPH_PULSE_LINE, 20.0, dim)
			"aimed_shot", "light_shot":
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(origin_cell) + Vector2(0.0, -34.0), P.cell_center(aim_cell), P.TELEGRAPH_SHOT_LINE, 8.0, dim)
			"charged_strike", "sakura_shock":
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(origin_cell) + Vector2(0.0, -30.0), P.cell_center(aim_cell), P.TELEGRAPH_CHARGE_LINE, 12.0, dim)
			"blight_field":
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(origin_cell) + Vector2(0.0, -30.0), P.cell_center(aim_cell), P.HAZARD_BLIGHT_LINE, 12.0, dim)
			"spring_bloom":
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(origin_cell) + Vector2(0.0, -32.0), P.cell_center(aim_cell), P.HAZARD_SPRING_LINE, 10.0, dim)
			"basic_melee", "shadow_raid":
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(origin_cell) + Vector2(0.0, -26.0), P.cell_center(aim_cell), P.RING_MELEE, 8.0, dim)
			"lock_on":
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -34.0), P.cell_center(aim_cell), P.TELEGRAPH_SHOT_LINE, 4.0, dim)
			"locked_shot":
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -34.0), P.cell_center(aim_cell), P.TELEGRAPH_SHOT_LINE, 12.0, dim)
			"rot_curse":
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -32.0), P.cell_center(aim_cell), P.TELEGRAPH_PULSE_LINE, 6.0, dim)
			"wait":
				if source != null and source.is_alive():
					P.draw_polyline_closed(canvas, P.cell_diamond(source.cell, 6.0), Color(P.RING_WAIT.r, P.RING_WAIT.g, P.RING_WAIT.b, dim), 1.5)


static func _draw_move_arrow_chain(canvas: CanvasItem, start_cell: Vector2i, path_cells: Array, dim: float, emphasize: bool) -> void:
	var fill := Color(P.TELEGRAPH_PURSUIT_FILL.r, P.TELEGRAPH_PURSUIT_FILL.g, P.TELEGRAPH_PURSUIT_FILL.b, P.TELEGRAPH_PURSUIT_FILL.a * dim)
	var line := Color(P.TELEGRAPH_PURSUIT_LINE.r, P.TELEGRAPH_PURSUIT_LINE.g, P.TELEGRAPH_PURSUIT_LINE.b, (0.96 if emphasize else 0.72) * dim)
	var prev := P.cell_center(start_cell)
	for path_cell in path_cells:
		var pts := P.cell_diamond(path_cell, 7.0)
		canvas.draw_colored_polygon(pts, fill)
		P.draw_polyline_closed(canvas, pts, line, 1.8 if emphasize else 1.2)
		var nxt := P.cell_center(path_cell)
		canvas.draw_dashed_line(prev, nxt, line, 2.6 if emphasize else 1.8, 6.0)
		prev = nxt
	# Crisp silver-white directional arrowhead at the landing cell
	var prev_cell: Vector2i = start_cell if path_cells.size() < 2 else path_cells[path_cells.size() - 2]
	var end_pos := P.cell_center(path_cells[path_cells.size() - 1])
	var dir := (end_pos - P.cell_center(prev_cell)).normalized()
	if dir.length_squared() > 0.01:
		var perp := Vector2(-dir.y, dir.x)
		var tip := end_pos + dir * 4.0
		var tri := PackedVector2Array([tip, tip - dir * 11.0 + perp * 5.5, tip - dir * 11.0 - perp * 5.5])
		canvas.draw_colored_polygon(tri, Color(0.92, 0.96, 1.0, 0.94 * dim))


## CONTRACT: _test_compact_reactive_warnings
static func caution_tiles(controller, fx_state: Dictionary) -> Dictionary:
	var tiles := {}
	var focused := _focused_source_ids(controller, fx_state)
	var hero = controller.get_active_character()
	for intent in _active_intents(controller):
		if intent.action_id != "basic_melee" or not intent.target_actor_id.is_empty(): continue
		for cell in _reactive_cells_for_intent(controller, intent):
			if controller.blocked_cells.has(cell): continue
			var emphasized: bool = (hero != null and hero.is_alive() and hero.cell == cell) or focused.has(intent.source_actor_id)
			tiles[cell] = maxf(float(tiles.get(cell, 0.0)), 0.9 if emphasized else 0.5)
	return tiles


static func _draw_caution_tile(canvas: CanvasItem, cell: Vector2i, color: Color, alpha: float) -> void:
	var pts := P.cell_diamond(cell, 4.5)
	for i in range(4):
		canvas.draw_dashed_line(pts[i], pts[(i + 1) % 4], Color(color.r, color.g, color.b, 0.88 * alpha), 1.8, 5.0)


# --- incoming threat summary & ultra-compact board chips ----------------------

## Single source of truth for everything about to hit `cell`: used both by the
## compact board chips and by the bottom-left HUD breakdown card (no board clutter).
static func incoming_threats_at(controller, cell: Vector2i) -> Dictionary:
	var active := _active_intents(controller)
	var entries := _projected_entries(controller, cell, active)
	var total_dmg := 0
	var hit_count := 0
	for entry in entries:
		total_dmg += int(entry["dmg"])
		if entry.get("hit", false):
			hit_count += 1
	var caution := ""
	if hit_count == 0:
		for intent in active:
			if (not intent.move_path.is_empty() and intent.move_path.has(cell)) or (intent.action_id == "pursuit" and intent.affected_cells.has(cell)):
				caution = "⚠ 拦路截击：站此路径会被冲锋撞击"
				break
		if caution.is_empty():
			for intent in active:
				if TacticalPressure.is_reactive_cell(controller, intent, cell):
					caution = "⚠ 贴身追击：敌方近战将转身或追步劈砍"
					break
	return {"entries": entries, "total_dmg": total_dmg, "hit_count": hit_count, "caution": caution}


static func _projected_entries(controller, cell: Vector2i, active: Array, focused: Dictionary = {}) -> Array[Dictionary]:
	var defender := BattleThreatPreview.defender_at(controller, cell)
	var entries: Array[Dictionary] = []
	for i in range(active.size()):
		var intent = active[i]
		if not BattleThreatPreview.targets_cell(intent, defender, cell):
			continue
		var info := _label_for_intent(controller, intent, _order_symbol(i), defender)
		if not info.is_empty() and (focused.is_empty() or focused.has(intent.source_actor_id)):
			entries.append(info)
	return entries


## CONTRACT: _test_compact_threat_labels
static func label_entries(controller, fx_state: Dictionary) -> Dictionary:
	var active := _active_intents(controller)
	var buckets: Dictionary = {}
	var hero = controller.get_active_character()
	if hero != null and hero.is_alive():
		buckets[hero.cell] = _projected_entries(controller, hero.cell, active)
	var hover: Vector2i = fx_state.get("hover_cell", Vector2i(-1, -1))
	if P.is_inside_board(hover, controller.grid_size) and not buckets.has(hover):
		buckets[hover] = _projected_entries(controller, hover, active)
	return buckets


static func draw_telegraph_labels(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	var buckets := label_entries(controller, fx_state)

	# Render AT MOST ONE tiny chip per tile (near floor center, never a tall tower
	# blocking standees behind it). Full multi-hit breakdown lives above the hero HUD.
	for cell in buckets:
		var entries: Array = buckets[cell]
		if entries.is_empty():
			continue
		var total_dmg := 0
		var hit_count := 0
		for e in entries:
			total_dmg += int(e["dmg"])
			if e.get("hit", false):
				hit_count += 1
		var chip_pos := P.cell_center(cell) + Vector2(0.0, 7.0)
		if hit_count >= 2:
			_draw_telegraph_tag(canvas, chip_pos, "⚠ -%d (%d击)" % [total_dmg, hit_count], Color("#ffecd2"), Color(0.58, 0.10, 0.12, 0.94))
		else:
			var e0: Dictionary = entries[0]
			for entry in entries:
				if entry.get("hit", false):
					e0 = entry
					break
			var short_txt: String = str(e0.get("short", e0["text"]))
			_draw_telegraph_tag(canvas, chip_pos, short_txt, e0["color"])


static func _label_for_intent(controller, intent, ord_sym: String, defender: BattleActor) -> Dictionary:
	var name := action_label_zh(intent.action_id)
	var color := P.TELEGRAPH_CHARGE_MARK
	match intent.action_id:
		"ground_pulse", "echo_bolt":
			color = P.TELEGRAPH_PULSE_MARK
		"aimed_shot", "light_shot", "locked_shot":
			color = P.TELEGRAPH_SHOT_MARK
		"lock_on":
			return {"cell": intent.target_cell, "text": "%s 锁命" % ord_sym, "short": "%s 锁命" % ord_sym, "color": P.TELEGRAPH_SHOT_MARK, "dmg": 0}
		"blight_field":
			color = P.HAZARD_BLIGHT_LINE
		"spring_bloom":
			color = P.HAZARD_SPRING_LINE
		"rot_curse":
			BattleThreatPreview.apply(controller, intent, defender)
			return {"cell": intent.target_cell, "text": "%s 降防 %d" % [ord_sym, intent.damage], "short": "%s -%d防" % [ord_sym, intent.damage], "color": P.TELEGRAPH_PULSE_MARK, "dmg": 0}
		"charged_strike", "basic_melee", "sakura_shock", "shadow_raid":
			color = P.TELEGRAPH_CHARGE_MARK
		_:
			return {}
	var source = controller.get_actor(intent.source_actor_id)
	var hit: bool = intent.damage > 0 and source != null and source.is_alive() and (defender == null or defender.is_alive())
	var shown := BattleThreatPreview.apply(controller, intent, defender)
	return {"cell": intent.target_cell, "text": "%s %s -%d" % [ord_sym, name, shown], "short": "%s -%d" % [ord_sym, shown], "color": color, "dmg": shown, "hit": hit}


static func action_label_zh(action_id: String) -> String:
	match action_id:
		"ground_pulse": return "脉冲"
		"echo_bolt": return "回声弹"
		"aimed_shot": return "贯通狙击"
		"light_shot": return "点射"
		"charged_strike": return "蓄力重斩"
		"basic_melee": return "斩击"
		"blight_field": return "樱落"
		"spring_bloom": return "春痕"
		"sakura_shock": return "震荡横扫"
		"lock_on": return "锁命"
		"locked_shot": return "锁命箭"
		"shadow_raid": return "突袭"
		"rot_curse": return "腐樱降防"
		"pursuit_intercept": return "拦路截击"
		"ward_stance": return "结界突进"
		"ward_ally": return "壁垒护佑"
		"tolerance_counter": return "容忍反击"
		_: return ""


## Converts enemy combat events into unmistakable overhead callouts & impact rings.
static func push_event_callout(controller, event: Dictionary, popups: Array, impacts: Array) -> String:
	var etype: String = str(event.get("type", ""))
	var actor_id: String = str(event.get("actor_id", ""))
	var target_id: String = str(event.get("target_id", ""))
	var detail: String = str(event.get("detail", ""))
	var actor = controller.get_actor(actor_id)
	if etype == "enemy_action_resolved" and actor != null:
		var lbl := action_label_zh(detail)
		if not lbl.is_empty():
			var prof = EnemyCatalogScript.get_definition(actor.archetype)
			var nm: String = prof.display_name_zh if prof != null else (actor.display_name_zh if not actor.display_name_zh.is_empty() else "敌方")
			popups.append({"pos": P.cell_center(actor.cell) + Vector2(-38.0, -76.0), "text": lbl, "color": Color("#ffd89b"), "age": 0.0, "duration": 1.05})
			var tgt = controller.get_actor(target_id)
			if tgt != null:
				impacts.append({"cell": tgt.cell, "color": P.TELEGRAPH_CHARGE_LINE, "age": 0.0, "duration": 0.36})
			return "%s 发动了「%s」！" % [nm, lbl]
	elif etype == "counter_resolved" and detail.find("tolerance_counter") >= 0 and actor != null:
		popups.append({"pos": P.cell_center(actor.cell) + Vector2(-42.0, -82.0), "text": "⚠ 容忍反击!", "color": Color("#ff8a4c"), "age": 0.0, "duration": 1.25})
		var tgt = controller.get_actor(target_id)
		if tgt != null:
			impacts.append({"cell": tgt.cell, "color": Color("#ff7b3b"), "age": 0.0, "duration": 0.42})
		return "连续近战触发了敌方「容忍反击」！"
	elif etype == "actor_moved" and detail.begins_with("reactive_step") and actor != null:
		popups.append({"pos": P.cell_center(actor.cell) + Vector2(-34.0, -78.0), "text": "追步截杀!", "color": Color("#ffba5a"), "age": 0.0, "duration": 1.0})
	elif etype == "boss_enraged" and actor != null:
		popups.append({"pos": P.cell_center(actor.cell) + Vector2(-46.0, -86.0), "text": "二阶段狂暴!", "color": Color("#ff6b7a"), "age": 0.0, "duration": 1.5})
		return "强敌进入二阶段狂暴并召唤了护卫！"
	return ""


# --- danger queries (single source of truth for the whole board family) -------

static func has_living_actor_at(controller, cell: Vector2i) -> bool:
	for actor_id in controller.actors:
		var a = controller.actors[actor_id]
		if a.is_alive() and a.cell == cell:
			return true
	return false


static func is_cell_in_danger(controller, cell: Vector2i) -> bool:
	if controller.hazards.has(cell):
		return true
	for intent in controller.intents:
		if intent.state != IntentScript.IntentState.ACTIVE or intent.action_id == "lock_on":
			continue
		if TacticalPressure.is_reactive_cell(controller, intent, cell):
			return true
		var source = controller.get_actor(intent.source_actor_id)
		if source != null and source.is_alive() and ThreatTiles.ACTION_STYLES.has(intent.action_id) and ThreatTiles.cells_for(controller, intent).has(cell):
			return true
	return false


# --- short-lived fx -----------------------------------------------------------

static func draw_impact_flashes(canvas: CanvasItem, fx_state: Dictionary) -> void:
	for f in fx_state.get("impacts", []):
		var age: float = float(f.get("age", 0.0))
		var dur: float = maxf(0.05, float(f.get("duration", 0.35)))
		var u: float = clampf(age / dur, 0.0, 1.0)
		var col: Color = f.get("color", P.TELEGRAPH_CHARGE_LINE)
		var pts := P.cell_diamond(f.get("cell", Vector2i.ZERO), -6.0 * u)
		canvas.draw_colored_polygon(pts, Color(col.r, col.g, col.b, (1.0 - u) * 0.55))
		P.draw_polyline_closed(canvas, pts, Color(1.0, 0.95, 0.9, (1.0 - u) * 0.95), 3.0)


static func draw_popups(canvas: CanvasItem, fx_state: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	for item in fx_state.get("popups", []):
		var age: float = float(item.get("age", 0.0))
		var duration: float = maxf(0.1, float(item.get("duration", 0.9)))
		var u: float = clampf(age / duration, 0.0, 1.0)
		var pos: Vector2 = item.get("pos", Vector2.ZERO) + Vector2(0.0, -36.0 * u)
		var base_color: Color = item.get("color", P.TEXT)
		var alpha: float = 1.0 - maxf(0.0, (u - 0.55) / 0.45)
		var text: String = str(item.get("text", ""))
		canvas.draw_string(font, pos + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.04, 0.05, 0.07, alpha * 0.9))
		canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(base_color.r, base_color.g, base_color.b, alpha))


# --- helpers ------------------------------------------------------------------

static func _draw_telegraph_tag(canvas: CanvasItem, center: Vector2, text: String, color: Color, bg: Color = Color(0.05, 0.06, 0.08, 0.84)) -> void:
	var font := ThemeDB.fallback_font
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var pos := Vector2(center.x - sz.x * 0.5, center.y + 4.0)
	var rect := Rect2(pos.x - 5.0, pos.y - 11.0, sz.x + 10.0, 16.0)
	canvas.draw_rect(rect, bg, true)
	canvas.draw_rect(rect, Color(color.r, color.g, color.b, 0.55), false, 1.0)
	canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


static func draw_aim_arc(canvas: CanvasItem, from_pos: Vector2, to_pos: Vector2, color: Color, lift: float, dim: float = 1.0) -> void:
	var line_color := Color(color.r, color.g, color.b, 0.78 * dim)
	var mid := (from_pos + to_pos) * 0.5 + Vector2(0.0, -lift)
	var steps := 10
	var prev := from_pos
	for i in range(1, steps + 1):
		var u := float(i) / float(steps)
		var p := from_pos.lerp(mid, u).lerp(mid.lerp(to_pos, u), u)
		if i % 2 == 1:
			canvas.draw_line(prev, p, line_color, 2.2 if dim > 0.5 else 1.5, true)
		prev = p
	# Arrow tip pointing into target_cell so attack direction is unmistakable
	var dir := (to_pos - mid).normalized()
	if dir.length_squared() > 0.01:
		var perp := Vector2(-dir.y, dir.x)
		canvas.draw_colored_polygon(PackedVector2Array([to_pos, to_pos - dir * 10.0 + perp * 5.0, to_pos - dir * 10.0 - perp * 5.0]), line_color)


static func draw_danger_vignette(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	if controller.phase != controller.BattlePhase.PLAYER:
		return
	var hero = controller.get_active_character()
	if hero == null or not hero.is_alive() or not is_cell_in_danger(controller, hero.cell):
		return
	var t: float = float(fx_state.get("time", 0.0))
	var breath: float = 0.45 + 0.55 * sin(t * 3.8)
	var max_alpha: float = 0.065 * breath
	var w: float = P.VIEW_SIZE.x
	var h: float = P.VIEW_SIZE.y
	var edge_x: float = 110.0
	var edge_y: float = 84.0
	var c_edge := Color(0.82, 0.10, 0.10, max_alpha)
	var c_zero := Color(0.82, 0.10, 0.10, 0.0)
	canvas.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, edge_y), Vector2(0, edge_y)]), PackedColorArray([c_edge, c_edge, c_zero, c_zero]))
	canvas.draw_polygon(PackedVector2Array([Vector2(0, h - edge_y), Vector2(w, h - edge_y), Vector2(w, h), Vector2(0, h)]), PackedColorArray([c_zero, c_zero, c_edge, c_edge]))
	canvas.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(edge_x, 0), Vector2(edge_x, h), Vector2(0, h)]), PackedColorArray([c_edge, c_zero, c_zero, c_edge]))
	canvas.draw_polygon(PackedVector2Array([Vector2(w - edge_x, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - edge_x, h)]), PackedColorArray([c_zero, c_edge, c_edge, c_zero]))
