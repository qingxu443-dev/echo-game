class_name GridRules
extends RefCounted

## Pure grid validation helpers. Gameplay state remains owned by the battle controller.

static func is_inside_bounds(cell: Vector2i, grid_size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


static func manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func is_path_legal(
	start: Vector2i,
	path: Array[Vector2i],
	grid_size: Vector2i,
	blocked_cells: Dictionary,
	occupied_cells: Dictionary,
	max_steps: int = 2
) -> bool:
	if path.is_empty() or path.size() > max_steps:
		return false

	var previous := start
	for cell in path:
		if not is_inside_bounds(cell, grid_size):
			return false
		if manhattan_distance(previous, cell) != 1:
			return false
		if blocked_cells.has(cell) or occupied_cells.has(cell):
			return false
		previous = cell

	return true


## Breadth-first candidate path generator for movement hints. Produces at most
## max_steps orthogonal steps toward the goal, or an empty array when the goal
## is unreachable, occupied or too far. The caller stays non-authoritative:
## the battle controller re-validates any produced path through is_path_legal
## before committing the move.
static func find_path(
	start: Vector2i,
	goal: Vector2i,
	grid_size: Vector2i,
	blocked_cells: Dictionary,
	occupied_cells: Dictionary,
	max_steps: int = 2
) -> Array[Vector2i]:
	if start == goal:
		return []
	var queue: Array[Vector2i] = [start]
	var came_from := {start: start}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == goal:
			break
		for direction in directions:
			var next: Vector2i = current + direction
			if not is_inside_bounds(next, grid_size):
				continue
			if blocked_cells.has(next) or occupied_cells.has(next) or came_from.has(next):
				continue
			came_from[next] = current
			queue.append(next)
	if not came_from.has(goal):
		return []
	var reversed_path: Array[Vector2i] = []
	var cursor: Vector2i = goal
	while cursor != start:
		reversed_path.push_front(cursor)
		cursor = came_from[cursor]
	if reversed_path.size() > max_steps:
		return []
	return reversed_path


static func has_clear_orthogonal_line(
	start: Vector2i,
	target: Vector2i,
	blocked_cells: Dictionary,
	occupied_cells: Dictionary,
	ignore_target_occupant: bool = true
) -> bool:
	if start == target:
		return false
	if start.x != target.x and start.y != target.y:
		return false

	var step := Vector2i(signi(target.x - start.x), signi(target.y - start.y))
	var cursor := start + step
	while cursor != target:
		if blocked_cells.has(cursor) or occupied_cells.has(cursor):
			return false
		cursor += step

	if blocked_cells.has(target):
		return false
	if not ignore_target_occupant and occupied_cells.has(target):
		return false
	return true


## Player-facing line of sight. Accepts any straight line: the same row, the same
## column, or an exact 45-degree diagonal. Non-aligned offsets still fail because
## there is no single straight line between them.
## The orthogonal-only helper above is kept for enemy firing lanes, which stay
## orthogonal by design.
static func has_clear_line_of_sight(
	start: Vector2i,
	target: Vector2i,
	blocked_cells: Dictionary,
	occupied_cells: Dictionary,
	ignore_target_occupant: bool = true
) -> bool:
	if start == target:
		return false
	var delta: Vector2i = target - start
	var dx: int = absi(delta.x)
	var dy: int = absi(delta.y)
	if dx != 0 and dy != 0 and dx != dy:
		return false

	var step := Vector2i(signi(delta.x), signi(delta.y))
	var cursor: Vector2i = start + step
	while cursor != target:
		if blocked_cells.has(cursor) or occupied_cells.has(cursor):
			return false
		cursor += step

	if blocked_cells.has(target):
		return false
	if not ignore_target_occupant and occupied_cells.has(target):
		return false
	return true
