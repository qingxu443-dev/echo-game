extends "res://tests/framework/test_case.gd"

const BattleScene = preload("res://scenes/main/main.tscn")
const MapScript = preload("res://scripts/spring/spring_map_view.gd")
const WALLET := "user://coordination-wallet.json"
const CHECKPOINT := "user://coordination-map.json"

func _run() -> void:
	_test_mode_rewards()
	await _test_map_flow_failures()
	_test_named_input()
	_test_skill_source()
	await _test_payload_boundaries()
	DirAccess.remove_absolute(WALLET)
	DirAccess.remove_absolute(CHECKPOINT)

func _battle() -> BattleController:
	var battle := BattleController.new()
	root.add_child(battle)
	battle.start_encounter(Vector2i(3, 3), [Vector2i(4, 3)])
	return battle

func _test_mode_rewards() -> void:
	DirAccess.remove_absolute(WALLET)
	AtelierStash.save_state({"shards": 20, "loadout": []}, WALLET)
	var battle := _battle()
	_check(not BattleRewards.settle(battle, false, WALLET), "unfinished fight cannot award meta currency")
	battle.get_actor("vanguard_00").health = 1
	_check(battle.request_skill(&"oathblade", "vanguard_00"), "standalone rules finish a normal fight")
	_check(int(AtelierStash.read_state(WALLET).shards) == 20, "standalone battle does not write a mode wallet")
	_check(BattleRewards.settle(battle, true, WALLET), "spring mode delegates rewards to spring settlement")
	_check(int(AtelierStash.read_state(WALLET).shards) == 20, "spring adapter does not also pay tutorial shards")
	_check(BattleRewards.settle(battle, false, WALLET), "owning tutorial mode can award the result")
	_check(int(AtelierStash.read_state(WALLET).shards) == 50, "tutorial victory awards the existing thirty shards")
	_check(BattleRewards.settle(battle, false, WALLET) and int(AtelierStash.read_state(WALLET).shards) == 50, "duplicate callback cannot pay twice")
	battle.start_encounter(Vector2i(3, 3), [Vector2i(4, 3)])
	battle.get_active_character().apply_damage(100000, "true")
	battle._check_battle_end()
	_check(not BattleRewards.settle(battle, false, "user://coordination-missing-parent/wallet.json") and not battle.ledger.rewards_settled, "failed write keeps settlement retryable")
	_check(BattleRewards.settle(battle, false, WALLET) and int(AtelierStash.read_state(WALLET).shards) == 65, "retry pays defeat reward once after a new encounter")
	battle.queue_free()

func _test_map_flow_failures() -> void:
	SpringBattleBridge.clear_pending()
	SpringBattleBridge.last_result = {}
	DirAccess.remove_absolute(CHECKPOINT)
	var map = MapScript.new()
	map.run = SpringRun.begin(909)
	map.save_path = CHECKPOINT
	map.atelier_save_path = WALLET
	root.add_child(map)
	map.set_process(false)
	var event_place = map.run.template.places_of(SpringPlace.Kind.EVENT)[0]
	map.event_place = event_place
	map.event_result = {"battle": "MISSING_ENCOUNTER"}
	map.event_open = true
	map.run.pending_event = {"place": String(event_place.id), "result": map.event_result}
	map._close_event()
	_check(map.event_open and not map.run.pending_event.is_empty(), "missing ambush keeps event open and pending")
	_check(not map.run.exploration.completed.has(event_place.id), "missing ambush cannot complete and discard its place")
	map.run.pending_event.clear()
	map.event_result = {}
	map.event_open = false
	var place = map.run.template.places_of(SpringPlace.Kind.BATTLE)[0]
	map.run.exploration.move_to(place.cell)
	var calls := {"count": 0}
	map.flow.scene_change = func(_tree, _path, _label): calls.count += 1; return ERR_CANT_OPEN
	map._start_battle(place, SpringBattleBridge.KIND_BATTLE)
	_check(calls.count == 1 and not SpringBattleBridge.has_pending(), "failed scene travel clears transient battle handoff")
	_check(FileAccess.file_exists(CHECKPOINT) and not map.run.exploration.completed.has(place.id), "failed travel preserves the saved run and unfinished fight")
	map.save_path = "user://coordination-missing-parent/checkpoint.json"
	map._start_battle(place, SpringBattleBridge.KIND_BATTLE)
	_check(calls.count == 1 and not SpringBattleBridge.has_pending(), "failed checkpoint prevents any scene travel")
	map.save_path = CHECKPOINT
	map.flow.scene_change = func(_tree, _path, _label): calls.count += 1; return OK
	map._start_battle(place, SpringBattleBridge.KIND_BATTLE)
	_check(SpringBattleBridge.has_pending() and calls.count == 2, "successful checkpoint enters battle through injected travel")
	SpringBattleBridge.clear_pending()
	map.queue_free()
	await process_frame

func _test_named_input() -> void:
	var saved := InputMap.action_get_events("echo_rotate_left")
	InputMap.action_erase_events("echo_rotate_left")
	var rebound := InputEventKey.new()
	rebound.keycode = KEY_R
	InputMap.action_add_event("echo_rotate_left", rebound)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_Q
	_check(InputRouter.translate(key).is_empty(), "old key follows InputMap removal")
	key.keycode = KEY_R
	_check(InputRouter.translate(key).get("step", 0) == -1, "rebound key reaches the same camera intent")
	key.echo = true
	_check(InputRouter.translate(key).is_empty(), "key-repeat cannot reenter an action")
	InputMap.action_erase_events("echo_rotate_left")
	for event in saved: InputMap.action_add_event("echo_rotate_left", event)
	var action := InputEventAction.new()
	action.action = "echo_skill_3"
	action.pressed = true
	_check(InputRouter.translate(action).get("index", -1) == 2, "named action can drive skill input without a hardcoded key")
	action.pressed = false
	_check(InputRouter.translate(action).is_empty(), "named release does not invoke an action")

func _test_payload_boundaries() -> void:
	var view = BattleScene.instantiate()
	root.add_child(view)
	view.set_process(false)
	var data := BattleSession.capture(view)
	var map = MapScript.new()
	map.run = SpringRun.begin(12)
	var original_run = map.run
	_check(not PlaySession.restore_map(map, data) and map.run == original_run, "map restore rejects battle payload before mutation")
	var old_battle = view.controller
	_check(not BattleSession.restore(view, {"scene": "map", "run": map.run.to_dict(), "ui": {}}) and view.controller == old_battle, "battle restore rejects map payload before mutation")
	data.actors[0].cell = Vector2i(-1, 0)
	_check(not SessionSave.valid(data), "out-of-board actor snapshot is rejected")
	data = BattleSession.capture(view)
	data.actors[0].health = int(data.actors[0].max_health) + 1
	_check(not SessionSave.valid(data), "snapshot cannot restore health above its maximum")
	BattleFlow.finish_battle(view.controller, "victory")
	data = BattleSession.capture(view)
	data.ledger.erase("rewards_settled")
	var restored = BattleScene.instantiate()
	root.add_child(restored)
	restored.controller.free()
	_check(BattleSession.restore(restored, data), "legacy finished snapshot still restores")
	_check(restored.controller.ledger.rewards_settled, "legacy finished snapshot cannot pay its old reward a second time")
	restored.queue_free()
	map.free()
	view.queue_free()
	await process_frame

func _test_skill_source() -> void:
	var skill := SkillRegistry.get_skill(&"sakura_falling_petals")
	var original_description: String = skill.description_zh
	var original_width: int = skill.shape_width
	var original_cost: int = skill.ap_cost
	skill.description_zh = "source fixture"
	skill.shape_width = 7
	skill.ap_cost = 3
	_check(SkillBarView.full_description(skill.skill_id).contains("source fixture"), "tooltip reads the live catalogue description")
	_check(SkillBarView.full_description(skill.skill_id).contains("3 AP"), "tooltip cost header reads the catalogue cost")
	_check(SkillBarView.hint_for(skill).contains("7×"), "short hint reads shape dimensions instead of a copied number")
	skill.description_zh = original_description
	skill.shape_width = original_width
	skill.ap_cost = original_cost
