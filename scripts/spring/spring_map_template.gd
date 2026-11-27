class_name SpringMapTemplate
extends RefCounted

## 春之境 map template (设计汇总 2026-11-26 §9.1).
##
## Static by design: the same template id yields the same cells on every run.
## Only the identities of two things move between runs - which template the run
## drew, and which random event fills the random slot - and both live on the run,
## not here.

const SIZE: int = 5
const START_CELL := Vector2i(1, 1)

var template_id: int = 0
var boss_cell: Vector2i = Vector2i.ZERO
var start_cell: Vector2i = START_CELL
var places: Array[SpringPlace] = []

var _by_cell: Dictionary = {}
var _by_id: Dictionary = {}


func add_place(place: SpringPlace) -> void:
	places.append(place)
	_by_cell[place.cell] = place
	_by_id[place.id] = place


func place_at(cell: Vector2i) -> SpringPlace:
	return _by_cell.get(cell)


func place_by_id(place_id: StringName) -> SpringPlace:
	return _by_id.get(place_id)


func boss() -> SpringPlace:
	for place in places:
		if place.kind == SpringPlace.Kind.BOSS:
			return place
	return null


func places_of(kind: SpringPlace.Kind) -> Array[SpringPlace]:
	var found: Array[SpringPlace] = []
	for place in places:
		if place.kind == kind:
			found.append(place)
	return found


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 1 and cell.y >= 1 and cell.x <= SIZE and cell.y <= SIZE


func is_occupied(cell: Vector2i) -> bool:
	return _by_cell.has(cell)


## Cells with no place on them. §9.2 picks hidden locations from these, never
## from an occupied cell and never on the start cell.
func free_cells() -> Array[Vector2i]:
	var free: Array[Vector2i] = []
	for row in range(1, SIZE + 1):
		for col in range(1, SIZE + 1):
			var cell := Vector2i(row, col)
			if not _by_cell.has(cell) and cell != start_cell:
				free.append(cell)
	return free


func all_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row in range(1, SIZE + 1):
		for col in range(1, SIZE + 1):
			cells.append(Vector2i(row, col))
	return cells


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
