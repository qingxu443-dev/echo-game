extends "res://tests/framework/test_case.gd"

const Scene = preload("res://scenes/main/main.tscn")
var shell: Node


func _run() -> void:
	shell = root.get_node_or_null("GameShell")
	if shell != null: shell.animations_enabled = false
	SessionSave.path_override = "user://party_rotation_%d.json" % OS.get_process_id()
	SessionSave.clear()
	_test_single_presence_and_cost()
	_test_independent_combat_state()
	_test_locked_attack_after_switch()
	_test_lethal_area_and_replacement()
	_test_hazard_replacement()
	_test_stage_healing_and_restart()
	await _test_portraits_and_checkpoint()
	await _test_run_retirement_and_equipment()
	await _test_surviving_equipment_next_fight()
	await _test_legacy_checkpoint()
	await _test_all_dead_on_entry()
	SessionSave.clear()
	SessionSave.path_override = ""
	SpringBattleBridge.clear_pending()
	SpringBattleBridge.suspended_map = {}
	if shell != null:
		for voice in shell.audio.voices: voice.stop()
	await create_timer(0.05, true).timeout


func _battle(deploy: bool = false) -> BattleController:
	var battle := BattleController.new()
	battle.single_active_party = true
	battle.run_state = RunState.new()
	root.add_child(battle)
	_check(battle.start_encounter(Vector2i(1, 5), [Vector2i(3, 5)], [], [], ["sevrin", "sakura", "dest_lee"], [Vector2i(2, 6), Vector2i(3, 6)], [], 0, [], deploy), "three-role rotation encounter starts")
	battle.beacons.clear()
	return battle


func _present(battle) -> Array[String]:
	var ids: Array[String] = []
	for actor in battle.actors.values():
		if actor.team == "player" and actor.blocks_cell(): ids.append(actor.actor_id)
	return ids


func _test_single_presence_and_cost() -> void:
	var battle := _battle()
	_check(_present(battle) == ["sevrin"], "only the front character occupies the board")
	_check(battle.get_switchable_characters() == ["sevrin", "sakura", "dest_lee"], "healthy reserves remain eligible in formation order")
	for id in ["sakura", "dest_lee"]:
		var actor = battle.actors[id]
		_check(actor.is_available() and not actor.is_alive(), "a reserve is available but outside field combat: " + id)
		_check(not BoardObjectsView.is_actor_visible(battle, actor), "reserve has no board sprite: " + id)
		_check(not battle.get_occupied_cells().has(actor.cell), "reserve original spawn tile is free: " + id)
		var hp: int = actor.health
		battle._apply_damage(id, 10000, "vanguard_00", "probe")
		_check(actor.health == hp, "reserve cannot be damaged through stale targeting: " + id)
	var charge: int = battle.actors.vanguard_00.skill_charge
	battle.actors.vanguard_00.skill_charge = 0
	_check(battle.request_switch_character("sakura"), "first paid switch succeeds")
	_check(battle.ap.current == 2 and battle.actors.vanguard_00.skill_charge == 1, "switch pays exactly one AP through the normal enemy-charge ledger")
	_check(_present(battle) == ["sakura"] and battle.actors.sakura.cell == Vector2i(1, 5), "replacement inherits the occupied tile, not the reserve spawn")
	_check(not battle.request_switch_character("sakura") and battle.ap.current == 2, "clicking the current character never spends AP")
	_check(not battle.request_switch_character("vanguard_00") and not battle.request_switch_character("missing") and battle.ap.current == 2, "invalid or enemy portraits cannot spend AP")
	_check(battle.request_switch_character("dest_lee") and battle.request_switch_character("sevrin"), "each successive switch uses the same action")
	_check(battle.ap.current == 0 and not battle.request_switch_character("sakura"), "zero AP prevents further switching")
	_check(_present(battle) == ["sevrin"], "a rejected switch leaves the active field character intact")
	for phase in [battle.BattlePhase.ENEMY, battle.BattlePhase.FINISHED, battle.BattlePhase.DEPLOY]:
		battle.phase = phase
		battle.ap.reset()
		_check(not battle.request_switch_character("sakura") and battle.ap.current == 3, "switching is forbidden outside the player phase: %d" % phase)
	battle.actors.vanguard_00.skill_charge = charge
	battle.queue_free()


func _test_independent_combat_state() -> void:
	var battle := _battle()
	var hero = battle.actors.sevrin
	hero.health = 777
	hero.shield = 123
	hero.ultimate_energy = 4
	hero.defense_penalty = 17
	battle.statuses.apply_status(&"absolute_guard", "sevrin", "sevrin", 1, 1, -1)
	var reserve = battle.actors.sakura
	reserve.health = 555
	reserve.resource_current = 3
	reserve.ultimate_energy = 2
	_check(battle.request_switch_character("sakura"), "switch wounded front to wounded reserve")
	_check(reserve.health == 555 and reserve.resource_current == 3 and reserve.ultimate_energy == 2, "incoming role retains its own HP, signature resource and energy")
	_check(battle.get_absolute_guardian().is_empty(), "benched guardian cannot redirect enemy attacks")
	_check(battle.request_switch_character("sevrin"), "return to the original front")
	_check(hero.health == 777 and hero.shield == 123 and hero.ultimate_energy == 4 and hero.defense_penalty == 17, "switching preserves HP, shield, energy and penalties without refreshing them")
	_check(battle.statuses.has_status("sevrin", &"absolute_guard") and battle.get_absolute_guardian() == "sevrin", "the returning actor retains its own live status")
	_check(reserve.health == 555 and reserve.resource_current == 3, "outgoing actor state stays independent")
	battle.queue_free()


func _test_locked_attack_after_switch() -> void:
	var battle := _battle()
	var intent := BattleIntent.new("locked", "vanguard_00", "locked_shot", BattleIntent.TargetMode.ACTOR_LOCKED, "sevrin", Vector2i(1, 5), [], 100, 0, "true")
	battle.intents.assign([intent])
	battle.actors.vanguard_00.lock_target_id = "sevrin"
	_check(battle.request_switch_character("sakura"), "switch while an actor lock is telegraphed")
	_check(intent.target_actor_id == "sakura" and battle.actors.vanguard_00.lock_target_id == "sakura", "both telegraph and archer lock follow the deployed character")
	_check(intent.damage == 100 and intent.target_cell == Vector2i(1, 5), "switching never rerolls damage or the telegraphed location")
	var reserve_hp: int = battle.actors.sevrin.health
	var front_hp: int = battle.actors.sakura.health
	IntentResolver._locked_shot(battle, intent)
	_check(battle.actors.sakura.health == front_hp - 100 and battle.actors.sevrin.health == reserve_hp, "the enemy hits the new front and leaves the reserve unharmed")
	_check(intent.state == BattleIntent.IntentState.RESOLVED, "the locked shot actually resolves rather than silently canceling")
	battle.queue_free()


func _test_lethal_area_and_replacement() -> void:
	var battle := _battle()
	var cell: Vector2i = battle.actors.sevrin.cell
	var next_hp: int = battle.actors.sakura.health
	var intent := BattleIntent.new("lethal", "vanguard_00", "ground_pulse", BattleIntent.TargetMode.AREA_LOCKED, "", cell, [cell], 999999, 0, "true")
	battle.intents.assign([intent])
	IntentResolver._area_attack(battle, intent)
	_check(battle.active_character_id == "sakura" and _present(battle) == ["sakura"], "a lethal area automatically deploys the next role at once")
	_check(battle.actors.sakura.health == next_hp, "one area hit cannot also kill the replacement arriving during its resolution")
	_check(battle.ap.current == 3, "death replacement does not consume player AP")
	_check(battle.actors.sevrin.is_defeated() and not battle.actors.sevrin.is_downed(), "the fallen role is retired, without a revivable board body")
	_check(not battle.actors.sevrin.revive(100) and not battle.request_switch_character("sevrin"), "neither revival nor switching can reuse a retired role")
	_check(battle.run_state.party_retired == ["sevrin"], "retirement is recorded in run carry")
	battle.phase = battle.BattlePhase.ENEMY
	battle._apply_damage("sakura", 999999, "vanguard_00", "next_enemy", "true")
	_check(battle.active_character_id == "dest_lee" and _present(battle) == ["dest_lee"], "another enemy can kill the new front and trigger the next formation member")
	battle._apply_damage("dest_lee", 999999, "vanguard_00", "last_enemy", "true")
	battle._check_battle_end()
	_check(battle.battle_result == "defeat" and _present(battle).is_empty(), "losing the last eligible character ends the battle")
	_check(battle.run_state.party_retired == ["sevrin", "sakura", "dest_lee"], "every death is remembered in formation order")
	battle.queue_free()
	var wrapped := _battle()
	_check(wrapped.request_switch_character("dest_lee"), "choose the last formation member first")
	wrapped._apply_damage("dest_lee", 999999, "vanguard_00", "probe", "true")
	_check(wrapped.active_character_id == "sevrin", "automatic succession wraps to the first surviving formation member")
	wrapped.queue_free()


func _test_hazard_replacement() -> void:
	var battle := _battle()
	var cell: Vector2i = battle.actors.sevrin.cell
	HazardField.spawn(battle, [cell], "blight", 999999, "vanguard_00", 3, "true")
	var hp: int = battle.actors.sakura.health
	HazardField.tick_player_turn_start(battle)
	_check(battle.active_character_id == "sakura" and battle.actors.sakura.health == hp, "one start-of-turn hazard tick does not cascade into newly arriving reserves")
	battle.queue_free()


func _test_stage_healing_and_restart() -> void:
	var battle := _battle()
	battle.actors.sevrin.health = 777
	PartyLoadout.capture(battle)
	battle.run_state.add_to_backpack(AtelierStash.recipe_by_id("item_dusk_potion").payload)
	battle.run_state.use_backpack_item(0, battle, battle.actors.sevrin)
	var hp: int = battle.actors.sevrin.health
	_check(hp > 777, "a shared-bag consumable heals the deployed role")
	_check(battle.start_encounter(Vector2i(1, 5), [Vector2i(3, 5)], [], [], ["sevrin", "sakura", "dest_lee"], [Vector2i(2, 6), Vector2i(3, 6)]), "advance to the next encounter with the same run state")
	_check(battle.actors.sevrin.health == hp, "stage advance captures recent item healing rather than restoring an earlier role snapshot")
	battle.run_state.reset()
	_check(battle.start_encounter(Vector2i(1, 5), [Vector2i(3, 5)]), "start a fresh run using the same controller")
	_check(battle.actors.sevrin.health == 3200 and battle.run_state.party_retired.is_empty(), "restart does not recapture HP or death records from the discarded run")
	battle.queue_free()


func _run_party() -> SpringRun:
	var run := SpringRun.begin(3)
	run.party_character_ids.assign(["sevrin", "sakura", "dest_lee"])
	run.hero_health = 1600
	run.party_vitals = {"sevrin": {"health": 1600, "max_health": 3200}, "sakura": {"health": 1050, "max_health": 2100}, "dest_lee": {"health": 800, "max_health": 1650}}
	return run


func _scene(run: SpringRun):
	_check(SpringBattleBridge.prepare(run, &"B001", &"battle_1"), "prepare the actual map-to-battle handshake")
	var view = Scene.instantiate()
	root.add_child(view)
	_check(view.controller.deploy_order.size() == 1, "actual battle scene offers just one deployment slot")
	_check(view.controller.request_deploy(view.controller.get_active_character().cell) and view.controller.request_begin_battle(), "confirm the single front character's deployment")
	return view


func _test_portraits_and_checkpoint() -> void:
	var view = _scene(_run_party())
	var position := PartyPortraitView.card_rect(1).get_center()
	_check(PartyPortraitView.hit(view.controller, position) == "sakura", "portrait hit geometry selects the intended teammate")
	view.selected_skill = 0
	view._handle_tap(position)
	_check(view.controller.active_character_id == "sakura" and view.controller.ap.current == 2, "clicking the actual portrait performs one paid switch")
	_check(view.selected_skill == -1 and str(view.skill_bar[0].id).begins_with("sakura"), "changing role cancels stale targets and rebuilds the correct skill bar")
	_check(view.fx.party_switch_left > 0 and view.fx.party_switch_id == "sakura", "switching starts a finite entry animation")
	view._handle_tap(PartyPortraitView.card_rect(2).get_center())
	_check(view.controller.active_character_id == "sakura" and view.controller.ap.current == 2, "repeated portrait clicks during entry animation do not reenter or double-charge")
	view.controller.actors.sakura.shield = 321
	view.controller.actors.sakura.resource_current = 3
	_check(PlaySession.save(view) and SessionSave.stage() == SessionSave.BATTLE_PATH, "a paused switching animation can be saved and staged")
	view.queue_free()
	await process_frame
	var resumed = Scene.instantiate()
	root.add_child(resumed)
	_check(_present(resumed.controller) == ["sakura"] and resumed.controller.ap.current == 2, "resuming preserves the sole active role and already paid AP")
	_check(resumed.controller.actors.sakura.health == 1050 and resumed.controller.actors.sakura.shield == 321 and resumed.controller.actors.sakura.resource_current == 3, "checkpoint preserves individual combat state")
	resumed.fx.advance(1.0, resumed.controller)
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.physical_keycode = KEY_TAB
	key.pressed = true
	resumed._input(key)
	_check(resumed.controller.active_character_id == "dest_lee" and resumed.controller.ap.current == 1, "resumed animation expires and the real Tab input performs the next paid switch")
	var invalid := BattleSession.capture(resumed)
	invalid.run_state.party_loadouts.sakura.hero_health = "bad"
	_check(not SessionSave.valid(invalid), "malformed nested role state is rejected before restore")
	resumed.queue_free()
	await process_frame
	SpringBattleBridge.clear_pending()


func _test_run_retirement_and_equipment() -> void:
	var run := _run_party()
	var view = _scene(run)
	var battle: BattleController = view.controller
	view.run_state.add_to_backpack({"id": &"rotation_armor", "kind": "armor", "name": "轮换护甲", "max_health": 400})
	view.run_state.equip_from_backpack(0, battle.actors.sevrin)
	_check(battle.request_switch_character("sakura"), "switch away from an equipped character")
	_check(view.run_state.equipped_armor.is_empty() and battle.actors.sevrin.max_health == 3600, "worn gear stays on its owner without entering the shared backpack")
	_check(battle.request_switch_character("sevrin") and view.run_state.equipped_armor.get("id") == &"rotation_armor", "returning restores the same equipment slot")
	_check(battle.actors.sevrin.health == 2000, "switching itself does not heal the equipped character")
	battle._apply_damage("sevrin", 999999, "vanguard_00", "probe", "true")
	_check(battle.active_character_id == "sakura", "death replaces an equipped front with the next role")
	PartyLoadout.capture(battle)
	var vitals := {}
	for actor in battle.actors.values():
		if actor.team == "player": vitals[actor.actor_id] = {"health": actor.health, "max_health": actor.max_health}
	var result := {"result": "victory", "kind": "battle", "place": "battle_1", "hero_health": 1050, "hero_max_health": 2100, "party_vitals": vitals, "carry": SpringBattleBridge.pack_carry(view.run_state)}
	SpringBattleBridge.settle_result(run, result)
	_check(run.hero_character_id == "sakura" and run.hero_health == 1050, "map scalar vitality now belongs to the surviving active role")
	run = SpringRun.from_dict(run.to_dict())
	_check(run != null and run.battle_carry.party_retired == ["sevrin"], "map JSON roundtrip preserves permanent retirement")
	view.queue_free()
	await process_frame
	var next = _scene(run)
	_check(next.controller.active_character_id == "sakura" and _present(next.controller) == ["sakura"], "next fight starts the surviving role without deploying the dead leader")
	_check(next.controller.actors.sevrin.health == 0 and not next.controller.request_switch_character("sevrin"), "death remains permanent across fights")
	_check(next.run_state.equipped_armor.is_empty() and next.run_state.backpack.is_empty(), "dead character equipment is neither cloned onto the replacement nor duplicated into the bag")
	_check(next.controller.actors.sakura.health == run.hero_health, "map reward healing enters the next fight on the correct role")
	for id in ["sakura", "dest_lee"]: next.controller._apply_damage(id, 999999, "vanguard_00", "probe", "true")
	next.controller._check_battle_end()
	PartyLoadout.capture(next.controller)
	result.result = "defeat"
	result.hero_health = 0
	result.carry = SpringBattleBridge.pack_carry(next.run_state)
	result.party_vitals = {}
	for actor in next.controller.actors.values():
		if actor.team == "player": result.party_vitals[actor.actor_id] = {"health": actor.health, "max_health": actor.max_health}
	var outcome := SpringBattleBridge.settle_result(run, result)
	_check(outcome.finished_run and not outcome.needs_revive and run.exploration.finished and run.hero_health == 0, "all retired ends the run without a resurrection prompt or phantom HP")
	var supplies: int = run.supplies
	_check(not SpringBattleBridge.can_continue(run) and not SpringBattleBridge.continue_run(run).ok and run.supplies == supplies, "the old supply continuation cannot resurrect a retired party")
	next.queue_free()
	await process_frame


func _test_legacy_checkpoint() -> void:
	var view = _scene(_run_party())
	view.run_state.add_to_backpack({"id": &"legacy_armor", "kind": "armor", "name": "旧护甲", "max_health": 400})
	view.run_state.equip_from_backpack(0, view.controller.actors.sevrin)
	var data := BattleSession.capture(view)
	# An old free command switch did not move the leader's equipment ownership.
	data.controller.active_character_id = "sakura"
	data.controller.erase("single_active_party")
	data.controller.erase("party_order")
	data.run_state.erase("party_loadouts")
	data.run_state.erase("party_retired")
	data.run_state.erase("party_owner_id")
	for row in data.actors: row.erase("is_benched")
	_check(SessionSave.valid(data), "pre-rotation checkpoints remain loadable")
	view.queue_free()
	await process_frame

	SessionSave.pending = data
	var resumed = Scene.instantiate()
	root.add_child(resumed)
	_check(resumed.controller.single_active_party and _present(resumed.controller) == ["sakura"], "legacy checkpoint migrates to its previously commanded role")
	_check(resumed.run_state.base_max_health == 2100, "legacy migration reconstructs the reserve's own equipment base")
	_check(resumed.run_state.equipped_armor.is_empty(), "old leader equipment is not reassigned to the commanded teammate")
	_check(resumed.controller.request_switch_character("sevrin") and resumed.controller.actors.sevrin.health == 1600, "migrated roles retain HP and can be switched normally")
	_check(resumed.run_state.equipped_armor.get("id") == &"legacy_armor", "old leader equipment remains on the old leader")
	resumed.queue_free()
	await process_frame


func _test_surviving_equipment_next_fight() -> void:
	var run := _run_party()
	var view = _scene(run)
	var battle: BattleController = view.controller
	view.run_state.add_to_backpack({"id": &"survivor_armor", "kind": "armor", "name": "继承护甲", "max_health": 400})
	view.run_state.equip_from_backpack(0, battle.actors.sevrin)
	_check(battle.request_switch_character("sakura"), "leave an equipped survivor on the bench before settlement")
	PartyLoadout.capture(battle)
	var vitals := {}
	for actor in battle.actors.values():
		if actor.team == "player": vitals[actor.actor_id] = {"health": actor.health, "max_health": actor.max_health}
	SpringBattleBridge.settle_result(run, {"result": "victory", "kind": "elite", "place": "elite_1", "hero_health": 1050, "hero_max_health": 2100, "party_vitals": vitals, "carry": SpringBattleBridge.pack_carry(view.run_state)})
	run = SpringRun.from_dict(run.to_dict())
	view.queue_free()
	await process_frame
	var next = _scene(run)
	_check(next.controller.active_character_id == "sakura" and next.controller.actors.sevrin.health == 2000, "cross-fight snapshot preserves the active choice and the equipped reserve's wounded HP")
	_check(next.controller.request_switch_character("sevrin"), "a healthy equipped reserve can deploy next fight")
	_check(next.run_state.equipped_armor.get("id") == &"survivor_armor" and next.controller.actors.sevrin.max_health == 3600, "worn armor and its maximum survive map JSON without duplication")
	_check(next.run_state.backpack.is_empty() and next.run_state.party_loadouts.sakura.equipped_armor.is_empty(), "one equipped item never appears in another role or the shared bag")
	next.run_state.unequip_slot("armor", next.controller.actors.sevrin)
	_check(next.controller.actors.sevrin.max_health == 3200 and next.controller.actors.sevrin.health == 1600, "removing inherited armor symmetrically reclaims HP and maximum")
	next.queue_free()
	await process_frame


func _test_all_dead_on_entry() -> void:
	var run := _run_party()
	for row in run.party_vitals.values(): row.health = 0
	_check(SpringBattleBridge.prepare(run, &"B001", &"battle_1"), "prepare a legacy snapshot with no survivors")
	var view = Scene.instantiate()
	root.add_child(view)
	_check(view.controller.phase == BattleController.BattlePhase.FINISHED and view.controller.battle_result == "defeat", "all-dead legacy entry finishes without a deployment softlock")
	_check(_present(view.controller).is_empty() and view.run_state.party_retired.size() == 3, "all-dead entry has no phantom body or usable dead portrait")
	view.queue_free()
	await process_frame
