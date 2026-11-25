class_name EnemyDefinition
extends Resource

## Data-only enemy profile. Behaviour (intent generation, priorities, damage
## multipliers) deliberately stays in BattleController: only the numbers live
## here, so tuning a stat is a data edit while a new behaviour is still code.

@export var archetype_id: StringName = &""
@export var display_name_zh: String = ""
## Single character drawn on the board token, mirroring the character sheets
## (锋 / 射 / 术) so the player can tell archetypes apart at a glance.
@export var glyph: String = "锋"
@export var health: int = 0
@export var attack: int = 0
@export var defense: int = 0
@export var magic_resistance: int = 0


func is_valid() -> bool:
	if archetype_id == &"" or display_name_zh.strip_edges().is_empty():
		return false
	if health <= 0:
		return false
	if attack < 0 or defense < 0 or magic_resistance < 0:
		return false
	return true
