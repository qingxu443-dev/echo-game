extends "res://tests/framework/test_case.gd"

## 春之境 exploration rules (设计汇总 2026-11-26 §8.2, §8.3).
##
## Scenario cells are looked up from the template instead of hard-coded, so
## replacing LAYOUT_ORDER with the author's real layout does not break these
## assertions. Only the rules are pinned: cost equals manhattan distance, a move
## is atomic, an exact-empty arrival keeps its interaction window, and ending the
## run discards the remaining bar.

const FactoryScript = preload("res://scripts/spring/spring_map_factory.gd")


func _run() -> void:
	_test_initial_state()
	_test_cost_is_manhattan()
	_test_move_spends_the_distance()
	_test_same_cell_is_not_a_move()
	_test_off_board_is_refused()
	_test_insufficient_stamina_keeps_state()
	_test_exact_empty_at_a_place_keeps_the_window()
	_test_exact_empty_on_empty_cell_ends_at_once()
	_test_completed_place_cannot_be_used_again()
	_test_shop_stays_usable()
	_test_restore_never_exceeds_the_cap()
	_test_player_can_end_with_stamina_left()
	_test_path_lists_every_step()
	_test_moving_is_refused_after_the_window_closes()
	_test_hard_mode_route_planning_and_forced_execution()


func _fresh() -> ExplorationState:
	return ExplorationState.create(FactoryScript.build(1))


func _test_initial_state() -> void:
	var state := _fresh()
	_check(state.stamina == 10, "a run starts with ten stamina")
	_check(state.stamina == ExplorationState.STAMINA_MAX, "ten is the fixed cap")
	_check(state.position == state.template.start_cell, "the team starts on the start cell")
	_check(not state.finished, "a new run is not finished")
	_check(state.completed.is_empty(), "nothing is completed at the start")


func _test_cost_is_manhattan() -> void:
	var state := _fresh()
	var place = state.template.places_of(SpringPlace.Kind.BATTLE)[0]
	var expected: int = SpringMapTemplate.manhattan(state.position, place.cell)
	_check(state.cost_to(place.cell) == expected, "cost is the manhattan distance", "expected %d" % expected)
	_check(state.cost_to(state.position) == 0, "standing on a cell costs nothing")


func _test_move_spends_the_distance() -> void:
	var state := _fresh()
	var place = state.template.places_of(SpringPlace.Kind.BATTLE)[0]
	var cost: int = state.cost_to(place.cell)
	_check(state.move_to(place.cell), "a reachable place is entered")
	_check(state.stamina == 10 - cost, "the whole distance is spent at once", "stamina %d" % state.stamina)
	_check(state.position == place.cell, "the team stands on the place")


func _test_same_cell_is_not_a_move() -> void:
	var state := _fresh()
	_check(not state.move_to(state.position), "moving to the current cell is not a move")
	_check(state.stamina == 10, "a refused same-cell move spends nothing")


func _test_off_board_is_refused() -> void:
	var state := _fresh()
	_check(not state.move_to(Vector2i(0, 1)), "column zero is off the board")
	_check(not state.move_to(Vector2i(1, 6)), "row six is off the board")
	_check(state.stamina == 10, "an off-board move spends nothing")


func _test_insufficient_stamina_keeps_state() -> void:
	var state := _fresh()
	var place = state.template.places_of(SpringPlace.Kind.BATTLE)[0]
	state.stamina = 1
	var position_before := state.position
	_check(not state.move_to(place.cell), "a place beyond the bar is refused")
	_check(state.stamina == 1, "a refused move does not partially spend the bar")
	_check(state.position == position_before, "a refused move leaves the team where it stood")


func _test_exact_empty_at_a_place_keeps_the_window() -> void:
	var state := _fresh()
	var place = state.template.places_of(SpringPlace.Kind.BATTLE)[0]
	state.stamina = state.cost_to(place.cell)
	_check(state.move_to(place.cell), "the place is reached on the last point of stamina")
	_check(state.stamina == 0, "the bar is empty")
	_check(state.awaiting_finish, "an exact-empty arrival waits instead of ending")
	_check(not state.finished, "the run is not over while the window is open")
	_check(state.can_interact(), "the reached place can still be used")
	state.mark_completed(place.id)
	_check(state.finished, "closing the window ends the run")
	_check(state.finish_reason == "exhausted", "the run ended because the bar emptied")


func _test_exact_empty_on_empty_cell_ends_at_once() -> void:
	var state := _fresh()
	var free_cells := state.template.free_cells()
	var target := free_cells[0]
	state.stamina = state.cost_to(target)
	_check(state.move_to(target), "an empty cell is reachable")
	_check(state.finished, "an empty cell offers no window, so the run ends")
	_check(state.finish_reason == "exhausted", "the empty-cell ending is exhaustion")


func _test_completed_place_cannot_be_used_again() -> void:
	var state := _fresh()
	var place = state.template.places_of(SpringPlace.Kind.EVENT)[0]
	state.stamina = 10
	state.move_to(place.cell)
	_check(state.can_interact(), "a fresh one-shot place can be used")
	state.mark_completed(place.id)
	_check(not state.can_interact(), "a finished one-shot place cannot be used again")
	_check(state.completed.has(place.id), "the completion is recorded")


func _test_shop_stays_usable() -> void:
	var state := _fresh()
	var shop = state.template.places_of(SpringPlace.Kind.SHOP)[0]
	state.move_to(shop.cell)
	state.mark_completed(shop.id)
	_check(state.can_interact(), "a shop can be entered again after being used")
	_check(not shop.one_shot, "the shop is the only place marked repeatable")


func _test_restore_never_exceeds_the_cap() -> void:
	var state := _fresh()
	state.stamina = 3
	state.restore(4)
	_check(state.stamina == 7, "restoring adds what was asked")
	state.restore(20)
	_check(state.stamina == 10, "restoring cannot pass the cap")
	_check(state.restore(0) == 10, "a zero restore changes nothing")


func _test_player_can_end_with_stamina_left() -> void:
	var state := _fresh()
	state.stamina = 6
	_check(state.end_exploration(), "ending exploration by choice succeeds")
	_check(state.finished, "the run is finished")
	_check(state.stamina == 0, "the remaining bar is discarded, never carried forward")
	_check(not state.end_exploration(), "an already finished run cannot be ended twice")


func _test_path_lists_every_step() -> void:
	var state := _fresh()
	var target := state.template.boss_cell
	var path := state.path_to(target)
	_check(path.size() == SpringMapTemplate.manhattan(state.position, target), "the path has one entry per cell walked")
	var cursor := state.position
	var all_adjacent: bool = true
	for cell in path:
		if SpringMapTemplate.manhattan(cursor, cell) != 1:
			all_adjacent = false
		cursor = cell
	_check(all_adjacent, "every step of the path is one cell long")
	_check(cursor == target, "the path ends on the target cell")
	_check(not path.has(state.position), "the path does not repeat the cell the team stands on")


func _test_moving_is_refused_after_the_window_closes() -> void:
	var state := _fresh()
	var place = state.template.places_of(SpringPlace.Kind.BATTLE)[0]
	state.stamina = state.cost_to(place.cell)
	state.move_to(place.cell)
	state.mark_completed(place.id)
	_check(not state.move_to(Vector2i(2, 2)), "a finished run refuses further movement")


func _test_hard_mode_route_planning_and_forced_execution() -> void:
	var run := SpringRun.begin(2, true)
	var plan: SpringRoutePlan = run.route_plan
	_check(plan != null and plan.hard_mode and plan.is_planning(), "hard mode starts in route-planning phase")
	_check(not plan.can_lock(run.template, run.exploration.stamina), "an empty route cannot be locked")
	_check(not plan.is_allowed_destination(run.template.boss_cell), "free movement is blocked before the route is locked")

	# Adding start cell is refused.
	var start_res: Dictionary = plan.toggle_waypoint(run.template.start_cell, run.template, run.exploration.stamina)
	_check(not bool(start_res["ok"]), "the fixed start cell cannot be added as a waypoint")

	# Pick a mid-route cell between start and boss so start -> mid -> boss fits in 10 stamina.
	var mid_cell := Vector2i(-1, -1)
	for place in run.template.places:
		if place.cell == run.template.start_cell or place.cell == run.template.boss_cell:
			continue
		var d: int = SpringRoutePlan.manhattan(run.template.start_cell, place.cell) + SpringRoutePlan.manhattan(place.cell, run.template.boss_cell)
		if d <= run.exploration.stamina:
			mid_cell = place.cell
			break
	_check(mid_cell != Vector2i(-1, -1), "template has an intermediate stop on the way to the boss within stamina")

	var push_mid: Dictionary = plan.toggle_waypoint(mid_cell, run.template, run.exploration.stamina)
	_check(bool(push_mid["ok"]) and plan.waypoints.size() == 1, "an intermediate waypoint is added")
	_check(not plan.can_lock(run.template, run.exploration.stamina), "a route that does not end on the boss cell cannot be locked")
	var bad_lock: Dictionary = plan.lock_plan(run.template, run.exploration.stamina)
	_check(not bool(bad_lock["ok"]), "locking a non-boss tail is rejected")

	# Duplicate waypoint is refused; tapping the tail pops it.
	var pop_mid: Dictionary = plan.toggle_waypoint(mid_cell, run.template, run.exploration.stamina)
	_check(bool(pop_mid["ok"]) and str(pop_mid["action"]) == "pop" and plan.waypoints.is_empty(), "tapping the current tail cell undoes the last step")

	# Rebuild mid -> boss route and verify over-budget refusal & post-boss lock.
	plan.toggle_waypoint(mid_cell, run.template, run.exploration.stamina)
	var push_boss: Dictionary = plan.toggle_waypoint(run.template.boss_cell, run.template, run.exploration.stamina)
	_check(bool(push_boss["ok"]) and plan.ends_at_boss(run.template), "connecting the boss cell completes the tail requirement")
	var after_boss: Dictionary = plan.toggle_waypoint(Vector2i(2, 2), run.template, run.exploration.stamina)
	_check(not bool(after_boss["ok"]), "no further waypoints may be appended after the boss tail")
	_check(plan.can_lock(run.template, run.exploration.stamina), "a valid route ending on the boss can be locked")

	var locked: Dictionary = plan.lock_plan(run.template, run.exploration.stamina)
	_check(bool(locked["ok"]) and plan.is_locked_active(), "locking switches hard mode into forced execution")
	_check(plan.is_allowed_destination(mid_cell), "the first planned waypoint is the only allowed next move")
	_check(not plan.is_allowed_destination(run.template.boss_cell), "skipping ahead to the boss is refused while an earlier stop is pending")

	# Save / load roundtrip preserves hard mode, locked route, and cursor.
	var snapshot: Dictionary = run.to_dict()
	var restored := SpringRun.from_dict(snapshot)
	_check(restored != null and restored.route_plan.hard_mode and restored.route_plan.locked, "save roundtrip preserves hard-mode locked state")
	_check(restored.route_plan.waypoints == plan.waypoints and restored.route_plan.cursor == 0, "save roundtrip preserves waypoints and cursor")

	# Stepping strictly follows mid -> boss.
	_check(run.exploration.move_to(mid_cell), "moving to the first planned stop succeeds")
	plan.advance_cursor()
	_check(plan.next_stop() == run.template.boss_cell, "advancing cursor unlocks the boss as the next stop")
	_check(plan.is_allowed_destination(run.template.boss_cell), "boss stop is now allowed")
	_check(run.exploration.move_to(run.template.boss_cell), "moving to the boss stop succeeds within stamina")
	plan.advance_cursor()
	_check(not plan.has_next_stop(), "cursor reaches end of route after arriving at the boss")

	# Every template guarantees at least a direct route to the boss within 10 stamina.
	for tid in [1, 2, 3]:
		var tmpl := FactoryScript.build(tid)
		var direct := SpringRoutePlan.create(true)
		var res := direct.toggle_waypoint(tmpl.boss_cell, tmpl, ExplorationState.STAMINA_MAX)
		_check(bool(res["ok"]) and direct.can_lock(tmpl, ExplorationState.STAMINA_MAX), "template %d supports a valid boss-tail route within stamina" % tid)
