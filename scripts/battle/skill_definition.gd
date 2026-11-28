class_name SkillDefinition
extends Resource

## Data-only skill specification. Runtime execution is handled by BattleController.

const TARGET_SELF: StringName = &"self"
const TARGET_SELF_AND_ALLY: StringName = &"self_and_ally"
const TARGET_ACTOR: StringName = &"actor"
const TARGET_CELL: StringName = &"cell"
const TARGET_AREA: StringName = &"area"

const DAMAGE_NONE: StringName = &"none"
const DAMAGE_PHYSICAL: StringName = &"physical"
const DAMAGE_MAGICAL: StringName = &"magical"

@export var skill_id: StringName = &""
@export var display_name_zh: String = ""
@export_multiline var description_zh: String = ""
@export var ap_cost: int = 1
@export var target_mode: StringName = TARGET_SELF
@export var min_range: int = 0
@export var max_range: int = 0
@export var damage_type: StringName = DAMAGE_NONE
@export var damage_multiplier: float = 0.0
## Healing output coefficient used by support-build scoring and healing resolution.
@export var healing_multiplier: float = 0.0
## Which runtime branch resolves this skill. Assigning it is the catalogue's
## job; a skill without one fails loudly in the runtime instead of doing nothing.
@export var executor_id: StringName = &""
@export var is_passive: bool = false
## Design plan §15: which of the five slots this skill occupies.
@export var slot: StringName = &""
## Plan §26: an action may consist of several independently calculated segments.
@export var hits: int = 1
## Per-segment multipliers. Empty means damage_multiplier is split evenly across
## hits, which is what most skills want; a finisher-heavy skill lists them.
@export var hit_multipliers: Array[float] = []
## Area shape for multi-target skills. "single" is the default.
const SHAPE_SINGLE: StringName = &"single"
const SHAPE_CROSS: StringName = &"cross"
const SHAPE_FAN: StringName = &"fan"
const SHAPE_DIAMOND: StringName = &"diamond"
@export var shape: StringName = SHAPE_SINGLE
@export var shape_radius: int = 0
## Rectangle footprint in front of the caster, used by SHAPE_FAN.
## depth is how many cells it reaches forward, width how many it spans across.
@export var shape_width: int = 0
@export var shape_depth: int = 0


func is_valid() -> bool:
	if skill_id == &"" or display_name_zh.strip_edges().is_empty():
		return false
	if ap_cost < 0 or (ap_cost == 0 and not is_passive) or (is_passive and ap_cost != 0) or min_range < 0 or max_range < min_range:
		return false
	if target_mode != TARGET_SELF and target_mode != TARGET_SELF_AND_ALLY and target_mode != TARGET_ACTOR and target_mode != TARGET_CELL and target_mode != TARGET_AREA:
		return false
	if damage_multiplier < 0.0 or healing_multiplier < 0.0:
		return false
	if hits <= 0:
		return false
	if not hit_multipliers.is_empty() and hit_multipliers.size() != hits:
		return false
	for hit_multiplier in hit_multipliers:
		if hit_multiplier < 0.0:
			return false
	if shape != SHAPE_SINGLE and shape != SHAPE_CROSS and shape != SHAPE_FAN and shape != SHAPE_DIAMOND:
		return false
	if shape == SHAPE_DIAMOND and shape_radius <= 0:
		return false
	if shape == SHAPE_FAN and (shape_width <= 0 or shape_depth <= 0):
		return false
	if damage_multiplier > 0.0:
		if damage_type != DAMAGE_PHYSICAL and damage_type != DAMAGE_MAGICAL:
			return false
	elif damage_type != DAMAGE_NONE:
		return false
	return true
