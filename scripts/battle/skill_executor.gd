class_name SkillExecutor
extends RefCounted

## Every player skill action, in one file.
##
## Each function validates first and only then mutates, so a rejected cast never
## spends AP, never applies a status and never emits a "resolved" event.
##
## The v1 kit (oathguard stance, echo counter, watchwall, the v1 judgment mark and
## oath severance) was removed with the systems only it produced: area effects,
## echo counter, oathguard mitigation and the intent-mark / exposed debuff.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")
const SkillRegistryScript = preload("res://scripts/battle/skill_registry.gd")

## Costs, ranges and damage multipliers are NOT repeated here. They live in the
## skill definitions, which is also what the skill bar reads - the two used to be
## separate constants, so editing the catalogue changed the hint and the target
## ring while the cast kept judging by the old numbers. Two sources for one rule
## is the bug; a test that compares the two would only paper over it.
##
## What stays here is what neither the catalogue nor the sheet has a field for:
## mechanism parameters that are not per-skill or per-character numbers.
##
## Ultimate energy is not one of them any more. Releasing an ultimate spends the
## caster's whole pool, and the pool's size lives on the character sheet, so
## neither this file nor the bar needs a number.
const OATH_SHIELD_BASE: int = 650
const OATH_SHIELD_VOW_FLAT: int = 100
const KNOCKBACK_COLLISION_DMG: int = 450


static func absolute_guard(battle) -> bool:
	## Ultimate (绝对裁决): consumes 2 AP and full ultimate energy (4) to slam
	## every enemy within Chebyshev distance 1 (8 surrounding tiles) for 130% ATK
	## and knock them back 1 tile (with wall/unit collision bonus).
	var actors = battle.actors
	if battle.phase != battle.BattlePhase.PLAYER:
		return false
	var caster = battle.get_active_character()
	if caster == null:
		return false
	var skill := SkillRegistryScript.get_skill(&"absolute_guard")
	if skill == null:
		return false
	var caster_id: String = caster.actor_id
	var energy_cost: int = caster.ultimate_energy_max
	if not caster.is_alive() or not battle.ap.can_spend(skill.ap_cost) or caster.ultimate_energy < energy_cost:
		return false
	var spent_energy: bool = caster.spend_ultimate_energy(energy_cost)
	var spent_ap: bool = battle.ap.spend(skill.ap_cost)
	if not (spent_energy and spent_ap):
		if spent_energy:
			caster.gain_ultimate_energy(energy_cost)
		if spent_ap:
			battle.ap.refund(skill.ap_cost)
		return false

	var raw_damage: int = CombatMathScript.calculate_raw_damage(caster.attack, skill.damage_multiplier)
	var radius: int = battle.run_state.ultimate_radius() if battle.run_state != null else 1
	var col_dmg: int = battle.run_state.collision_damage() if battle.run_state != null else KNOCKBACK_COLLISION_DMG
	var hit_targets: Array = []
	for actor_id in actors.keys():
		var enemy = actors[actor_id]
		if enemy.team != "enemy" or not enemy.is_alive():
			continue
		var dx: int = absi(enemy.cell.x - caster.cell.x)
		var dy: int = absi(enemy.cell.y - caster.cell.y)
		if maxi(dx, dy) <= radius:
			hit_targets.append(enemy)

	for enemy in hit_targets:
		battle._apply_damage(enemy.actor_id, raw_damage, caster_id, "absolute_guard", "physical")
		if enemy.is_alive():
			_knockback_one(battle, caster, enemy, enemy.cell - caster.cell, col_dmg)

	battle._emit_event("skill_resolved", caster_id, caster_id, "skill=absolute_guard ap=%d energy=%d hits=%d" % [skill.ap_cost, energy_cost, hit_targets.size()])
	battle._check_battle_end()
	return true


static func _knockback_one(battle, caster, target, direction: Vector2i, collision_damage: int) -> void:
	if direction == Vector2i.ZERO:
		return
	var step := Vector2i(signi(direction.x), signi(direction.y))
	var dest: Vector2i = target.cell + step
	var out_of_bounds: bool = dest.x < 0 or dest.y < 0 or dest.x >= battle.grid_size.x or dest.y >= battle.grid_size.y
	if out_of_bounds or battle.blocked_cells.has(dest):
		battle._apply_damage(target.actor_id, collision_damage, caster.actor_id, "knockback_collision", "true")
		return
	if battle.beacons.has(dest) and int(battle.beacons[dest].get("health", 0)) > 0:
		battle._apply_damage(target.actor_id, collision_damage, caster.actor_id, "knockback_collision", "true")
		battle.damage_beacon_at(dest, collision_damage, caster.actor_id, "knockback_collision")
		return
	for other_id in battle.actors:
		var other = battle.actors[other_id]
		if other.actor_id == target.actor_id:
			continue
		if (other.is_alive() or other.is_downed()) and other.cell == dest:
			battle._apply_damage(target.actor_id, collision_damage, caster.actor_id, "knockback_collision", "true")
			if other.is_alive():
				battle._apply_damage(other.actor_id, collision_damage, caster.actor_id, "knockback_collision", "true")
			return
	target.cell = dest
	for intent in battle.intents:
		if intent.source_actor_id != target.actor_id or intent.state != 0:
			continue
		if intent.action_id not in ["charged_strike", "aimed_shot", "light_shot", "ground_pulse", "echo_bolt", "basic_melee"]:
			continue
		intent.target_cell = intent.target_cell + step
		if intent.action_id == "charged_strike":
			var forward := Vector2i(signi(intent.target_cell.x - target.cell.x), signi(intent.target_cell.y - target.cell.y))
			var perp := Vector2i(-forward.y, forward.x)
			var rebuilt: Array[Vector2i] = []
			for depth in [1, 2]:
				var row_center: Vector2i = target.cell + forward * depth
				for side in [-1, 0, 1]:
					var c: Vector2i = row_center + perp * side
					if GridRulesScript.is_inside_bounds(c, battle.grid_size) and not battle.blocked_cells.has(c) and c != target.cell:
						rebuilt.append(c)
			intent.affected_cells = rebuilt
		elif intent.action_id == "aimed_shot":
			var astep := Vector2i(signi(intent.target_cell.x - target.cell.x), signi(intent.target_cell.y - target.cell.y))
			var rebuilt: Array[Vector2i] = []
			for offset in [-1, 0, 1]:
				var c: Vector2i = intent.target_cell + astep * offset
				if GridRulesScript.is_inside_bounds(c, battle.grid_size) and not battle.blocked_cells.has(c) and c != target.cell:
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
	battle._emit_event("actor_moved", target.actor_id, caster.actor_id, "knockback dest=%s" % str(dest))


static func gain_active_energy(battle, actor_id: String) -> void:
	var actors = battle.actors
	if not actors.has(actor_id):
		return
	var actor = actors[actor_id]
	if actor.team != "player" or not actor.is_alive() or actor.active_energy_gain_turn == battle.turn_number:
		return
	actor.active_energy_gain_turn = battle.turn_number
	var before: int = actor.ultimate_energy
	actor.gain_ultimate_energy(1)
	if actor.ultimate_energy != before:
		battle._emit_event("ultimate_energy_gained", actor_id, actor_id, "source=active_action energy=%d" % actor.ultimate_energy)


static func oath_shield(battle, target_actor_id: String = "") -> bool:
	var actors = battle.actors
	if battle.phase != battle.BattlePhase.PLAYER:
		return false
	var caster = battle.get_active_character()
	if caster == null or not caster.is_alive():
		return false
	var resolved_target_id: String = target_actor_id if not target_actor_id.is_empty() else caster.actor_id
	if not actors.has(resolved_target_id):
		return false
	var skill := SkillRegistryScript.get_skill(&"oath_shield")
	if skill == null:
		return false
	var target = actors[resolved_target_id]
	var reviving: bool = target.is_downed()
	if target.team != "player" or not (target.is_alive() or reviving):
		return false
	if reviving and battle.oath_shield_revived.has(resolved_target_id):
		return false
	var ally_range: int = maxi(skill.max_range, 2)
	if resolved_target_id != caster.actor_id and GridRulesScript.manhattan_distance(caster.cell, target.cell) > ally_range:
		return false
	if not battle.ap.can_spend(skill.ap_cost):
		return false
	var caster_id: String = caster.actor_id
	var vow_stacks: int = battle.get_oath_vow_stacks(caster_id)
	var mod_bonus: int = battle.run_state.shield_bonus() if battle.run_state != null else 0
	var raw_shield: int = OATH_SHIELD_BASE + vow_stacks * OATH_SHIELD_VOW_FLAT + mod_bonus
	var shielded_ids: Array[String] = [caster_id]
	if resolved_target_id != caster_id:
		shielded_ids.append(resolved_target_id)
	if not battle.ap.spend(skill.ap_cost):
		return false
	if reviving:
		target.revive(raw_shield)
		battle.oath_shield_revived[resolved_target_id] = true
		battle._emit_event("member_revived", caster_id, resolved_target_id, "skill=oath_shield restored=%d" % raw_shield)
	for shielded_id in shielded_ids:
		var shielded = actors[shielded_id]
		var previous_shield: int = shielded.shield
		var final_shield: int = shielded.grant_shield(raw_shield)
		battle.oath_shield_expiry_turn[shielded_id] = battle.turn_number + 1
		battle._emit_event(
			"oath_shield_applied",
			caster_id,
			shielded_id,
			"raw=%d previous=%d current=%d cap=%d expires_after_player_turn=%d" % [
				raw_shield,
				previous_shield,
				final_shield,
				floori(float(shielded.max_health) * 0.30),
				battle.turn_number + 1
			]
		)
	gain_active_energy(battle, caster_id)
	if vow_stacks > 0:
		battle.statuses.remove_status(caster_id, &"oath_vow")
		battle._emit_event("status_consumed", caster_id, caster_id, "status=oath_vow stacks=%d" % vow_stacks)
	# Shock Shield roguelite mod: activating Oath Shield pushes adjacent enemies back 1 tile
	if battle.run_state != null and battle.run_state.has_mod(&"shock_shield"):
		var col_dmg: int = battle.run_state.collision_damage()
		for eid in actors.keys():
			var e = actors[eid]
			if e.team == "enemy" and e.is_alive() and GridRulesScript.manhattan_distance(caster.cell, e.cell) == 1:
				_knockback_one(battle, caster, e, e.cell - caster.cell, col_dmg)
	battle._emit_event("skill_resolved", caster_id, resolved_target_id, "skill=oath_shield ap=%d vow_stacks=%d shield=%d" % [skill.ap_cost, vow_stacks, raw_shield])
	battle._check_battle_end()
	return true


static func marked_target(battle) -> String:
	for actor_id in battle.actors.keys():
		if battle.statuses.has_status(String(actor_id), &"oathkeeper_mark"):
			return String(actor_id)
	return ""


static func judgment_mark_v2(battle, target_actor_id: String) -> bool:
	## V2 Judgment Mark: a DEF-scaled strike and a single replaceable mark.
	## This is deliberately separate from the legacy judgment_mark status/API.
	var actors = battle.actors
	if battle.phase != battle.BattlePhase.PLAYER or not actors.has(target_actor_id):
		return false
	var caster = battle.get_active_character()
	if caster == null:
		return false
	var skill := SkillRegistryScript.get_skill(&"oathkeeper_judgment_mark")
	if skill == null:
		return false
	var caster_id: String = caster.actor_id
	var target = actors[target_actor_id]
	if not caster.is_alive() or not target.is_alive() or target.team != "enemy":
		return false
	var distance: int = GridRulesScript.manhattan_distance(caster.cell, target.cell)
	if distance < skill.min_range or distance > skill.max_range:
		return false
	if not GridRulesScript.has_clear_line_of_sight(caster.cell, target.cell, battle.blocked_cells, battle.get_occupied_cells()):
		return false
	if not battle.ap.can_spend(skill.ap_cost):
		return false
	if not battle.ap.spend(skill.ap_cost):
		return false
	for actor_id in actors.keys():
		battle.statuses.remove_status(String(actor_id), &"oathkeeper_mark")
	if not battle.statuses.apply_status(&"oathkeeper_mark", caster_id, target_actor_id, 1, 1, -1, &"enemy_phase_end", &"replace"):
		battle.ap.refund(skill.ap_cost)
		return false
	gain_active_energy(battle, caster_id)
	var raw_damage: int = CombatMathScript.calculate_raw_damage(caster.attack, skill.damage_multiplier)
	battle._apply_damage(target_actor_id, raw_damage, caster_id, "oathkeeper_judgment_mark", "physical")
	battle._emit_event(
		"skill_resolved",
		caster_id,
		target_actor_id,
		"skill=oathkeeper_judgment_mark ap=%d raw=%d mark=oathkeeper_mark expires=enemy_phase_end" % [skill.ap_cost, raw_damage]
	)
	battle._check_battle_end()
	return true

