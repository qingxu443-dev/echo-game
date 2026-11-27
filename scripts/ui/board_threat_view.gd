class_name BoardThreatView
extends RefCounted

## The threat layer of the 2.5D board: enemy attack telegraphs, hazard tiles,
## hover-focused intent inspection, turn-order badges, directional move arrows,
## reactive-melee / intercept caution zones, stacked damage labels and event callouts.

const IntentScript = preload("res://scripts/battle/battle_intent.gd")
const IntentPlannerScript = preload("res://scripts/battle/intent_planner.gd")
const P = preload("res://scripts/ui/theme_palette.gd")
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
		if intent.target_cell == hc or intent.affected_cells.has(hc) or intent.move_path.has(hc):
			out[intent.source_actor_id] = true
		elif _reactive_cells_for_intent(controller, intent).has(hc):
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
	var cells: Array[Vector2i] = []
	if intent.action_id != "basic_melee" or not intent.target_actor_id.is_empty():
		return cells
	var source = controller.get_actor(intent.source_actor_id)
	if source == null or not source.is_alive():
		return cells
	var origin: Vector2i = intent.move_path[intent.move_path.size() - 1] if not intent.move_path.is_empty() else source.cell
	var occupied: Dictionary = controller.get_occupied_cells(source.actor_id)
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var adj: Vector2i = origin + dir
		if adj == intent.target_cell or not P.is_inside_board(adj, controller.grid_size) or controller.blocked_cells.has(adj):
			continue
		cells.append(adj)
		# Elites & bosses can also step 1 tile to chase a hero within 2 tiles.
		if int(source.tier) >= 1 and not occupied.has(adj):
			for dir2 in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var c2: Vector2i = adj + dir2
				if c2 != origin and c2 != intent.target_cell and GridRulesScript.manhattan_distance(origin, c2) == 2 and P.is_inside_board(c2, controller.grid_size) and not controller.blocked_cells.has(c2) and not cells.has(c2):
					cells.append(c2)
	return cells


static func draw_telegraphs(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	var t: float = float(fx_state.get("time", 0.0))
	var pulse: float = 0.72 + 0.28 * sin(t * 5.2)
	var focused := _focused_source_ids(controller, fx_state)
	var has_focus := not focused.is_empty()
	var active := _active_intents(controller)

	for i in range(active.size()):
		var intent = active[i]
		var source = controller.get_actor(intent.source_actor_id)
		var is_focus: bool = (not has_focus) or focused.has(intent.source_actor_id)
		var dim: float = 1.0 if is_focus else 0.22
		var p_eff: float = pulse * dim
		var path_cells: Array = intent.move_path if not intent.move_path.is_empty() else (intent.affected_cells if intent.action_id == "pursuit" else [])
		if not path_cells.is_empty() and source != null and source.is_alive():
			_draw_move_arrow_chain(canvas, source.cell, path_cells, dim, is_focus and has_focus)
		var origin_cell: Vector2i = intent.move_path[intent.move_path.size() - 1] if not intent.move_path.is_empty() else (source.cell if source != null else Vector2i.ZERO)

		# Draw subtle amber caution rings on reactive melee pivot/chase tiles so the
		# player never gets surprised by an unadvertised sidestep strike.
		if intent.action_id == "basic_melee" and intent.target_actor_id.is_empty():
			var hero = controller.get_active_character()
			for rc in _reactive_cells_for_intent(controller, intent):
				var hero_on_rc: bool = hero != null and hero.is_alive() and hero.cell == rc
				if (is_focus and has_focus) or hero_on_rc or (source != null and GridRulesScript.manhattan_distance(origin_cell, rc) == 1):
					_draw_caution_tile(canvas, rc, Color(0.98, 0.68, 0.22), (0.85 if hero_on_rc else 0.48) * dim)

		match intent.action_id:
			"ground_pulse", "echo_bolt":
				for area_cell in intent.affected_cells:
					_draw_hazard_tile(canvas, area_cell, P.TELEGRAPH_PULSE_FILL, P.TELEGRAPH_PULSE_LINE, p_eff)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(origin_cell) + Vector2(0.0, -34.0), P.cell_center(intent.target_cell), P.TELEGRAPH_PULSE_LINE, 20.0, dim)
			"aimed_shot", "light_shot":
				for area_cell in intent.affected_cells:
					_draw_hazard_tile(canvas, area_cell, P.TELEGRAPH_SHOT_FILL, P.TELEGRAPH_SHOT_LINE, p_eff)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(origin_cell) + Vector2(0.0, -34.0), P.cell_center(intent.target_cell), P.TELEGRAPH_SHOT_LINE, 8.0, dim)
			"charged_strike", "sakura_shock":
				for area_cell in intent.affected_cells:
					_draw_hazard_tile(canvas, area_cell, P.TELEGRAPH_CHARGE_FILL, P.TELEGRAPH_CHARGE_LINE, p_eff)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(origin_cell) + Vector2(0.0, -30.0), P.cell_center(intent.target_cell), P.TELEGRAPH_CHARGE_LINE, 12.0, dim)
			"blight_field":
				for area_cell in intent.affected_cells:
					_draw_hazard_tile(canvas, area_cell, P.HAZARD_BLIGHT_FILL, P.HAZARD_BLIGHT_LINE, p_eff)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(origin_cell) + Vector2(0.0, -30.0), P.cell_center(intent.target_cell), P.HAZARD_BLIGHT_LINE, 12.0, dim)
			"spring_bloom":
				for area_cell in intent.affected_cells:
					_draw_hazard_tile(canvas, area_cell, P.HAZARD_SPRING_FILL, P.HAZARD_SPRING_LINE, p_eff)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(origin_cell) + Vector2(0.0, -32.0), P.cell_center(intent.target_cell), P.HAZARD_SPRING_LINE, 10.0, dim)
			"basic_melee", "shadow_raid":
				_draw_hazard_tile(canvas, intent.target_cell, P.TELEGRAPH_CHARGE_FILL, P.RING_MELEE, p_eff)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(origin_cell) + Vector2(0.0, -26.0), P.cell_center(intent.target_cell), P.RING_MELEE, 8.0, dim)
			"lock_on":
				_draw_hazard_tile(canvas, intent.target_cell, P.TELEGRAPH_SHOT_FILL, P.TELEGRAPH_SHOT_LINE, p_eff)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -34.0), P.cell_center(intent.target_cell), P.TELEGRAPH_SHOT_LINE, 4.0, dim)
			"locked_shot":
				for area_cell in intent.affected_cells:
					_draw_hazard_tile(canvas, area_cell, P.TELEGRAPH_SHOT_FILL, P.TELEGRAPH_SHOT_LINE, p_eff)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -34.0), P.cell_center(intent.target_cell), P.TELEGRAPH_SHOT_LINE, 12.0, dim)
			"rot_curse":
				_draw_hazard_tile(canvas, intent.target_cell, P.TELEGRAPH_PULSE_FILL, P.TELEGRAPH_PULSE_LINE, p_eff)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -32.0), P.cell_center(intent.target_cell), P.TELEGRAPH_PULSE_LINE, 6.0, dim)
			"wait":
				if source != null and source.is_alive():
					P.draw_polyline_closed(canvas, P.cell_diamond(source.cell, 6.0), Color(P.RING_WAIT.r, P.RING_WAIT.g, P.RING_WAIT.b, dim), 1.5)


static func _draw_move_arrow_chain(canvas: CanvasItem, start_cell: Vector2i, path_cells: Array, dim: float, emphasize: bool) -> void:
	var fill := Color(P.TELEGRAPH_PURSUIT_FILL.r, P.TELEGRAPH_PURSUIT_FILL.g, P.TELEGRAPH_PURSUIT_FILL.b, P.TELEGRAPH_PURSUIT_FILL.a * dim)
	var line := Color(P.TELEGRAPH_PURSUIT_LINE.r, P.TELEGRAPH_PURSUIT_LINE.g, P.TELEGRAPH_PURSUIT_LINE.b, (0.95 if emphasize else 0.72) * dim)
	var warn := Color(0.98, 0.70, 0.28, 0.42 * dim)
	var prev := P.cell_center(start_cell)
	for path_cell in path_cells:
		var pts := P.cell_diamond(path_cell, 6.0)
		canvas.draw_colored_polygon(pts, fill)
		P.draw_polyline_closed(canvas, pts, line, 2.0 if emphasize else 1.5)
		P.draw_polyline_closed(canvas, P.cell_diamond(path_cell, 11.5), warn, 1.1)
		var nxt := P.cell_center(path_cell)
		canvas.draw_line(prev, nxt, line, 3.0 if emphasize else 2.2, true)
		prev = nxt
	# Clear arrowhead at the landing cell
	var prev_cell: Vector2i = start_cell if path_cells.size() < 2 else path_cells[path_cells.size() - 2]
	var end_pos := P.cell_center(path_cells[path_cells.size() - 1])
	var dir := (end_pos - P.cell_center(prev_cell)).normalized()
	if dir.length_squared() > 0.01:
		var perp := Vector2(-dir.y, dir.x)
		var tip := end_pos + dir * 4.0
		var tri := PackedVector2Array([tip, tip - dir * 12.0 + perp * 6.5, tip - dir * 12.0 - perp * 6.5])
		canvas.draw_colored_polygon(tri, Color(0.98, 0.88, 0.54, 0.95 * dim))


static func _draw_caution_tile(canvas: CanvasItem, cell: Vector2i, color: Color, alpha: float) -> void:
	var pts := P.cell_diamond(cell, 4.5)
	canvas.draw_colored_polygon(pts, Color(color.r, color.g, color.b, 0.12 * alpha))
	for i in range(4):
		canvas.draw_dashed_line(pts[i], pts[(i + 1) % 4], Color(color.r, color.g, color.b, 0.88 * alpha), 1.8, 5.0)


static func _draw_hazard_tile(canvas: CanvasItem, cell: Vector2i, fill: Color, line: Color, pulse: float) -> void:
	var outer := P.cell_diamond(cell, 1.5)
	canvas.draw_colored_polygon(outer, Color(fill.r, fill.g, fill.b, fill.a * pulse))
	var stripe_col := Color(line.r, line.g, line.b, 0.35 * pulse)
	for frac in [0.25, 0.5, 0.75]:
		canvas.draw_line(outer[0].lerp(outer[3], frac), outer[1].lerp(outer[2], frac), stripe_col, 2.0, true)
	P.draw_polyline_closed(canvas, outer, Color(line.r, line.g, line.b, minf(1.0, 0.7 + 0.3 * pulse) * minf(1.0, pulse / 0.45)), 3.0)
	P.draw_polyline_closed(canvas, P.cell_diamond(cell, 7.0), Color(line.r, line.g, line.b, 0.45 * pulse), 1.4)


# --- stacked telegraph labels + total damage summary --------------------------

static func draw_telegraph_labels(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	var focused := _focused_source_ids(controller, fx_state)
	var has_focus := not focused.is_empty()
	var active := _active_intents(controller)
	var buckets: Dictionary = {}  # Vector2i -> Array[Dictionary]

	for i in range(active.size()):
		var intent = active[i]
		if has_focus and not focused.has(intent.source_actor_id):
			continue
		var info := _label_for_intent(controller, intent, _order_symbol(i))
		if info.is_empty():
			continue
		var cell: Vector2i = info["cell"]
		if not buckets.has(cell):
			buckets[cell] = []
		(buckets[cell] as Array).append(info)

	# Warn if the active hero is standing on a reactive-melee or intercept path tile.
	var hero = controller.get_active_character()
	if hero != null and hero.is_alive():
		var on_intercept := false
		var on_reactive := false
		for intent in active:
			if (not intent.move_path.is_empty() and intent.move_path.has(hero.cell)) or (intent.action_id == "pursuit" and intent.affected_cells.has(hero.cell)):
				on_intercept = true
			if _reactive_cells_for_intent(controller, intent).has(hero.cell):
				on_reactive = true
		if on_intercept and not is_cell_in_danger(controller, hero.cell):
			if not buckets.has(hero.cell):
				buckets[hero.cell] = []
			(buckets[hero.cell] as Array).append({"text": "⚠ 拦路截击", "color": Color("#ffba5a"), "dmg": 0})
		elif on_reactive and not is_cell_in_danger(controller, hero.cell):
			if not buckets.has(hero.cell):
				buckets[hero.cell] = []
			(buckets[hero.cell] as Array).append({"text": "⚠ 贴身追击", "color": Color("#ffba5a"), "dmg": 0})

	for cell in buckets:
		var entries: Array = buckets[cell]
		var base_pos := P.cell_center(cell)
		var has_actor := has_living_actor_at(controller, cell)
		if has_actor:
			base_pos += Vector2(0.0, -P.STANDEE_HEIGHT - 10.0)
		var total_dmg := 0
		var hit_count := 0
		for e in entries:
			if int(e.get("dmg", 0)) > 0:
				total_dmg += int(e["dmg"])
				hit_count += 1
		var row_h := 17.0
		for idx in range(entries.size()):
			var e: Dictionary = entries[idx]
			var txt: String = ("! " + str(e["text"])) if (has_actor and idx == 0 and hit_count == 1) else str(e["text"])
			_draw_telegraph_tag(canvas, base_pos - Vector2(0.0, float(idx) * row_h), txt, e["color"])
		if hit_count >= 2:
			_draw_telegraph_tag(canvas, base_pos - Vector2(0.0, float(entries.size()) * row_h + 2.0), "⚠ 合计 -%d" % total_dmg, Color("#ffecd2"), Color(0.56, 0.11, 0.13, 0.94))


static func _label_for_intent(controller, intent, ord_sym: String) -> Dictionary:
	var shown: int = intent.preview_health_damage(controller)
	var name := action_label_zh(intent.action_id)
	var color := P.TELEGRAPH_CHARGE_MARK
	match intent.action_id:
		"ground_pulse", "echo_bolt":
			color = P.TELEGRAPH_PULSE_MARK
		"aimed_shot", "light_shot", "locked_shot":
			color = P.TELEGRAPH_SHOT_MARK
		"lock_on":
			return {"cell": intent.target_cell, "text": "%s 锁命" % ord_sym, "color": P.TELEGRAPH_SHOT_MARK, "dmg": 0}
		"blight_field":
			color = P.HAZARD_BLIGHT_LINE
		"spring_bloom":
			color = P.HAZARD_SPRING_LINE
		"rot_curse":
			return {"cell": intent.target_cell, "text": "%s 降防 %d" % [ord_sym, intent.damage], "color": P.TELEGRAPH_PULSE_MARK, "dmg": 0}
		"charged_strike", "basic_melee", "sakura_shock", "shadow_raid":
			color = P.TELEGRAPH_CHARGE_MARK
		_:
			return {}
	return {"cell": intent.target_cell, "text": "%s %s %d" % [ord_sym, name, shown], "color": color, "dmg": shown}


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
		if intent.state != IntentScript.IntentState.ACTIVE:
			continue
		match intent.action_id:
			"charged_strike", "aimed_shot", "light_shot", "ground_pulse", "echo_bolt", "basic_melee", "blight_field", "spring_bloom", "sakura_shock":
				if intent.target_cell == cell or intent.affected_cells.has(cell):
					return true
			"locked_shot", "shadow_raid", "rot_curse":
				if intent.target_cell == cell or intent.affected_cells.has(cell):
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
	var max_alpha: float = 0.16 * breath
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
