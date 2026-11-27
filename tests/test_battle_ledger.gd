extends "res://tests/framework/test_case.gd"

## 架构 #2 的契约钉子：机制记账从 BattleController 平铺字段收编到 BattleLedger。
##
## 锁定四件事：
##   1. 11 个字段的名字、类型与默认值与旧版逐字一致
##   2. reset_for_encounter 清空全部账本，包含旧版藏在 roster 循环里的 free_move
##   3. reset_for_player_turn 只清"每回合一次"的绝对防御反击账
##   4. controller.ledger 是唯一实例，start_encounter 会走统一重置

const ControllerScript = preload("res://scripts/battle/battle_controller.gd")
const LevelCatalogScript = preload("res://scripts/battle/level_catalog.gd")

const DICT_KEYS: Array[String] = [
	"hazard_trigger_turn",
	"summon_last_used_turn",
	"oath_shield_expiry_turn",
	"oath_shield_revived",
	"oath_vow_triggered_intents",
	"absolute_guard_hit_intents",
	"absolute_guard_countered_enemies",
	"resource_gain_turn",
	"resource_gain_count",
	"echo_return_gain_turn",
]


func _run() -> void:
	_test_defaults()
	_test_snapshot_contract()
	_test_reset_for_encounter()
	_test_reset_for_player_turn()
	_test_controller_owns_one_ledger()
	_test_start_encounter_resets_ledger()


func _test_defaults() -> void:
	var ledger := BattleLedger.new()
	for key in DICT_KEYS:
		var value = ledger.get(key)
		_check(value is Dictionary, "ledger field is a dictionary: %s" % key)
		_check((value as Dictionary).is_empty(), "ledger field starts empty: %s" % key)
	_check(ledger.free_move_used_turn == -1, "free move starts at -1")


func _test_snapshot_contract() -> void:
	var ledger := BattleLedger.new()
	ledger.resource_gain_count["sakura"] = 2
	ledger.free_move_used_turn = 3
	var snap: Dictionary = ledger.snapshot()
	for key in DICT_KEYS:
		_check(snap.has(key), "snapshot keeps field: %s" % key)
	_check(snap.has("free_move_used_turn"), "snapshot keeps free_move_used_turn")
	_check(int(snap["resource_gain_count"]["sakura"]) == 2, "snapshot carries live values")
	_check(int(snap["free_move_used_turn"]) == 3, "snapshot carries the free-move turn")
	(snap["resource_gain_count"] as Dictionary).erase("sakura")
	_check(int(ledger.resource_gain_count["sakura"]) == 2, "snapshot does not alias the live ledger")


func _test_reset_for_encounter() -> void:
	var ledger := BattleLedger.new()
	for key in DICT_KEYS:
		(ledger.get(key) as Dictionary)[key] = true
	ledger.free_move_used_turn = 7
	ledger.reset_for_encounter()
	for key in DICT_KEYS:
		_check((ledger.get(key) as Dictionary).is_empty(), "encounter reset clears %s" % key)
	_check(ledger.free_move_used_turn == -1, "encounter reset clears free move")


func _test_reset_for_player_turn() -> void:
	var ledger := BattleLedger.new()
	for key in DICT_KEYS:
		(ledger.get(key) as Dictionary)[key] = true
	ledger.free_move_used_turn = 4
	ledger.reset_for_player_turn()
	_check(ledger.absolute_guard_countered_enemies.is_empty(), "turn reset clears countered enemies")
	_check(not ledger.hazard_trigger_turn.is_empty(), "turn reset keeps cross-turn hazard ledger")
	_check(not ledger.summon_last_used_turn.is_empty(), "turn reset keeps summon cooldown ledger")
	_check(not ledger.oath_shield_expiry_turn.is_empty(), "turn reset keeps oath shield ledger")
	_check(not ledger.resource_gain_count.is_empty(), "turn reset keeps resource ledger")
	_check(ledger.free_move_used_turn == 4, "turn reset keeps the free-move marker")


func _fresh_controller() -> BattleController:
	var controller = ControllerScript.new()
	root.add_child(controller)
	var level: EncounterDefinition = LevelCatalogScript.create_prototype_levels()[0]
	controller.start_encounter(level.player_cell, level.enemy_cells, level.obstacles, level.enemy_archetypes, level.character_ids, [], level.chest_items)
	return controller


func _test_controller_owns_one_ledger() -> void:
	var controller := _fresh_controller()
	_check(controller.ledger is BattleLedger, "controller exposes a BattleLedger")
	var first = controller.ledger
	controller.ledger.resource_gain_count["hero"] = 5
	_check(first == controller.ledger, "ledger is a stable instance on the controller")
	_check(int(controller.ledger.resource_gain_count["hero"]) == 5, "ledger is writable through the controller")


func _test_start_encounter_resets_ledger() -> void:
	var controller := _fresh_controller()
	controller.ledger.summon_last_used_turn["hunter"] = 2
	controller.ledger.oath_shield_revived["hero"] = true
	controller.ledger.free_move_used_turn = 2
	var level: EncounterDefinition = LevelCatalogScript.create_prototype_levels()[0]
	var started: bool = controller.start_encounter(level.player_cell, level.enemy_cells, level.obstacles, level.enemy_archetypes, level.character_ids, [], level.chest_items)
	_check(started, "second encounter starts")
	_check(controller.ledger.summon_last_used_turn.is_empty(), "start clears summon ledger")
	_check(controller.ledger.oath_shield_revived.is_empty(), "start clears revival ledger")
	_check(controller.ledger.free_move_used_turn == -1, "start clears the free-move marker")
