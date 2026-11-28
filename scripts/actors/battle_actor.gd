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
## Fragment-derived combat stats. Every character starts at 0% crit rate and 150% crit damage.
var crit_rate: float = 0.0
var crit_damage: float = 150.0
var healing_efficiency: float = 0.0
## Encounter snapshot; equipment recalculation must not reread the hub loadout.
var fragment_bonuses: Dictionary = {}

var attenuation_k: int = CombatMathScript.ATTENUATION_K
## Defeated / downed state is read through predicate methods, exactly like
## is_alive(): every state query on this class takes parentheses - is_alive(),
## is_defeated(), is_downed(), blocks_cell(). The property/method mix is how
## the downed-tap break hid inside a green suite (#34), so it is gone.
var _is_defeated: bool = false
## Legacy engine §12: a party member at zero health can be downed. Rotation
## scenes retire the role through PartyRotation instead. A downed
## unit cannot act and cannot be targeted, but it keeps its cell, so it still
## blocks movement until revived. Enemies have no downed state - they simply die.
var _is_downed: bool = false
## Rotation reserves keep their data while remaining outside field combat.
var is_benched: bool = false
var shield: int = 0
## Independent ultimate-energy pool. The ceiling comes from the character sheet
## so a character with a bigger pool is data, not a code branch; enemies keep the
## default and never gain any.
var ultimate_energy: int = 0
var ultimate_energy_max: int = 5
## Prevents more than one successful-action energy gain per player turn.
var active_energy_gain_turn: int = -1
## Character sheet this unit was spawned from. Empty for enemies.
var character_id: StringName = &""
## Board token glyph, so the view does not have to know every character.
var glyph: String = ""
## Display name from the character sheet, for the HUD.
var display_name_zh: String = ""
## Role label from the sheet ("守誓者" / "剑舞者"), shown beside the name.
var role_label_zh: String = ""
## Class resource (design plan §19: 剑意). Empty id means the unit has none.
var resource_id: StringName = &""
var resource_name_zh: String = ""
var resource_max: int = 0
var resource_current: int = 0

## Enemy signature-skill charge bar: fills whenever the player spends AP.
var skill_charge: int = 0
var skill_charge_max: int = 3
## Orthogonal cells this unit may cover in one reposition, copied from its
## EnemyDefinition. Kept on the actor because the planner and the resolver read
## it while the board is live, and neither of them holds the data profile.
var move_steps: int = 2
## 0 ordinary, 1 elite, 2 boss; copied from the sheet. Player characters keep 0.
var tier: int = 0
## Shield this unit can grant to a lesser ally (古木壁垒). Zero for everyone
## except the one elite that carries the ward.
var ward_shield: int = 0
## Flat raw damage for this unit's signature skill; 0 means "derive from attack".
var skill_damage: int = 0
## 结界守护 coefficients (§15.2). Both zero except 千枝神将.
var ward_stance_percent: float = 0.0
var ward_stance_node_bonus: float = 0.0
## Overrides the action's default multiplier for this unit's plain attack.
var basic_attack_multiplier: float = 0.0
## 樱华蓄斩: whether this unit's charged strike can be broken by control.
var interruptible_skill: bool = false
## 腐樱诅咒: flat defence this unit strips from its target (0 = no curse).
var curse_defense_down: int = 0
## Turn on which a temporary shield lapses; -1 means "no expiry". The player's
## oath shield uses a table on the battle; an enemy stance is one actor's own
## state, so it rides on the actor.
var shield_expiry_turn: int = -1
## 百花锁命 (§14): the hero this sniper has marked, or empty. The mark survives a
## whole player turn so the shot can be telegraphed, then either lands or breaks
## when the target leaves the archer's reach or sight.
var lock_target_id: String = ""
## 腐樱诅咒 (§14): flat defence removed from this actor, and the turn after which
## it lapses. Expiry is swept at the end of an enemy phase, which is what
## "持续至下一敌方行动阶段结束" describes.
var defense_penalty: int = 0
var defense_penalty_expiry_turn: int = -1
## Weapons/armors stolen from destroyed Relic Chests; dropped onto the ground on death.
var stolen_equipment: Array[Dictionary] = []
## Melee retaliation tolerance (2 consecutive melee hits in one turn -> counter;
## ranged hits never advance it; cleared at end of player turn).
var melee_tolerance: int = 0
var melee_tolerance_max: int = 2
var last_melee_hit_seq: int = -1
## Armor layers & Break state (multi-layer boss armor / break cadence).
var armor_layers: int = 0
var armor_max: int = 0
var armor_chip_hits: int = 0
var last_armor_chip_seq: int = -1
var last_armor_break_seq: int = -1
var armor_broken_until_turn: int = -1
## Boss phase tracker (1 = normal, 2 = enraged at <= 50% HP with escort summon).
var boss_phase: int = 1


## CONTRACT: _test_equipped_modules_apply_to_battle
func fragment_scaled(stat: String, amount: int) -> int:
	return roundi(float(amount) * (1.0 + float(fragment_bonuses.get(stat, 0.0)) / 100.0))


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
	ultimate_energy = clampi(ultimate_energy + maxi(0, amount), 0, ultimate_energy_max)
	return ultimate_energy


func spend_ultimate_energy(amount: int) -> bool:
	if amount < 0 or ultimate_energy < amount:
		return false
	ultimate_energy -= amount
	return true


func grant_shield(requested_amount: int) -> int:
	## Reapplication never lowers a stronger remaining shield; cap at 30% max HP.
	var shield_cap: int = floori(float(max_health) * 0.30)
	var new_shield: int = clampi(requested_amount, 0, shield_cap)
	shield = maxi(shield, new_shield)
	return shield


func apply_damage(
	raw_damage: int,
	damage_type: String = "physical",
	final_reduction_percent: int = 0,
	additional_reduction_percents: Array[int] = []
) -> int:
	## Compatibility API: legacy callers still receive health damage only.
	var result: Dictionary = apply_damage_with_result(
		raw_damage,
		damage_type,
		final_reduction_percent,
		additional_reduction_percents
	)
	return int(result.get("health_damage", 0))


## The mitigation expression, and the only one. The resolver bills with it and
## the telegraph quotes with it, so the number printed on the board and the
## number the hit actually removes cannot drift apart. Pure: no state changes.
##
## Defence debuffs come from ONE place: `defense_penalty` on the actor, read by
## DamageTypes.resistance_for. An earlier `resistance_penalty` parameter carried
## the same cut a second time; passing both subtracted it twice and turned a
## 1562 hit into a 1688 one. It had no callers, so it is gone rather than
## documented as a trap.
func mitigated_damage(
	raw_damage: int,
	damage_type: String = "physical",
	final_reduction_percent: int = 0,
	additional_reduction_percents: Array[int] = [],
	crit_multiplier: float = 1.0
) -> int:
	if _is_defeated or raw_damage <= 0:
		return 0
	if not DamageTypes.is_valid(damage_type):
		return 0
	if crit_multiplier > 1.0:
		raw_damage = maxi(1, roundi(float(raw_damage) * crit_multiplier))
	var final_damage: int = raw_damage
	# §47 待决 3 option C: true damage keeps only the shield step.
	if not DamageTypes.ignores_mitigation(damage_type):
		var resistance: int = DamageTypes.resistance_for(self, damage_type)
		final_damage = CombatMathScript.calculate_damage(raw_damage, resistance, attenuation_k)
		# Contextual reductions (for example, area protection) resolve after resistance.
		for reduction_percent in additional_reduction_percents:
			var reduction: int = clampi(reduction_percent, 0, 100)
			if reduction > 0 and final_damage > 0:
				final_damage = maxi(1, floori(float(final_damage) * float(100 - reduction) / 100.0))
		# Personal defensive states resolve last, preserving their existing precedence.
		var personal_reduction: int = clampi(final_reduction_percent, 0, 100)
		if personal_reduction > 0 and final_damage > 0:
			final_damage = maxi(1, floori(float(final_damage) * float(100 - personal_reduction) / 100.0))
	return final_damage


## What a hit of `raw_damage` would cost this actor right now, shield included,
## without touching anything. Used by the telegraph; the resolver goes through
## apply_damage_with_result, which shares mitigated_damage underneath.
func preview_damage(
	raw_damage: int,
	damage_type: String = "physical"
) -> int:
	var final_damage: int = mitigated_damage(raw_damage, damage_type)
	var absorbed: int = mini(shield, final_damage)
	return mini(final_damage - absorbed, health)


func apply_damage_with_result(
	raw_damage: int,
	damage_type: String = "physical",
	final_reduction_percent: int = 0,
	additional_reduction_percents: Array[int] = [],
	crit_multiplier: float = 1.0
) -> Dictionary:
	## Detailed result for new combat systems. "hit" means a valid positive
	## damage instance reached this living actor, even if shield absorbs all of it.
	##
	## crit_multiplier is supplied by DamagePipeline after the attacker’s crit
	## rate roll. This function only applies the resolved multiplier.
	if _is_defeated or raw_damage <= 0:
		return {"hit": false, "absorbed": 0, "health_damage": 0, "final_damage": 0, "was_critical": false}
	# §10.6: an unknown type used to fall through to zero resistance, which let a
	# typo hit at full strength. Reject it instead of resolving it.
	if not DamageTypes.is_valid(damage_type):
		push_error("BattleActor: unknown damage type '%s' (expected %s)" % [damage_type, DamageTypes.describe()])
		return {"hit": false, "invalid_type": true, "absorbed": 0, "health_damage": 0, "final_damage": 0, "was_critical": false}
	var was_critical: bool = crit_multiplier > 1.0
	var final_damage: int = mitigated_damage(
		raw_damage,
		damage_type,
		final_reduction_percent,
		additional_reduction_percents,
		crit_multiplier
	)
	var absorbed: int = mini(shield, final_damage)
	shield -= absorbed
	var health_damage: int = mini(final_damage - absorbed, health)
	health -= health_damage
	if health <= 0:
		health = 0
		_is_defeated = true
		if team == "player":
			_is_downed = true
	return {
		"hit": true,
		"absorbed": absorbed,
		"health_damage": health_damage,
		"final_damage": final_damage,
		"was_critical": was_critical
	}

func is_available() -> bool:
	return not _is_defeated and health > 0


func is_alive() -> bool:
	return not is_benched and is_available()


func is_defeated() -> bool:
	return _is_defeated


func is_downed() -> bool:
	return _is_downed


## Class resource track (design plan §19: 剑意). Capped, never negative, and a
## no-op for units without one, so callers do not have to ask first.
func gain_resource(amount: int) -> int:
	if resource_max <= 0 or amount <= 0:
		return resource_current
	resource_current = clampi(resource_current + amount, 0, resource_max)
	return resource_current


func spend_resource(amount: int) -> bool:
	if amount < 0 or resource_current < amount:
		return false
	resource_current -= amount
	return true


func scaled_healing_amount(base_amount: int) -> int:
	if base_amount <= 0:
		return 0
	return maxi(1, roundi(float(base_amount) * (1.0 + maxf(0.0, healing_efficiency) / 100.0)))


func has_resource() -> bool:
	return resource_id != &"" and resource_max > 0


func is_resource_full() -> bool:
	return resource_max > 0 and resource_current >= resource_max


## Whether this unit still occupies its cell. A downed body does: §12 says the
## cell stays blocked until the unit is revived and moved.
func blocks_cell() -> bool:
	return not is_benched and (is_alive() or is_downed())


## Bring a downed unit back at the given health. Reviving a unit that is not
## downed is a no-op, so a skill cannot top up a standing ally by accident.
func revive(restored_health: int) -> bool:
	if not is_downed():
		return false
	health = clampi(restored_health, 1, max_health)
	_is_defeated = false
	_is_downed = false
	return true

