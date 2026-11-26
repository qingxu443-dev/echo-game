extends "res://tests/framework/test_case.gd"

const ActorScript = preload("res://scripts/actors/battle_actor.gd")


func _run() -> void:
	_test_shield_cap_and_reapplication()
	_test_shield_absorption_and_overflow()
	_test_legacy_damage_return_value()
	_test_ultimate_energy_limits()
	_report()


func _test_shield_cap_and_reapplication() -> void:
	var actor = ActorScript.new("ally", "player", Vector2i.ZERO, 1000)
	_check(actor.grant_shield(500) == 300, "shield is capped at 30 percent of max health")
	_check(actor.grant_shield(80) == 300, "reapplying a weaker shield preserves the stronger remaining shield")
	actor.shield = 40
	_check(actor.grant_shield(100) == 100, "reapplying a stronger shield replaces the lower remaining shield")
	_check(actor.grant_shield(-10) == 100, "negative shield values cannot reduce an existing shield")


func _test_shield_absorption_and_overflow() -> void:
	var actor = ActorScript.new("ally", "player", Vector2i.ZERO, 1000)
	actor.grant_shield(100)
	var fully_absorbed: Dictionary = actor.apply_damage_with_result(60)
	_check(bool(fully_absorbed.get("hit", false)), "a positive damage instance counts as a hit")
	_check(int(fully_absorbed.get("absorbed", 0)) == 60, "shield absorbs incoming damage first")
	_check(int(fully_absorbed.get("health_damage", 0)) == 0, "fully absorbed damage does not reduce health")
	_check(actor.health == 1000 and actor.shield == 40, "full absorption preserves health and reduces shield")

	var overflow: Dictionary = actor.apply_damage_with_result(100)
	_check(int(overflow.get("absorbed", 0)) == 40, "remaining shield absorbs the first part of overflow damage")
	_check(int(overflow.get("health_damage", 0)) == 60, "damage beyond the shield reduces health")
	_check(actor.health == 940 and actor.shield == 0, "shield is depleted before health is reduced")


func _test_legacy_damage_return_value() -> void:
	var actor = ActorScript.new("legacy", "player", Vector2i.ZERO, 1000)
	actor.grant_shield(75)
	var applied: int = actor.apply_damage(100)
	_check(applied == 25, "legacy apply_damage still returns health damage only")
	_check(actor.health == 975 and actor.shield == 0, "legacy damage API also respects shield absorption")
	var invalid: Dictionary = actor.apply_damage_with_result(0)
	_check(not bool(invalid.get("hit", true)), "zero damage is not reported as a hit")


func _test_ultimate_energy_limits() -> void:
	var actor = ActorScript.new("energy", "player", Vector2i.ZERO, 1000)
	_check(actor.gain_ultimate_energy(1) == 1, "ultimate energy increases")
	_check(actor.gain_ultimate_energy(10) == 5, "ultimate energy is capped at five")
	_check(actor.spend_ultimate_energy(5), "ultimate energy can be spent")
	_check(actor.ultimate_energy == 0, "spending ultimate energy reduces the pool")
	_check(not actor.spend_ultimate_energy(1), "cannot spend unavailable ultimate energy")

