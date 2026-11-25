class_name BoardView
extends RefCounted

## The battlefield: grid, telegraphs, target rings and the units themselves.
##
## Static and canvas-agnostic: it draws onto whatever CanvasItem it is given, so
## it holds no state and can be exercised without a scene tree.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const IntentScript = preload("res://scripts/battle/battle_intent.gd")
const P = preload("res://scripts/ui/theme_palette.gd")
const SummonServiceScript = preload("res://scripts/battle/summon_service.gd")


static func draw(canvas: CanvasItem, controller, selected_skill: int, skill_bar: Array) -> void:
	_draw_grid(canvas, controller)
	_draw_telegraphs(canvas, controller)
	_draw_target_hints(canvas, controller, selected_skill, skill_bar)
	_draw_actors(canvas, controller)


static func _draw_grid(canvas: CanvasItem, controller) -> void:
	for y in range(controller.grid_size.y):
		for x in range(controller.grid_size.x):
			var cell := Vector2i(x, y)
			var rect := P.cell_rect(cell)
			var fill := P.BOARD_LIGHT if (x + y) % 2 == 0 else P.BOARD_DARK
			canvas.draw_rect(rect, fill, true)
			canvas.draw_rect(rect, P.BOARD_LINE, false, 1.0)
			if controller.blocked_cells.has(cell):
				canvas.draw_rect(rect.grow(-5.0), P.BLOCKED_FILL, true)
				canvas.draw_rect(rect.grow(-5.0), P.BLOCKED_LINE, false, 2.0)


static func _draw_actors(canvas: CanvasItem, controller) -> void:
	for actor_id in controller.actors:
		var actor = controller.actors[actor_id]
		if not actor.is_alive():
			continue
		var center := P.cell_center(actor.cell)
		var body_color := P.PLAYER_BODY if actor.team == "player" else P.ENEMY_BODY
		var outline := P.PLAYER_OUTLINE if actor.team == "player" else P.ENEMY_OUTLINE
		canvas.draw_circle(center, 22.0, body_color)
		canvas.draw_arc(center, 22.0, 0.0, TAU, 48, outline, 3.0)
		var glyph: String = actor.glyph
		if glyph.is_empty():
			glyph = "锋" if actor.team == "enemy" else "守"
		canvas.draw_string(ThemeDB.fallback_font, center + Vector2(-7.0, 7.0), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, P.TEXT_ON_DARK)
		_draw_actor_badges(canvas, controller, actor_id, actor, center)


## V2 status markers: shield/guard on Sevrin and the isolated mark on enemies.
static func _draw_actor_badges(canvas: CanvasItem, controller, actor_id: String, actor, center: Vector2) -> void:
	if actor.team == "player":
		if actor.shield > 0:
			canvas.draw_arc(center, 27.0, 0.0, TAU, 48, P.RING_SHIELD, 3.0)
		if actor_id == "sevrin" and controller.statuses.has_status(actor_id, &"absolute_guard"):
			canvas.draw_arc(center, 32.0, 0.0, TAU, 48, P.RING_GUARD, 3.0)
		return
	if controller.statuses.has_status(actor_id, &"oathkeeper_mark"):
		canvas.draw_arc(center, 27.0, 0.0, TAU, 48, P.RING_MARK, 3.0)
		canvas.draw_string(ThemeDB.fallback_font, center + Vector2(-7.0, -28.0), "印", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.MARK_LABEL)


static func _draw_telegraphs(canvas: CanvasItem, controller) -> void:
	for intent in controller.intents:
		if intent.state != IntentScript.IntentState.ACTIVE:
			continue
		match intent.action_id:
			"ground_pulse":
				for area_cell in intent.affected_cells:
					var area_rect := P.cell_rect(area_cell).grow(-5.0)
					canvas.draw_rect(area_rect, P.TELEGRAPH_PULSE_FILL, true)
					canvas.draw_rect(area_rect, P.TELEGRAPH_PULSE_LINE, false, 3.0)
				var center_rect := P.cell_rect(intent.target_cell).grow(-9.0)
				canvas.draw_string(ThemeDB.fallback_font, center_rect.position + Vector2(13.0, 35.0), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, P.TELEGRAPH_PULSE_MARK)
			"aimed_shot":
				var shot_rect := P.cell_rect(intent.target_cell).grow(-4.0)
				canvas.draw_rect(shot_rect, P.TELEGRAPH_SHOT_FILL, true)
				canvas.draw_rect(shot_rect, P.TELEGRAPH_SHOT_LINE, false, 4.0)
				canvas.draw_string(ThemeDB.fallback_font, shot_rect.position + Vector2(8.0, 20.0), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, P.TELEGRAPH_SHOT_MARK)
			"charged_strike":
				var charge_rect := P.cell_rect(intent.target_cell).grow(-4.0)
				canvas.draw_rect(charge_rect, P.TELEGRAPH_CHARGE_FILL, true)
				canvas.draw_rect(charge_rect, P.TELEGRAPH_CHARGE_LINE, false, 4.0)
				canvas.draw_string(ThemeDB.fallback_font, charge_rect.position + Vector2(8.0, 20.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, P.TELEGRAPH_CHARGE_MARK)
			"basic_melee":
				var target = controller.get_actor(intent.target_actor_id)
				if target != null and target.is_alive():
					canvas.draw_arc(P.cell_center(target.cell), 29.0, 0.0, TAU, 48, P.RING_MELEE, 4.0)
			"pursuit":
				for path_cell in intent.affected_cells:
					canvas.draw_rect(P.cell_rect(path_cell).grow(-10.0), P.TELEGRAPH_PURSUIT_FILL, true)
					canvas.draw_rect(P.cell_rect(path_cell).grow(-10.0), P.TELEGRAPH_PURSUIT_LINE, false, 2.0)
			"wait":
				var wait_center := P.cell_center(controller.get_actor(intent.source_actor_id).cell)
				canvas.draw_arc(wait_center, 27.0, 0.0, TAU, 48, P.RING_WAIT, 2.0)


## Whether the selected skill may legally target this enemy right now.
##
## The single source of truth for both the highlight and the cast: hunter_summon
## needs a free cell beside the target as well as a ready cooldown, so a ring
## derived from distance alone used to promise a cast the controller refused.
static func can_target(controller, skill_bar: Array, skill_id: String, actor_id: String) -> bool:
	var player = controller.get_actor("sevrin")
	if player == null:
		return false
	var actor = controller.get_actor(actor_id)
	if actor == null or actor.team != "enemy" or not actor.is_alive():
		return false

	# Ranges come from the skill bar, which is built from the V2 catalog: the
	# hint and the cast read the same numbers instead of repeating them.
	var skill: Dictionary = {}
	for entry in skill_bar:
		if str(entry["id"]) == skill_id:
			skill = entry
			break
	if skill.is_empty():
		return false

	var distance: int = absi(actor.cell.x - player.cell.x) + absi(actor.cell.y - player.cell.y)
	if distance < int(skill["min_range"]) or distance > int(skill["max_range"]):
		return false
	if skill_id == "oathkeeper_judgment_mark":
		return GridRulesScript.has_clear_line_of_sight(player.cell, actor.cell, controller.blocked_cells, controller.get_occupied_cells())
	if skill_id.begins_with("summon:"):
		return SummonServiceScript.can_summon(controller, StringName(skill_id.substr(7)), actor_id)
	return false


static func _draw_target_hints(canvas: CanvasItem, controller, selected_skill: int, skill_bar: Array) -> void:
	if controller.phase != controller.BattlePhase.PLAYER:
		return
	if selected_skill < 0 or selected_skill >= skill_bar.size():
		return
	var skill: Dictionary = skill_bar[selected_skill]
	if skill["mode"] != "actor":
		return
	for actor_id in controller.actors:
		if not can_target(controller, skill_bar, str(skill["id"]), str(actor_id)):
			continue
		canvas.draw_arc(P.cell_center(controller.actors[actor_id].cell), 31.0, 0.0, TAU, 48, P.RING_TARGET, 2.0)
