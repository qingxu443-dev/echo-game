class_name APBudget
extends RefCounted

## Small deterministic AP ledger. Call spend only after action confirmation.

var maximum: int
var current: int


func _init(ap_maximum: int = 3) -> void:
	maximum = maxi(0, ap_maximum)
	current = maximum


func reset() -> void:
	current = maximum


func can_spend(cost: int) -> bool:
	return cost >= 0 and current >= cost


func spend(cost: int) -> bool:
	if not can_spend(cost):
		return false
	current -= cost
	return true


## Explicit refund for a spend that was already committed. An invalid refund
## keeps the ledger untouched; only the battle controller may call this.
func refund(cost: int) -> bool:
	if cost < 0 or current + cost > maximum:
		return false
	current += cost
	return true


func clear() -> void:
	current = 0
