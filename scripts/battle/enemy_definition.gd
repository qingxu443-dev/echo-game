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
## 0 ordinary, 1 elite, 2 boss. Only used by rules that draw a line between the
## ranks - 古木壁垒 shields *ordinary* allies and never another elite or boss
## (§14), so the distinction has to live in the data rather than in a name check.
@export var tier: int = 0
## Shield this archetype grants to one ordinary ally within two cells when its
## charge bar is full (§14 古木壁垒: 500). Zero means the archetype has no ward
## action at all, which is every other sheet.
@export var ward_shield: int = 0
## Flat raw damage for this archetype's signature skill. Zero falls back to
## `attack x action multiplier`. §14 is explicit that skill damage must not ride
## on the base attack: the sheets carry attacks already cut by 30%, and without
## this field cutting the attack would quietly cut the skill too.
@export var skill_damage: int = 0
## 结界守护 (§15.2): shield itself for `ward_stance_percent` of max health plus
## `ward_stance_node_bonus` per standing 结界 node, when the charge bar is full.
## Zero on every sheet that has no such stance.
@export var ward_stance_percent: float = 0.0
@export var ward_stance_node_bonus: float = 0.0
## Multiplier for this archetype's plain attack, overriding the action default
## (basic_melee 0.80 / light_shot 0.75 / echo_bolt 0.70). Zero keeps the default.
## §15 gives each boss its own attendance number - 樱刃 0.80, 重盾击 0.70,
## 花影弹 0.65 - and they are not interchangeable: a boss whose sheet says 0.65
## should not be swinging the generic 0.80.
@export var basic_attack_multiplier: float = 0.0


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
	if tier < 0 or tier > 2:
		return false
	if ward_shield < 0:
		return false
	if skill_damage < 0:
		return false
	if ward_stance_percent < 0.0 or ward_stance_node_bonus < 0.0:
		return false
	if basic_attack_multiplier < 0.0:
		return false
	return true
