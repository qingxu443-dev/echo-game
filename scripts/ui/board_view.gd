class_name BoardView
extends RefCounted

## Composition layer of the 2.5D battlefield: the elevated stone slab grid,
## movement / hover / target hints and the targeting predicates. Everything
## else draws through the two layers it owns - the threat layer (what is
## about to hurt) and the world-object layer (what is standing on the slabs,
## depth-sorted).
##
## The shared isometric draw primitives live in the palette so all three
## layers depend downward only: BoardView -> {threat, objects} -> palette.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const P = preload("res://scripts/ui/theme_palette.gd")
const BoardThreatViewScript = preload("res://scripts/ui/board_threat_view.gd")
const BoardObjectsViewScript = preload("res://scripts/ui/board_objects_view.gd")
const SummonServiceScript = preload("res://scripts/battle/summon_service.gd")
const SkillRegistryScript = preload("res://scripts/battle/skill_registry.gd")
const CharacterSkillRuntimeScript = preload("res://scripts/battle/character_skill_runtime.gd")


static func draw(canvas: CanvasItem, controller, selected_skill: int, skill_bar: Array, fx_state: Dictionary = {}) -> void:
	_draw_grid(canvas, controller)
	_draw_deploy_zone(canvas, controller)
	_draw_move_hints(canvas, controller, selected_skill, fx_state)
	# Hazards paint OVER the move hints, not under them: "this tile will hurt you"
	# outranks "this tile is reachable", and a cyan move fill is opaque enough to
	# hide the ground entirely. The player must see the cost of the step they are
	# about to take, not just that the step is allowed.
	BoardThreatViewScript.draw_hazard_tiles(canvas, controller, fx_state)
	BoardThreatViewScript.draw_formation_links(canvas, controller, fx_state)
	_draw_hover_hint(canvas, controller, fx_state)
	BoardThreatViewScript.draw_telegraphs(canvas, controller, fx_state)
	_draw_target_hints(canvas, controller, selected_skill, skill_bar, fx_state)
	BoardObjectsViewScript.draw_dropped_loot(canvas, controller, fx_state)
	BoardObjectsViewScript.draw_depth_sorted_objects(canvas, controller, fx_state)
	BoardThreatViewScript.draw_impact_flashes(canvas, fx_state)
	BoardThreatViewScript.draw_telegraph_labels(canvas, controller, fx_state)
	BoardThreatViewScript.draw_popups(canvas, fx_state)
	BoardThreatViewScript.draw_danger_vignette(canvas, controller, fx_state)


# --- 2.5D isometric stone slab grid -----------------------------------------

static func _draw_grid(canvas: CanvasItem, controller) -> void:
	P.board_grid_size = controller.grid_size
	var view_size := P.view_grid_size()
	var max_x: int = view_size.x - 1
	var max_y: int = view_size.y - 1

	# Soft ambient drop shadow beneath the floating ruin board (in view-space)
	var shadow_poly := PackedVector2Array([
		P.view_cell_diamond(Vector2i(0, 0), -4.0, P.ISO_TILE_DEPTH + 10.0)[0],
		P.view_cell_diamond(Vector2i(max_x, 0), -4.0, P.ISO_TILE_DEPTH + 10.0)[1],
		P.view_cell_diamond(Vector2i(max_x, max_y), -4.0, P.ISO_TILE_DEPTH + 10.0)[2],
		P.view_cell_diamond(Vector2i(0, max_y), -4.0, P.ISO_TILE_DEPTH + 10.0)[3],
	])
	canvas.draw_colored_polygon(shadow_poly, Color(0.01, 0.015, 0.025, 0.55))

	# Draw tiles back-to-front by view-space isometric depth (vx + vy)
	for depth in range(view_size.x + view_size.y - 1):
		for vx in range(view_size.x):
			var vy: int = depth - vx
			if vy < 0 or vy >= view_size.y:
				continue
			var vc := Vector2i(vx, vy)
			var logical_cell := P.from_view_cell(vc)
			var pts := P.view_cell_diamond(vc)
			var fill := P.BOARD_LIGHT if (logical_cell.x + logical_cell.y) % 2 == 0 else P.BOARD_DARK
			canvas.draw_colored_polygon(pts, fill)
			P.draw_polyline_closed(canvas, pts, P.BOARD_LINE, 1.0)

			# Outer front edges in view-space always carry the 2.5D slab thickness
			if vy == max_y:
				var left_face := PackedVector2Array([
					pts[3],
					pts[2],
					pts[2] + Vector2(0.0, P.ISO_TILE_DEPTH),
					pts[3] + Vector2(0.0, P.ISO_TILE_DEPTH),
				])
				canvas.draw_colored_polygon(left_face, P.BOARD_SIDE_LEFT)
				P.draw_polyline_closed(canvas, left_face, Color(0.09, 0.11, 0.14, 0.9), 1.0)
			if vx == max_x:
				var right_face := PackedVector2Array([
					pts[2],
					pts[1],
					pts[1] + Vector2(0.0, P.ISO_TILE_DEPTH),
					pts[2] + Vector2(0.0, P.ISO_TILE_DEPTH),
				])
				canvas.draw_colored_polygon(right_face, P.BOARD_SIDE_RIGHT)
				P.draw_polyline_closed(canvas, right_face, Color(0.07, 0.08, 0.11, 0.9), 1.0)


# --- movement / hover / target hints ----------------------------------------

## §11.1 部署区. Same diamond vocabulary as the move hints, different hue: the
## player is choosing a starting position, not spending this turn's movement.
static func _draw_deploy_zone(canvas: CanvasItem, controller) -> void:
	if controller.phase != controller.BattlePhase.DEPLOY:
		return
	var hero = controller.get_active_character()
	for cell in controller.deploy_zone:
		if controller.blocked_cells.has(cell):
			continue
		if controller.beacons.has(cell) and int(controller.beacons[cell].get("health", 0)) > 0:
			continue
		var pending_here: bool = hero != null and hero.cell == cell
		var pts := P.cell_diamond(cell, 3.0)
		canvas.draw_colored_polygon(pts, P.DEPLOY_ACTIVE_FILL if pending_here else P.DEPLOY_FILL)
		P.draw_polyline_closed(canvas, pts, P.DEPLOY_ACTIVE_LINE if pending_here else P.DEPLOY_LINE, 2.4 if pending_here else 1.4)


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
	var mover_in_danger: bool = BoardThreatViewScript.is_cell_in_danger(controller, mover.cell)
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
			var goal_safe: bool = not BoardThreatViewScript.is_cell_in_danger(controller, goal)
			var emphasize_escape: bool = mover_in_danger and goal_safe and absi(dx) + absi(dy) == 1
			var pts := P.cell_diamond(goal, 2.5)
			if emphasize_escape:
				var fcol := Color(P.MOVE_GUIDE_FILL.r, P.MOVE_GUIDE_FILL.g, P.MOVE_GUIDE_FILL.b, P.MOVE_GUIDE_FILL.a * guide_pulse)
				var lcol := Color(P.MOVE_GUIDE_LINE.r, P.MOVE_GUIDE_LINE.g, P.MOVE_GUIDE_LINE.b, 0.65 + 0.35 * guide_pulse)
				canvas.draw_colored_polygon(pts, fcol)
				P.draw_polyline_closed(canvas, pts, lcol, 2.6)
				# Pulsing inner diamond beacon so escape tiles are unmistakable
				var inner := P.cell_diamond(goal, 12.0 - 3.0 * guide_pulse)
				P.draw_polyline_closed(canvas, inner, Color(0.85, 0.99, 1.0, 0.65 * guide_pulse), 1.6)
			else:
				canvas.draw_colored_polygon(pts, P.MOVE_FILL)
				P.draw_polyline_closed(canvas, pts, P.MOVE_LINE, 1.8)


static func _draw_hover_hint(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	if not fx_state.has("hover_cell"):
		return
	var cell: Vector2i = fx_state["hover_cell"]
	if not P.is_inside_board(cell, controller.grid_size):
		return
	var pts := P.cell_diamond(cell, 1.5)
	canvas.draw_colored_polygon(pts, P.HOVER_FILL)
	P.draw_polyline_closed(canvas, pts, P.HOVER_LINE, 2.0)


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
		var hero = controller.get_active_character()
		var sid := str(skill["id"])
		for actor_id in controller.actors:
			if not can_target(controller, skill_bar, sid, str(actor_id)):
				continue
			var enemy = controller.actors[actor_id]
			var pts := P.cell_diamond(enemy.cell, inset)
			canvas.draw_colored_polygon(pts, Color(P.RING_TARGET.r, P.RING_TARGET.g, P.RING_TARGET.b, 0.22))
			P.draw_polyline_closed(canvas, pts, P.GOLD_PALE, 2.5)
			var will_melee: bool = hero != null and (GridRulesScript.manhattan_distance(hero.cell, enemy.cell) == 1 or sid == "sakura_flowing_wind")
			if will_melee and enemy.melee_tolerance_max > 0 and enemy.melee_tolerance + 1 >= enemy.melee_tolerance_max:
				var tip_pos := P.cell_center(enemy.cell) + Vector2(-46.0, -P.STANDEE_HEIGHT - 28.0)
				var pill := Rect2(tip_pos, Vector2(92.0, 18.0))
				canvas.draw_rect(pill, Color(0.62, 0.12, 0.10, 0.94), true)
				canvas.draw_rect(pill, Color("#ffae52"), false, 1.4)
				canvas.draw_string(ThemeDB.fallback_font, pill.position + Vector2(0.0, 13.0), "⚠ 命中触发反击!", HORIZONTAL_ALIGNMENT_CENTER, pill.size.x, 10, Color("#fff5e0"))
		var skill_def = SkillRegistryScript.get_skill(StringName(sid))
		if skill_def != null:
			for b_cell in controller.beacons:
				var b: Dictionary = controller.beacons[b_cell]
				if str(b.get("kind", "")) != "ward_node" or int(b.get("health", 0)) <= 0:
					continue
				if CharacterSkillRuntimeScript.can_aim_ward_node(controller, skill_def, b_cell):
					var wpts := P.cell_diamond(b_cell, inset)
					canvas.draw_colored_polygon(wpts, Color(0.37, 0.92, 0.72, 0.28))
					P.draw_polyline_closed(canvas, wpts, Color("#9effdf"), 2.6)
		return
	if mode == "ally":
		for actor_id in controller.actors:
			if not can_target_ally(controller, skill_bar, str(skill["id"]), str(actor_id)):
				continue
			var pts := P.cell_diamond(controller.actors[actor_id].cell, inset)
			canvas.draw_colored_polygon(pts, Color(P.RING_ALLY.r, P.RING_ALLY.g, P.RING_ALLY.b, 0.22))
			P.draw_polyline_closed(canvas, pts, P.RING_ALLY, 2.5)


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
