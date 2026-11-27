extends "res://tests/framework/test_case.gd"

## Design plan §10.2 and §10.6: the damage type is a closed set.
##
## An unrecognised type used to resolve with zero resistance, so a typo bypassed
## every defensive stat and still reported a normal hit. These cases pin the
## closed set, the stat each type is resisted by, the true-damage semantics
## settled in §47 待决 3 (option C), and the §47 待决 4 critical hook.
##
## The rejection cases deliberately emit an engine error; that is the intended
## behaviour for a programming mistake, and the harness reads results rather than
## stderr.

const ActorScript = preload("res://scripts/actors/battle_actor.gd")


func _run() -> void:
	_test_valid_types_are_closed()
	_test_physical_reads_defense()
	_test_magical_reads_magic_resistance()
	_test_unknown_types_are_rejected()
	_test_true_damage_ignores_mitigation_but_not_shield()
	_test_critical_is_a_hook_not_a_rule()
	_test_resistance_percent_matches_the_pipeline()
	_report()


func _make_actor() -> BattleActor:
	return ActorScript.new("probe", "enemy", Vector2i(1, 1), 10000, "vanguard", 1000, 700, 300)


func _test_valid_types_are_closed() -> void:
	_check(DamageTypes.is_valid("physical"), "physical is a valid damage type")
	_check(DamageTypes.is_valid("magical"), "magical is a valid damage type")
	# §47 待决 2/3 settled 2026-11-26: true damage joined the set under option C.
	_check(DamageTypes.is_valid("true"), "true damage is part of the closed set")
	_check(not DamageTypes.is_valid("none"), "the skill spec's damage-none sentinel is not a damage type")


func _test_physical_reads_defense() -> void:
	var actor := _make_actor()
	# 1000 raw against 700 defense: floor(1000 * 1000 / 1700) = 588
	var result: Dictionary = actor.apply_damage_with_result(1000, "physical")
	_check(result["hit"], "a physical hit lands")
	_check(result["health_damage"] == 588, "physical damage is resisted by defense")


func _test_magical_reads_magic_resistance() -> void:
	var actor := _make_actor()
	# 1000 raw against 300 magic resistance: floor(1000 * 1000 / 1300) = 769
	var result: Dictionary = actor.apply_damage_with_result(1000, "magical")
	_check(result["hit"], "a magical hit lands")
	_check(result["health_damage"] == 769, "magical damage is resisted by magic resistance, not defense")


func _test_unknown_types_are_rejected() -> void:
	var actor := _make_actor()
	var health_before: int = actor.health

	var typo: Dictionary = actor.apply_damage_with_result(1000, "phyiscal")
	_check(not typo["hit"], "a misspelled type is not a hit")
	_check(typo["health_damage"] == 0, "a misspelled type deals no damage")
	_check(actor.health == health_before, "a misspelled type leaves health untouched")

	var empty: Dictionary = actor.apply_damage_with_result(1000, "")
	_check(not empty["hit"] and actor.health == health_before, "an empty type is rejected without damage")


## §47 待决 3 option C: true damage skips defence values and every percentage
## reduction, but a shield still eats it first - the shield is a resource, not a
## defensive stat, and §11 promises it takes the hit before HP.
func _test_true_damage_ignores_mitigation_but_not_shield() -> void:
	var bare := _make_actor()
	var plain: Dictionary = bare.apply_damage_with_result(1000, "true")
	_check(plain["hit"] and plain["health_damage"] == 1000, "true damage ignores the 700 defense")

	# Both reduction layers are skipped even though they would halve physical.
	var reduced := _make_actor()
	var through_reductions: Dictionary = reduced.apply_damage_with_result(1000, "true", 50, [50] as Array[int])
	_check(through_reductions["health_damage"] == 1000, "true damage ignores percentage reductions")

	var shielded := _make_actor()
	shielded.grant_shield(400)
	var against_shield: Dictionary = shielded.apply_damage_with_result(1000, "true")
	_check(against_shield["absorbed"] == 400, "a shield still absorbs true damage")
	_check(against_shield["health_damage"] == 600, "only the shield's remainder reaches health")

	# Physical against the same shield must still be resisted first.
	var control := _make_actor()
	control.grant_shield(400)
	var physical: Dictionary = control.apply_damage_with_result(1000, "physical")
	_check(physical["absorbed"] == 400 and physical["health_damage"] == 188, "physical is still resisted before the shield")


## §47 待决 4 option A: the pipeline has the hook, no skill in 0.1 pulls it.
func _test_critical_is_a_hook_not_a_rule() -> void:
	var plain := _make_actor()
	var normal: Dictionary = plain.apply_damage_with_result(1000, "physical")
	_check(not normal["was_critical"], "a normal hit is not critical")
	_check(normal["health_damage"] == 588, "the default multiplier leaves damage unchanged")

	var crit := _make_actor()
	# 2000 raw against 700 defense: floor(2000 * 1000 / 1700) = 1176
	var landed: Dictionary = crit.apply_damage_with_result(1000, "physical", 0, [] as Array[int], 2.0)
	_check(landed["was_critical"], "a multiplier above 1 is reported as critical")
	_check(landed["health_damage"] == 1176, "the critical multiplier scales raw damage before mitigation")


## §47 待决 1 option B: points stay the settlement unit, the display layer shows
## a percentage. 111 points must read as the 10% the plan gives Sakura.
func _test_resistance_percent_matches_the_pipeline() -> void:
	_check(CombatMath.resistance_percent(0) == 0.0, "zero resistance reads as 0%")
	_check(absf(CombatMath.resistance_percent(1000) - 50.0) < 0.001, "1000 points reads as 50%")
	_check(absf(CombatMath.resistance_percent(111) - 9.99) < 0.01, "Sakura's 111 points reads as 10%")
