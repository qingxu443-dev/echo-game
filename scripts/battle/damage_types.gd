class_name DamageTypes
extends RefCounted

## Explicit damage types (design plan §10.2, §10.6).
##
## Previously an unrecognised type fell through to a zero-resistance branch, so a
## typo like "phyiscal" silently bypassed defense and magic resistance entirely -
## the hit landed at full strength and nothing reported it. Types are now a
## closed set and anything outside it is rejected before any damage is applied.
##
## True damage is deliberately absent. §10.6 lists whether it bypasses mitigation
## and shields as undecided, so no caller may request it until that is settled.

const PHYSICAL: StringName = &"physical"
const MAGICAL: StringName = &"magical"


static func is_valid(damage_type: String) -> bool:
	return damage_type == PHYSICAL or damage_type == MAGICAL


## Which stat this damage type is resisted by. Only called for valid types; the
## explicit zero below keeps an unknown type from reading as "no defense".
static func resistance_for(actor, damage_type: String) -> int:
	match damage_type:
		PHYSICAL:
			return actor.defense
		MAGICAL:
			return actor.magic_resistance
	return 0


static func describe() -> String:
	return "%s / %s" % [PHYSICAL, MAGICAL]
