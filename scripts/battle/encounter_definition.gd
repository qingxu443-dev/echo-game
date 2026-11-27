class_name EncounterDefinition
extends Resource

## Data-only level configuration. Runtime state stays in BattleController.
## A level fixes the player cell, the enemy roster, and the obstacle layout so
## the same decisions always produce the same battle, per the level design
## principles in docs/design/skill_design_principles_zh-CN.md.

@export var level_id: StringName = &""
@export var display_name_zh: String = ""
@export var tactical_hint_zh: String = ""
@export var player_cell: Vector2i = Vector2i.ZERO
## Characters deployed this level, in the same order as their spawn cells.
## Empty means the prototype default (Sevrin alone).
@export var character_ids: Array[String] = []
## Spawn cells for the second and later characters. character_ids[0] uses
## player_cell; character_ids[i] uses ally_cells[i - 1].
@export var ally_cells: Array[Vector2i] = []
@export var enemy_cells: Array[Vector2i] = []
@export var enemy_archetypes: Array[String] = []
@export var obstacles: Array[Vector2i] = []
## Fixed chest contents, one StringName item id per beacon, in placement order.
## Empty means every beacon rolls a random item from the LootCatalog pool
## (the pre-2.5D behaviour). Teaching levels pin their rewards here so the
## lesson they promise is the lesson the player actually gets.
@export var chest_items: Array[StringName] = []

const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")

## Kept for readers who want the prototype trio at a glance. Validation no longer
## uses this list: a new archetype is one .tres plus one line in EnemyCatalog, so
## the authority for "which ids exist" has to be the catalog itself.
const KNOWN_ARCHETYPES: Array[String] = ["vanguard", "marksman", "area_controller"]


func is_valid() -> bool:
	if level_id == &"" or display_name_zh.strip_edges().is_empty():
		return false
	if tactical_hint_zh.strip_edges().is_empty():
		return false
	if enemy_cells.is_empty():
		return false
	if enemy_archetypes.size() != enemy_cells.size():
		return false
	for archetype in enemy_archetypes:
		if not EnemyCatalogScript.has_definition(archetype):
			return false
	return true


## Returns the first structural problem, or an empty string when the layout is
## self-consistent. BattleController performs its own bounds validation; this
## only catches authoring mistakes inside the catalog.
func describe_layout_error() -> String:
	if enemy_cells.size() != enemy_archetypes.size():
		return "enemy_cells 与 enemy_archetypes 数量不一致"
	if enemy_cells.has(player_cell):
		return "敌人与玩家起始格重叠"
	if obstacles.has(player_cell):
		return "障碍与玩家起始格重叠"
	var seen: Dictionary = {}
	for cell in enemy_cells:
		if seen.has(cell):
			return "敌人起始格重复: %s" % str(cell)
		seen[cell] = true
		if obstacles.has(cell):
			return "敌人起始格与障碍重叠: %s" % str(cell)
	return ""
