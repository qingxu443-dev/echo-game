class_name BoardThreatView
extends RefCounted

## The threat layer of the 2.5D board: enemy attack telegraphs, hazard tiles,
## floating danger labels, impact flashes, damage popups and the danger
## vignette. Everything here answers one question - what is about to hurt -
## and nothing here knows about sprites or world-object depth sorting.
##
## It is the leaf of the board split: the composition (BoardView) and the
## world-object layer both ask it whether a cell is in danger, so the answer
## exists in exactly one place.

const IntentScript = preload("res://scripts/battle/battle_intent.gd")
const IntentPlannerScript = preload("res://scripts/battle/intent_planner.gd")
const P = preload("res://scripts/ui/theme_palette.gd")
const HazardFieldScript = preload("res://scripts/battle/hazard_field.gd")


## The whole threat layer, in composition order.
static func draw(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	draw_hazard_tiles(canvas, controller, fx_state)
	draw_formation_links(canvas, controller, fx_state)
	draw_telegraphs(canvas, controller, fx_state)
	draw_impact_flashes(canvas, fx_state)
	draw_telegraph_labels(canvas, controller, fx_state)
	draw_popups(canvas, fx_state)
	draw_danger_vignette(canvas, controller, fx_state)


## Draws subtle tactical formation links beneath living coordinated enemies so
## the player can read the formation at a glance and see it break on a kill.
static func draw_formation_links(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
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

## Painted under every telegraph and every standee: terrain, not an incoming hit.
## The two kinds differ in hue and in mark (cracks vs petals) so a player can tell
## 凋零 from 残春 without reading a label.
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
	# Three short cracks: dead ground, not a rune circle.
	var center := P.cell_center(cell)
	for angle in [-0.9, 0.2, 1.5]:
		var dir := Vector2(cos(angle), sin(angle))
		canvas.draw_line(center - dir * 12.0, center + dir * 17.0, Color(P.HAZARD_BLIGHT_LINE.r, P.HAZARD_BLIGHT_LINE.g, P.HAZARD_BLIGHT_LINE.b, 0.85), 2.0, true)


static func _draw_lingering_tile(canvas: CanvasItem, cell: Vector2i, pulse: float) -> void:
	var diamond := P.cell_diamond(cell, 7.0)
	canvas.draw_colored_polygon(diamond, Color(P.HAZARD_SPRING_FILL.r, P.HAZARD_SPRING_FILL.g, P.HAZARD_SPRING_FILL.b, P.HAZARD_SPRING_FILL.a * pulse))
	P.draw_polyline_closed(canvas, diamond, Color(P.HAZARD_SPRING_LINE.r, P.HAZARD_SPRING_LINE.g, P.HAZARD_SPRING_LINE.b, 0.50 + 0.25 * pulse), 1.4)
	# Petals: pink dots that read as fallen blossom rather than hazard paint.
	var center := P.cell_center(cell)
	for offset in [Vector2(-13, -3), Vector2(7, 8), Vector2(15, -8), Vector2(-4, 10)]:
		canvas.draw_circle(center + offset, 3.6, Color(P.HAZARD_SPRING_LINE.r, P.HAZARD_SPRING_LINE.g, P.HAZARD_SPRING_LINE.b, 0.92))


# --- telegraphs ---------------------------------------------------------------

static func draw_telegraphs(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	var t: float = float(fx_state.get("time", 0.0))
	var pulse: float = 0.72 + 0.28 * sin(t * 5.2)

	for intent in controller.intents:
		if intent.state != IntentScript.IntentState.ACTIVE:
			continue
		var source = controller.get_actor(intent.source_actor_id)
		match intent.action_id:
			"ground_pulse", "echo_bolt":
				for area_cell in intent.affected_cells:
					_draw_hazard_tile(canvas, area_cell, P.TELEGRAPH_PULSE_FILL, P.TELEGRAPH_PULSE_LINE, pulse)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -38.0), P.cell_center(intent.target_cell), P.TELEGRAPH_PULSE_LINE, 20.0)
			"aimed_shot", "light_shot":
				for area_cell in intent.affected_cells:
					_draw_hazard_tile(canvas, area_cell, P.TELEGRAPH_SHOT_FILL, P.TELEGRAPH_SHOT_LINE, pulse)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -36.0), P.cell_center(intent.target_cell), P.TELEGRAPH_SHOT_LINE, 8.0)
			"charged_strike":
				for area_cell in intent.affected_cells:
					_draw_hazard_tile(canvas, area_cell, P.TELEGRAPH_CHARGE_FILL, P.TELEGRAPH_CHARGE_LINE, pulse)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -32.0), P.cell_center(intent.target_cell), P.TELEGRAPH_CHARGE_LINE, 12.0)
			"blight_field":
				for area_cell in intent.affected_cells:
					_draw_hazard_tile(canvas, area_cell, P.HAZARD_BLIGHT_FILL, P.HAZARD_BLIGHT_LINE, pulse)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -32.0), P.cell_center(intent.target_cell), P.HAZARD_BLIGHT_LINE, 12.0)
			"spring_bloom":
				for area_cell in intent.affected_cells:
					_draw_hazard_tile(canvas, area_cell, P.HAZARD_SPRING_FILL, P.HAZARD_SPRING_LINE, pulse)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -34.0), P.cell_center(intent.target_cell), P.HAZARD_SPRING_LINE, 10.0)
			"sakura_shock":
				for area_cell in intent.affected_cells:
					_draw_hazard_tile(canvas, area_cell, P.TELEGRAPH_CHARGE_FILL, P.TELEGRAPH_CHARGE_LINE, pulse)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -30.0), P.cell_center(intent.target_cell), P.TELEGRAPH_CHARGE_LINE, 10.0)
			"basic_melee":
				_draw_hazard_tile(canvas, intent.target_cell, P.TELEGRAPH_CHARGE_FILL, P.RING_MELEE, pulse)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -28.0), P.cell_center(intent.target_cell), P.RING_MELEE, 8.0)
			"lock_on":
				# The mark itself deals no damage; it paints the hero the archer
				# has chosen so the next turn's arrow is not a surprise.
				_draw_hazard_tile(canvas, intent.target_cell, P.TELEGRAPH_SHOT_FILL, P.TELEGRAPH_SHOT_LINE, pulse)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -36.0), P.cell_center(intent.target_cell), P.TELEGRAPH_SHOT_LINE, 4.0)
			"locked_shot":
				for area_cell in intent.affected_cells:
					_draw_hazard_tile(canvas, area_cell, P.TELEGRAPH_SHOT_FILL, P.TELEGRAPH_SHOT_LINE, pulse)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -36.0), P.cell_center(intent.target_cell), P.TELEGRAPH_SHOT_LINE, 12.0)
			"shadow_raid":
				for path_cell in intent.move_path:
					var pts := P.cell_diamond(path_cell, 7.0)
					canvas.draw_colored_polygon(pts, P.TELEGRAPH_PURSUIT_FILL)
					P.draw_polyline_closed(canvas, pts, P.TELEGRAPH_PURSUIT_LINE, 1.8)
				_draw_hazard_tile(canvas, intent.target_cell, P.TELEGRAPH_CHARGE_FILL, P.RING_MELEE, pulse)
				if source != null and source.is_alive():
					# Draw the blow from where the dash actually ends, so the arc
					# matches the path instead of the archer's original tile.
					var start_cell: Vector2i = source.cell
					if not intent.move_path.is_empty():
						start_cell = intent.move_path[intent.move_path.size() - 1]
					draw_aim_arc(canvas, P.cell_center(start_cell) + Vector2(0.0, -28.0), P.cell_center(intent.target_cell), P.RING_MELEE, 8.0)
			"rot_curse":
				_draw_hazard_tile(canvas, intent.target_cell, P.TELEGRAPH_PULSE_FILL, P.TELEGRAPH_PULSE_LINE, pulse)
				if source != null and source.is_alive():
					draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -34.0), P.cell_center(intent.target_cell), P.TELEGRAPH_PULSE_LINE, 6.0)
			"pursuit":
				for path_cell in intent.affected_cells:
					var pts := P.cell_diamond(path_cell, 7.0)
					canvas.draw_colored_polygon(pts, P.TELEGRAPH_PURSUIT_FILL)
					P.draw_polyline_closed(canvas, pts, P.TELEGRAPH_PURSUIT_LINE, 1.8)
			"wait":
				if source != null and source.is_alive():
					var pts := P.cell_diamond(source.cell, 6.0)
					P.draw_polyline_closed(canvas, pts, P.RING_WAIT, 1.5)


## Into-the-Breach style unmistakable hazard tile: bright fill + diagonal
## caution stripes + pulsing double outline.
static func _draw_hazard_tile(canvas: CanvasItem, cell: Vector2i, fill: Color, line: Color, pulse: float) -> void:
	var outer := P.cell_diamond(cell, 1.5)
	canvas.draw_colored_polygon(outer, Color(fill.r, fill.g, fill.b, fill.a * pulse))

	# Diagonal caution stripes across the diamond
	var stripe_col := Color(line.r, line.g, line.b, 0.35 * pulse)
	for frac in [0.25, 0.5, 0.75]:
		var p1 := outer[0].lerp(outer[3], frac)
		var p2 := outer[1].lerp(outer[2], frac)
		canvas.draw_line(p1, p2, stripe_col, 2.0, true)

	P.draw_polyline_closed(canvas, outer, Color(line.r, line.g, line.b, 0.7 + 0.3 * pulse), 3.0)
	var inner := P.cell_diamond(cell, 7.0)
	P.draw_polyline_closed(canvas, inner, Color(line.r, line.g, line.b, 0.45 * pulse), 1.4)


## Drawn ABOVE actors so danger labels are never hidden behind a standee's legs.
static func draw_telegraph_labels(canvas: CanvasItem, controller, _fx_state: Dictionary) -> void:
	for intent in controller.intents:
		if intent.state != IntentScript.IntentState.ACTIVE:
			continue
		var label := ""
		var color := P.TEXT
		var anchor_cell: Vector2i = intent.target_cell
		# Quote the same mitigation the resolver bills with. A badge that says
		# 1688 for a hit that removes 1508 trains players to ignore badges.
		var shown: int = intent.preview_health_damage(controller)
		match intent.action_id:
			"ground_pulse":
				label = "脉冲 %d" % shown
				color = P.TELEGRAPH_PULSE_MARK
			"echo_bolt":
				label = "回声弹 %d" % shown
				color = P.TELEGRAPH_PULSE_MARK
			"aimed_shot":
				label = "贯通狙击 %d" % shown
				color = P.TELEGRAPH_SHOT_MARK
			"light_shot":
				label = "点射 %d" % shown
				color = P.TELEGRAPH_SHOT_MARK
			"charged_strike":
				label = "蓄力 %d" % shown
				color = P.TELEGRAPH_CHARGE_MARK
			"basic_melee":
				anchor_cell = intent.target_cell
				label = "斩击 %d" % shown
				color = P.TELEGRAPH_CHARGE_MARK
			"blight_field":
				label = "樱落 %d" % shown
				color = P.HAZARD_BLIGHT_LINE
			"spring_bloom":
				label = "春痕 %d" % shown
				color = P.HAZARD_SPRING_LINE
			"sakura_shock":
				label = "震荡 %d" % shown
				color = P.TELEGRAPH_CHARGE_MARK
			"lock_on":
				label = "锁命"
				color = P.TELEGRAPH_SHOT_MARK
			"locked_shot":
				label = "锁命箭 %d" % shown
				color = P.TELEGRAPH_SHOT_MARK
			"shadow_raid":
				label = "突袭 %d" % shown
				color = P.TELEGRAPH_CHARGE_MARK
			"rot_curse":
				label = "降防 %d" % intent.damage
				color = P.TELEGRAPH_PULSE_MARK
			_:
				continue

		var pos := P.cell_center(anchor_cell)
		# If an actor stands on this cell, float the danger badge cleanly above their head
		if has_living_actor_at(controller, anchor_cell):
			pos += Vector2(0.0, -P.STANDEE_HEIGHT - 6.0)
			label = "! " + label
		_draw_telegraph_tag(canvas, pos, label, color)


# --- danger queries (the single source for the whole board family) ------------

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
			"charged_strike", "aimed_shot", "light_shot", "ground_pulse", "echo_bolt", "basic_melee":
				if intent.target_cell == cell or intent.affected_cells.has(cell):
					return true
			"locked_shot", "shadow_raid", "rot_curse":
				if intent.target_cell == cell or intent.affected_cells.has(cell):
					return true
	return false


# --- short-lived fx ------------------------------------------------------------

static func draw_impact_flashes(canvas: CanvasItem, fx_state: Dictionary) -> void:
	var flashes: Array = fx_state.get("impacts", [])
	for f in flashes:
		var age: float = float(f.get("age", 0.0))
		var dur: float = maxf(0.05, float(f.get("duration", 0.35)))
		var u: float = clampf(age / dur, 0.0, 1.0)
		var cell: Vector2i = f.get("cell", Vector2i.ZERO)
		var col: Color = f.get("color", P.TELEGRAPH_CHARGE_LINE)
		var pts := P.cell_diamond(cell, -6.0 * u)
		canvas.draw_colored_polygon(pts, Color(col.r, col.g, col.b, (1.0 - u) * 0.55))
		P.draw_polyline_closed(canvas, pts, Color(1.0, 0.95, 0.9, (1.0 - u) * 0.95), 3.0)


static func draw_popups(canvas: CanvasItem, fx_state: Dictionary) -> void:
	var popups: Array = fx_state.get("popups", [])
	var font := ThemeDB.fallback_font
	for item in popups:
		var age: float = float(item.get("age", 0.0))
		var duration: float = maxf(0.1, float(item.get("duration", 0.9)))
		var u: float = clampf(age / duration, 0.0, 1.0)
		var pos: Vector2 = item.get("pos", Vector2.ZERO) + Vector2(0.0, -36.0 * u)
		var base_color: Color = item.get("color", P.TEXT)
		var alpha: float = 1.0 - maxf(0.0, (u - 0.55) / 0.45)
		var text: String = str(item.get("text", ""))
		# Subtle dark outline for readability
		canvas.draw_string(font, pos + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.04, 0.05, 0.07, alpha * 0.9))
		canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(base_color.r, base_color.g, base_color.b, alpha))


# --- helpers -------------------------------------------------------------------

static func _draw_telegraph_tag(canvas: CanvasItem, center: Vector2, text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var pos := Vector2(center.x - sz.x * 0.5, center.y + 4.0)
	canvas.draw_rect(Rect2(pos.x - 4.0, pos.y - 11.0, sz.x + 8.0, 15.0), Color(0.05, 0.06, 0.08, 0.78), true)
	canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


static func draw_aim_arc(canvas: CanvasItem, from_pos: Vector2, to_pos: Vector2, color: Color, lift: float) -> void:
	var line_color := Color(color.r, color.g, color.b, 0.55)
	var mid := (from_pos + to_pos) * 0.5 + Vector2(0.0, -lift)
	var steps := 10
	var prev := from_pos
	for i in range(1, steps + 1):
		var u := float(i) / float(steps)
		var p := from_pos.lerp(mid, u).lerp(mid.lerp(to_pos, u), u)
		if i % 2 == 1:
			canvas.draw_line(prev, p, line_color, 1.8, true)
		prev = p


## Subtle breathing crimson vignette around the viewport edges whenever the
## active hero is standing inside an active enemy attack tile.
static func draw_danger_vignette(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	if controller.phase != controller.BattlePhase.PLAYER:
		return
	var hero = controller.get_active_character()
	if hero == null or not hero.is_alive():
		return
	if not is_cell_in_danger(controller, hero.cell):
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

	# Four soft gradient strips framing the screen without obscuring the center
	canvas.draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, edge_y), Vector2(0, edge_y)]),
		PackedColorArray([c_edge, c_edge, c_zero, c_zero])
	)
	canvas.draw_polygon(
		PackedVector2Array([Vector2(0, h - edge_y), Vector2(w, h - edge_y), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([c_zero, c_zero, c_edge, c_edge])
	)
	canvas.draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(edge_x, 0), Vector2(edge_x, h), Vector2(0, h)]),
		PackedColorArray([c_edge, c_zero, c_zero, c_edge])
	)
	canvas.draw_polygon(
		PackedVector2Array([Vector2(w - edge_x, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - edge_x, h)]),
		PackedColorArray([c_zero, c_edge, c_edge, c_zero])
	)
