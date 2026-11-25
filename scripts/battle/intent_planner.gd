class_name IntentPlanner
extends RefCounted

## Builds the enemy intents for one player turn.
##
## Pure planning: it reads the battlefield and returns intent snapshots, but it
## never mutates actors or statuses. The only write is the judgment_mark flag on
## the intent it is about to return, which is what makes the telegraph show that
## the mark will reduce the hit.
##
## Behaviour lives here per archetype. Stats come from data/enemies/; the
## decision rules below are code by design, because the telegraph has to stay
## readable and reviewable.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const BattleIntentScript = preload("res://scripts/battle/battle_intent.gd")
const CombatMathScript = preload("res://scripts/battle/combat_math.gd")

## Damage multipliers per action, kept next to the decision that uses them.
const CHARGED_STRIKE_MULTIPLIER: float = 1.5
const BASIC_MELEE_MULTIPLIER: float = 0.8
const AIMED_SHOT_MULTIPLIER: float = 1.0
const GROUND_PULSE_MULTIPLIER: float = 0.7



static func plan(battle) -> Array:
	var actors = battle.actors
	var generated: Array = []
	var occupied: Dictionary = battle.get_occupied_cells()

	for actor_id in actors:
		var enemy = actors[actor_id]
		if not enemy.is_alive() or enemy.team != "enemy":
			continue
		var target = actors["sevrin"]
		if not target.is_alive():
			continue
		var intent = _marksman_intent(battle, enemy, target, occupied) if enemy.archetype == "marksman" else (_area_controller_intent(battle, enemy, target) if enemy.archetype == "area_controller" else _vanguard_intent(battle, enemy, target, occupied))
		if intent != null:
			generated.append(intent)

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


static func _vanguard_intent(battle, enemy, target, occupied: Dictionary):
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance == 2 and GridRulesScript.has_clear_orthogonal_line(enemy.cell, target.cell, battle.blocked_cells, occupied):
		return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "charged_strike", BattleIntentScript.TargetMode.TILE_LOCKED, "", target.cell, [target.cell], CombatMathScript.calculate_raw_damage(enemy.attack, CHARGED_STRIKE_MULTIPLIER), 0)
	if distance == 1:
		return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "basic_melee", BattleIntentScript.TargetMode.ACTOR_LOCKED, "sevrin", target.cell, [target.cell], CombatMathScript.calculate_raw_damage(enemy.attack, BASIC_MELEE_MULTIPLIER), 1)
	var pursuit_path: Array[Vector2i] = _pursuit_path(battle, enemy.cell, target.cell, enemy.actor_id, 2)
	if not pursuit_path.is_empty():
		return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "pursuit", BattleIntentScript.TargetMode.NONE, "", pursuit_path[pursuit_path.size() - 1], pursuit_path, 0, 2)
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "wait", BattleIntentScript.TargetMode.NONE, "", enemy.cell, [], 0, 3)


static func _marksman_intent(battle, enemy, target, occupied: Dictionary):
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	var aligned: bool = enemy.cell.x == target.cell.x or enemy.cell.y == target.cell.y
	var legal_range: bool = distance >= 3 and distance <= 6
	var clear_line: bool = GridRulesScript.has_clear_orthogonal_line(enemy.cell, target.cell, battle.blocked_cells, occupied)
	if aligned and legal_range and clear_line:
		return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "aimed_shot", BattleIntentScript.TargetMode.TILE_LOCKED, "", target.cell, [target.cell], CombatMathScript.calculate_raw_damage(enemy.attack, AIMED_SHOT_MULTIPLIER), 2)
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "wait", BattleIntentScript.TargetMode.NONE, "", enemy.cell, [], 0, 3)


static func _area_controller_intent(battle, enemy, target):
	var distance: int = GridRulesScript.manhattan_distance(enemy.cell, target.cell)
	if distance < 2 or distance > 4:
		return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "wait", BattleIntentScript.TargetMode.NONE, "", enemy.cell, [], 0, 3)
	var affected: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for offset in offsets:
		var cell: Vector2i = target.cell + offset
		if GridRulesScript.is_inside_bounds(cell, battle.grid_size):
			affected.append(cell)
	return BattleIntentScript.new(_intent_id(battle, enemy), enemy.actor_id, "ground_pulse", BattleIntentScript.TargetMode.AREA_LOCKED, "", target.cell, affected, CombatMathScript.calculate_raw_damage(enemy.attack, GROUND_PULSE_MULTIPLIER), 1, "magical")


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
