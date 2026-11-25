class_name DamageTypes
extends RefCounted

## Explicit damage types (design plan §10.2, §10.6). The set is closed: anything
## outside it is rejected before any damage is applied, so a typo like "phyiscal"
## cannot fall through to a zero-resistance branch and bypass every defensive
## stat.
##
## §47 待决 2 and 待决 3 were settled on 2026-11-26. True damage now exists, with
## the semantics of option C: it ignores defence values and every percentage
## reduction, but a shield still absorbs it - a shield is an explicit resource,
## not a defensive stat, so bypassing it would break the §11 promise that a
## shield takes the hit before HP does.

const PHYSICAL: StringName = &"physical"
const MAGICAL: StringName = &"magical"
const TRUE_DAMAGE: StringName = &"true"


static func is_valid(damage_type: String) -> bool:
	return damage_type == PHYSICAL or damage_type == MAGICAL or damage_type == TRUE_DAMAGE


## Which stat this damage type is resisted by. Only called for valid types; the
## explicit zero below keeps an unknown type from reading as "no defense".
static func resistance_for(actor, damage_type: String) -> int:
	match damage_type:
		PHYSICAL:
			return actor.defense
		MAGICAL:
			return actor.magic_resistance
		TRUE_DAMAGE:
			return 0
	return 0


## §47 待决 3 option C: true damage skips the resistance stat and every
## percentage reduction. Shield absorption is deliberately not included here -
## the caller applies it for all types.
static func ignores_mitigation(damage_type: String) -> bool:
	return damage_type == TRUE_DAMAGE


static func describe() -> String:
	return "%s / %s / %s" % [PHYSICAL, MAGICAL, TRUE_DAMAGE]
