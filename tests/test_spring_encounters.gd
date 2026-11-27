extends "res://tests/framework/test_case.gd"

## 春之境 fight rosters (设计汇总 2026-11-26 §13, §14, §15).
##
## These assertions pin what the document actually fixes: the twelve ordinary
## fights and their rosters, the five elite fights, the three bosses, and the
## guarantee that a built battlefield is legal. Board *coordinates* are a draft
## (the document withholds the real layout) so nothing here asserts a specific
## cell - only that the geometry is consistent, deterministic and keeps ranged
## enemies behind melee ones.

const CatalogScript = preload("res://scripts/spring/spring_encounter_catalog.gd")
const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")
const FactoryScript = preload("res://scripts/spring/spring_map_factory.gd")


func _run() -> void:
	_test_pool_sizes()
	_test_rosters_match_the_document()
	_test_every_archetype_resolves()
	_test_elites_carry_an_elite()
	_test_bosses_are_alone()
	_test_built_boards_are_legal()
	_test_build_is_deterministic()
	_test_ranged_stand_behind_melee()
	_test_unknown_id_is_refused()
	_test_templates_do_not_share_fights()
	_test_boss_ids_match_the_map()


func _test_pool_sizes() -> void:
	_check(CatalogScript.ENCOUNTERS.size() == 12, "the ordinary pool holds the document's twelve fights")
	_check(CatalogScript.ELITES.size() == 5, "the elite pool holds five fights")
	_check(CatalogScript.BOSSES.size() == 3, "there are three bosses")
	_check(CatalogScript.all_ids().size() == 20, "the catalog knows twenty encounters in total")
	var unique: Dictionary = {}
	for encounter_id in CatalogScript.all_ids():
		_check(not unique.has(encounter_id), "encounter id %s is unique" % encounter_id)
		unique[encounter_id] = true


func _test_rosters_match_the_document() -> void:
	# §13 table, verbatim: id -> (name, roster size).
	var expected := {
		"B001": ["林间巡逻", 2],
		"B002": ["花径伏击", 3],
		"B003": ["古道守卫", 3],
		"B004": ["花影追猎", 3],
		"B005": ["春蚀低语", 3],
		"B006": ["枯木阵线", 3],
		"B007": ["逐风围猎", 4],
		"B008": ["无声花阵", 4],
		"B009": ["樱落之前", 4],
		"B010": ["永春守望", 5],
		"B011": ["双翼夹击", 4],
		"B012": ["守望者的阵地", 5],
	}
	for encounter_id in expected:
		var row: Array = expected[encounter_id]
		var key := StringName(encounter_id)
		_check(CatalogScript.title_of(key) == str(row[0]), "%s keeps its document name" % encounter_id)
		_check(CatalogScript.roster_of(key).size() == int(row[1]), "%s fields %d enemies" % [encounter_id, int(row[1])])

	# §13 difficulty draft: one easy, two normal, one hard per template.
	var easy: int = 0
	var normal: int = 0
	var hard: int = 0
	for encounter_id in CatalogScript.ENCOUNTERS:
		match CatalogScript.difficulty_of(StringName(encounter_id)):
			CatalogScript.DIFFICULTY_EASY:
				easy += 1
			CatalogScript.DIFFICULTY_NORMAL:
				normal += 1
			CatalogScript.DIFFICULTY_HARD:
				hard += 1
	_check(easy == 3, "three fights are labelled easy")
	_check(hard == 2, "two fights are labelled hard")
	_check(easy + normal + hard == 12, "every fight carries a difficulty label")


func _test_every_archetype_resolves() -> void:
	for encounter_id in CatalogScript.all_ids():
		var key := StringName(encounter_id)
		for archetype in CatalogScript.roster_of(key):
			_check(EnemyCatalogScript.has_definition(archetype), "%s fields a known archetype (%s)" % [encounter_id, archetype])


func _test_elites_carry_an_elite() -> void:
	var elite_ids := ["crimson_sword_guard", "hundred_bloom_sniper", "ancient_bulwark", "gale_blade", "rotten_blossom_witch", "sakura_beast"]
	for encounter_id in CatalogScript.ELITES:
		var key := StringName(encounter_id)
		var roster: Array[String] = CatalogScript.roster_of(key)
		_check(roster.size() >= 3 and roster.size() <= 5, "%s has 3-5 units (§14)" % encounter_id)
		var elites: int = 0
		for archetype in roster:
			if elite_ids.has(archetype):
				elites += 1
		_check(elites >= 1 and elites <= 2, "%s carries 1-2 elites (§14)" % encounter_id)


func _test_bosses_are_alone() -> void:
	for encounter_id in CatalogScript.BOSSES:
		var key := StringName(encounter_id)
		var roster: Array[String] = CatalogScript.roster_of(key)
		_check(roster.size() == 1, "%s has no escort (§15)" % encounter_id)
		_check(roster[0] == String(encounter_id), "%s fields itself" % encounter_id)
		_check(CatalogScript.is_elite_or_boss(key), "%s counts as a boss fight" % encounter_id)


func _test_built_boards_are_legal() -> void:
	for encounter_id in CatalogScript.all_ids():
		var key := StringName(encounter_id)
		var definition: EncounterDefinition = CatalogScript.build(key, ["sevrin"])
		_check(definition != null, "%s builds a definition" % encounter_id)
		if definition == null:
			continue
		_check(definition.is_valid(), "%s passes definition validation" % encounter_id)
		_check(definition.describe_layout_error().is_empty(), "%s has a self-consistent layout (%s)" % [encounter_id, definition.describe_layout_error()])
		_check(definition.enemy_cells.size() == CatalogScript.roster_of(key).size(), "%s places one cell per enemy" % encounter_id)
		_check(not definition.enemy_cells.has(definition.player_cell), "%s never puts an enemy on the hero" % encounter_id)
		_check(definition.obstacles.size() == 2, "%s places two obstacles" % encounter_id)
		for cell in definition.obstacles:
			_check(not definition.enemy_cells.has(cell), "%s keeps obstacles off enemies" % encounter_id)
			_check(cell != definition.player_cell, "%s keeps obstacles off the hero" % encounter_id)
		_check(definition.character_ids == ["sevrin"], "%s deploys the requested hero" % encounter_id)


func _test_build_is_deterministic() -> void:
	# A resumed run must not see a different board, so two builds have to match.
	for encounter_id in ["B010", "E-B005", "boss_spring_echo"]:
		var key := StringName(encounter_id)
		var first: EncounterDefinition = CatalogScript.build(key, ["sevrin"])
		var second: EncounterDefinition = CatalogScript.build(key, ["sevrin"])
		_check(first.enemy_cells == second.enemy_cells, "%s places enemies identically twice" % encounter_id)
		_check(first.obstacles == second.obstacles, "%s places obstacles identically twice" % encounter_id)


func _test_ranged_stand_behind_melee() -> void:
	# The one geometric rule the board has: shooters start further from the hero.
	#
	# Whether an archetype shoots is decided here from EnemyCatalog's action list,
	# NOT by asking the catalog under test - otherwise breaking prefers_back_rank
	# would make every enemy "melee", skip the comparison, and stay green.
	var checked_fights: int = 0
	for encounter_id in CatalogScript.ENCOUNTERS:
		var key := StringName(encounter_id)
		var definition: EncounterDefinition = CatalogScript.build(key, ["sevrin"])
		var ranged_rows: Array[int] = []
		var melee_rows: Array[int] = []
		for index in range(definition.enemy_archetypes.size()):
			var row: int = definition.enemy_cells[index].y
			if _shoots_at_range(definition.enemy_archetypes[index]):
				ranged_rows.append(row)
			else:
				melee_rows.append(row)
		if ranged_rows.is_empty() or melee_rows.is_empty():
			continue
		checked_fights += 1
		var deepest_melee: int = 0
		for row in melee_rows:
			deepest_melee = maxi(deepest_melee, row)
		for row in ranged_rows:
			_check(row < deepest_melee, "%s keeps every shooter ahead of the melee" % encounter_id)
	_check(checked_fights >= 6, "the back-rank rule was exercised on at least six fights")


## Independent of SpringEncounterCatalog: reads the enemy sheet directly.
func _shoots_at_range(archetype: String) -> bool:
	var definition: EnemyDefinition = EnemyCatalogScript.get_definition(archetype)
	if definition == null:
		return false
	for action in definition.actions:
		if ["light_shot", "aimed_shot", "echo_bolt"].has(String(action)):
			return true
	return false


func _test_unknown_id_is_refused() -> void:
	_check(CatalogScript.build(&"B999", ["sevrin"]) == null, "an unknown encounter id builds nothing")
	_check(not CatalogScript.has_encounter(&"B999"), "an unknown id is not offered")
	_check(CatalogScript.build(&"", ["sevrin"]) == null, "an empty id builds nothing")
	_check(CatalogScript.status_of(&"B001") == "battle", "B001 reports as a battle")
	_check(CatalogScript.status_of(&"E-B002") == "elite", "E-B002 reports as an elite")
	_check(CatalogScript.status_of(&"boss_petalfall") == "boss", "the boss reports as a boss")


func _test_templates_do_not_share_fights() -> void:
	# §13: the three templates never repeat a fight between them.
	var seen: Dictionary = {}
	for template_id in FactoryScript.template_ids():
		var spec: Dictionary = FactoryScript.TEMPLATE_SPECS[template_id]
		for battle_id in spec["battles"]:
			_check(not seen.has(String(battle_id)), "fight %s is not shared with another template" % battle_id)
			seen[String(battle_id)] = true
			_check(CatalogScript.has_encounter(StringName(battle_id)), "template %d only assigns known fights" % template_id)
		_check(CatalogScript.has_encounter(StringName(str(spec["elite_id"]))), "template %d assigns a known elite" % template_id)
	_check(seen.size() == 12, "the three templates use twelve distinct fights")


func _test_boss_ids_match_the_map() -> void:
	# The map factory names the boss a place points at; the catalog must agree.
	for template_id in FactoryScript.template_ids():
		var spec: Dictionary = FactoryScript.TEMPLATE_SPECS[template_id]
		var boss_id: String = str(spec["boss_id"])
		_check(CatalogScript.has_encounter(StringName(boss_id)), "the map's boss id %s exists in the catalog" % boss_id)
		_check(CatalogScript.title_of(StringName(boss_id)) == str(spec["boss_title"]), "the map's boss title %s matches" % boss_id)
