extends "res://tests/framework/test_case.gd"

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")


func _run() -> void:
	_test_line_of_sight_geometry()
	_test_diagonal_judgment_mark()
	_test_diagonal_mark_blocked()
	_test_non_aligned_targets_still_fail()
	_test_marksman_lane_stays_orthogonal()

	_report()


func _test_line_of_sight_geometry() -> void:
	var empty: Dictionary = {}
	_check(GridRulesScript.has_clear_line_of_sight(Vector2i(1, 1), Vector2i(3, 1), empty, empty), "same row is a clear line")
	_check(GridRulesScript.has_clear_line_of_sight(Vector2i(1, 1), Vector2i(1, 3), empty, empty), "same column is a clear line")
	_check(GridRulesScript.has_clear_line_of_sight(Vector2i(1, 1), Vector2i(3, 3), empty, empty), "exact diagonal is a clear line")
	_check(GridRulesScript.has_clear_line_of_sight(Vector2i(3, 3), Vector2i(1, 1), empty, empty), "diagonal works in the other direction")
	_check(not GridRulesScript.has_clear_line_of_sight(Vector2i(1, 1), Vector2i(2, 3), empty, empty), "offset that is neither row, column nor diagonal fails")
	_check(not GridRulesScript.has_clear_line_of_sight(Vector2i(1, 1), Vector2i(1, 1), empty, empty), "same cell is not a line")

	var diagonal_blocker: Dictionary = {Vector2i(2, 2): true}
	_check(not GridRulesScript.has_clear_line_of_sight(Vector2i(1, 1), Vector2i(3, 3), diagonal_blocker, empty), "obstacle on the diagonal blocks sight")
	_check(not GridRulesScript.has_clear_line_of_sight(Vector2i(1, 1), Vector2i(3, 3), empty, diagonal_blocker), "occupied diagonal cell blocks sight")

	var blocked_target: Dictionary = {Vector2i(3, 3): true}
	_check(not GridRulesScript.has_clear_line_of_sight(Vector2i(1, 1), Vector2i(3, 3), blocked_target, empty), "blocked target cell fails")

	# The orthogonal helper is unchanged and still rejects diagonals for enemy lanes.
	_check(not GridRulesScript.has_clear_orthogonal_line(Vector2i(1, 1), Vector2i(3, 3), empty, empty), "orthogonal helper still rejects a diagonal")


func _test_diagonal_judgment_mark() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 3), [Vector2i(2, 4)])
	_check(battle.request_oathkeeper_judgment_mark("vanguard_00"), "Judgment Mark reaches a diagonally adjacent target")
	_check(battle.ap.current == battle.ap.maximum - 1, "diagonal Judgment Mark spends one AP")
	_check(battle.statuses.has_status("vanguard_00", &"oathkeeper_mark"), "diagonal Judgment Mark applies the mark")
	battle.queue_free()

	var far = ControllerScript.new()
	root.add_child(far)
	far.start_encounter(Vector2i(1, 3), [Vector2i(3, 5)])
	_check(far.request_oathkeeper_judgment_mark("vanguard_00"), "Judgment Mark reaches a diagonal at the edge of its range")
	far.queue_free()


func _test_diagonal_mark_blocked() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 3), [Vector2i(3, 5)], [Vector2i(2, 4)])
	_check(not battle.request_oathkeeper_judgment_mark("vanguard_00"), "Judgment Mark fails when the diagonal is blocked")
	_check(battle.ap.current == battle.ap.maximum, "blocked diagonal Judgment Mark spends no AP")
	battle.queue_free()



func _test_non_aligned_targets_still_fail() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	# Offset (3, 2): within four cells by Manhattan distance but on no straight line.
	battle.start_encounter(Vector2i(1, 3), [Vector2i(4, 5)])
	_check(GridRulesScript.manhattan_distance(Vector2i(1, 3), Vector2i(4, 5)) == 5, "control target is out of range by distance")
	battle.queue_free()

	var aligned = ControllerScript.new()
	root.add_child(aligned)
	aligned.start_encounter(Vector2i(1, 3), [Vector2i(3, 4)])
	_check(not aligned.request_oathkeeper_judgment_mark("vanguard_00"), "a knight-offset target still fails even at close range")
	aligned.queue_free()


func _test_marksman_lane_stays_orthogonal() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	var archetypes: Array[String] = ["marksman"]
	# Diagonal at Manhattan distance six: in range, but off the orthogonal lane.
	battle.start_encounter(Vector2i(1, 3), [Vector2i(4, 6)], [], archetypes)
	_check(battle.intents.size() == 1, "marksman still produces an intent")
	_check(battle.intents[0].action_id == "wait", "marksman does not fire along a diagonal")
	battle.queue_free()
