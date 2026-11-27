class_name SpringEncounterCatalog
extends RefCounted

## The eighteen 春之境 fights (设计汇总 2026-11-26 §13, §14, §15) and the
## turnkey conversion from "a place on the map" to a battle the existing
## controller can start.
##
## Rosters, ids, names and difficulty labels are the document's data. What the
## document does not give is a battlefield for each fight - §13 only says the
## config is drawn from a pool and dropped onto "地图合法预设位置". So the board
## is built here from one shared geometric rule (hero at the south edge, ranged
## enemies on the back rank, melee in front, two obstacles on the flanks) and is
## deterministic per encounter id: the same fight always looks the same, which is
## what lets a save resume mid-run without re-rolling anything.
##
## Deliberately NOT here: the elites' signature skills (§14) and the bosses'
## (§15). Those need battlefield zones, area telegraphs and destructible nodes -
## none of which the battle layer has - so each elite and boss currently fights
## with its normal attack. Recorded as debt in PROJECT_STATUS.md rather than
## faked with numbers that do nothing.

const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")

const DIFFICULTY_EASY: String = "简单"
const DIFFICULTY_NORMAL: String = "普通"
const DIFFICULTY_HARD: String = "较高"

## §13 table. `roster` lists archetype ids, one entry per enemy on the board.
const ENCOUNTERS := {
	"B001": {"title": "林间巡逻", "difficulty": DIFFICULTY_EASY, "roster": ["petal_warrior", "petal_warrior"]},
	"B002": {"title": "花径伏击", "difficulty": DIFFICULTY_EASY, "roster": ["petal_archer", "petal_archer", "petal_warrior"]},
	"B003": {"title": "古道守卫", "difficulty": DIFFICULTY_EASY, "roster": ["withered_guard", "petal_warrior", "petal_warrior"]},
	"B004": {"title": "花影追猎", "difficulty": DIFFICULTY_NORMAL, "roster": ["wind_ranger", "wind_ranger", "petal_warrior"]},
	"B005": {"title": "春蚀低语", "difficulty": DIFFICULTY_NORMAL, "roster": ["spring_blight", "petal_warrior", "petal_warrior"]},
	"B006": {"title": "枯木阵线", "difficulty": DIFFICULTY_NORMAL, "roster": ["withered_guard", "withered_guard", "petal_archer"]},
	"B007": {"title": "逐风围猎", "difficulty": DIFFICULTY_NORMAL, "roster": ["wind_ranger", "petal_archer", "petal_archer", "petal_warrior"]},
	"B008": {"title": "无声花阵", "difficulty": DIFFICULTY_NORMAL, "roster": ["spring_blight", "withered_guard", "petal_archer", "petal_warrior"]},
	"B009": {"title": "樱落之前", "difficulty": DIFFICULTY_HARD, "roster": ["petal_warrior", "petal_warrior", "petal_archer", "wind_ranger"]},
	"B010": {"title": "永春守望", "difficulty": DIFFICULTY_HARD, "roster": ["spring_blight", "withered_guard", "petal_warrior", "petal_archer", "wind_ranger"]},
	"B011": {"title": "双翼夹击", "difficulty": DIFFICULTY_NORMAL, "roster": ["petal_archer", "petal_archer", "wind_ranger", "petal_warrior"]},
	"B012": {"title": "守望者的阵地", "difficulty": DIFFICULTY_NORMAL, "roster": ["withered_guard", "spring_blight", "petal_warrior", "petal_warrior", "petal_archer"]},
}

## §14 elite table. 1-2 elites plus 2-3 ordinary enemies, 3-5 total.
const ELITES := {
	"E-B001": {"title": "绯樱巡狩", "roster": ["crimson_sword_guard", "petal_warrior", "petal_warrior", "petal_archer"]},
	"E-B002": {"title": "百花围猎", "roster": ["hundred_bloom_sniper", "wind_ranger", "petal_warrior", "petal_archer"]},
	"E-B003": {"title": "古木壁垒", "roster": ["ancient_bulwark", "rotten_blossom_witch", "withered_guard", "petal_warrior"]},
	"E-B004": {"title": "风樱急袭", "roster": ["gale_blade", "crimson_sword_guard", "petal_archer", "spring_blight"]},
	"E-B005": {"title": "永春镇守", "roster": ["sakura_beast", "rotten_blossom_witch", "withered_guard", "wind_ranger", "petal_archer"]},
}

## §15 boss table. One boss, no escort.
const BOSSES := {
	"boss_petalfall": {"title": "凋樱剑主", "roster": ["boss_petalfall"], "hint": "高机动近战：相邻即斩，别让它贴上来。"},
	"boss_thousand_boughs": {"title": "千枝神将", "roster": ["boss_thousand_boughs"], "hint": "高防御守阵：每一次交换都在考验你能不能磨穿它。"},
	"boss_spring_echo": {"title": "春痕回响", "roster": ["boss_spring_echo"], "hint": "远程法术：直线与视线之外才是安全区。"},
}

## Board geometry (§13 leaves it open; one rule serves all eighteen fights).
const BOARD_SIZE: Vector2i = Vector2i(8, 8)
const HERO_CELL: Vector2i = Vector2i(3, 6)
## Back rank first: ranged archetypes take these before any melee does.
const BACK_SLOTS: Array[Vector2i] = [
	Vector2i(3, 0), Vector2i(2, 0), Vector2i(4, 0), Vector2i(1, 0), Vector2i(5, 0),
]
const FRONT_SLOTS: Array[Vector2i] = [
	Vector2i(3, 2), Vector2i(2, 2), Vector2i(4, 2), Vector2i(1, 1), Vector2i(5, 1),
]
## Two of these become obstacles, picked by encounter id so a fight is stable.
const OBSTACLE_SLOTS: Array[Vector2i] = [
	Vector2i(0, 4), Vector2i(7, 4), Vector2i(0, 2), Vector2i(7, 2), Vector2i(3, 4), Vector2i(4, 5),
]

const RANGED_ACTIONS: Array[String] = ["light_shot", "aimed_shot", "echo_bolt"]


static func has_encounter(encounter_id: StringName) -> bool:
	var key := String(encounter_id)
	return ENCOUNTERS.has(key) or ELITES.has(key) or BOSSES.has(key)


static func status_of(encounter_id: StringName) -> String:
	var key := String(encounter_id)
	if ENCOUNTERS.has(key):
		return "battle"
	if ELITES.has(key):
		return "elite"
	if BOSSES.has(key):
		return "boss"
	return ""


static func title_of(encounter_id: StringName) -> String:
	var entry: Dictionary = _entry(encounter_id)
	return str(entry.get("title", ""))


static func roster_of(encounter_id: StringName) -> Array[String]:
	var roster: Array[String] = []
	var entry: Dictionary = _entry(encounter_id)
	for archetype in entry.get("roster", []):
		roster.append(str(archetype))
	return roster


static func difficulty_of(encounter_id: StringName) -> String:
	var entry: Dictionary = _entry(encounter_id)
	return str(entry.get("difficulty", ""))


static func is_elite_or_boss(encounter_id: StringName) -> bool:
	var key := String(encounter_id)
	return ELITES.has(key) or BOSSES.has(key)


static func _entry(encounter_id: StringName) -> Dictionary:
	var key := String(encounter_id)
	if ENCOUNTERS.has(key):
		return ENCOUNTERS[key]
	if ELITES.has(key):
		return ELITES[key]
	if BOSSES.has(key):
		return BOSSES[key]
	return {}


## Whether an archetype prefers the back rank. Read from the data, not from a
## hand-kept second list: an archetype whose first action is a ranged one stands
## back, everything else walks forward.
static func prefers_back_rank(archetype_id: String) -> bool:
	var definition: EnemyDefinition = EnemyCatalogScript.get_definition(archetype_id)
	if definition == null:
		return false
	for action in definition.actions:
		if RANGED_ACTIONS.has(String(action)):
			return true
	return false


## Builds the battle the controller will accept. `character_ids` is passed in
## rather than hard-coded so the same fight can be replayed by whichever hero the
## mode currently deploys.
static func build(encounter_id: StringName, character_ids: Array[String] = []) -> EncounterDefinition:
	var entry: Dictionary = _entry(encounter_id)
	if entry.is_empty():
		return null
	var roster: Array[String] = roster_of(encounter_id)
	if roster.is_empty():
		return null

	var slots := _enemy_slots(roster)
	if slots.size() != roster.size():
		return null

	var definition := EncounterDefinition.new()
	definition.level_id = encounter_id
	definition.display_name_zh = str(entry["title"])
	definition.tactical_hint_zh = str(entry.get("hint", _default_hint(encounter_id)))
	definition.player_cell = HERO_CELL
	definition.character_ids = character_ids.duplicate()
	definition.ally_cells = []
	definition.enemy_archetypes = roster
	for cell in slots:
		definition.enemy_cells.append(cell)
	definition.obstacles = _obstacles_for(encounter_id, slots)
	# Empty chest_items keeps the existing random-loot behaviour. §12 makes the
	# chest's presence probabilistic and leaves the probability open, so nothing
	# here pins a chest count.
	definition.chest_items = []
	return definition


## Ranged archetypes fill the back rank in roster order, then melee fills the
## front. Deterministic: same roster, same cells, every run.
static func _enemy_slots(roster: Array[String]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var back_cursor: int = 0
	var front_cursor: int = 0
	for archetype in roster:
		if prefers_back_rank(archetype):
			if back_cursor >= BACK_SLOTS.size():
				return []
			result.append(BACK_SLOTS[back_cursor])
			back_cursor += 1
		else:
			if front_cursor >= FRONT_SLOTS.size():
				return []
			result.append(FRONT_SLOTS[front_cursor])
			front_cursor += 1
	return result


## Two obstacles, chosen by the encounter's own id so a resumed fight has the
## same cover, and never on a cell an enemy or the hero occupies.
static func _obstacles_for(encounter_id: StringName, enemy_cells: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var taken: Dictionary = {HERO_CELL: true}
	for cell in enemy_cells:
		taken[cell] = true
	var offset: int = posmod(String(encounter_id).hash(), OBSTACLE_SLOTS.size())
	for step in range(OBSTACLE_SLOTS.size()):
		if result.size() >= 2:
			break
		var cell: Vector2i = OBSTACLE_SLOTS[(offset + step) % OBSTACLE_SLOTS.size()]
		if taken.has(cell):
			continue
		result.append(cell)
		taken[cell] = true
	return result


static func _default_hint(encounter_id: StringName) -> String:
	var key := String(encounter_id)
	if ENCOUNTERS.has(key):
		return "敌人从上风处压来，读准预告再落子。"
	if ELITES.has(key):
		return "精英带队：先拆掉随行的小兵，还是直接压精英，由你决定。"
	if BOSSES.has(key):
		return "首领在前，这一战决定本局能走多远。"
	return ""


## Every id this catalog knows, in document order. Used by the tests to assert
## the pool is complete and by the map to check a place actually has content.
static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in ENCOUNTERS.keys():
		ids.append(String(key))
	for key in ELITES.keys():
		ids.append(String(key))
	for key in BOSSES.keys():
		ids.append(String(key))
	return ids
