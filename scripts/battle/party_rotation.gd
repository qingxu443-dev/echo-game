class_name PartyRotation
extends RefCounted

## Actual battle scenes use a single deployed unit; reserve actors retain their
## own combat state but cannot block, receive damage, assist or be targeted.
static func setup(battle, roster: Array[String]) -> void:
	battle.party_order.assign(roster)
	var state = battle.run_state
	var preferred: String = state.party_owner_id if state != null else roster[0]
	for actor_id in roster:
		var actor = battle.actors[actor_id]
		actor.is_benched = true
		if state != null and state.party_retired.has(actor_id): retire(battle, actor)
	if not roster.has(preferred) or not battle.actors[preferred].is_available():
		preferred = ""
		for actor_id in roster:
			if battle.actors[actor_id].is_available():
				preferred = actor_id
				break
	if not preferred.is_empty():
		battle.actors[preferred].cell = battle.actors[roster[0]].cell
		battle.active_character_id = preferred
		battle.actors[preferred].is_benched = false
		PartyLoadout.select_role(battle, preferred)
	battle.deploy_order.assign([preferred] if not preferred.is_empty() else [])


## CONTRACT: _test_single_presence_and_cost
static func request_switch(battle, actor_id: String) -> bool:
	if battle.phase != battle.BattlePhase.PLAYER or actor_id == battle.active_character_id: return false
	var actor = battle.actors.get(actor_id)
	if actor == null or actor.team != "player" or not actor.is_available(): return false
	if not battle.ap.spend(1): return false
	activate(battle, actor_id, false)
	return true


## CONTRACT: _test_independent_combat_state
## CONTRACT: _test_locked_attack_after_switch
static func activate(battle, actor_id: String, automatic: bool) -> void:
	var outgoing = battle.get_active_character()
	var incoming = battle.actors[actor_id]
	var previous: String = battle.active_character_id
	PartyLoadout.capture(battle)
	if outgoing != null:
		incoming.cell = outgoing.cell
		outgoing.is_benched = true
	incoming.is_benched = false
	battle.active_character_id = actor_id
	PartyLoadout.select_role(battle, actor_id)
	# Actor-locked attacks follow the deployed role at the same cell. Fixed
	# ground telegraphs keep their original area and charge, without rerolling.
	for intent in battle.intents:
		if intent.target_actor_id == previous: intent.target_actor_id = actor_id
	for enemy in battle.actors.values():
		if enemy.team == "enemy" and enemy.lock_target_id == previous: enemy.lock_target_id = actor_id
	battle._emit_event("party_switched", actor_id, previous, "automatic=%s" % str(automatic))


static func retire(battle, actor) -> void:
	actor.health = 0
	actor._is_defeated = true
	actor._is_downed = false
	actor.is_benched = true
	if battle.run_state != null and not battle.run_state.party_retired.has(actor.actor_id):
		battle.run_state.party_retired.append(actor.actor_id)


## CONTRACT: _test_lethal_area_and_replacement
static func ensure_active(battle) -> void:
	if not battle.single_active_party: return
	var current = battle.get_active_character()
	if current != null and current.is_available(): return
	if current != null: retire(battle, current)
	var start: int = battle.party_order.find(battle.active_character_id)
	for offset in range(1, battle.party_order.size() + 1):
		var actor_id: String = battle.party_order[posmod(start + offset, battle.party_order.size())]
		if battle.actors[actor_id].is_available():
			activate(battle, actor_id, true)
			if battle.phase == battle.BattlePhase.DEPLOY: battle.deploy_order.assign([actor_id])
			return
	PartyLoadout.capture(battle)


static func migrate_session(battle) -> void:
	# Old simultaneous-party saves retain every role's HP. Only the previously
	# commanded living role remains deployed after migration.
	battle.single_active_party = true
	var roster: Array[String] = []
	for actor in battle.actors.values():
		if actor.team != "player": continue
		roster.append(actor.actor_id)
		if battle.run_state != null and battle.run_state.party_owner_id.is_empty(): battle.run_state.party_owner_id = actor.actor_id
		actor.is_benched = actor.actor_id != battle.active_character_id
		if actor.health <= 0 or (battle.run_state != null and battle.run_state.party_retired.has(actor.actor_id)): retire(battle, actor)
		if battle.run_state != null and not battle.run_state.party_loadouts.has(actor.actor_id):
			PartyLoadout.adopt_actor(battle, actor)
	battle.party_order.assign(roster)
	PartyLoadout.select_role(battle, battle.active_character_id)
	ensure_active(battle)
	if battle.phase == battle.BattlePhase.DEPLOY:
		battle.deploy_order.assign([battle.active_character_id])
		battle.deploy_index = mini(battle.deploy_index, 1)
