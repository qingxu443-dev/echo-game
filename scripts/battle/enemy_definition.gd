class_name EnemyDefinition
extends Resource

## Data-only enemy profile.
##
## The boundary is the same one the character framework draws: what an archetype
## *is made of* is data, and what a single action *does* is code. `actions` lists
## the actions this archetype tries, in priority order; the rules that decide
## whether one is legal live in IntentPlanner. So a new enemy that reuses existing
## actions is one .tres, while an action nobody has written yet is a new branch.

@export var archetype_id: StringName = &""
@export var display_name_zh: String = ""
## Single character drawn on the board token, mirroring the character sheets
## (锋 / 射 / 术) so the player can tell archetypes apart at a glance.
@export var glyph: String = "锋"
@export var health: int = 0
@export var attack: int = 0
@export var defense: int = 0
@export var magic_resistance: int = 0
## Actions this archetype attempts, in priority order. The first one that is legal
## on the current board is the intent; if none are, the enemy waits.
## Known ids: charged_strike, basic_melee, pursuit, aimed_shot, ground_pulse.
@export var actions: Array[StringName] = []
## Orthogonal cells this archetype may cover in one reposition. The prototype
## baseline is two (docs/design/ENEMY_AI_AND_TELEGRAPH §"移动 最多 2 个正交格"),
## so two is the default and a profile only overrides it to express weight:
## a heavy guard plods (1) while a wind runner skirmishes (3).
@export var move_steps: int = 2


func is_valid() -> bool:
	if archetype_id == &"" or display_name_zh.strip_edges().is_empty():
		return false
	if health <= 0:
		return false
	if attack < 0 or defense < 0 or magic_resistance < 0:
		return false
	if actions.is_empty():
		return false
	if move_steps <= 0:
		return false
	return true
