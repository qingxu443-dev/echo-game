class_name BoardView
extends RefCounted

## 2.5D Isometric battlefield renderer: elevated stone slab grid, telegraphs,
## movement/target hints, depth-sorted 3D-style ruin pillars and AI standee
## sprites with procedural idle/move/hit animations and floating damage popups.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const IntentScript = preload("res://scripts/battle/battle_intent.gd")
const P = preload("res://scripts/ui/theme_palette.gd")
const SummonServiceScript = preload("res://scripts/battle/summon_service.gd")
const SkillRegistryScript = preload("res://scripts/battle/skill_registry.gd")
const CharacterSkillRuntimeScript = preload("res://scripts/battle/character_skill_runtime.gd")

const ACTOR_SPRITE_DIR: String = "res://assets/actors/"
const STANDEE_HEIGHT: float = 96.0

static var _sprite_cache: Dictionary = {}


static func draw(canvas: CanvasItem, controller, selected_skill: int, skill_bar: Array, fx_state: Dictionary = {}) -> void:
	_draw_grid(canvas, controller)
	_draw_move_hints(canvas, controller, selected_skill, fx_state)
	_draw_hover_hint(canvas, controller, fx_state)
	_draw_telegraphs(canvas, controller, fx_state)
	_draw_target_hints(canvas, controller, selected_skill, skill_bar, fx_state)
	_draw_dropped_loot(canvas, controller, fx_state)
	_draw_depth_sorted_objects(canvas, controller, fx_state)
	_draw_impact_flashes(canvas, fx_state)
	_draw_telegraph_labels(canvas, controller, fx_state)
	_draw_popups(canvas, fx_state)
	_draw_danger_vignette(canvas, controller, fx_state)


# --- 2.5D isometric stone slab grid -----------------------------------------

static func _draw_grid(canvas: CanvasItem, controller) -> void:
	P.board_grid_size = controller.grid_size
	var max_x: int = controller.grid_size.x - 1
	var max_y: int = controller.grid_size.y - 1

	# Soft ambient drop shadow beneath the floating ruin board (in view-space)
	var shadow_poly := PackedVector2Array([
		P.view_cell_diamond(Vector2i(0, 0), -4.0, P.ISO_TILE_DEPTH + 10.0)[0],
		P.view_cell_diamond(Vector2i(max_x, 0), -4.0, P.ISO_TILE_DEPTH + 10.0)[1],
		P.view_cell_diamond(Vector2i(max_x, max_y), -4.0, P.ISO_TILE_DEPTH + 10.0)[2],
		P.view_cell_diamond(Vector2i(0, max_y), -4.0, P.ISO_TILE_DEPTH + 10.0)[3],
	])
	canvas.draw_colored_polygon(shadow_poly, Color(0.01, 0.015, 0.025, 0.55))

	# Draw tiles back-to-front by view-space isometric depth (vx + vy)
	for depth in range(controller.grid_size.x + controller.grid_size.y - 1):
		for vx in range(controller.grid_size.x):
			var vy: int = depth - vx
			if vy < 0 or vy >= controller.grid_size.y:
				continue
			var vc := Vector2i(vx, vy)
			var logical_cell := P.from_view_cell(vc)
			var pts := P.view_cell_diamond(vc)
			var fill := P.BOARD_LIGHT if (logical_cell.x + logical_cell.y) % 2 == 0 else P.BOARD_DARK
			canvas.draw_colored_polygon(pts, fill)
			_draw_closed_polyline(canvas, pts, P.BOARD_LINE, 1.0)

			# Outer front edges in view-space always carry the 2.5D slab thickness
			if vy == max_y:
				var left_face := PackedVector2Array([
					pts[3],
					pts[2],
					pts[2] + Vector2(0.0, P.ISO_TILE_DEPTH),
					pts[3] + Vector2(0.0, P.ISO_TILE_DEPTH),
				])
				canvas.draw_colored_polygon(left_face, P.BOARD_SIDE_LEFT)
				_draw_closed_polyline(canvas, left_face, Color(0.09, 0.11, 0.14, 0.9), 1.0)
			if vx == max_x:
				var right_face := PackedVector2Array([
					pts[2],
					pts[1],
					pts[1] + Vector2(0.0, P.ISO_TILE_DEPTH),
					pts[2] + Vector2(0.0, P.ISO_TILE_DEPTH),
				])
				canvas.draw_colored_polygon(right_face, P.BOARD_SIDE_RIGHT)
				_draw_closed_polyline(canvas, right_face, Color(0.07, 0.08, 0.11, 0.9), 1.0)


static func _draw_move_hints(canvas: CanvasItem, controller, selected_skill: int, fx_state: Dictionary) -> void:
	if controller.phase != controller.BattlePhase.PLAYER or selected_skill >= 0:
		return
	var free_stride: bool = controller.run_state != null and controller.run_state.has_mod(&"echo_stride") and controller.free_move_used_turn != controller.turn_number
	if not free_stride and not controller.ap.can_spend(1):
		return
	var mover = controller.get_active_character()
	if mover == null or not mover.is_alive():
		return
	var t: float = float(fx_state.get("time", 0.0))
	var mover_in_danger: bool = _is_cell_in_danger(controller, mover.cell)
	var guide_pulse: float = 0.65 + 0.35 * sin(t * 5.0)
	var occupied: Dictionary = controller.get_occupied_cells(mover.actor_id)
	var max_steps: int = controller.PLAYER_MOVE_MAX_STEPS
	for dy in range(-max_steps, max_steps + 1):
		for dx in range(-max_steps, max_steps + 1):
			if dx == 0 and dy == 0:
				continue
			if absi(dx) + absi(dy) > max_steps:
				continue
			var goal: Vector2i = mover.cell + Vector2i(dx, dy)
			if not P.is_inside_board(goal, controller.grid_size):
				continue
			if controller.blocked_cells.has(goal) or occupied.has(goal):
				continue
			var path := GridRulesScript.find_path(mover.cell, goal, controller.grid_size, controller.blocked_cells, occupied, max_steps)
			if path.is_empty():
				continue
			var goal_safe: bool = not _is_cell_in_danger(controller, goal)
			var emphasize_escape: bool = mover_in_danger and goal_safe and absi(dx) + absi(dy) == 1
			var pts := P.cell_diamond(goal, 2.5)
			if emphasize_escape:
				var fcol := Color(P.MOVE_GUIDE_FILL.r, P.MOVE_GUIDE_FILL.g, P.MOVE_GUIDE_FILL.b, P.MOVE_GUIDE_FILL.a * guide_pulse)
				var lcol := Color(P.MOVE_GUIDE_LINE.r, P.MOVE_GUIDE_LINE.g, P.MOVE_GUIDE_LINE.b, 0.65 + 0.35 * guide_pulse)
				canvas.draw_colored_polygon(pts, fcol)
				_draw_closed_polyline(canvas, pts, lcol, 2.6)
				# Pulsing inner diamond beacon so escape tiles are unmistakable
				var inner := P.cell_diamond(goal, 12.0 - 3.0 * guide_pulse)
				_draw_closed_polyline(canvas, inner, Color(0.85, 0.99, 1.0, 0.65 * guide_pulse), 1.6)
			else:
				canvas.draw_colored_polygon(pts, P.MOVE_FILL)
				_draw_closed_polyline(canvas, pts, P.MOVE_LINE, 1.8)


static func _draw_hover_hint(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	if not fx_state.has("hover_cell"):
		return
	var cell: Vector2i = fx_state["hover_cell"]
	if not P.is_inside_board(cell, controller.grid_size):
		return
	var pts := P.cell_diamond(cell, 1.5)
	canvas.draw_colored_polygon(pts, P.HOVER_FILL)
	_draw_closed_polyline(canvas, pts, P.HOVER_LINE, 2.0)


# --- telegraphs & target hints ----------------------------------------------

static func _draw_telegraphs(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
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
					_draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -38.0), P.cell_center(intent.target_cell), P.TELEGRAPH_PULSE_LINE, 20.0)
			"aimed_shot", "light_shot":
				for area_cell in intent.affected_cells:
					_draw_hazard_tile(canvas, area_cell, P.TELEGRAPH_SHOT_FILL, P.TELEGRAPH_SHOT_LINE, pulse)
				if source != null and source.is_alive():
					_draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -36.0), P.cell_center(intent.target_cell), P.TELEGRAPH_SHOT_LINE, 8.0)
			"charged_strike":
				for area_cell in intent.affected_cells:
					_draw_hazard_tile(canvas, area_cell, P.TELEGRAPH_CHARGE_FILL, P.TELEGRAPH_CHARGE_LINE, pulse)
				if source != null and source.is_alive():
					_draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -32.0), P.cell_center(intent.target_cell), P.TELEGRAPH_CHARGE_LINE, 12.0)
			"basic_melee":
				_draw_hazard_tile(canvas, intent.target_cell, P.TELEGRAPH_CHARGE_FILL, P.RING_MELEE, pulse)
				if source != null and source.is_alive():
					_draw_aim_arc(canvas, P.cell_center(source.cell) + Vector2(0.0, -28.0), P.cell_center(intent.target_cell), P.RING_MELEE, 8.0)
			"pursuit":
				for path_cell in intent.affected_cells:
					var pts := P.cell_diamond(path_cell, 7.0)
					canvas.draw_colored_polygon(pts, P.TELEGRAPH_PURSUIT_FILL)
					_draw_closed_polyline(canvas, pts, P.TELEGRAPH_PURSUIT_LINE, 1.8)
			"wait":
				if source != null and source.is_alive():
					var pts := P.cell_diamond(source.cell, 6.0)
					_draw_closed_polyline(canvas, pts, P.RING_WAIT, 1.5)


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

	_draw_closed_polyline(canvas, outer, Color(line.r, line.g, line.b, 0.7 + 0.3 * pulse), 3.0)
	var inner := P.cell_diamond(cell, 7.0)
	_draw_closed_polyline(canvas, inner, Color(line.r, line.g, line.b, 0.45 * pulse), 1.4)


## Drawn ABOVE actors so danger labels are never hidden behind a standee's legs.
static func _draw_telegraph_labels(canvas: CanvasItem, controller, _fx_state: Dictionary) -> void:
	for intent in controller.intents:
		if intent.state != IntentScript.IntentState.ACTIVE:
			continue
		var label := ""
		var color := P.TEXT
		var anchor_cell: Vector2i = intent.target_cell
		match intent.action_id:
			"ground_pulse":
				label = "脉冲 %d" % intent.damage
				color = P.TELEGRAPH_PULSE_MARK
			"echo_bolt":
				label = "回声弹 %d" % intent.damage
				color = P.TELEGRAPH_PULSE_MARK
			"aimed_shot":
				label = "贯通狙击 %d" % intent.damage
				color = P.TELEGRAPH_SHOT_MARK
			"light_shot":
				label = "点射 %d" % intent.damage
				color = P.TELEGRAPH_SHOT_MARK
			"charged_strike":
				label = "蓄力 %d" % intent.damage
				color = P.TELEGRAPH_CHARGE_MARK
			"basic_melee":
				anchor_cell = intent.target_cell
				label = "斩击 %d" % intent.damage
				color = P.TELEGRAPH_CHARGE_MARK
			_:
				continue

		var pos := P.cell_center(anchor_cell)
		# If an actor stands on this cell, float the danger badge cleanly above their head
		if _has_living_actor_at(controller, anchor_cell):
			pos += Vector2(0.0, -STANDEE_HEIGHT - 6.0)
			label = "! " + label
		_draw_telegraph_tag(canvas, pos, label, color)


static func _has_living_actor_at(controller, cell: Vector2i) -> bool:
	for actor_id in controller.actors:
		var a = controller.actors[actor_id]
		if a.is_alive() and a.cell == cell:
			return true
	return false


static func _is_cell_in_danger(controller, cell: Vector2i) -> bool:
	for intent in controller.intents:
		if intent.state != IntentScript.IntentState.ACTIVE:
			continue
		match intent.action_id:
			"charged_strike", "aimed_shot", "light_shot", "ground_pulse", "echo_bolt", "basic_melee":
				if intent.target_cell == cell or intent.affected_cells.has(cell):
					return true
	return false


static func _draw_telegraph_tag(canvas: CanvasItem, center: Vector2, text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var pos := Vector2(center.x - sz.x * 0.5, center.y + 4.0)
	canvas.draw_rect(Rect2(pos.x - 4.0, pos.y - 11.0, sz.x + 8.0, 15.0), Color(0.05, 0.06, 0.08, 0.78), true)
	canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


static func _draw_aim_arc(canvas: CanvasItem, from_pos: Vector2, to_pos: Vector2, color: Color, lift: float) -> void:
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


static func _draw_target_hints(canvas: CanvasItem, controller, selected_skill: int, skill_bar: Array, fx_state: Dictionary) -> void:
	if controller.phase != controller.BattlePhase.PLAYER:
		return
	if selected_skill < 0 or selected_skill >= skill_bar.size():
		return
	var t: float = float(fx_state.get("time", 0.0))
	var inset: float = 2.0 + 1.5 * sin(t * 6.0)
	var skill: Dictionary = skill_bar[selected_skill]
	var mode := str(skill["mode"])
	if mode == "actor":
		for actor_id in controller.actors:
			if not can_target(controller, skill_bar, str(skill["id"]), str(actor_id)):
				continue
			var pts := P.cell_diamond(controller.actors[actor_id].cell, inset)
			canvas.draw_colored_polygon(pts, Color(P.RING_TARGET.r, P.RING_TARGET.g, P.RING_TARGET.b, 0.22))
			_draw_closed_polyline(canvas, pts, P.GOLD_PALE, 2.5)
		return
	if mode == "ally":
		for actor_id in controller.actors:
			if not can_target_ally(controller, skill_bar, str(skill["id"]), str(actor_id)):
				continue
			var pts := P.cell_diamond(controller.actors[actor_id].cell, inset)
			canvas.draw_colored_polygon(pts, Color(P.RING_ALLY.r, P.RING_ALLY.g, P.RING_ALLY.b, 0.22))
			_draw_closed_polyline(canvas, pts, P.RING_ALLY, 2.5)


# --- depth-sorted 2.5D pillars & standee actors ------------------------------

static func _draw_dropped_loot(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	if controller.dropped_loot.is_empty():
		return
	var t: float = float(fx_state.get("time", 0.0))
	var bob: float = sin(t * 4.2) * 3.0
	var font := ThemeDB.fallback_font
	for cell in controller.dropped_loot:
		var items: Array = controller.dropped_loot[cell]
		if items.is_empty():
			continue
		var c := P.cell_center(cell)
		# Golden beacon beam + floating equipment diamond on the ground
		var pts := P.cell_diamond(cell, 10.0)
		canvas.draw_colored_polygon(pts, Color(0.95, 0.80, 0.38, 0.28))
		_draw_closed_polyline(canvas, pts, P.GOLD_PALE, 2.0)
		var gem_c := c + Vector2(0.0, -14.0 + bob)
		var gem := PackedVector2Array([
			gem_c + Vector2(0.0, -9.0),
			gem_c + Vector2(8.0, 0.0),
			gem_c + Vector2(0.0, 9.0),
			gem_c + Vector2(-8.0, 0.0),
		])
		canvas.draw_colored_polygon(gem, P.GOLD_LIGHT)
		_draw_closed_polyline(canvas, gem, Color.WHITE, 1.4)
		var label: String = "掉落: " + str(items[0].get("name", "装备"))
		var sz := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		var lpos := Vector2(c.x - sz.x * 0.5, c.y - 28.0 + bob)
		canvas.draw_rect(Rect2(lpos.x - 4.0, lpos.y - 10.0, sz.x + 8.0, 14.0), Color(0.06, 0.07, 0.09, 0.85), true)
		canvas.draw_string(font, lpos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.GOLD_PALE)


static func _draw_depth_sorted_objects(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	var items: Array = []

	for cell in controller.blocked_cells:
		if not P.is_inside_board(cell, controller.grid_size):
			continue
		var vc := P.to_view_cell(cell)
		items.append({
			"kind": "obstacle",
			"cell": cell,
			"depth": float(vc.x + vc.y) - 0.1,
		})

	for b_cell in controller.beacons:
		var b: Dictionary = controller.beacons[b_cell]
		if int(b.get("health", 0)) <= 0:
			continue
		var vc := P.to_view_cell(b_cell)
		items.append({
			"kind": "beacon",
			"cell": b_cell,
			"beacon": b,
			"depth": float(vc.x + vc.y) - 0.05,
		})

	var actor_positions: Dictionary = fx_state.get("actor_pos", {})
	for actor_id in controller.actors:
		var actor = controller.actors[actor_id]
		if not actor.is_alive() and not actor.is_downed():
			continue
		var screen_pos: Vector2 = actor_positions.get(actor_id, P.cell_center(actor.cell))
		# Depth sort by visual ground Y so mid-hop actors sort cleanly too
		var depth_val: float = (screen_pos.y - P.ISO_ORIGIN.y) / (P.ISO_TILE_H * 0.5)
		items.append({
			"kind": "actor",
			"actor_id": String(actor_id),
			"actor": actor,
			"pos": screen_pos,
			"depth": depth_val,
		})

	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["depth"]) < float(b["depth"])
	)

	for item in items:
		if item["kind"] == "obstacle":
			_draw_obstacle_pillar(canvas, item["cell"])
		elif item["kind"] == "beacon":
			_draw_relic_beacon(canvas, controller, item["cell"], item["beacon"], fx_state)
		else:
			_draw_single_actor(canvas, controller, item["actor_id"], item["actor"], item["pos"], fx_state)


static func _draw_relic_beacon(canvas: CanvasItem, controller, cell: Vector2i, beacon: Dictionary, fx_state: Dictionary) -> void:
	var t: float = float(fx_state.get("time", 0.0))
	var in_danger: bool = _is_cell_in_danger(controller, cell)
	var base := P.cell_diamond(cell, 10.0)
	var mid := P.cell_diamond(cell, 10.0, -18.0)
	var lid := P.cell_diamond(cell, 11.5, -26.0)

	# 2.5D Relic Chest body (dark iron-bound ancient timber + gold trim)
	var wood_left := Color("#4f3825")
	var wood_right := Color("#382618")
	var lid_top := Color("#6b4d31")
	var trim := P.TELEGRAPH_CHARGE_LINE if in_danger else P.GOLD_LIGHT

	# Left & right lower chest walls
	canvas.draw_colored_polygon(PackedVector2Array([base[3], base[2], mid[2], mid[3]]), wood_left)
	canvas.draw_colored_polygon(PackedVector2Array([base[2], base[1], mid[1], mid[2]]), wood_right)
	# Upper arched lid sides & top
	canvas.draw_colored_polygon(PackedVector2Array([mid[3], mid[2], lid[2], lid[3]]), Color("#5c412a"))
	canvas.draw_colored_polygon(PackedVector2Array([mid[2], mid[1], lid[1], lid[2]]), Color("#432e1d"))
	canvas.draw_colored_polygon(lid, lid_top)

	# Gold metal bands & clasp
	_draw_closed_polyline(canvas, mid, trim, 1.8)
	_draw_closed_polyline(canvas, lid, trim, 1.6)
	var clasp := mid[2] + Vector2(0.0, 2.0)
	canvas.draw_rect(Rect2(clasp - Vector2(4.0, 4.0), Vector2(8.0, 9.0)), P.GOLD_PALE, true)
	canvas.draw_rect(Rect2(clasp - Vector2(4.0, 4.0), Vector2(8.0, 9.0)), Color("#2b1f14"), false, 1.0)

	# Subtle warm golden treasure shimmer above the chest
	var glow_alpha: float = 0.25 + 0.20 * sin(t * 3.8)
	var glow_col := Color(1.0, 0.35, 0.30, glow_alpha + 0.15) if in_danger else Color(0.98, 0.84, 0.45, glow_alpha)
	canvas.draw_circle(P.cell_center(cell) + Vector2(0.0, -32.0), 8.0, glow_col)

	# Chest durability HP bar underneath
	var pos := P.cell_center(cell) + Vector2(0.0, 13.0)
	var bar_w: float = 42.0
	var bar_h: float = 5.0
	var rect := Rect2(pos.x - bar_w * 0.5, pos.y, bar_w, bar_h)
	canvas.draw_rect(rect.grow(1.0), P.HP_BG, true)
	var ratio: float = clampf(float(beacon["health"]) / float(maxi(1, int(beacon["max_health"]))), 0.0, 1.0)
	if ratio > 0.0:
		canvas.draw_rect(Rect2(rect.position, Vector2(bar_w * ratio, bar_h)), P.GOLD_LIGHT, true)


static func _draw_impact_flashes(canvas: CanvasItem, fx_state: Dictionary) -> void:
	var flashes: Array = fx_state.get("impacts", [])
	for f in flashes:
		var age: float = float(f.get("age", 0.0))
		var dur: float = maxf(0.05, float(f.get("duration", 0.35)))
		var u: float = clampf(age / dur, 0.0, 1.0)
		var cell: Vector2i = f.get("cell", Vector2i.ZERO)
		var col: Color = f.get("color", P.TELEGRAPH_CHARGE_LINE)
		var pts := P.cell_diamond(cell, -6.0 * u)
		canvas.draw_colored_polygon(pts, Color(col.r, col.g, col.b, (1.0 - u) * 0.55))
		_draw_closed_polyline(canvas, pts, Color(1.0, 0.95, 0.9, (1.0 - u) * 0.95), 3.0)


static func _draw_obstacle_pillar(canvas: CanvasItem, cell: Vector2i) -> void:
	var base := P.cell_diamond(cell, 5.0)
	var top := P.cell_diamond(cell, 5.0, -P.ISO_OBSTACLE_H)

	# Left face
	var left_face := PackedVector2Array([base[3], base[2], top[2], top[3]])
	canvas.draw_colored_polygon(left_face, P.BLOCKED_LEFT)
	_draw_closed_polyline(canvas, left_face, Color(0.11, 0.11, 0.12, 0.9), 1.0)

	# Right face
	var right_face := PackedVector2Array([base[2], base[1], top[1], top[2]])
	canvas.draw_colored_polygon(right_face, P.BLOCKED_RIGHT)
	_draw_closed_polyline(canvas, right_face, Color(0.08, 0.08, 0.09, 0.9), 1.0)

	# Top cap with subtle inner stone bevel
	canvas.draw_colored_polygon(top, P.BLOCKED_FILL)
	_draw_closed_polyline(canvas, top, P.BLOCKED_LINE, 1.5)
	var inner_top := P.cell_diamond(cell, 11.0, -P.ISO_OBSTACLE_H)
	_draw_closed_polyline(canvas, inner_top, Color(0.55, 0.52, 0.46, 0.35), 1.0)


static func _draw_single_actor(canvas: CanvasItem, controller, actor_id: String, actor, base_pos: Vector2, fx_state: Dictionary) -> void:
	if actor.is_downed():
		_draw_downed_actor(canvas, actor, base_pos)
		return

	var t: float = float(fx_state.get("time", 0.0))
	var hit_flashes: Dictionary = fx_state.get("hit_flash", {})
	var lunges: Dictionary = fx_state.get("lunge", {})
	var flash: float = clampf(float(hit_flashes.get(actor_id, 0.0)), 0.0, 1.0)
	var lunge_offset: Vector2 = lunges.get(actor_id, Vector2.ZERO)

	# Hit shake + lunge offset
	var shake_x: float = sin(t * 65.0) * 5.0 * flash if flash > 0.01 else 0.0
	var foot_pos: Vector2 = base_pos + lunge_offset + Vector2(shake_x, 0.0)

	# Ground contact shadow (ellipse approximated as stretched polygon)
	_draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 2.0), 22.0, 11.0, P.SHADOW_COLOR, true)

	# Breathing red danger-pressure filter when standing inside an enemy attack tile
	var in_danger: bool = _is_cell_in_danger(controller, actor.cell)
	var danger_breath: float = (0.5 + 0.5 * sin(t * 4.4)) if in_danger else 0.0

	# Base status rings on the floor beneath the standee
	if in_danger:
		var dr_col := Color(0.98, 0.26, 0.24, 0.35 + 0.45 * danger_breath)
		_draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 1.0), 30.0 + 3.0 * danger_breath, 16.0 + 1.5 * danger_breath, dr_col, false, 2.8)
	if actor.team == "player" and actor_id == controller.active_character_id:
		_draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 1.0), 26.0, 14.0, P.RING_ACTIVE, false, 2.2)
	_draw_floor_status_rings(canvas, controller, actor_id, actor, base_pos)

	# Standee sprite with 4-way isometric facing (front/back + horizontal flip)
	var facing: Dictionary = _compute_facing(controller, actor_id, actor, base_pos, fx_state)
	var use_back: bool = bool(facing["use_back"])
	var flip_h: bool = bool(facing["flip_h"])
	var tex: Texture2D = _resolve_actor_texture(actor, use_back)
	if tex != null:
		var phase: float = float(abs(actor_id.hash() % 100)) * 0.06
		var breathe: float = 1.0 + 0.022 * sin(t * 2.6 + phase)
		var tex_size: Vector2 = tex.get_size()
		var aspect: float = tex_size.x / maxf(1.0, tex_size.y)
		var draw_h: float = STANDEE_HEIGHT * breathe
		var draw_w: float = STANDEE_HEIGHT * aspect * (2.0 - breathe)
		var top_y: float = foot_pos.y - draw_h + 7.0
		var base_tint := Color.WHITE
		if in_danger:
			# Soft pulsing red oppressive tint on the character inside hazard tiles
			base_tint = Color.WHITE.lerp(Color(1.26, 0.72, 0.70, 1.0), 0.35 + 0.55 * danger_breath)
		var modulate := base_tint.lerp(Color(1.8, 1.75, 1.65, 1.0), flash)
		# Mirror cleanly around the standee's foot center so shadow, feet and HP bar stay aligned
		if flip_h:
			canvas.draw_set_transform(Vector2(foot_pos.x, 0.0), 0.0, Vector2(-1.0, 1.0))
			canvas.draw_texture_rect(tex, Rect2(Vector2(-draw_w * 0.5, top_y), Vector2(draw_w, draw_h)), false, modulate)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			canvas.draw_texture_rect(tex, Rect2(Vector2(foot_pos.x - draw_w * 0.5, top_y), Vector2(draw_w, draw_h)), false, modulate)
	else:
		_draw_fallback_token(canvas, actor, foot_pos + Vector2(0.0, -24.0), flash)

	# Compact HP + shield bar under feet & overhead mark badges
	_draw_compact_hp_bar(canvas, actor, base_pos + Vector2(0.0, 13.0))
	_draw_overhead_badges(canvas, controller, actor_id, foot_pos + Vector2(0.0, -STANDEE_HEIGHT + 2.0))


static func _draw_fallback_token(canvas: CanvasItem, actor, center: Vector2, flash: float) -> void:
	var body_color := P.PLAYER_BODY if actor.team == "player" else P.ENEMY_BODY
	var outline := P.PLAYER_OUTLINE if actor.team == "player" else P.ENEMY_OUTLINE
	body_color = body_color.lerp(Color.WHITE, flash * 0.7)
	canvas.draw_circle(center, 18.0, body_color)
	canvas.draw_arc(center, 18.0, 0.0, TAU, 36, outline, 2.5)
	var glyph: String = actor.glyph
	if glyph.is_empty():
		glyph = "锋" if actor.team == "enemy" else "守"
	canvas.draw_string(ThemeDB.fallback_font, center + Vector2(-7.0, 6.0), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, P.TEXT_ON_DARK)


static func _draw_downed_actor(canvas: CanvasItem, actor, base_pos: Vector2) -> void:
	_draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 2.0), 22.0, 11.0, P.SHADOW_COLOR, true)
	var center := base_pos + Vector2(0.0, -10.0)
	canvas.draw_circle(center, 16.0, P.PLAYER_BODY_DOWNED)
	canvas.draw_arc(center, 16.0, 0.0, TAU, 32, P.PLAYER_OUTLINE_DOWNED, 2.0)
	var glyph: String = actor.glyph if not actor.glyph.is_empty() else "守"
	canvas.draw_string(ThemeDB.fallback_font, center + Vector2(-6.0, 6.0), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.TEXT_DISABLED)
	canvas.draw_line(center + Vector2(-10.0, -10.0), center + Vector2(10.0, 10.0), P.DOWNED_MARK, 2.0)
	canvas.draw_line(center + Vector2(10.0, -10.0), center + Vector2(-10.0, 10.0), P.DOWNED_MARK, 2.0)


static func _draw_floor_status_rings(canvas: CanvasItem, controller, actor_id: String, actor, base_pos: Vector2) -> void:
	if actor.team == "player":
		if actor.shield > 0:
			_draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 1.0), 23.0, 12.0, P.RING_SHIELD, false, 2.5)
		if controller.statuses.has_status(actor_id, &"absolute_guard"):
			_draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 1.0), 30.0, 16.0, P.RING_GUARD, false, 2.8)
		return
	if controller.statuses.has_status(actor_id, &"sakura_petal_mark"):
		_draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 1.0), 27.0, 14.5, P.RING_PETAL, false, 2.5)
	if controller.statuses.has_status(actor_id, &"oathkeeper_mark"):
		_draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 1.0), 23.0, 12.0, P.RING_MARK, false, 2.5)


static func _draw_overhead_badges(canvas: CanvasItem, controller, actor_id: String, top_pos: Vector2) -> void:
	var tags: Array[Dictionary] = []
	if controller.statuses.has_status(actor_id, &"absolute_guard"):
		tags.append({"text": "守", "color": P.RING_GUARD})
	if controller.statuses.has_status(actor_id, &"oathkeeper_mark"):
		tags.append({"text": "印", "color": P.MARK_LABEL})
	if controller.statuses.has_status(actor_id, &"sakura_petal_mark"):
		tags.append({"text": "香", "color": P.PETAL_LABEL})
	if tags.is_empty():
		return
	var start_x := top_pos.x - float(tags.size() - 1) * 10.0
	for i in range(tags.size()):
		var p := Vector2(start_x + float(i) * 20.0, top_pos.y)
		canvas.draw_circle(p + Vector2(0.0, -4.0), 9.0, Color(0.08, 0.09, 0.12, 0.85))
		canvas.draw_string(ThemeDB.fallback_font, p + Vector2(-6.0, 1.0), str(tags[i]["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tags[i]["color"])


static func _draw_compact_hp_bar(canvas: CanvasItem, actor, pos: Vector2) -> void:
	var bar_w: float = 42.0
	var bar_h: float = 5.0
	var rect := Rect2(pos.x - bar_w * 0.5, pos.y, bar_w, bar_h)
	canvas.draw_rect(rect.grow(1.0), P.HP_BG, true)
	var ratio: float = clampf(float(actor.health) / float(maxi(1, actor.max_health)), 0.0, 1.0)
	var fill_color := P.HP_PLAYER if actor.team == "player" else P.HP_ENEMY
	if ratio > 0.0:
		canvas.draw_rect(Rect2(rect.position, Vector2(bar_w * ratio, bar_h)), fill_color, true)
	if actor.shield > 0:
		var shield_ratio: float = clampf(float(actor.shield) / float(maxi(1, actor.max_health)), 0.0, 1.0)
		var sh_rect := Rect2(rect.position.x, rect.position.y - 3.0, bar_w * minf(1.0, shield_ratio * 2.5), 2.5)
		canvas.draw_rect(sh_rect, P.HP_SHIELD, true)
	# Enemy AP-driven signature skill charge bar right beneath the HP bar
	if actor.team == "enemy" and actor.skill_charge_max > 0:
		var segs: int = actor.skill_charge_max
		var gap: float = 2.0
		var seg_w: float = (bar_w - gap * float(segs - 1)) / float(segs)
		var full: bool = actor.skill_charge >= segs
		var lit_col := P.TELEGRAPH_CHARGE_LINE if full else P.GOLD_LIGHT
		for i in range(segs):
			var sr := Rect2(rect.position.x + float(i) * (seg_w + gap), rect.end.y + 3.0, seg_w, 3.5)
			canvas.draw_rect(sr, lit_col if i < actor.skill_charge else Color(0.16, 0.18, 0.22, 0.9), true)


static func _draw_popups(canvas: CanvasItem, fx_state: Dictionary) -> void:
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


## Subtle breathing crimson vignette around the viewport edges whenever the
## active hero is standing inside an active enemy attack tile.
static func _draw_danger_vignette(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	if controller.phase != controller.BattlePhase.PLAYER:
		return
	var hero = controller.get_active_character()
	if hero == null or not hero.is_alive():
		return
	if not _is_cell_in_danger(controller, hero.cell):
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


# --- 4-way facing & sprite loading helpers ----------------------------------

## Computes whether this standee should use its rear 3/4 sprite and/or mirror
## horizontally so units always face their active target on the isometric board.
static func _compute_facing(controller, actor_id: String, actor, self_pos: Vector2, fx_state: Dictionary) -> Dictionary:
	var target_pos: Vector2 = _find_look_target_pos(controller, actor_id, actor, fx_state)
	var delta: Vector2 = target_pos - self_pos
	var default_faces_right: bool = (actor.team == "player")

	if delta.length_squared() < 4.0:
		return {"use_back": false, "flip_h": false}

	var want_back: bool = delta.y < -6.0
	var want_right: bool = delta.x >= 0.0
	var flip_h: bool = (want_right != default_faces_right)
	return {"use_back": want_back, "flip_h": flip_h}


static func _find_look_target_pos(controller, actor_id: String, actor, fx_state: Dictionary) -> Vector2:
	if actor.team == "player":
		# Face hovered enemy first if the player is inspecting/aiming at one
		if fx_state.has("hover_cell"):
			var hcell: Vector2i = fx_state["hover_cell"]
			for other_id in controller.actors:
				var other = controller.actors[other_id]
				if other.team == "enemy" and other.is_alive() and other.cell == hcell:
					return P.cell_center(other.cell)
		# Otherwise face the nearest living enemy
		var best_dist: int = 999
		var best_pos: Vector2 = P.cell_center(actor.cell) + Vector2(40.0, 20.0)
		for other_id in controller.actors:
			var other = controller.actors[other_id]
			if other.team == "enemy" and other.is_alive():
				var d: int = absi(other.cell.x - actor.cell.x) + absi(other.cell.y - actor.cell.y)
				if d < best_dist:
					best_dist = d
					best_pos = P.cell_center(other.cell)
		return best_pos

	# Enemy: face its active telegraph target cell/actor first
	for intent in controller.intents:
		if intent.source_actor_id == actor_id and intent.state == IntentScript.IntentState.ACTIVE:
			if not intent.target_actor_id.is_empty():
				var t_actor = controller.get_actor(intent.target_actor_id)
				if t_actor != null and t_actor.is_alive():
					return P.cell_center(t_actor.cell)
			if intent.action_id != "wait" and P.is_inside_board(intent.target_cell, controller.grid_size):
				return P.cell_center(intent.target_cell)

	# Fallback: face nearest living player
	var p_best_dist: int = 999
	var p_best_pos: Vector2 = P.cell_center(actor.cell) + Vector2(-40.0, 20.0)
	for other_id in controller.actors:
		var other = controller.actors[other_id]
		if other.team == "player" and other.is_alive():
			var d: int = absi(other.cell.x - actor.cell.x) + absi(other.cell.y - actor.cell.y)
			if d < p_best_dist:
				p_best_dist = d
				p_best_pos = P.cell_center(other.cell)
	return p_best_pos


static func _resolve_actor_texture(actor, prefer_back: bool = false) -> Texture2D:
	var keys: Array[String] = []
	if actor.team == "player":
		if actor.character_id != &"":
			keys.append(String(actor.character_id))
		keys.append(String(actor.actor_id))
	else:
		keys.append(String(actor.archetype))

	var lookup_keys: Array[String] = []
	if prefer_back:
		for k in keys:
			if not k.is_empty():
				lookup_keys.append(k + "_back")
	for k in keys:
		if not k.is_empty():
			lookup_keys.append(k)

	for key in lookup_keys:
		var tex := _load_cached_texture(ACTOR_SPRITE_DIR + key + ".png")
		if tex != null:
			return tex
	return null


static func _load_cached_texture(path: String) -> Texture2D:
	if _sprite_cache.has(path):
		return _sprite_cache[path]
	var loaded: Texture2D = null
	if ResourceLoader.exists(path, "Texture2D"):
		var res := ResourceLoader.load(path)
		if res is Texture2D:
			loaded = res
	if loaded == null:
		var abs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null and not img.is_empty():
				loaded = ImageTexture.create_from_image(img)
	_sprite_cache[path] = loaded
	return loaded


static func _draw_closed_polyline(canvas: CanvasItem, pts: PackedVector2Array, color: Color, width: float) -> void:
	if pts.size() < 2:
		return
	var closed := PackedVector2Array(pts)
	closed.append(pts[0])
	canvas.draw_polyline(closed, color, width, true)


static func _draw_iso_ellipse(canvas: CanvasItem, center: Vector2, rx: float, ry: float, color: Color, filled: bool, width: float = 2.0) -> void:
	var segs := 28
	var pts := PackedVector2Array()
	pts.resize(segs)
	for i in range(segs):
		var a := (float(i) / float(segs)) * TAU
		pts[i] = center + Vector2(cos(a) * rx, sin(a) * ry)
	if filled:
		canvas.draw_colored_polygon(pts, color)
	else:
		_draw_closed_polyline(canvas, pts, color, width)


# --- targeting predicates (single source of truth with BattleView & tests) ---

static func can_target(controller, skill_bar: Array, skill_id: String, actor_id: String) -> bool:
	var player = controller.get_active_character()
	if player == null:
		return false
	var actor = controller.get_actor(actor_id)
	if actor == null or actor.team != "enemy" or not actor.is_alive():
		return false

	if skill_id.begins_with("summon:"):
		var entry: Dictionary = _entry_for(skill_bar, skill_id)
		if entry.is_empty():
			return false
		var distance: int = absi(actor.cell.x - player.cell.x) + absi(actor.cell.y - player.cell.y)
		if distance < int(entry["min_range"]) or distance > int(entry["max_range"]):
			return false
		return SummonServiceScript.can_summon(controller, StringName(skill_id.substr(7)), actor_id)

	var skill = SkillRegistryScript.get_skill(StringName(skill_id))
	if skill == null:
		return false
	return CharacterSkillRuntimeScript.can_aim(controller, skill, actor)


static func can_target_ally(controller, skill_bar: Array, skill_id: String, actor_id: String) -> bool:
	var player = controller.get_active_character()
	if player == null:
		return false
	var actor = controller.get_actor(actor_id)
	if actor == null or actor.team != "player":
		return false
	var revivable: bool = actor.is_downed() and not controller.oath_shield_revived.has(actor_id)
	if not (actor.is_alive() or revivable):
		return false
	var entry: Dictionary = _entry_for(skill_bar, skill_id)
	if entry.is_empty() or str(entry["mode"]) != "ally":
		return false
	var distance: int = absi(actor.cell.x - player.cell.x) + absi(actor.cell.y - player.cell.y)
	return distance >= int(entry["min_range"]) and distance <= int(entry["max_range"])


static func _entry_for(skill_bar: Array, skill_id: String) -> Dictionary:
	for entry in skill_bar:
		if str(entry["id"]) == skill_id:
			return entry
	return {}
