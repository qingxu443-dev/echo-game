class_name CharacterDefinition
extends Resource

## Data-only character sheet.
##
## Adding a playable character should mean dropping one .tres into
## data/characters/ and listing its skills in a catalog - not editing the
## controller, the flow or the view. Everything the runtime needs to spawn and
## describe a character lives here.
##
## Slots follow design plan §15: every character has a normal attack, a passive,
## two active skills and an ultimate. A slot may be left out; the skill bar shows
## what exists rather than reserving empty rows.

const SLOT_NORMAL: StringName = &"normal"
const SLOT_PASSIVE: StringName = &"passive"
const SLOT_ACTIVE_ONE: StringName = &"active_one"
const SLOT_ACTIVE_TWO: StringName = &"active_two"
const SLOT_ULTIMATE: StringName = &"ultimate"

const SLOT_ORDER: Array[StringName] = [SLOT_NORMAL, SLOT_PASSIVE, SLOT_ACTIVE_ONE, SLOT_ACTIVE_TWO, SLOT_ULTIMATE]

@export var character_id: StringName = &""
@export var display_name_zh: String = ""
@export var role_label_zh: String = ""
## Single character drawn on the board token, as the enemies use 锋 / 射 / 术.
@export var glyph: String = "守"

## Optional character artwork paths. Empty values retain legacy filename lookup.
@export_file("*.png", "*.webp") var portrait_path: String = ""
@export_file("*.png", "*.webp") var full_illustration_path: String = ""
@export_file("*.png", "*.webp") var battlefield_sprite_path: String = ""
@export_file("*.png", "*.webp") var battlefield_sprite_back_path: String = ""
@export var max_health: int = 1000
@export var attack: int = 100
@export var defense: int = 50
@export var magic_resistance: int = 50

## Skill ids in slot order, matching SLOT_ORDER. Shorter lists are allowed.
@export var skill_ids: Array[StringName] = []

## Ultimate energy ceiling (design plan §13). It belongs to the character, not to
## the skill: releasing an ultimate spends the whole pool, so a character with a
## larger pool charges and spends more. Five for both prototypes.
@export var ultimate_energy_max: int = 5

## Class resource, if the character has one (剑意 for Sakura). An empty
## resource_id means the character has no personal resource track.
@export var resource_id: StringName = &""
@export var resource_name_zh: String = ""
@export var resource_max: int = 0


func is_valid() -> bool:
	if character_id == &"" or display_name_zh.strip_edges().is_empty():
		return false
	if max_health <= 0 or attack <= 0 or defense < 0 or magic_resistance < 0:
		return false
	if glyph.strip_edges().is_empty():
		return false
	if resource_id == &"" and (resource_max != 0 or not resource_name_zh.is_empty()):
		return false
	if resource_id != &"" and resource_max <= 0:
		return false
	return true


func has_resource() -> bool:
	return resource_id != &"" and resource_max > 0


func skill_id_for_slot(slot: StringName) -> StringName:
	var index: int = SLOT_ORDER.find(slot)
	if index < 0 or index >= skill_ids.size():
		return &""
	return skill_ids[index]
