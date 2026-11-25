extends "res://tests/framework/test_case.gd"

const BattleStatusScript = preload("res://scripts/battle/battle_status.gd")
const StatusCollectionScript = preload("res://scripts/battle/battle_status_collection.gd")


func _run() -> void:
	var statuses: BattleStatusCollection = StatusCollectionScript.new()

	_check(statuses.apply_status(&"oathguard", "sevrin", "sevrin", 1, 1, 1, &"enemy_phase_end"), "one-trigger defensive status can be applied")
	_check(statuses.has_status("sevrin", &"oathguard"), "applied status can be queried")
	var guard: BattleStatus = statuses.get_status("sevrin", &"oathguard")
	_check(guard != null and guard.remaining_triggers == 1, "status exposes remaining trigger count")
	_check(statuses.consume_trigger("sevrin", &"oathguard"), "status trigger can be consumed")
	_check(not statuses.has_status("sevrin", &"oathguard"), "status is removed after final trigger")

	_check(statuses.apply_status(&"judgment_mark", "sevrin", "marksman", 1, 1, 1, &"enemy_phase_end"), "judgment mark can be applied to another actor")
	_check(statuses.expire_boundary("marksman", &"enemy_phase_end") == 1, "phase boundary expires matching status")
	_check(not statuses.has_status("marksman", &"judgment_mark"), "expired status is no longer present")

	_check(statuses.apply_status(&"judgment_mark", "sevrin", "vanguard_mark", 1, 1, -1, &"enemy_phase_end"), "deferred judgment mark can be applied")
	_check(statuses.defer_status_boundary(&"judgment_mark", &"enemy_phase_end", &"enemy_phase_end_next") == 1, "unused mark can defer its expiry by one enemy phase")
	var deferred_mark: BattleStatus = statuses.get_status("vanguard_mark", &"judgment_mark")
	_check(deferred_mark != null and deferred_mark.expiry_boundary == &"enemy_phase_end_next", "deferred mark stores its next enemy-phase boundary")
	_check(statuses.expire_all_boundary(&"enemy_phase_end_next") == 1, "deferred mark expires after the following enemy phase")

	_check(statuses.apply_status(&"exposed", "sevrin", "vanguard", 1, 3, -1, &""), "unlimited status can be applied")
	_check(statuses.apply_status(&"exposed", "sevrin", "vanguard", 1, 3, -1, &"", BattleStatusScript.STACK_ADD), "stack policy adds stacks")
	var exposed: BattleStatus = statuses.get_status("vanguard", &"exposed")
	_check(exposed != null and exposed.stacks == 2, "additive stack policy increments stacks")
	_check(statuses.apply_status(&"exposed", "sevrin", "vanguard", 1, 3, 2, &"player_phase_start", BattleStatusScript.STACK_REFRESH), "refresh policy is accepted")
	exposed = statuses.get_status("vanguard", &"exposed")
	_check(exposed != null and exposed.remaining_triggers == 2 and exposed.expiry_boundary == &"player_phase_start", "refresh policy resets trigger count and expiry boundary")
	exposed = statuses.get_status("vanguard", &"exposed")
	_check(exposed != null and exposed.stacks == 2, "refresh policy preserves existing stack count")
	_check(statuses.apply_status(&"exposed", "sevrin", "vanguard", 1, 3, -1, &"", BattleStatusScript.STACK_REPLACE), "replace policy is accepted")
	exposed = statuses.get_status("vanguard", &"exposed")
	_check(exposed != null and exposed.stacks == 1, "replace policy resets stack count")

	# §47 待决 15 option A: the shared default is replace. Seeded to three
	# stacks so a refresh default would keep 3 and be visibly wrong.
	_check(statuses.apply_status(&"exposed", "sevrin", "vanguard", 2, 3, -1, &"", BattleStatusScript.STACK_ADD), "stacks can be seeded for the default-policy check")
	exposed = statuses.get_status("vanguard", &"exposed")
	_check(exposed != null and exposed.stacks == 3, "seeded stacks are in place")
	_check(statuses.apply_status(&"exposed", "sevrin", "vanguard", 1, 3, -1, &""), "stack policy may be omitted")
	exposed = statuses.get_status("vanguard", &"exposed")
	_check(exposed != null and exposed.stacks == 1, "an omitted stack policy behaves as replace")

	_check(not statuses.apply_status(&"", "sevrin", "vanguard"), "empty status ID is rejected")
	_check(not statuses.apply_status(&"invalid", "sevrin", "vanguard", 0), "zero stack application is rejected")
	_check(statuses.remove_status("vanguard", &"exposed"), "status can be removed explicitly")
	_check(statuses.clear_actor("marksman") == 0, "clearing an actor with no statuses is safe")
	_check(statuses.clear_actor("vanguard") == 0, "cleared status collection remains empty")

	_report()

