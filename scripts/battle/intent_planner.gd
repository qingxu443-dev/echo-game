class_name IntentPlanner
extends RefCounted

## Builds the enemy intents for one player turn.
##
## Pure planning: it reads the battlefield and returns intent snapshots, but it
## never mutates actors or statuses.
##
## Which actions an archetype knows is data (`EnemyDefinition.actions`, in
## priority order). Whether a given action is legal right now is code, because it
## reads the board - distance, line of sight, reachable cells - and a data format
## expressive enough to describe that would be a scripting language. The split
## means a new enemy that reuses existing actions is one .tres, and a genuinely
## new action is one branch here.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const BattleIntentScript = preload("res://scripts/battle/battle_intent.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")
const EnemyCatalogScript = preload("res://scripts/battle/enemy_catalog.gd")

## Damage multipliers per action, kept next to the decision that uses them. These
## describe the action rather than the archetype, so they are not in the .tres.
const CHARGED_STRIKE_MULTIPLIER: float = 1.5
const BASIC_MELEE_MULTIPLIER: float = 0.8
const AIMED_SHOT_MULTIPLIER: float = 1.35
const LIGHT_SHOT_MULTIPLIER: float = 0.75
const GROUND_PULSE_MULTIPLIER: float = 1.15
const ECHO_BOLT_MULTIPLIER: float = 0.7

## Reach and priority per action. Priority only orders the execution list; the
## choice between actions is the order in `actions`.
const CHARGED_STRIKE_RANGE: int = 2
const BASIC_MELEE_RANGE: int = 1
const AIMED_SHOT_MIN_RANGE: int = 3
const AIMED_SHOT_MAX_RANGE: int = 6
const GROUND_PULSE_MIN_RANGE: int = 2
const GROUND_PULSE_MAX_RANGE: int = 4


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
			if intent.action_id != "wait" and intent.action_id != "pursuit":
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
				if action_id == &"pursuit":
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
		return _ranged_reposition_path(battle, enemy, target, AIMED_SHOT_MIN_RANGE, AIMED_SHOT_MAX_RANGE, true, steps)
	if enemy.archetype == "area_controller":
		return _ranged_reposition_path(battle, enemy, target, GROUND_PULSE_MIN_RANGE, GROUND_PULSE_MAX_RANGE, false, steps)
	return _pursuit_path(battle, enemy.cell, target.cell, enemy.actor_id, steps)


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
static func _build_intent(battle, enemy, target, occupied: Dictionary, action_id: StringName, claimed_cells: Dictionary = {}):
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
	# Signature skill: only fires when the enemy's AP-driven charge bar is full.
	if enemy.skill_charge_max > 0 and enemy.skill_charge < enemy.skill_charge_max:
		return null
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < 1 or distance > CHARGED_STRIKE_RANGE:
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
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "charged_strike", BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, affected, CombatMathScript.calculate_raw_damage(enemy.attack, CHARGED_STRIKE_MULTIPLIER), 0)


static func _basic_melee(battle, enemy, target):
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance != BASIC_MELEE_RANGE:
		return null
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "basic_melee", BattleIntentScript.TargetMode.TILE_LOCKED, "", target.cell, [target.cell], CombatMathScript.calculate_raw_damage(enemy.attack, BASIC_MELEE_MULTIPLIER), 1)


static func _pursuit(battle, enemy, target):
	var pursuit_path: Array[Vector2i] = _compute_move_path(battle, enemy, target)
	if pursuit_path.is_empty():
		return null
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "pursuit", BattleIntentScript.TargetMode.NONE, "", pursuit_path[pursuit_path.size() - 1], pursuit_path, 0, 2)


static func _aimed_shot(battle, enemy, target, occupied: Dictionary):
	# Signature skill: full AP-driven charge fires a piercing 3-tile line shot (orthogonal or diagonal)
	if enemy.skill_charge_max > 0 and enemy.skill_charge < enemy.skill_charge_max:
		return null
	var dx: int = target.cell.x - enemy.cell.x
	var dy: int = target.cell.y - enemy.cell.y
	var chebyshev: int = maxi(absi(dx), absi(dy))
	if chebyshev < 2 or chebyshev > AIMED_SHOT_MAX_RANGE:
		return null
	var aligned: bool = (dx == 0 or dy == 0 or absi(dx) == absi(dy))
	if not aligned:
		return null
	if not GridRulesScript.has_clear_line_of_sight(enemy.cell, target.cell, battle.blocked_cells, occupied):
		return null
	var step := Vector2i(signi(dx), signi(dy))
	var affected: Array[Vector2i] = []
	for offset in [-1, 0, 1]:
		var c: Vector2i = target.cell + step * offset
		if GridRulesScript.is_inside_bounds(c, battle.grid_size) and not battle.blocked_cells.has(c) and c != enemy.cell:
			affected.append(c)
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "aimed_shot", BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, affected, CombatMathScript.calculate_raw_damage(enemy.attack, AIMED_SHOT_MULTIPLIER), 2)


static func _light_shot(battle, enemy, target, occupied: Dictionary):
	var dx: int = target.cell.x - enemy.cell.x
	var dy: int = target.cell.y - enemy.cell.y
	var chebyshev: int = maxi(absi(dx), absi(dy))
	if chebyshev < 2 or chebyshev > AIMED_SHOT_MAX_RANGE:
		return null
	var aligned: bool = (dx == 0 or dy == 0 or absi(dx) == absi(dy))
	if not aligned:
		return null
	if not GridRulesScript.has_clear_line_of_sight(enemy.cell, target.cell, battle.blocked_cells, occupied):
		return null
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "light_shot", BattleIntentScript.TargetMode.TILE_LOCKED, "", target.cell, [target.cell], CombatMathScript.calculate_raw_damage(enemy.attack, LIGHT_SHOT_MULTIPLIER), 2)


static func _ground_pulse(battle, enemy, target, claimed_cells: Dictionary = {}):
	# Signature skill: full AP-driven charge fires the 5-tile cross pulse
	if enemy.skill_charge_max > 0 and enemy.skill_charge < enemy.skill_charge_max:
		return null
	var aim_cell: Vector2i = _pick_uncrowded_aim(battle, enemy.cell, target.cell, GROUND_PULSE_MIN_RANGE, GROUND_PULSE_MAX_RANGE, claimed_cells)
	if aim_cell == Vector2i(-1, -1):
		return null
	var affected: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for offset in offsets:
		var cell: Vector2i = aim_cell + offset
		if GridRulesScript.is_inside_bounds(cell, battle.grid_size):
			affected.append(cell)
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "ground_pulse", BattleIntentScript.TargetMode.AREA_LOCKED, "", aim_cell, affected, CombatMathScript.calculate_raw_damage(enemy.attack, GROUND_PULSE_MULTIPLIER), 1, "magical")


static func _echo_bolt(battle, enemy, target, claimed_cells: Dictionary = {}):
	var aim_cell: Vector2i = _pick_uncrowded_aim(battle, enemy.cell, target.cell, GROUND_PULSE_MIN_RANGE, GROUND_PULSE_MAX_RANGE, claimed_cells)
	if aim_cell == Vector2i(-1, -1):
		return null
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "echo_bolt", BattleIntentScript.TargetMode.TILE_LOCKED, "", aim_cell, [aim_cell], CombatMathScript.calculate_raw_damage(enemy.attack, ECHO_BOLT_MULTIPLIER), 1, "magical")


## If target_cell is already locked by another enemy, try locking an adjacent
## escape tile around the target so enemies create a real crossfire net.
static func _pick_uncrowded_aim(battle, source_cell: Vector2i, target_cell: Vector2i, min_r: int, max_r: int, claimed_cells: Dictionary) -> Vector2i:
	var base_dist: int = GridRulesScript.manhattan_distance(source_cell, target_cell)
	if not claimed_cells.has(target_cell) and base_dist >= min_r and base_dist <= max_r:
		return target_cell
	for offset in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var adj: Vector2i = target_cell + offset
		if not GridRulesScript.is_inside_bounds(adj, battle.grid_size) or battle.blocked_cells.has(adj):
			continue
		if claimed_cells.has(adj):
			continue
		var d: int = GridRulesScript.manhattan_distance(source_cell, adj)
		if d >= min_r and d <= max_r:
			return adj
	if base_dist >= min_r and base_dist <= max_r:
		return target_cell
	return Vector2i(-1, -1)


static func _wait_intent(battle, enemy):
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "wait", BattleIntentScript.TargetMode.NONE, "", enemy.cell, [], 0, 3)


static func _intent_id(battle, enemy) -> String:
	return "intent_%d_%s" % [battle.turn_number, enemy.actor_id]


## Breadth-first walk that stops on the first cell adjacent to the goal, then
## returns the first max_steps of the path. Deterministic direction order.
static func _pursuit_path(battle, start: Vector2i, goal: Vector2i, actor_id: String, max_steps: int) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [start]
	var came_from := {start: start}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var occupied: Dictionary = battle.get_occupied_cells(actor_id)
	var found_cell := start
	var found := false
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if GridRulesScript.manhattan_distance(current, goal) == 1:
			found_cell = current
			found = true
			break
		for direction in directions:
			var next: Vector2i = current + direction
			if not GridRulesScript.is_inside_bounds(next, battle.grid_size):
				continue
			if battle.blocked_cells.has(next) or occupied.has(next) or came_from.has(next):
				continue
			came_from[next] = current
			queue.append(next)
	if not found or found_cell == start:
		return []
	var reversed_path: Array[Vector2i] = []
	var cursor: Vector2i = found_cell
	while cursor != start:
		reversed_path.push_front(cursor)
		cursor = came_from[cursor]
	var result: Array[Vector2i] = []
	for index in range(mini(max_steps, reversed_path.size())):
		result.append(reversed_path[index])
	return result


## Smart ranged/caster kiting & line-of-fire positioning:
## Picks a reachable cell within max_steps that establishes a valid firing lane
## (or retreats out of dead-zone range) instead of walking into melee range.
static func _ranged_reposition_path(
	battle,
	enemy,
	target,
	min_range: int,
	max_range: int,
	require_line: bool,
	max_steps: int
) -> Array[Vector2i]:
	var occupied: Dictionary = battle.get_occupied_cells(enemy.actor_id)
	var all_occupied: Dictionary = battle.get_occupied_cells()
	var ideal_dist: int = clampi(min_range + 1, min_range, max_range)

	var best_score: int = -999999
	var best_path: Array[Vector2i] = []
	for dy in range(-max_steps, max_steps + 1):
		for dx in range(-max_steps, max_steps + 1):
			if dx == 0 and dy == 0:
				continue
			if absi(dx) + absi(dy) > max_steps:
				continue
			var cand: Vector2i = enemy.cell + Vector2i(dx, dy)
			if not GridRulesScript.is_inside_bounds(cand, battle.grid_size):
				continue
			if battle.blocked_cells.has(cand) or occupied.has(cand):
				continue
			var path := GridRulesScript.find_path(enemy.cell, cand, battle.grid_size, battle.blocked_cells, occupied, max_steps)
			if path.is_empty():
				continue

			var dist: int = maxi(absi(cand.x - target.cell.x), absi(cand.y - target.cell.y)) if require_line else GridRulesScript.manhattan_distance(cand, target.cell)
			var eff_min: int = 2 if require_line else min_range
			var aligned: bool = (cand.x == target.cell.x or cand.y == target.cell.y or absi(cand.x - target.cell.x) == absi(cand.y - target.cell.y))
			var in_range: bool = dist >= eff_min and dist <= max_range
			var clear_line: bool = false
			if require_line and aligned and in_range:
				var sim_occ := all_occupied.duplicate()
				sim_occ.erase(enemy.cell)
				sim_occ[cand] = enemy.actor_id
				clear_line = GridRulesScript.has_clear_line_of_sight(cand, target.cell, battle.blocked_cells, sim_occ)

			var score: int = 0
			if require_line:
				if clear_line:
					score += 1000
				elif aligned:
					score += 120
			else:
				if in_range:
					score += 800

			if in_range:
				score += 250
			elif dist < min_range:
				# Retreat away from melee dead-zone
				score -= (min_range - dist) * 300
			else:
				# Close distance gently toward firing band
				score -= (dist - max_range) * 80

			score -= absi(dist - ideal_dist) * 15
			# Slight preference for moving closer to an aligned row/column for marksmen
			if require_line and not aligned:
				var axis_gap: int = mini(absi(cand.x - target.cell.x), absi(cand.y - target.cell.y))
				score -= axis_gap * 40

			if score > best_score:
				best_score = score
				best_path = path

	return best_path
