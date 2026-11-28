class_name BattleThreatPreview
extends RefCounted

## Projects announced actions for one cell, holding the board fixed. Keeping a
## private defender lets consecutive hits share the same shield, health and
## defence-penalty state. Movement interceptions and reactive attacks have
## separate caution markers and are resolved on the live board.


static func defender_at(battle, cell: Vector2i) -> BattleActor:
	var hero = battle.get_active_character()
	for actor in battle.actors.values():
		if actor.is_alive() and actor.cell == cell:
			if actor.team != "player":
				return null
			hero = actor
			break
	if hero == null or not hero.is_alive():
		return null
	var projected := BattleActor.new(
		hero.actor_id, hero.team, cell, hero.max_health, hero.archetype,
		hero.attack, hero.defense, hero.magic_resistance
	)
	projected.health = hero.health
	projected.shield = hero.shield
	projected.defense_penalty = hero.defense_penalty
	projected.attenuation_k = hero.attenuation_k
	return projected


static func targets_cell(intent, defender: BattleActor, cell: Vector2i) -> bool:
	if intent.target_mode == BattleIntent.TargetMode.ACTOR_LOCKED:
		return defender != null and intent.target_actor_id == defender.actor_id
	if intent.target_mode == BattleIntent.TargetMode.AREA_LOCKED:
		return intent.affected_cells.has(cell)
	return intent.target_cell == cell


static func apply(battle, intent, defender: BattleActor) -> int:
	if defender == null:
		return intent.damage
	var source = battle.get_actor(intent.source_actor_id)
	if not defender.is_alive() or source == null or not source.is_alive():
		return 0
	if intent.action_id == "rot_curse":
		var origin: Vector2i = source.cell if intent.move_path.is_empty() else intent.move_path.back()
		if IntentResolver.rot_curse_position_failure(battle, source.actor_id, origin, defender.cell).is_empty():
			defender.defense_penalty = maxi(defender.defense_penalty, intent.damage)
		return 0
	if intent.action_id == "lock_on":
		return 0
	return int(defender.apply_damage_with_result(intent.damage, intent.damage_type)["health_damage"])
