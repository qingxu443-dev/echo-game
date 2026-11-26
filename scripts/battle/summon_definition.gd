class_name SummonDefinition
extends Resource

## Data-only summon spec.
##
## A summon is a player-side support strike, not a character: it never joins the
## board, never appears in the intent order and cannot be targeted. Adding a
## second summon should mean adding one .tres, the same way adding a character
## means adding one sheet.

@export var summon_id: StringName = &""
@export var display_name_zh: String = ""
@export_multiline var description_zh: String = ""
@export var attack: int = 1000
@export var damage_multiplier: float = 1.0
## Player turns before it can be called again.
@export var cooldown_turns: int = 2
@export var ap_cost: int = 0


func is_valid() -> bool:
	if summon_id == &"" or display_name_zh.strip_edges().is_empty():
		return false
	if attack <= 0 or damage_multiplier <= 0.0:
		return false
	if cooldown_turns < 0 or ap_cost < 0:
		return false
	return true
