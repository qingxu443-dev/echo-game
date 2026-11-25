class_name BattleActor
extends RefCounted

const CombatMathScript = preload("res://scripts/battle/combat_math.gd")

## Runtime combatant stats and damage resolution.

var actor_id: String
var team: String
var archetype: String = "vanguard"
var cell: Vector2i
var max_health: int
var health: int
var attack: int
var defense: int
var magic_resistance: int
var is_defeated: bool = false
## Design plan §12: a party member at zero health is downed, not gone. A downed
## unit cannot act and cannot be targeted, but it keeps its cell, so it still
## blocks movement until revived. Enemies have no downed state - they simply die.
var is_downed: bool = false
var shield: int = 0
## Independent ultimate-energy pool; capped at five for each actor.
var ultimate_energy: int = 0
## Prevents more than one successful-action energy gain per player turn.
var active_energy_gain_turn: int = -1


func _init(
	p_actor_id: String,
	p_team: String,
	p_cell: Vector2i,
	p_max_health: int,
	p_archetype: String = "vanguard",
	p_attack: int = 1000,
	p_defense: int = 0,
	p_magic_resistance: int = 0
) -> void:
	actor_id = p_actor_id
	team = p_team
	archetype = p_archetype
	cell = p_cell
	max_health = maxi(1, p_max_health)
	health = max_health
	attack = maxi(0, p_attack)
	defense = maxi(0, p_defense)
	magic_resistance = maxi(0, p_magic_resistance)


func gain_ultimate_energy(amount: int = 1) -> int:
	ultimate_energy = clampi(ultimate_energy + maxi(0, amount), 0, 5)
	return ultimate_energy


func spend_ultimate_energy(amount: int) -> bool:
	if amount < 0 or ultimate_energy < amount:
		return false
	ultimate_energy -= amount
	return true


func grant_shield(requested_amount: int) -> int:
	## Reapplication never lowers a stronger remaining shield; each actor has
	## an independent cap of 15% max health.
	var shield_cap: int = floori(float(max_health) * 0.15)
	var new_shield: int = clampi(requested_amount, 0, shield_cap)
	shield = maxi(shield, new_shield)
	return shield


func apply_damage(
	raw_damage: int,
	damage_type: String = "physical",
	final_reduction_percent: int = 0,
	resistance_penalty: int = 0,
	additional_reduction_percents: Array[int] = []
) -> int:
	## Compatibility API: legacy callers still receive health damage only.
	var result: Dictionary = apply_damage_with_result(
		raw_damage,
		damage_type,
		final_reduction_percent,
		resistance_penalty,
		additional_reduction_percents
	)
	return int(result.get("health_damage", 0))


func apply_damage_with_result(
	raw_damage: int,
	damage_type: String = "physical",
	final_reduction_percent: int = 0,
	resistance_penalty: int = 0,
	additional_reduction_percents: Array[int] = []
) -> Dictionary:
	## Detailed result for new combat systems. "hit" means a valid positive
	## damage instance reached this living actor, even if shield absorbs all of it.
	if is_defeated or raw_damage <= 0:
		return {"hit": false, "absorbed": 0, "health_damage": 0, "final_damage": 0}
	# §10.6: an unknown type used to fall through to zero resistance, which let a
	# typo hit at full strength. Reject it instead of resolving it.
	if not DamageTypes.is_valid(damage_type):
		push_error("BattleActor: unknown damage type '%s' (expected %s)" % [damage_type, DamageTypes.describe()])
		return {"hit": false, "invalid_type": true, "absorbed": 0, "health_damage": 0, "final_damage": 0}
	var base_resistance: int = DamageTypes.resistance_for(self, damage_type)
	var resistance: int = maxi(0, base_resistance - maxi(0, resistance_penalty))
	var mitigated: int = CombatMathScript.calculate_damage(raw_damage, resistance)
	var final_damage: int = mitigated
	# Contextual reductions (for example, area protection) resolve after resistance.
	for reduction_percent in additional_reduction_percents:
		var reduction: int = clampi(reduction_percent, 0, 100)
		if reduction > 0 and final_damage > 0:
			final_damage = maxi(1, floori(float(final_damage) * float(100 - reduction) / 100.0))
	# Personal defensive states resolve last, preserving their existing precedence.
	var personal_reduction: int = clampi(final_reduction_percent, 0, 100)
	if personal_reduction > 0 and final_damage > 0:
		final_damage = maxi(1, floori(float(final_damage) * float(100 - personal_reduction) / 100.0))
	var absorbed: int = mini(shield, final_damage)
	shield -= absorbed
	var health_damage: int = mini(final_damage - absorbed, health)
	health -= health_damage
	if health <= 0:
		health = 0
		is_defeated = true
		if team == "player":
			is_downed = true
	return {
		"hit": true,
		"absorbed": absorbed,
		"health_damage": health_damage,
		"final_damage": final_damage
	}

func is_alive() -> bool:
	return not is_defeated and health > 0


## Whether this unit still occupies its cell. A downed body does: §12 says the
## cell stays blocked until the unit is revived and moved.
func blocks_cell() -> bool:
	return is_alive() or is_downed


## Bring a downed unit back at the given health. Reviving a unit that is not
## downed is a no-op, so a skill cannot top up a standing ally by accident.
func revive(restored_health: int) -> bool:
	if not is_downed:
		return false
	health = clampi(restored_health, 1, max_health)
	is_defeated = false
	is_downed = false
	return true

