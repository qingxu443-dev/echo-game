class_name BoardMoveRange
extends RefCounted


## CONTRACT: _test_movement_matches_controller
static func cells(controller) -> Dictionary:
	var result := {}
	var actor = controller.get_active_character()
	if controller.phase != controller.BattlePhase.PLAYER or actor == null or not actor.is_alive(): return result
	var free: bool = controller.run_state != null and controller.run_state.has_mod(&"echo_stride") and controller.ledger.free_move_used_turn != controller.turn_number
	if not free and not controller.ap.can_spend(1): return result
	var occupied: Dictionary = controller.get_occupied_cells(actor.actor_id)
	var limit: int = controller.PLAYER_MOVE_MAX_STEPS
	for dy in range(-limit, limit + 1):
		for dx in range(-limit, limit + 1):
			var goal: Vector2i = actor.cell + Vector2i(dx, dy)
			if absi(dx) + absi(dy) > limit or goal == actor.cell: continue
			if not GridRules.is_inside_bounds(goal, controller.grid_size): continue
			var path := GridRules.find_path(actor.cell, goal, controller.grid_size, controller.blocked_cells, occupied, limit)
			if GridRules.is_path_legal(actor.cell, path, controller.grid_size, controller.blocked_cells, occupied, limit): result[goal] = true
	return result


static func visible_cells(controller, selected_skill: int, state: Dictionary) -> Dictionary:
	if selected_skill >= 0 or str(state.get("move_actor_id", "")) != controller.active_character_id: return {}
	return cells(controller)


static func draw(canvas: CanvasItem, controller, selected_skill: int, state: Dictionary) -> void:
	BoardOverlayRegion.draw(canvas, visible_cells(controller, selected_skill, state), BoardOverlayRegion.MOVE_FILL, BoardOverlayRegion.MOVE_LINE)
