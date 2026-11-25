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
const AIMED_SHOT_MULTIPLIER: float = 1.0
const GROUND_PULSE_MULTIPLIER: float = 0.7

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

	for actor_id in actors:
		var enemy = actors[actor_id]
		if not enemy.is_alive() or enemy.team != "enemy":
			continue
		var target = battle.get_defender()
		if target == null or not target.is_alive():
			continue
		generated.append(_choose_intent(battle, enemy, target, occupied))

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
static func _choose_intent(battle, enemy, target, occupied: Dictionary):
	for action_id in actions_for(enemy):
		var intent = _build_intent(battle, enemy, target, occupied, action_id)
		if intent != null:
			return intent
	return _wait_intent(battle, enemy)


## Returns null when the action is not legal on this board. Each branch checks
## only its own preconditions, so adding an action cannot change another one.
static func _build_intent(battle, enemy, target, occupied: Dictionary, action_id: StringName):
	match action_id:
		&"charged_strike":
			return _charged_strike(battle, enemy, target, occupied)
		&"basic_melee":
			return _basic_melee(battle, enemy, target)
		&"pursuit":
			return _pursuit(battle, enemy, target)
		&"aimed_shot":
			return _aimed_shot(battle, enemy, target, occupied)
		&"ground_pulse":
			return _ground_pulse(battle, enemy, target)
	push_error("IntentPlanner: unknown action '%s' for archetype '%s'" % [action_id, enemy.archetype])
	return null


static func _charged_strike(battle, enemy, target, occupied: Dictionary):
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance != CHARGED_STRIKE_RANGE:
		return null
	if not GridRulesScript.has_clear_orthogonal_line(enemy.cell, target.cell, battle.blocked_cells, occupied):
		return null
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "charged_strike", BattleIntentScript.TargetMode.TILE_LOCKED, "", target.cell, [target.cell], CombatMathScript.calculate_raw_damage(enemy.attack, CHARGED_STRIKE_MULTIPLIER), 0)


static func _basic_melee(battle, enemy, target):
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance != BASIC_MELEE_RANGE:
		return null
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "basic_melee", BattleIntentScript.TargetMode.ACTOR_LOCKED, target.actor_id, target.cell, [target.cell], CombatMathScript.calculate_raw_damage(enemy.attack, BASIC_MELEE_MULTIPLIER), 1)


static func _pursuit(battle, enemy, target):
	var pursuit_path: Array[Vector2i] = _pursuit_path(battle, enemy.cell, target.cell, enemy.actor_id, 2)
	if pursuit_path.is_empty():
		return null
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "pursuit", BattleIntentScript.TargetMode.NONE, "", pursuit_path[pursuit_path.size() - 1], pursuit_path, 0, 2)


static func _aimed_shot(battle, enemy, target, occupied: Dictionary):
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < AIMED_SHOT_MIN_RANGE or distance > AIMED_SHOT_MAX_RANGE:
		return null
	var aligned: bool = enemy.cell.x == target.cell.x or enemy.cell.y == target.cell.y
	if not aligned:
		return null
	if not GridRulesScript.has_clear_orthogonal_line(enemy.cell, target.cell, battle.blocked_cells, occupied):
		return null
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "aimed_shot", BattleIntentScript.TargetMode.TILE_LOCKED, "", target.cell, [target.cell], CombatMathScript.calculate_raw_damage(enemy.attack, AIMED_SHOT_MULTIPLIER), 2)


static func _ground_pulse(battle, enemy, target):
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < GROUND_PULSE_MIN_RANGE or distance > GROUND_PULSE_MAX_RANGE:
		return null
	var affected: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for offset in offsets:
		var cell: Vector2i = target.cell + offset
		if GridRulesScript.is_inside_bounds(cell, battle.grid_size):
			affected.append(cell)
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "ground_pulse", BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, affected, CombatMathScript.calculate_raw_damage(enemy.attack, GROUND_PULSE_MULTIPLIER), 1, "magical")


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
