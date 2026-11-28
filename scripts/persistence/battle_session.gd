class_name BattleSession
extends RefCounted

const VIEW_FIELDS: Array[String] = ["status_message", "selected_skill", "inventory_open", "inventory_page", "pending_rewards"]
const CONTROLLER_CONTAINERS: Array[String] = ["actors", "intents", "ap", "statuses", "ledger", "run_state"]


static func capture(view: Node) -> Dictionary:
	var battle: BattleController = view.controller
	var data := {
		"scene": "battle", "spring_mode": view.spring_mode, "level": view.current_level,
		"encounter_override_id": str(view.encounter_override.level_id) if view.encounter_override != null else "",
		"bridge": SpringBattleBridge.pending.duplicate(true),
		"parent_run": SpringBattleBridge.suspended_map.duplicate(true),
		"controller": SessionCodec.fields(battle, CONTROLLER_CONTAINERS),
		"run_state": SessionCodec.fields(view.run_state), "ap": SessionCodec.fields(battle.ap),
		"ledger": SessionCodec.fields(battle.ledger), "fx": SessionCodec.fields(view.fx),
		"camera": UiPalette.camera_quadrant, "actors": [], "intents": [], "statuses": [], "view": {},
		"loot_state": LootCatalog._rng.state, "loot_seed": LootCatalog._rng.seed,
	}
	for actor in battle.actors.values(): data.actors.append(SessionCodec.fields(actor))
	for intent in battle.intents: data.intents.append(SessionCodec.fields(intent))
	for statuses in battle.statuses._statuses_by_actor.values():
		for status in statuses.values(): data.statuses.append(SessionCodec.fields(status))
	for key in VIEW_FIELDS: data.view[key] = view.get(key)
	if view.has_method("custom_definition"): data["custom_level"] = view.custom_definition()
	return data


static func restore(view: Node, data: Dictionary) -> bool:
	if data.get("scene", "") != "battle" or not SessionSave.valid(data): return false
	view.spring_mode = bool(data.get("spring_mode", false))
	if data.has("custom_level"):
		CustomLevelBridge.design = CustomLevelData.from_dict(data.custom_level)
		view.encounter_override = CustomLevelBridge.design.encounter()
		view.levels.assign([view.encounter_override])
	elif view.spring_mode:
		SpringBattleBridge.pending = data.bridge.duplicate(true)
		SpringBattleBridge.suspended_map = data.parent_run.duplicate(true)
		SpringBattleBridge.restore_map = true
		var party_ids: Array[String] = []
		for character_id in data.bridge.get("character_ids", [SpringRun.HERO_CHARACTER_ID]):
			party_ids.append(str(character_id))
		view.levels.assign([SpringEncounterCatalog.build(StringName(str(data.bridge.encounter)), party_ids)])
	else:
		SpringBattleBridge.clear_pending()
		view.levels = LevelCatalog.create_prototype_levels()
		view.encounter_override = LevelCatalog.optional_encounter(StringName(str(data.get("encounter_override_id", ""))))
		if view.encounter_override != null: view.levels.assign([view.encounter_override])
	view.current_level = int(data.level)
	view.run_state = RunState.new()
	SessionCodec.apply_fields(view.run_state, data.run_state)
	var battle := BattleController.new()
	view.controller = battle
	battle.run_state = view.run_state
	view.add_child(battle)
	SessionCodec.apply_fields(battle, data.controller)
	SessionCodec.apply_fields(battle.ap, data.ap)
	SessionCodec.apply_fields(battle.ledger, data.get("ledger", {}))
	# Old finished snapshots were captured after BattleFlow paid mode rewards.
	if not data.get("ledger", {}).has("rewards_settled") and battle.phase == battle.BattlePhase.FINISHED:
		battle.ledger.rewards_settled = true
	# Older snapshots stored pressure counters outside the ledger.
	if not data.get("ledger", {}).has("pressure_sequence"):
		battle.ledger.pressure_sequence = int(data.get("pressure_sequence", 0))
		var refunds: Dictionary = data.get("pressure_refunds", {})
		battle.ledger.pressure_refund_turn = int(refunds.get("turn", -1))
		battle.ledger.pressure_refund_count = int(refunds.get("count", 0))
	for row in data.actors:
		var actor := BattleActor.new(str(row.actor_id), str(row.team), row.cell, int(row.max_health))
		SessionCodec.apply_fields(actor, row)
		battle.actors[actor.actor_id] = actor
	for row in data.intents:
		var intent := BattleIntent.new(str(row.intent_id), str(row.source_actor_id), str(row.action_id), int(row.target_mode))
		SessionCodec.apply_fields(intent, row)
		battle.intents.append(intent)
	for row in data.get("statuses", []):
		var status := BattleStatus.new()
		SessionCodec.apply_fields(status, row)
		if not battle.statuses._statuses_by_actor.has(status.target_actor_id):
			battle.statuses._statuses_by_actor[status.target_actor_id] = {}
		battle.statuses._statuses_by_actor[status.target_actor_id][status.status_id] = status
	UiPalette.camera_quadrant = int(data.get("camera", 0))
	UiPalette.board_grid_size = battle.grid_size
	SessionCodec.apply_fields(view.fx, data.get("fx", {}))
	LootCatalog._rng.seed = int(data.get("loot_seed", 0))
	LootCatalog._rng.state = int(data.get("loot_state", 0))
	for key in VIEW_FIELDS:
		if data.get("view", {}).has(key):
			if key == "pending_rewards": view.pending_rewards.assign(data.view[key])
			else: view.set(key, data.view[key])
	battle.battle_event.connect(view._on_battle_event)
	battle.battle_finished.connect(view._on_battle_finished)
	view.skill_bar = preload("res://scripts/ui/skill_bar_view.gd").build_entries(battle)
	view.queue_redraw()
	return true
