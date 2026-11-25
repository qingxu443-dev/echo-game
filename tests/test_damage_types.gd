extends "res://tests/framework/test_case.gd"

## Design plan §10.2 and §10.6: the damage type is a closed set.
##
## An unrecognised type used to resolve with zero resistance, so a typo bypassed
## every defensive stat and still reported a normal hit. These cases pin the
## closed set, the stat each type is resisted by, and the rejection path.
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
	_report()


func _make_actor() -> BattleActor:
	return ActorScript.new("probe", "enemy", Vector2i(1, 1), 10000, "vanguard", 1000, 700, 300)


func _test_valid_types_are_closed() -> void:
	_check(DamageTypes.is_valid("physical"), "physical is a valid damage type")
	_check(DamageTypes.is_valid("magical"), "magical is a valid damage type")
	_check(not DamageTypes.is_valid("none"), "the skill spec's damage-none sentinel is not a damage type")
	_check(not DamageTypes.is_valid("true"), "true damage stays undefined until the plan settles it")


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

	var true_damage: Dictionary = actor.apply_damage_with_result(1000, "true")
	_check(not true_damage["hit"] and actor.health == health_before, "true damage is rejected while undecided")
