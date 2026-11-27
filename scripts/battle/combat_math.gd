class_name CombatMath
extends RefCounted

## Shared deterministic damage math. Defense uses diminishing returns.
## Effective damage = raw damage * K / (K + resistance).
## §法则三: K (the attenuation constant) is the named "exchange rate" of
## resistance. It is a public Law parameter, exposed as ATTENUATION_K below.

## 法则三的公开参数：抗性的衰减常数（"汇率"）。默认值与历史数值一致，
## 因此不传参时所有既有结算逐点保持不变。
const ATTENUATION_K: int = 1000


static func calculate_raw_damage(attack_power: int, multiplier: float) -> int:
	if attack_power <= 0 or multiplier <= 0.0:
		return 0
	return maxi(1, roundi(float(attack_power) * multiplier))


static func calculate_damage(raw_damage: int, resistance: int, attenuation_k: int = ATTENUATION_K) -> int:
	if raw_damage <= 0:
		return 0
	var safe_resistance: int = maxi(0, resistance)
	var safe_k: int = maxi(1, attenuation_k)
	return maxi(1, floori(float(raw_damage) * float(safe_k) / (float(safe_k) + float(safe_resistance))))


## §47 待决 1 option B: the pipeline keeps integer points, the display layer
## speaks percentages. This is the one direction that has to exist for the two
## to agree; the reverse (R = K*p / (1 - p)) is a design-time table, not a
## runtime call. p = R / (K + R), so 111 points reads as 9.99% at K = 1000.
static func resistance_percent(resistance: int, attenuation_k: int = ATTENUATION_K) -> float:
	var safe_resistance: float = float(maxi(0, resistance))
	var safe_k: float = float(maxi(1, attenuation_k))
	return 100.0 * safe_resistance / (safe_k + safe_resistance)
