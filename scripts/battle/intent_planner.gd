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


static func plan(battle) -> Array:
	var actors = battle.actors
	var generated: Array = []
	var occupied: Dictionary = battle.get_occupied_cells()
	var claimed_cells: Dictionary = {}

	for actor_id in actors:
		var enemy = actors[actor_id]
		if not enemy.is_alive() or enemy.team != "enemy":
			continue
		var target = _pick_target_for_enemy(battle, enemy, claimed_cells)
		if target == null:
			continue
		var intent = _choose_intent(battle, enemy, target, occupied, claimed_cells)
		if intent != null:
			generated.append(intent)
			if intent.action_id not in ["wait", "pursuit", "ward_ally"]:
				claimed_cells[intent.target_cell] = true

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


## First legal action wins; otherwise the enemy waits. This is the whole of the
## per-archetype behaviour, expressed once instead of three times.
## Picks either the hero or a stationary Relic Beacon so multiple enemies split
## pressure (attacking beacons the player cannot simply walk away from) instead
## of all stacking onto the player's single tile.
static func _pick_target_for_enemy(battle, enemy, claimed_cells: Dictionary):
	var hero = battle.get_defender()
	if hero == null or not hero.is_alive():
		return null
	var beacons: Array[Dictionary] = battle.alive_beacons()
	if beacons.is_empty():
		return hero

	var hero_claimed: bool = claimed_cells.has(hero.cell)
	var best_beacon: Dictionary = {}
	var best_b_dist: int = 999
	for b in beacons:
		# A boss's own 结界 nodes are scenery it protects, not something it
		# attacks. Everything else (the relic chests) stays a valid objective.
		if not bool(b.get("enemy_objective", true)):
			continue
		var bc: Vector2i = b["cell"]
		var d: int = GridRulesScript.manhattan_distance(enemy.cell, bc)
		# Prefer unclaimed beacons first, then nearest beacon
		var penalty: int = 4 if claimed_cells.has(bc) else 0
		if d + penalty < best_b_dist:
			best_b_dist = d + penalty
			best_beacon = b

	var hero_dist: int = GridRulesScript.manhattan_distance(enemy.cell, hero.cell)
	# If another enemy already locked the hero's tile, or a beacon is closer, target the beacon!
	if not best_beacon.is_empty() and (hero_claimed or best_b_dist <= hero_dist):
		return {"cell": best_beacon["cell"], "actor_id": str(best_beacon["id"]), "is_beacon": true}
	return hero


static func _choose_intent(battle, enemy, target, occupied: Dictionary, claimed_cells: Dictionary = {}):
	# 百花锁命 第二段: a mark placed last enemy phase fires now. It is checked
	# before the action list because the shot is not one of the archer's choices -
	# it is the delayed half of a decision already made.
	var locked_intent = EliteSkillsScript.locked_shot(battle, enemy)
	if locked_intent != null:
		return locked_intent

	var actions: Array[StringName] = actions_for(enemy)

	# 1. Try any non-movement attack from the current tile first.
	for action_id in actions:
		if action_id == &"pursuit":
			continue
		var intent = _build_intent(battle, enemy, target, occupied, action_id, claimed_cells)
		if intent != null:
			return intent

	# 2. Into-the-Breach enemy cadence: if out of attack position after turn 1,
	#    reposition first (up to 2 tiles) and IMMEDIATELY telegraph an attack
	#    from the new tile instead of wasting a whole turn just walking.
	#
	#    The move is recorded on the intent (move_path) and applied by
	#    IntentResolver during the enemy phase. Planning must not touch the
	#    board: the old version wrote enemy.cell here and emitted actor_moved,
	#    so calling plan() twice moved the enemy twice and the telegraph could
	#    disagree with what actually happened.
	if actions.has(&"pursuit") and battle.turn_number > 1:
		var move_path: Array[Vector2i] = _compute_move_path(battle, enemy, target)
		if not move_path.is_empty():
			var dest: Vector2i = move_path[move_path.size() - 1]
			var origin: Vector2i = enemy.cell
			# Evaluate the follow-up from the destination, then restore the board
			# exactly as it was. No event, no lasting mutation.
			occupied.erase(origin)
			occupied[dest] = enemy.actor_id
			enemy.cell = dest
			var follow_intent = null
			for action_id in actions:
				# 逐影突袭 already carries its own path; evaluating it again from a
				# simulated destination would stack two moves into one intent.
				if action_id == &"pursuit" or action_id == &"shadow_raid":
					continue
				follow_intent = _build_intent(battle, enemy, target, occupied, action_id, claimed_cells)
				if follow_intent != null:
					break
			enemy.cell = origin
			occupied.erase(dest)
			occupied[origin] = enemy.actor_id
			if follow_intent != null:
				follow_intent.move_path = move_path
				return follow_intent
			# Cannot attack even after stepping: walk instead of the old
			# teleport-then-wait, so the movement is a real intent the resolver
			# animates in the enemy phase.
			return _pursuit(battle, enemy, target)

	# 3. Still too far after moving (or turn 1 setup): fall back to pursuit / wait.
	if actions.has(&"pursuit") and battle.turn_number == 1:
		var p_intent = _pursuit(battle, enemy, target)
		if p_intent != null:
			return p_intent
	return _wait_intent(battle, enemy)


static func _compute_move_path(battle, enemy, target) -> Array[Vector2i]:
	var steps: int = _move_steps_of(enemy)
	if enemy.archetype == "marksman":
		var shot = EnemySkillCatalogScript.get_skill(&"aimed_shot")
		var keep: int = shot.reposition_min_range if shot.reposition_min_range > 0 else shot.min_range
		return IntentSupportScript.ranged_reposition_path(battle, enemy, target, keep, shot.max_range, true, steps)
	if enemy.archetype == "area_controller":
		var pulse = EnemySkillCatalogScript.get_skill(&"ground_pulse")
		return IntentSupportScript.ranged_reposition_path(battle, enemy, target, pulse.min_range, pulse.max_range, false, steps)
	return IntentSupportScript.pursuit_path(battle, enemy.cell, target.cell, enemy.actor_id, steps)


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


static func _pursuit(battle, enemy, target):
	var pursuit_path: Array[Vector2i] = _compute_move_path(battle, enemy, target)
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
	var aim_cell: Vector2i = IntentSupportScript.pick_uncrowded_aim(battle, enemy.cell, target.cell, spec.min_range, spec.max_range, claimed_cells)
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
