class_name APBudget
extends RefCounted

## Deterministic AP ledger. One instance is the whole party's pool, so every
## character draws from the same numbers. Call spend only after the action is
## confirmed.

var maximum: int
var current: int
## Optional callback invoked whenever AP is actually spent (amount: int).
var on_spend: Callable = Callable()


func _init(ap_maximum: int = 5) -> void:
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
	if cost > 0 and on_spend.is_valid():
		on_spend.call(cost)
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
