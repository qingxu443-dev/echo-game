class_name CombatMath
extends RefCounted

## Shared deterministic damage math. Defense uses diminishing returns.
## Effective damage = raw damage * 1000 / (1000 + resistance).

static func calculate_raw_damage(attack_power: int, multiplier: float) -> int:
	if attack_power <= 0 or multiplier <= 0.0:
		return 0
	return maxi(1, roundi(float(attack_power) * multiplier))


static func calculate_damage(raw_damage: int, resistance: int) -> int:
	if raw_damage <= 0:
		return 0
	var safe_resistance: int = maxi(0, resistance)
	return maxi(1, floori(float(raw_damage) * 1000.0 / (1000.0 + float(safe_resistance))))


## §47 待决 1 option B: the pipeline keeps integer points, the display layer
## speaks percentages. This is the one direction that has to exist for the two
## to agree; the reverse (R = 1000p / (1 - p)) is a design-time table, not a
## runtime call. p = R / (1000 + R), so 111 points reads as 9.99%.
static func resistance_percent(resistance: int) -> float:
	var safe_resistance: float = float(maxi(0, resistance))
	return 100.0 * safe_resistance / (1000.0 + safe_resistance)
