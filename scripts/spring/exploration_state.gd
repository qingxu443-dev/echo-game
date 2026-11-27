class_name ExplorationState
extends RefCounted

## 春之境 exploration rules (设计汇总 2026-11-26 §8.2, §8.3).
##
## One number drives everything: 探索体力, 10 at the start, 10 at most, never
## raised by a relic or an event. Moving to a place costs its manhattan distance,
## because §9.1 fixes the board as obstacle-free, so no path is longer than the
## straight one (§8.3 only asks the UI to show the shortest path).
##
## Deliberately NOT modelled here: what happens at a place. Battle, event and
## shop content are separate layers, and keeping them out means this file can be
## tested with no controller, no actor and no renderer.

const STAMINA_MAX: int = 10

var template: SpringMapTemplate
var stamina: int = STAMINA_MAX
var position: Vector2i = SpringMapTemplate.START_CELL
## place id -> true. One-shot places stay marked once finished (§9.4); shops are
## never added here, since they may be entered again.
var completed: Dictionary = {}
var finished: bool = false
var finish_reason: String = ""
## Set when a move empties the bar. §8.3 keeps the interaction window open at the
## cell just reached, so the run does not end until that window closes.
var awaiting_finish: bool = false


static func create(p_template: SpringMapTemplate) -> ExplorationState:
	var state := ExplorationState.new()
	state.template = p_template
	state.position = p_template.start_cell
	return state


func cost_to(cell: Vector2i) -> int:
	return SpringMapTemplate.manhattan(position, cell)


func can_afford(cell: Vector2i) -> bool:
	return stamina >= cost_to(cell)


## §8.3: an unaffordable place is greyed out but still inspectable - so this asks
## only whether the move itself is legal, and the view decides what to show.
func can_move_to(cell: Vector2i) -> bool:
	if finished or awaiting_finish:
		return false
	if not template.is_inside(cell):
		return false
	if cell == position:
		return false
	var cost: int = cost_to(cell)
	if cost <= 0:
		return false
	return stamina >= cost


## Atomic: either the whole distance is spent and the team stands on the target,
## or nothing changes. §8.3 forbids partial deduction.
func move_to(cell: Vector2i) -> bool:
	if not can_move_to(cell):
		return false
	stamina = maxi(0, stamina - cost_to(cell))
	position = cell
	if stamina == 0:
		# Reached the cell exactly on empty: keep the window open (§8.3).
		awaiting_finish = true
		settle_if_nothing_to_do()
	return true


func path_to(cell: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cursor := position
	while cursor.x != cell.x:
		cursor.x += signi(cell.x - cursor.x)
		path.append(cursor)
	while cursor.y != cell.y:
		cursor.y += signi(cell.y - cursor.y)
		path.append(cursor)
	return path


func place_here() -> SpringPlace:
	return template.place_at(position)


## §8.3: the cell you are standing on can be used without spending stamina.
func can_interact() -> bool:
	if finished:
		return false
	var place := place_here()
	if place == null:
		return false
	if place.one_shot and completed.has(place.id):
		return false
	return true


## Called after a one-shot place resolves. Closes the exhausted-turn window.
func mark_completed(place_id: StringName) -> void:
	completed[place_id] = true
	if awaiting_finish:
		finish("exhausted")


## If the bar emptied on an empty cell there is no window to keep open.
func settle_if_nothing_to_do() -> void:
	if awaiting_finish and not can_interact():
		finish("exhausted")


## §8.2: events and relics may restore stamina, never above 10.
func restore(amount: int) -> int:
	if finished or amount <= 0:
		return stamina
	stamina = mini(STAMINA_MAX, stamina + amount)
	if stamina > 0 and awaiting_finish:
		awaiting_finish = false
	return stamina


## §8.2: the remaining bar is discarded, never carried forward.
func finish(reason: String) -> void:
	finished = true
	finish_reason = reason
	awaiting_finish = false
	stamina = 0


func end_exploration() -> bool:
	if finished:
		return false
	finish("ended_by_player")
	return true


# --- persistence -------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"position": [position.x, position.y],
		"stamina": stamina,
		"completed": completed.keys(),
		"finished": finished,
		"finish_reason": finish_reason,
		"awaiting_finish": awaiting_finish,
	}


## Restores in place. The template is supplied by the caller from the saved
## template id, which is what keeps a resumed run on the same board.
func restore_from_dict(data: Dictionary) -> void:
	var pos: Array = data.get("position", [position.x, position.y])
	if pos.size() == 2:
		position = Vector2i(int(pos[0]), int(pos[1]))
	stamina = int(data.get("stamina", stamina))
	completed = {}
	for place_id in data.get("completed", []):
		completed[StringName(place_id)] = true
	finished = bool(data.get("finished", false))
	finish_reason = str(data.get("finish_reason", ""))
	awaiting_finish = bool(data.get("awaiting_finish", false))
