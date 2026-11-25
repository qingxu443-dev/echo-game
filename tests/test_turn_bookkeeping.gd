extends "res://tests/framework/test_case.gd"

## Covers the turn bookkeeping primitives that the battle logic depends on but
## no existing suite exercises directly: the AP ledger, the intent state
## machine, clearing area effects, and the occupied-cell query.

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const APBudgetScript = preload("res://scripts/battle/ap_budget.gd")
const IntentScript = preload("res://scripts/battle/battle_intent.gd")


func _run() -> void:
	_check_ap_ledger()
	_check_intent_state_machine()
	_check_occupied_cells()

	_report()


func _check_ap_ledger() -> void:
	var ap: APBudget = APBudgetScript.new(3)
	_check(ap.current == 3 and ap.maximum == 3, "AP ledger starts full")
	_check(ap.can_spend(0), "a zero-cost action is affordable")
	_check(not ap.can_spend(-1), "a negative cost is rejected")
	_check(ap.can_spend(3), "the whole budget is affordable while untouched")
	_check(not ap.can_spend(4), "one point beyond the budget is rejected")

	_check(not ap.spend(4), "spending beyond the budget fails")
	_check(ap.current == 3, "a failed spend leaves the ledger untouched")
	_check(ap.spend(2) and ap.current == 1, "a partial spend records the remainder")
	_check(not ap.can_spend(2), "the spent portion is no longer available")
	_check(ap.can_spend(1), "the remaining point stays available")

	ap.clear()
	_check(ap.current == 0, "clear empties the ledger")
	_check(not ap.can_spend(1), "an empty ledger rejects any positive cost")
	_check(ap.can_spend(0), "an empty ledger still allows a zero-cost action")
	ap.reset()
	_check(ap.current == 3, "reset restores the maximum")

	ap.spend(1)
	_check(ap.refund(1) and ap.current == 3, "a refund restores a committed spend")
	_check(not ap.refund(1) and ap.current == 3, "a refund beyond the maximum keeps the ledger untouched")
	_check(not ap.refund(-1) and ap.current == 3, "a negative refund is rejected")

	var clamped: APBudget = APBudgetScript.new(-2)
	_check(clamped.maximum == 0 and clamped.current == 0, "a negative maximum is clamped to zero")


func _check_intent_state_machine() -> void:
	var intent = IntentScript.new(
		"intent_cancel",
		"vanguard_00",
		"charged_strike",
		IntentScript.TargetMode.TILE_LOCKED,
		"",
		Vector2i(1, 1),
		[Vector2i(1, 1)] as Array[Vector2i],
		500,
		0
	)
	_check(intent.state == IntentScript.IntentState.ACTIVE, "a new intent starts active")
	_check(intent.cancel_reason == "", "an active intent carries no cancel reason")
	_check(intent.cancel("player_left_marked_cell"), "an active intent can be canceled")
	_check(intent.state == IntentScript.IntentState.CANCELED, "a canceled intent reports the canceled state")
	_check(intent.cancel_reason == "player_left_marked_cell", "the cancel reason is recorded")
	_check(not intent.cancel("second_reason"), "a canceled intent cannot be canceled twice")
	_check(intent.cancel_reason == "player_left_marked_cell", "the first cancel reason is preserved")
	_check(not intent.mark_resolved(), "a canceled intent cannot be marked resolved")
	_check(intent.state == IntentScript.IntentState.CANCELED, "a rejected resolve does not change the state")

	var resolved = IntentScript.new(
		"intent_resolve",
		"vanguard_00",
		"pursuit",
		IntentScript.TargetMode.ACTOR_LOCKED,
		"sevrin"
	)
	_check(resolved.mark_resolved(), "an active intent can be marked resolved")
	_check(resolved.state == IntentScript.IntentState.RESOLVED, "a resolved intent reports the resolved state")
	_check(resolved.cancel_reason == "", "a resolved intent carries no cancel reason")
	_check(not resolved.mark_resolved(), "an intent cannot be resolved twice")
	_check(not resolved.cancel("late_cancel"), "a resolved intent cannot be canceled")
	_check(resolved.state == IntentScript.IntentState.RESOLVED, "a rejected cancel does not change the state")



func _check_occupied_cells() -> void:
	var battle = ControllerScript.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 1), [Vector2i(5, 5), Vector2i(6, 6)]), "occupied-cell encounter starts")

	var occupied: Dictionary = battle.get_occupied_cells()
	_check(occupied.size() == 3, "every living actor occupies its cell")
	_check(occupied.get(Vector2i(1, 1)) == "sevrin", "the player cell maps to the player")
	_check(occupied.get(Vector2i(5, 5)) == "vanguard_00", "an enemy cell maps to that enemy")
	_check(not occupied.has(Vector2i(0, 0)), "an empty cell is not reported as occupied")

	var without_player: Dictionary = battle.get_occupied_cells("sevrin")
	_check(without_player.size() == 2, "excluding one actor removes exactly one entry")
	_check(not without_player.has(Vector2i(1, 1)), "the excluded actor does not hold its cell")
	_check(without_player.has(Vector2i(5, 5)), "other actors keep their cells when one is excluded")

	battle.get_actor("vanguard_00").health = 0
	var after_defeat: Dictionary = battle.get_occupied_cells()
	_check(after_defeat.size() == 2, "a defeated actor stops occupying its cell")
	_check(not after_defeat.has(Vector2i(5, 5)), "the defeated actor cell becomes free")
	_check(after_defeat.has(Vector2i(6, 6)), "surviving actors keep their cells")

	battle.queue_free()
