class_name KnockbackService
extends RefCounted

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")

static func apply(battle, caster, target, direction: Vector2i, collision_damage: int, collision_events: bool = true) -> int:
	if direction == Vector2i.ZERO:
		return 0
	var step := Vector2i(signi(direction.x), signi(direction.y))
	var dest: Vector2i = target.cell + step
	var kills: int = 0

	# Out of bounds or stone pillar obstacle -> wall slam
	var out_of_bounds: bool = dest.x < 0 or dest.y < 0 or dest.x >= battle.grid_size.x or dest.y >= battle.grid_size.y
	if out_of_bounds or battle.blocked_cells.has(dest):
		var was_alive: bool = target.is_alive()
		battle._apply_damage(target.actor_id, collision_damage, caster.actor_id, "knockback_collision", "true")
		if was_alive and target.is_defeated():
			kills += 1
		if collision_events:
			battle._emit_event("knockback_collision", caster.actor_id, target.actor_id, "wall dest=%s" % str(dest))
		return kills

	# Relic Beacon occupies destination -> slam into beacon (never overlap it)
	if battle.beacons.has(dest) and int(battle.beacons[dest].get("health", 0)) > 0:
		var was_alive: bool = target.is_alive()
		battle._apply_damage(target.actor_id, collision_damage, caster.actor_id, "knockback_collision", "true")
		if was_alive and target.is_defeated():
			kills += 1
		battle.damage_beacon_at(dest, collision_damage, caster.actor_id, "knockback_collision")
		if collision_events:
			battle._emit_event("knockback_collision", caster.actor_id, target.actor_id, "beacon dest=%s" % str(dest))
		return kills

	# Another unit occupies destination -> unit-to-unit collision
	for other_id in battle.actors:
		var other = battle.actors[other_id]
		if other.actor_id == target.actor_id:
			continue
		if (other.is_alive() or other.is_downed()) and other.cell == dest:
			var t_alive: bool = target.is_alive()
			battle._apply_damage(target.actor_id, collision_damage, caster.actor_id, "knockback_collision", "true")
			if t_alive and target.is_defeated():
				kills += 1
			if other.is_alive():
				var o_alive: bool = other.is_alive()
				battle._apply_damage(other.actor_id, collision_damage, caster.actor_id, "knockback_collision", "true")
				if o_alive and other.is_defeated():
					kills += 1
			if collision_events:
				battle._emit_event("knockback_collision", caster.actor_id, target.actor_id, "unit=%s" % other.actor_id)
			return kills

	# Free cell -> knock target back cleanly and shift its active attack telegraphs with it
	target.cell = dest
	battle.interrupt_enemy_charge(target.actor_id, "knockback")
	shift_intents(battle, target.actor_id, step)
	battle._emit_event("actor_moved", target.actor_id, caster.actor_id, "knockback dest=%s" % str(dest))
	return kills


## Core displacement rule: displacing an enemy shifts its locked attack tiles
## by the same vector and rebuilds full area shapes cleanly from the new origin
## so edge-clipped cells recover and never overlap the enemy's own tile.
static func shift_intents(battle, actor_id: String, delta: Vector2i) -> void:
	var source = battle.get_actor(actor_id)
	for intent in battle.intents:
		if intent.source_actor_id != actor_id or intent.state != 0:
			continue
		if intent.action_id not in ["charged_strike", "aimed_shot", "light_shot", "ground_pulse", "echo_bolt", "basic_melee"]:
			continue
		intent.target_cell = intent.target_cell + delta
		if intent.action_id == "charged_strike" and source != null:
			var forward := Vector2i(signi(intent.target_cell.x - source.cell.x), signi(intent.target_cell.y - source.cell.y))
			var perp := Vector2i(-forward.y, forward.x)
			var rebuilt: Array[Vector2i] = []
			for depth in [1, 2]:
				var row_center: Vector2i = source.cell + forward * depth
				for side in [-1, 0, 1]:
					var c: Vector2i = row_center + perp * side
					if GridRulesScript.is_inside_bounds(c, battle.grid_size) and not battle.blocked_cells.has(c) and c != source.cell:
						rebuilt.append(c)
			intent.affected_cells = rebuilt
		elif intent.action_id == "aimed_shot" and source != null:
			var step := Vector2i(signi(intent.target_cell.x - source.cell.x), signi(intent.target_cell.y - source.cell.y))
			var rebuilt: Array[Vector2i] = []
			for offset in [-1, 0, 1]:
				var c: Vector2i = intent.target_cell + step * offset
				if GridRulesScript.is_inside_bounds(c, battle.grid_size) and not battle.blocked_cells.has(c) and c != source.cell:
					rebuilt.append(c)
			intent.affected_cells = rebuilt
		elif intent.action_id == "ground_pulse":
			var rebuilt: Array[Vector2i] = []
			for offset in [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var c: Vector2i = intent.target_cell + offset
				if GridRulesScript.is_inside_bounds(c, battle.grid_size):
					rebuilt.append(c)
			intent.affected_cells = rebuilt
		else:
			var shifted: Array[Vector2i] = []
			if GridRulesScript.is_inside_bounds(intent.target_cell, battle.grid_size) and not battle.blocked_cells.has(intent.target_cell):
				shifted.append(intent.target_cell)
			intent.affected_cells = shifted
