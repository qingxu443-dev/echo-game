class_name CombatGeometry
extends RefCounted

## Grid queries that answer "where" and "can this be aimed at", with no opinion
## about damage, resources or design numbers.
##
## Everything here is a pure function of the board: cells, blockers, occupancy.
## The one place a design value leaks in is `depth_bonus`, and it is a parameter
## rather than a constant so that 极意's expanded footprint stays a decision made
## by the caller that knows about blade intent.

const GridRulesScript = preload("res://scripts/battle/grid_rules.gd")
const SkillDefinitionScript = preload("res://scripts/battle/skill_definition.gd")


## Whether the aim itself is legal: range and line of sight, before AP, energy or
## resource are considered. The target ring and the cast both call this, so the
## highlight can never promise a shot the controller then refuses - and a skill
## that forgets one of the two checks cannot silently pass it.
##
## Three aim shapes, because they are genuinely different:
##  - A rectangle (FAN) is aimed by direction, not at a point. A three-wide row
##    cannot sit on a single line, so only its centre lane has to be clear.
##  - A dash needs a straight orthogonal lane: the landing walk steps along one
##    axis, so a diagonal target three cells out would spend the AP and stop two
##    cells short of striking anything.
##  - Everything else needs a clear straight line to the target (45 degrees
##    included). Adjacent targets skip it - nothing can stand in between.
##
## `depth_bonus` widens the lane check the same way the cast widens its rectangle,
## so the ring cannot promise a footprint the cast will then refuse.
static func can_aim(battle, skill, target, depth_bonus: int = 0, needs_orthogonal_lane: bool = false) -> bool:
	var caster = battle.get_active_character()
	if caster == null or target == null or not target.is_alive():
		return false
	return can_aim_cell(battle, skill, target.cell, depth_bonus, needs_orthogonal_lane)


static func can_aim_cell(battle, skill, cell: Vector2i, depth_bonus: int = 0, needs_orthogonal_lane: bool = false) -> bool:
	var caster = battle.get_active_character()
	if caster == null or not caster.is_alive() or not GridRulesScript.is_inside_bounds(cell, battle.grid_size) or battle.blocked_cells.has(cell):
		return false
	var distance: int = GridRulesScript.manhattan_distance(caster.cell, cell)
	if distance < skill.min_range or distance > skill.max_range:
		return false
	if skill.shape == SkillDefinitionScript.SHAPE_FAN:
		return centre_lane_clear_at(battle, caster, cell, skill.shape_depth + depth_bonus)
	if distance <= 1:
		return true
	if needs_orthogonal_lane:
		return GridRulesScript.has_clear_orthogonal_line(
			caster.cell, cell, battle.blocked_cells, battle.get_occupied_cells(caster.actor_id))
	return GridRulesScript.has_clear_line_of_sight(
		caster.cell, cell, battle.blocked_cells, battle.get_sight_blockers(caster.actor_id))


## A rectangle is cast through the cell in front of the caster, so only that lane
## has to be open. Checking every hit cell instead would refuse the whole skill
## whenever one corner sat behind a wall, and a three-wide block has no single
## line to begin with.
static func centre_lane_clear(battle, caster, target, depth: int) -> bool:
	return centre_lane_clear_at(battle, caster, target.cell, depth)


static func centre_lane_clear_at(battle, caster, cell: Vector2i, depth: int) -> bool:
	var direction: Vector2i = direction_toward(caster.cell, cell)
	if direction == Vector2i.ZERO:
		return false
	for step in range(1, depth + 1):
		var lane_cell: Vector2i = caster.cell + direction * step
		if not GridRulesScript.is_inside_bounds(lane_cell, battle.grid_size):
			break
		if battle.blocked_cells.has(lane_cell):
			return false
	return true


## The orthogonal direction the cast is aimed at; ties go to the larger axis.
static func direction_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var delta: Vector2i = to - from
	if delta == Vector2i.ZERO:
		return Vector2i.ZERO
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))


## Rectangular footprint in front of the caster. With an even width the cast axis
## is the first column rather than the middle, because a two-wide block cannot be
## centred on a single line - documented so the asymmetry is deliberate.
static func rectangle_cells(battle, origin: Vector2i, direction: Vector2i, width: int, depth: int) -> Dictionary:
	var cells: Dictionary = {}
	var perpendicular := Vector2i(direction.y, direction.x)
	var start: int = -int((width - 1) / 2)
	for step in range(1, depth + 1):
		var row_origin: Vector2i = origin + direction * step
		for offset in range(start, start + width):
			var cell: Vector2i = row_origin + perpendicular * offset
			if GridRulesScript.is_inside_bounds(cell, battle.grid_size):
				cells[cell] = true
	return cells


## Cells out to `reach` in each orthogonal direction, kept on the board.
static func cross_cells(battle, origin: Vector2i, reach: int) -> Dictionary:
	var cells: Dictionary = {}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for direction in directions:
		for step in range(1, reach + 1):
			var cell: Vector2i = origin + direction * step
			if not GridRulesScript.is_inside_bounds(cell, battle.grid_size):
				break
			cells[cell] = true
	return cells


## Living enemies standing on any of these cells. Order follows `battle.actors`,
## so callers that apply damage get a stable sequence.
static func actors_in_cells(battle, cells: Dictionary) -> Array:
	var targets: Array = []
	for actor_id in battle.actors:
		var actor = battle.actors[actor_id]
		if actor.team == "enemy" and actor.is_alive() and cells.has(actor.cell):
			targets.append(actor)
	return targets


## Walk toward the target until blocked or adjacent, at most `max_steps` steps.
## Returns the cell the caster would end on - the caster's own cell when it cannot
## move at all.
static func dash_landing(battle, caster, target, max_steps: int) -> Vector2i:
	var cursor: Vector2i = caster.cell
	var occupied: Dictionary = battle.get_occupied_cells(caster.actor_id)
	for _i in range(max_steps):
		var next := cursor
		if target.cell.x != cursor.x:
			next.x += signi(target.cell.x - cursor.x)
		elif target.cell.y != cursor.y:
			next.y += signi(target.cell.y - cursor.y)
		if next == cursor:
			break
		if GridRulesScript.manhattan_distance(next, target.cell) < 1:
			break
		if not GridRulesScript.is_inside_bounds(next, battle.grid_size):
			break
		if battle.blocked_cells.has(next) or occupied.has(next):
			break
		cursor = next
	return cursor
