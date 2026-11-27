class_name IntentPlanner
extends RefCounted

## Builds the enemy intents for one player turn.
##
## Pure planning: it reads the battlefield and returns intent snapshots, but it
## never mutates actors or statuses.
##
## 三层分工：
##   - EnemySkillCatalog 说「这一招的数值是多少」；
##   - EliteSkills 说「这一招的几何形状长什么样」（专属技）；
##   - 本文件说「这一招现在合不合法」，并把结果排成执行顺序。
## 通用招式（蓄力斩/近战/追击/远程）的几何仍留在本文件，因为它们的形状由
## 距离和视线直接决定，抽出去只会多一层跳转。

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const BattleIntentScript = preload("res://scripts/battle/battle_intent.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")
const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")
const HazardFieldScript = preload("res://scripts/battle/hazard_field.gd")
const EnemySkillCatalogScript = preload("res://scripts/battle/enemy_skill_catalog.gd")
const EnemySkillDefinitionScript = preload("res://scripts/battle/enemy_skill_definition.gd")
const EliteSkillsScript = preload("res://scripts/battle/elite_skills.gd")
const IntentSupportScript = preload("res://scripts/battle/intent_support.gd")
const TacticalPressureScript = preload("res://scripts/battle/tactical_pressure.gd")


## Read-only tactical formation detector shared by the planner and the UI.
## Returns {} when fewer than two living enemies remain (formation broken).
static func analyze_formation(battle) -> Dictionary:
	if battle == null or battle.actors == null:
		return {}
	var melee_ids: Array[String] = []
	var ranged_ids: Array[String] = []
	var melee_cells: Array[Vector2i] = []
	var ranged_cells: Array[Vector2i] = []
	for actor_id in battle.actors:
		var enemy = battle.actors[actor_id]
		if enemy == null or not enemy.is_alive() or enemy.team != "enemy":
			continue
		if _is_ranged_kit(actions_for(enemy)):
			ranged_ids.append(String(actor_id))
			ranged_cells.append(enemy.cell)
		else:
			melee_ids.append(String(actor_id))
			melee_cells.append(enemy.cell)
	var total: int = melee_ids.size() + ranged_ids.size()
	if total < 2:
		return {}
	var form_id: String = "pincer_lockdown"
	var name_zh: String = "鹤翼合围阵"
	var desc_zh: String = "多面夹击 · 封锁退路"
	var links: Array[Dictionary] = []
	if not melee_ids.is_empty() and not ranged_ids.is_empty():
		form_id = "shield_wall"
		name_zh = "雁行护射阵"
		desc_zh = "前排卡位 · 异轴火网"
		for m_id in melee_ids:
			var m_cell: Vector2i = battle.actors[m_id].cell
			var best_r: String = ranged_ids[0]
			var best_d: int = 999
			for r_id in ranged_ids:
				var d: int = GridRulesScript.manhattan_distance(m_cell, battle.actors[r_id].cell)
				if d < best_d:
					best_d = d
					best_r = r_id
			links.append({"from": m_id, "to": best_r})
	elif ranged_ids.size() >= 2:
		form_id = "crossfire_net"
		name_zh = "天罗火网阵"
		desc_zh = "异轴封格 · 压缩走位"
		for i in range(ranged_ids.size() - 1):
			links.append({"from": ranged_ids[i], "to": ranged_ids[i + 1]})
	else:
		for i in range(melee_ids.size() - 1):
			links.append({"from": melee_ids[i], "to": melee_ids[i + 1]})
	return {
		"id": form_id, "name_zh": name_zh, "desc_zh": desc_zh,
		"melee_ids": melee_ids, "ranged_ids": ranged_ids,
		"melee_cells": melee_cells, "ranged_cells": ranged_cells,
		"links": links,
	}


static func plan(battle) -> Array:
	var actors = battle.actors
	var generated: Array = []
	var occupied: Dictionary = battle.get_occupied_cells()
	var claimed_cells: Dictionary = {}
	var reserved_cells: Dictionary = {}
	var formation: Dictionary = analyze_formation(battle)
	var threatened_cells: Dictionary = {}
	var used_axes: Dictionary = {}
	if not formation.is_empty():
		formation["threatened_cells"] = threatened_cells
		formation["used_axes"] = used_axes

	for actor_id in actors:
		var enemy = actors[actor_id]
		if not enemy.is_alive() or enemy.team != "enemy":
			continue
		var target = _pick_target_for_enemy(battle, enemy, claimed_cells, formation)
		if target == null:
			continue
		var intent = _choose_intent(battle, enemy, target, occupied, claimed_cells, reserved_cells, formation)
		if intent != null:
			generated.append(intent)
			if intent.action_id not in ["wait", "pursuit", "ward_ally", "ward_stance"]:
				claimed_cells[intent.target_cell] = true
				for c in intent.affected_cells:
					threatened_cells[c] = true
				threatened_cells[intent.target_cell] = true
				if intent.action_id in ["aimed_shot", "light_shot", "locked_shot", "lock_on"]:
					var fire_from: Vector2i = intent.move_path[intent.move_path.size() - 1] if not intent.move_path.is_empty() else enemy.cell
					var axis: int = IntentSupportScript.fire_axis_of(fire_from, intent.target_cell)
					if axis >= 0:
						used_axes[axis] = true
			if not intent.move_path.is_empty():
				reserved_cells[intent.move_path[intent.move_path.size() - 1]] = true
			elif intent.action_id == "pursuit" and not intent.affected_cells.is_empty():
				reserved_cells[intent.affected_cells[intent.affected_cells.size() - 1]] = true
			if int(enemy.tier) >= 2 and not (target is Dictionary):
				var combo = TacticalPressureScript.build_boss_combo_intent(battle, enemy, intent, target, threatened_cells)
				if combo != null:
					generated.append(combo)
					for cc in combo.affected_cells:
						threatened_cells[cc] = true

	generated.sort_custom(func(a, b):
		if a.execution_priority != b.execution_priority:
			return a.execution_priority < b.execution_priority
		var source_a = actors[a.source_actor_id]
		var source_b = actors[b.source_actor_id]
		if source_a.cell.y != source_b.cell.y:
			return source_a.cell.y < source_b.cell.y
		if source_a.cell.x != source_b.cell.x:
			return source_a.cell.x < source_b.cell.x
		return a.source_actor_id < b.source_actor_id
	)
	return generated


## The actions this enemy tries, in order. Falls back loudly rather than silently:
## an archetype with an empty list would stand still every turn, which reads as a
## frozen enemy rather than a data mistake.
static func actions_for(enemy) -> Array[StringName]:
	var actions: Array[StringName] = []
	var definition = EnemyCatalogScript.get_definition(String(enemy.archetype))
	if definition != null:
		actions.append_array(definition.actions)
	if actions.is_empty():
		push_error("IntentPlanner: archetype '%s' declares no actions" % enemy.archetype)
		actions.append(&"basic_melee")
	return actions


## Enemies choose a living player character as the target for every planned
## action. Chests and ward nodes remain in the battle geometry: area attacks can
## still damage them when their affected cells overlap, but they are never
## selected as a single-target objective.
static func _pick_target_for_enemy(battle, _enemy, _claimed_cells: Dictionary, _formation: Dictionary = {}):
	var hero = battle.get_defender()
	if hero == null or not hero.is_alive():
		return null
	return hero


static func _choose_intent(battle, enemy, target, occupied: Dictionary, claimed_cells: Dictionary = {}, reserved_cells: Dictionary = {}, formation: Dictionary = {}):
	# 百花锁命 第二段: a mark placed last enemy phase fires now. If cover broke
	# line of sight, a mobile sniper steps around cover to take the locked shot.
	var locked_intent = EliteSkillsScript.locked_shot(battle, enemy)
	if locked_intent != null:
		return locked_intent
	var actions: Array[StringName] = actions_for(enemy)
	if "lock_target_id" in enemy and not String(enemy.lock_target_id).is_empty() and actions.has(&"pursuit") and battle.turn_number > 1:
		var lock_target = battle.actors.get(String(enemy.lock_target_id))
		if lock_target != null and lock_target.is_alive():
			var lock_path: Array[Vector2i] = IntentSupportScript.ranged_reposition_path(battle, enemy, lock_target, 1, 6, true, _move_steps_of(enemy), true, reserved_cells, formation)
			if not lock_path.is_empty():
				var origin_l: Vector2i = enemy.cell
				var dest_l: Vector2i = lock_path[lock_path.size() - 1]
				occupied.erase(origin_l)
				occupied[dest_l] = enemy.actor_id
				enemy.cell = dest_l
				var moved_lock = EliteSkillsScript.locked_shot(battle, enemy)
				enemy.cell = origin_l
				occupied.erase(dest_l)
				occupied[origin_l] = enemy.actor_id
				if moved_lock != null:
					moved_lock.move_path = lock_path
					return moved_lock

	# 1. Try any non-movement attack from the current tile first.
	var area_mask: Dictionary = formation.get("threatened_cells", claimed_cells)
	for action_id in actions:
		if action_id == &"pursuit":
			continue
		var intent = _build_intent(battle, enemy, target, occupied, action_id, area_mask)
		if intent != null:
			return intent

	# 2. Tactical enemy cadence: if out of attack position after turn 1,
	#    reposition first and IMMEDIATELY telegraph an attack from the new tile
	#    instead of wasting a whole turn just walking.
	if actions.has(&"pursuit") and battle.turn_number > 1:
		var move_path: Array[Vector2i] = _compute_move_path(battle, enemy, target, reserved_cells, formation)
		if not move_path.is_empty():
			var dest: Vector2i = move_path[move_path.size() - 1]
			var origin: Vector2i = enemy.cell
			occupied.erase(origin)
			occupied[dest] = enemy.actor_id
			enemy.cell = dest
			var follow_intent = null
			for action_id in actions:
				if action_id == &"pursuit" or action_id == &"shadow_raid":
					continue
				follow_intent = _build_intent(battle, enemy, target, occupied, action_id, area_mask)
				if follow_intent != null:
					break
			enemy.cell = origin
			occupied.erase(dest)
			occupied[origin] = enemy.actor_id
			if follow_intent != null:
				follow_intent.move_path = move_path
				return follow_intent
			return _pursuit(battle, enemy, target, reserved_cells, formation)

	# 3. Still too far after moving (or turn 1 setup): fall back to pursuit / wait.
	if actions.has(&"pursuit") and battle.turn_number == 1:
		var p_intent = _pursuit(battle, enemy, target, reserved_cells, formation)
		if p_intent != null:
			return p_intent
	# Cornered ranged fallback: if any ranged/caster unit is pinned adjacent with
	# no legal retreat tile, strike back in melee instead of passing helplessly.
	if _is_ranged_kit(actions) and GridRulesScript.manhattan_distance(enemy.cell, target.cell) == 1:
		var fallback_melee = _basic_melee(battle, enemy, target)
		if fallback_melee != null:
			return fallback_melee
	return _wait_intent(battle, enemy)


static func _is_ranged_kit(actions: Array[StringName]) -> bool:
	if actions.has(&"basic_melee"):
		return false
	for a in [&"aimed_shot", &"lock_on", &"light_shot", &"ground_pulse", &"echo_bolt", &"spring_bloom"]:
		if actions.has(a):
			return true
	return false


static func _has_ready_ortho_cleave(enemy, actions: Array[StringName]) -> bool:
	for a in [&"charged_strike", &"sakura_shock", &"blight_field"]:
		if actions.has(a):
			var spec = EnemySkillCatalogScript.get_skill(a)
			if spec != null and IntentSupportScript.charge_ready(enemy, spec):
				return true
	return false


static func _compute_move_path(battle, enemy, target, reserved_cells: Dictionary = {}, formation: Dictionary = {}) -> Array[Vector2i]:
	var steps: int = _move_steps_of(enemy)
	var actions: Array[StringName] = actions_for(enemy)
	# Hybrid bruisers carrying basic_melee (e.g. 千枝神将 with mid-range quake)
	# press forward aggressively instead of kiting backward like pure casters.
	if not actions.has(&"basic_melee"):
		if actions.has(&"aimed_shot") or actions.has(&"lock_on") or actions.has(&"light_shot"):
			var shot = EnemySkillCatalogScript.get_skill(&"aimed_shot")
			var keep: int = shot.reposition_min_range if shot.reposition_min_range > 0 else shot.min_range
			return IntentSupportScript.ranged_reposition_path(battle, enemy, target, keep, shot.max_range, true, steps, true, reserved_cells, formation)
		if actions.has(&"ground_pulse") or actions.has(&"echo_bolt") or actions.has(&"spring_bloom"):
			var spec_id: StringName = &"spring_bloom" if actions.has(&"spring_bloom") else (&"ground_pulse" if actions.has(&"ground_pulse") else &"echo_bolt")
			var pulse = EnemySkillCatalogScript.get_skill(spec_id)
			var need_sight: bool = actions.has(&"rot_curse") or actions.has(&"spring_bloom")
			return IntentSupportScript.ranged_reposition_path(battle, enemy, target, pulse.min_range, pulse.max_range, false, steps, need_sight, reserved_cells, formation)
	return IntentSupportScript.melee_tactical_path(battle, enemy, target, steps, _has_ready_ortho_cleave(enemy, actions), reserved_cells, formation)


## Reposition budget for this actor. Two is the prototype baseline; a profile
## overrides it to express weight (heavy guard 1, wind runner 3). Read through a
## guard because the planner is also driven by test doubles that only model the
## handful of fields a scenario needs.
static func _move_steps_of(enemy) -> int:
	var steps: int = 2
	if enemy != null and "move_steps" in enemy:
		steps = int(enemy.move_steps)
	return clampi(steps, 1, 4)


## Returns null when the action is not legal on this board. Each branch checks
## only its own preconditions, so adding an action cannot change another one.
##
## 专属技先走 EliteSkills 的表：那张表随技能一起放在 elite_skills.gd 里，
## 所以加一条新专属技不需要回头改这里。只有通用招式的几何还留在这个 match。
static func _build_intent(battle, enemy, target, occupied: Dictionary, action_id: StringName, claimed_cells: Dictionary = {}):
	var elite: Dictionary = EliteSkillsScript.executors()
	if elite.has(action_id):
		return elite[action_id].call(battle, enemy, target)
	match action_id:
		&"charged_strike":
			return _charged_strike(battle, enemy, target, occupied)
		&"basic_melee":
			return _basic_melee(battle, enemy, target)
		&"pursuit":
			return _pursuit(battle, enemy, target)
		&"aimed_shot":
			return _aimed_shot(battle, enemy, target, occupied)
		&"light_shot":
			return _light_shot(battle, enemy, target, occupied)
		&"ground_pulse":
			return _ground_pulse(battle, enemy, target, claimed_cells)
		&"echo_bolt":
			return _echo_bolt(battle, enemy, target, claimed_cells)
	push_error("IntentPlanner: unknown action '%s' for archetype '%s'" % [action_id, enemy.archetype])
	return null


static func _charged_strike(battle, enemy, target, occupied: Dictionary):
	var spec = EnemySkillCatalogScript.get_skill(&"charged_strike")
	if not IntentSupportScript.charge_ready(enemy, spec):
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < spec.min_range or distance > spec.max_range:
		return null
	if not GridRulesScript.has_clear_orthogonal_line(enemy.cell, target.cell, battle.blocked_cells, occupied):
		return null
	# 3x2 (6-tile) sweeping cleave directly in front of the Vanguard
	var forward := Vector2i(signi(target.cell.x - enemy.cell.x), signi(target.cell.y - enemy.cell.y))
	var perp := Vector2i(-forward.y, forward.x)
	var affected: Array[Vector2i] = []
	for depth in [1, 2]:
		var row_center: Vector2i = enemy.cell + forward * depth
		for side in [-1, 0, 1]:
			var cell: Vector2i = row_center + perp * side
			if GridRulesScript.is_inside_bounds(cell, battle.grid_size) and not battle.blocked_cells.has(cell):
				affected.append(cell)
	var intent = BattleIntentScript.new(IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "charged_strike", BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, affected, IntentSupportScript.signature_damage(enemy, spec.damage_multiplier), spec.execution_priority)
	# §14 樱华蓄斩: the one charged strike the player can break. The flag rides on
	# the intent so the interrupt itself can stay a single generic rule.
	intent.interruptible = "interruptible_skill" in enemy and bool(enemy.interruptible_skill)
	return intent


static func _basic_melee(battle, enemy, target):
	var spec = EnemySkillCatalogScript.get_skill(&"basic_melee")
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance != spec.max_range:
		return null
	return BattleIntentScript.new(IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "basic_melee", BattleIntentScript.TargetMode.TILE_LOCKED, "", target.cell, [target.cell], IntentSupportScript.plain_attack_damage(enemy, spec.damage_multiplier), spec.execution_priority)


static func _pursuit(battle, enemy, target, reserved_cells: Dictionary = {}, formation: Dictionary = {}):
	var pursuit_path: Array[Vector2i] = _compute_move_path(battle, enemy, target, reserved_cells, formation)
	if pursuit_path.is_empty():
		return null
	return BattleIntentScript.new(IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "pursuit", BattleIntentScript.TargetMode.NONE, "", pursuit_path[pursuit_path.size() - 1], pursuit_path, 0, 2)


static func _aimed_shot(battle, enemy, target, occupied: Dictionary):
	# Signature skill: full AP-driven charge fires a piercing 3-tile line shot
	# (orthogonal or diagonal). Reach comes from the sheet, not from here.
	var spec = EnemySkillCatalogScript.get_skill(&"aimed_shot")
	if not IntentSupportScript.charge_ready(enemy, spec):
		return null
	var dx: int = target.cell.x - enemy.cell.x
	var dy: int = target.cell.y - enemy.cell.y
	var chebyshev: int = maxi(absi(dx), absi(dy))
	if chebyshev < spec.min_range or chebyshev > spec.max_range:
		return null
	var aligned: bool = (dx == 0 or dy == 0 or absi(dx) == absi(dy))
	if not aligned:
		return null
	if not GridRulesScript.has_clear_line_of_sight(enemy.cell, target.cell, battle.blocked_cells, battle.get_sight_blockers(enemy.actor_id)):
		return null
	var step := Vector2i(signi(dx), signi(dy))
	var affected: Array[Vector2i] = []
	for offset in [-1, 0, 1]:
		var c: Vector2i = target.cell + step * offset
		if GridRulesScript.is_inside_bounds(c, battle.grid_size) and not battle.blocked_cells.has(c) and c != enemy.cell:
			affected.append(c)
	return BattleIntentScript.new(IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "aimed_shot", BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, affected, IntentSupportScript.signature_damage(enemy, spec.damage_multiplier), spec.execution_priority)


static func _light_shot(battle, enemy, target, occupied: Dictionary):
	var spec = EnemySkillCatalogScript.get_skill(&"light_shot")
	var dx: int = target.cell.x - enemy.cell.x
	var dy: int = target.cell.y - enemy.cell.y
	var chebyshev: int = maxi(absi(dx), absi(dy))
	if chebyshev < spec.min_range or chebyshev > spec.max_range:
		return null
	var aligned: bool = (dx == 0 or dy == 0 or absi(dx) == absi(dy))
	if not aligned:
		return null
	if not GridRulesScript.has_clear_line_of_sight(enemy.cell, target.cell, battle.blocked_cells, battle.get_sight_blockers(enemy.actor_id)):
		return null
	return BattleIntentScript.new(IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "light_shot", BattleIntentScript.TargetMode.TILE_LOCKED, "", target.cell, [target.cell], IntentSupportScript.plain_attack_damage(enemy, spec.damage_multiplier), spec.execution_priority)


static func _ground_pulse(battle, enemy, target, claimed_cells: Dictionary = {}):
	# Signature skill: full AP-driven charge fires the 5-tile cross pulse
	var spec = EnemySkillCatalogScript.get_skill(&"ground_pulse")
	if not IntentSupportScript.charge_ready(enemy, spec):
		return null
	var aim_cell: Vector2i = IntentSupportScript.pick_uncrowded_aim(battle, enemy.cell, target.cell, spec.min_range, spec.max_range, claimed_cells, true)
	if aim_cell == Vector2i(-1, -1):
		return null
	var affected: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for offset in offsets:
		var cell: Vector2i = aim_cell + offset
		if GridRulesScript.is_inside_bounds(cell, battle.grid_size):
			affected.append(cell)
	return BattleIntentScript.new(IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "ground_pulse", BattleIntentScript.TargetMode.AREA_LOCKED, "", aim_cell, affected, CombatMathScript.calculate_raw_damage(enemy.attack, spec.damage_multiplier), spec.execution_priority, spec.damage_type)


static func _echo_bolt(battle, enemy, target, claimed_cells: Dictionary = {}):
	var spec = EnemySkillCatalogScript.get_skill(&"echo_bolt")
	var aim_cell: Vector2i = IntentSupportScript.pick_uncrowded_aim(battle, enemy.cell, target.cell, spec.min_range, spec.max_range, claimed_cells)
	if aim_cell == Vector2i(-1, -1):
		return null
	return BattleIntentScript.new(IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "echo_bolt", BattleIntentScript.TargetMode.TILE_LOCKED, "", aim_cell, [aim_cell], IntentSupportScript.plain_attack_damage(enemy, spec.damage_multiplier), spec.execution_priority, spec.damage_type)


static func _wait_intent(battle, enemy):
	return BattleIntentScript.new(IntentSupportScript.intent_id(battle, enemy), enemy.actor_id, "wait", BattleIntentScript.TargetMode.NONE, "", enemy.cell, [], 0, 3)
