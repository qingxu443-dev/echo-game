extends "res://tests/framework/test_case.gd"

## 本局存档 (设计汇总 2026-11-26 §16.2).
##
## §16.2 is a list of things a resumed run must restore *without re-rolling*
## them: the map template, the position, the bar, completed places, the random
## event, and the shop state. The random event is the interesting one - a naive
## `from_dict` that calls `begin()` would pick a fresh template and a fresh event
## and look fine until the player notices the board changed. These assertions
## compare the restored run against the original, not against constants.

const FactoryScript = preload("res://scripts/spring/spring_map_factory.gd")
const TEST_PATH := "user://spring_run_save_test.json"


func _run() -> void:
	_test_round_trip_keeps_the_board()
	_test_random_event_is_not_redrawn()
	_test_resources_round_trip()
	_test_progress_round_trip()
	_test_hidden_place_round_trip()
	_test_bad_payloads_are_refused()
	_test_json_file_round_trip()
	_test_templates_rebuild_identically()
	_test_old_versions_migrate_forward()
	_test_newer_version_is_refused()
	_test_migration_table_has_no_gaps()


## 迁移必须逐版走完，而不是靠「读不到就用默认值」蒙混。v2 的
## carry_max_health 是瑟弗林时代的 3600 上限，落到樱身上会让她双倍开局。
func _test_old_versions_migrate_forward() -> void:
	var base := SpringRun.begin(3).to_dict()

	var v2: Dictionary = base.duplicate(true)
	v2["version"] = 2
	v2["hero"] = {"health": 1500, "bonus_max_health": 0, "carry_max_health": 300}
	var from_v2 := SpringRun.from_dict(v2)
	_check(from_v2 != null, "v2 存档仍能加载")
	_check(from_v2 != null and from_v2.carry_max_health == 0, "v2 的 carry_max_health 被丢弃（瑟弗林上限不适用于樱）")
	_check(from_v2 != null and from_v2.hero_health == 1500, "v2 的当前血量原样保留，不因迁移被重置")

	var v1: Dictionary = base.duplicate(true)
	v1["version"] = 1
	v1.erase("hero")
	var from_v1 := SpringRun.from_dict(v1)
	_check(from_v1 != null, "v1 存档仍能加载")
	_check(from_v1 != null and from_v1.hero_health == from_v1.effective_max_health(), "v1 没有 hero 段时按满血开局")

	var v3: Dictionary = base.duplicate(true)
	v3["version"] = 3
	v3["hero"] = {"health": 1200, "bonus_max_health": 0, "carry_max_health": 300}
	var from_v3 := SpringRun.from_dict(v3)
	_check(from_v3 != null and from_v3.carry_max_health == 300, "已经是 v3 的档不做二次改写")


## 比本程序新的档必须拒绝：读得动不代表读得对，静默降级会丢字段。
func _test_newer_version_is_refused() -> void:
	var future := SpringRun.begin(4).to_dict()
	future["version"] = SpringRun.SAVE_VERSION + 1
	_check(SpringRun.from_dict(future) == null, "未来版本存档被拒绝，而不是勉强读取")


## 迁移表必须覆盖每一个中间版本，否则 1 → 3 会半路卡住（并且只在老玩家
## 身上出现，本地测试永远看不见）。
func _test_migration_table_has_no_gaps() -> void:
	for version in range(1, SpringRun.SAVE_VERSION):
		_check(SpringRun.MIGRATIONS.has(version), "v%d → v%d 有迁移函数" % [version, version + 1])
	_check(not SpringRun.MIGRATIONS.has(SpringRun.SAVE_VERSION), "当前版本不需要再迁移")


func _test_round_trip_keeps_the_board() -> void:
	for seed_value in range(0, 9):
		var run := SpringRun.begin(seed_value)
		var restored := SpringRun.from_dict(run.to_dict())
		_check(restored != null, "seed %d restores" % seed_value)
		if restored == null:
			continue
		_check(restored.template_id == run.template_id, "seed %d keeps its template" % seed_value)
		_check(restored.template.boss_cell == run.template.boss_cell, "seed %d keeps the boss cell" % seed_value)
		_check(restored.exploration.position == run.exploration.position, "seed %d keeps the position" % seed_value)
		_check(restored.exploration.stamina == run.exploration.stamina, "seed %d keeps the stamina" % seed_value)
		_check(restored.template.places.size() == run.template.places.size(), "seed %d keeps every place" % seed_value)


func _test_random_event_is_not_redrawn() -> void:
	for seed_value in range(0, 12):
		var run := SpringRun.begin(seed_value)
		var restored := SpringRun.from_dict(run.to_dict())
		if restored == null:
			_check(false, "seed %d restores for the event check" % seed_value)
			continue
		_check(restored.random_event_id == run.random_event_id, "seed %d keeps its random event instead of drawing a new one" % seed_value)

	# The loop above cannot tell "read from the file" apart from "draw again with
	# the same seed" - both produce the same id. Force a value the draw could
	# never produce, so only an implementation that honours the saved field can
	# pass. Same trick for the template: a seed that maps to template 1 with a
	# file that says template 3 must come back as template 3.
	var run := SpringRun.begin(0)
	_check(run.template_id == 1, "seed 0 draws template 1, so the check below is meaningful")
	var data := run.to_dict()
	data["random_event"] = "forced_event"
	data["template_id"] = 3
	var forced := SpringRun.from_dict(data)
	_check(forced != null, "a save naming another template still restores")
	if forced != null:
		_check(forced.random_event_id == &"forced_event", "the saved random event wins over a fresh draw")
		_check(forced.template_id == 3, "the saved template wins over the seed")
		_check(forced.template.boss_cell == Vector2i(4, 5), "the restored board is template 3's board")


func _test_resources_round_trip() -> void:
	var run := SpringRun.begin(3)
	run.coins = 47
	run.supplies = 5
	run.dew_cap = 8
	run.add_dew("spring", 3)
	run.add_dew("winter", 2)
	run.memory_pages = 4
	run.add_relic(&"relic_petal")
	run.add_relic(&"relic_echo")

	var restored := SpringRun.from_dict(run.to_dict())
	_check(restored.coins == 47, "coins survive a save")
	_check(restored.supplies == 5, "supplies survive a save")
	_check(restored.dew_cap == 8, "the 四时花露 cap survives a save")
	_check(int(restored.dew["spring"]) == 3 and int(restored.dew["winter"]) == 2, "each 花露 keeps its own count")
	_check(restored.dew_total() == 5, "the 花露 total is still the sum of the four")
	_check(restored.memory_pages == 4, "记忆残页 survive a save")
	_check(restored.relics.size() == 2 and restored.relics[1] == &"relic_echo", "relics keep their order")


func _test_progress_round_trip() -> void:
	var run := SpringRun.begin(1)
	var place = run.template.places_of(SpringPlace.Kind.BATTLE)[0]
	run.exploration.move_to(place.cell)
	run.complete_place(place)
	run.event_choices["sealed_chest"] = "bribe"
	var restored := SpringRun.from_dict(run.to_dict())
	_check(restored.exploration.completed.has(place.id), "a completed place stays completed")
	_check(not restored.exploration.can_interact() or restored.exploration.position != place.cell, "a completed one-shot place is not usable again")
	_check(str(restored.event_choices.get("sealed_chest", "")) == "bribe", "event choices are kept")


func _test_hidden_place_round_trip() -> void:
	var run := SpringRun.begin(2)
	var free := run.template.free_cells()
	_check(run.reveal_hidden(free[0]), "a hidden place can be revealed on a free cell")
	_check(not run.reveal_hidden(free[1]), "only one hidden place per board")
	var restored := SpringRun.from_dict(run.to_dict())
	_check(restored.hidden_revealed, "the hidden place stays revealed")
	_check(restored.hidden_cell == run.hidden_cell, "the hidden cell is restored")
	_check(restored.template.place_by_id(&"hidden") != null, "the hidden place is back on the board")


func _test_bad_payloads_are_refused() -> void:
	_check(SpringRun.from_dict({}) == null, "an empty dictionary restores nothing")
	_check(SpringRun.from_dict({"template_id": 9}) == null, "an unknown template id restores nothing")
	_check(SpringRun.load_from_file("user://definitely_absent_save.json") == null, "a missing file restores nothing")


func _test_json_file_round_trip() -> void:
	var run := SpringRun.begin(5)
	run.coins = 12
	run.exploration.move_to(run.template.boss_cell)
	_check(run.save_to_file(TEST_PATH), "the run writes to disk")
	var loaded := SpringRun.load_from_file(TEST_PATH)
	_check(loaded != null, "the run reads back")
	if loaded != null:
		_check(loaded.template_id == run.template_id, "the file keeps the template after a real JSON round trip")
		_check(loaded.random_event_id == run.random_event_id, "the file keeps the random event after JSON")
		_check(loaded.exploration.position == run.exploration.position, "the file keeps the position after JSON")
		_check(loaded.coins == 12, "the file keeps the coins after JSON")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _test_templates_rebuild_identically() -> void:
	for template_id in FactoryScript.template_ids():
		var first := FactoryScript.build(template_id)
		var second := FactoryScript.build(template_id)
		var same: bool = true
		if first.places.size() != second.places.size():
			same = false
		else:
			for index in range(first.places.size()):
				if first.places[index].cell != second.places[index].cell:
					same = false
				if first.places[index].id != second.places[index].id:
					same = false
		_check(same, "template %d rebuilds to the same layout every time" % template_id)
