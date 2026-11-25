extends "res://tests/framework/test_case.gd"

## Design plan §4: five AP per player turn, shared by the whole party.
##
## The distinction that matters is "one pool, many characters" versus "one pool
## per character". With a single character on the field the two look identical,
## so these cases assert the pool's identity and its reset boundaries rather than
## counting actions.

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const ActorScript = preload("res://scripts/actors/battle_actor.gd")


func _run() -> void:
	_test_pool_size_and_identity()
	_test_spending_is_sequential_from_one_pool()
	_test_refresh_and_no_carry_over()
	_test_overspend_is_rejected()
	_report()


func _test_pool_size_and_identity() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)]), "shared AP encounter starts")

	_check(battle.ap.maximum == 5, "the party shares five AP per player turn")
	_check(battle.ap.current == 5, "the pool starts full")

	# A second party member must not bring a second budget with it.
	var pool_before: int = battle.ap.current
	var maximum_before: int = battle.ap.maximum
	battle.actors["ally"] = ActorScript.new("ally", "player", Vector2i(1, 2), 1000, "support", 300, 100, 100)
	_check(battle.ap.current == pool_before, "adding a party member does not add AP")
	_check(battle.ap.maximum == maximum_before, "adding a party member does not raise the pool ceiling")
	battle.queue_free()


func _test_spending_is_sequential_from_one_pool() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)])
	battle.actors["ally"] = ActorScript.new("ally", "player", Vector2i(1, 2), 1000, "support", 300, 100, 100)

	_check(battle.request_oathkeeper_judgment_mark("vanguard_00"), "first action resolves")
	_check(battle.ap.current == 4, "first action draws one point from the shared pool")
	_check(battle.request_oathkeeper_judgment_mark("vanguard_00"), "second action resolves")
	_check(battle.ap.current == 3, "second action draws from the same pool, not a fresh budget")
	_check(battle.ap.current != battle.ap.maximum, "the second party member did not get an untouched pool")
	battle.queue_free()


func _test_refresh_and_no_carry_over() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 1)])
	battle.request_oathkeeper_judgment_mark("vanguard_00")
	battle.request_oathkeeper_judgment_mark("vanguard_00")
	_check(battle.ap.current == 3, "two actions spent two points")
	_check(battle.ap.current < battle.ap.maximum, "unspent points exist before the turn ends")

	_check(battle.end_player_turn(), "the player turn ends")
	_check(battle.ap.current == 5, "the pool is restored to five at the next player turn, not to three plus five")
	battle.queue_free()


func _test_overspend_is_rejected() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(1, 1), [Vector2i(2, 1)])

	var casts := 0
	while battle.request_oathkeeper_judgment_mark("vanguard_00"):
		casts += 1
		if casts > 10:
			break
	_check(casts == 5, "exactly five single-AP actions fit in one turn")
	_check(battle.ap.current == 0, "the pool is empty after five actions")
	_check(not battle.ap.can_spend(1), "an empty pool cannot be overdrawn")
	_check(not battle.ap.spend(1), "spending from an empty pool fails and leaves it at zero")
	_check(battle.ap.current == 0, "a rejected spend does not drive the pool negative")
	battle.queue_free()
