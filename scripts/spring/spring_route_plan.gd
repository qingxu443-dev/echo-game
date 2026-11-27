class_name SpringRoutePlan
extends RefCounted

## Hard-mode pattern-lock route planner for 春之境 (定轨一笔画模式).
##
## Players press-and-hold on the 5x5 map and drag continuously across any number
## of cells—just like a phone pattern lock—to plot a route. There is no cap on
## how many nodes may be linked, but the route MUST end on `template.boss_cell`.
## Releasing anywhere else clears the route and reports an error; releasing on
## the boss locks the route and starts automatic marching along every stop.

const AUTO_STEP_DELAY: float = 0.45

var hard_mode: bool = false
var locked: bool = false
var waypoints: Array[Vector2i] = []
var cursor: int = 0

## Runtime-only UI state (not persisted in saves).
var auto_step_timer: float = -1.0
var dragging: bool = false
var drag_point: Vector2 = Vector2.ZERO
var fail_flash_timer: float = 0.0
var fail_flash_message: String = ""


static func create(is_hard: bool = false) -> SpringRoutePlan:
	var plan := SpringRoutePlan.new()
	plan.hard_mode = is_hard
	return plan


func is_planning() -> bool:
	return hard_mode and not locked


func is_locked_active() -> bool:
	return hard_mode and locked


func tail_cell(start_cell: Vector2i) -> Vector2i:
	if waypoints.is_empty():
		return start_cell
	return waypoints[waypoints.size() - 1]


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func total_cost(start_cell: Vector2i) -> int:
	var cost: int = 0
	var prev: Vector2i = start_cell
	for cell in waypoints:
		cost += manhattan(prev, cell)
		prev = cell
	return cost


func ends_at_boss(template: SpringMapTemplate) -> bool:
	if template == null or waypoints.is_empty():
		return false
	return waypoints[waypoints.size() - 1] == template.boss_cell


## Starts a fresh pattern-lock drag from the pointer down cell.
func begin_drag(cell: Vector2i, point: Vector2, template: SpringMapTemplate) -> Dictionary:
	if not is_planning():
		return {"ok": false, "message": "路线已锁定，无法重绘。"}
	if template == null or not template.is_inside(cell):
		return {"ok": false, "message": "请在地图格子上长按拖动绘制路线。"}
	waypoints.clear()
	cursor = 0
	dragging = true
	drag_point = point
	fail_flash_timer = 0.0
	fail_flash_message = ""
	if cell != template.start_cell:
		waypoints.append(cell)
		if cell == template.boss_cell:
			return {"ok": true, "message": "已连至首领（王），松手即可锁定启程！"}
		return {"ok": true, "message": "已连 1 站，继续按住拖动并连向首领（王）…"}
	return {"ok": true, "message": "从起点出发，按住拖动连接任意数量节点，尾部须落于「王」！"}


## Extends (or smoothly backtracks) the route as the pointer drags across cells.
## Unlimited waypoint count; stops extending once the boss tail is reached.
func drag_over_cell(cell: Vector2i, template: SpringMapTemplate) -> Dictionary:
	if not is_planning() or not dragging:
		return {"ok": false, "changed": false, "message": ""}
	if template == null or not template.is_inside(cell):
		return {"ok": false, "changed": false, "message": ""}

	# Backtrack one step if the player drags back onto the previous node.
	if waypoints.size() >= 2 and cell == waypoints[waypoints.size() - 2]:
		waypoints.pop_back()
		return {"ok": true, "changed": true, "message": "已回退至第 %d 站，继续拖动连向首领（王）…" % waypoints.size()}
	if waypoints.size() == 1 and cell == template.start_cell:
		waypoints.pop_back()
		return {"ok": true, "changed": true, "message": "已回到起点，继续按住拖动绘制路线…"}

	if cell == template.start_cell or waypoints.has(cell):
		return {"ok": false, "changed": false, "message": ""}
	if ends_at_boss(template):
		return {"ok": false, "changed": false, "message": "终点已连至首领（王），松手即可锁定启程！"}

	waypoints.append(cell)
	if cell == template.boss_cell:
		return {"ok": true, "changed": true, "message": "已连至首领（王）！共 %d 站，松手即锁定自动推进！" % waypoints.size()}
	return {"ok": true, "changed": true, "message": "已连 %d 站（不限数量），请继续拖向首领（王）…" % waypoints.size()}


## Completes the drag on pointer release:
## - Tail is Boss -> locks immediately and arms auto-march.
## - Otherwise    -> clears the route and sets an explicit warning message.
func finish_drag(template: SpringMapTemplate) -> Dictionary:
	if not is_planning() or not dragging:
		return {"ok": false, "locked": false, "cleared": false, "message": ""}
	dragging = false
	if ends_at_boss(template):
		var lock_res := lock_plan(template)
		return {
			"ok": bool(lock_res["ok"]),
			"locked": bool(lock_res["ok"]),
			"cleared": false,
			"message": str(lock_res["message"]),
		}
	waypoints.clear()
	cursor = 0
	fail_flash_timer = 1.6
	fail_flash_message = "绘制失败：路线结尾必须是首领（王）！已自动清空，请长按重画。"
	return {
		"ok": false,
		"locked": false,
		"cleared": true,
		"message": fail_flash_message,
	}


func clear_plan() -> bool:
	if not is_planning():
		return false
	waypoints.clear()
	cursor = 0
	dragging = false
	return true


func lock_validation_error(template: SpringMapTemplate) -> String:
	if not hard_mode:
		return "当前并非困难模式。"
	if locked:
		return "路线已锁定。"
	if template == null or waypoints.is_empty():
		return "请长按地图拖动绘制路线，且结尾必须是首领（王）。"
	if not ends_at_boss(template):
		return "绘制失败：路线结尾必须是首领（王）格！"
	return ""


func can_lock(template: SpringMapTemplate) -> bool:
	return lock_validation_error(template).is_empty()


func lock_plan(template: SpringMapTemplate) -> Dictionary:
	var err := lock_validation_error(template)
	if not err.is_empty():
		return {"ok": false, "message": err}
	locked = true
	dragging = false
	cursor = 0
	auto_step_timer = 0.35
	return {
		"ok": true,
		"message": "路线锁定！共 %d 站，正在按路线自动启程…" % waypoints.size(),
	}


func has_next_stop() -> bool:
	return is_locked_active() and cursor >= 0 and cursor < waypoints.size()


func next_stop() -> Vector2i:
	if not has_next_stop():
		return Vector2i(-1, -1)
	return waypoints[cursor]


func is_allowed_destination(cell: Vector2i) -> bool:
	if not hard_mode:
		return true
	if not locked:
		return false
	return has_next_stop() and waypoints[cursor] == cell


func advance_cursor() -> void:
	if has_next_stop():
		cursor += 1


func to_dict() -> Dictionary:
	var serialized: Array = []
	for cell in waypoints:
		serialized.append([cell.x, cell.y])
	return {
		"hard_mode": hard_mode,
		"locked": locked,
		"waypoints": serialized,
		"cursor": cursor,
	}


static func from_dict(data: Dictionary) -> SpringRoutePlan:
	var plan := SpringRoutePlan.new()
	if data.is_empty():
		return plan
	plan.hard_mode = bool(data.get("hard_mode", false))
	plan.locked = bool(data.get("locked", false))
	plan.cursor = maxi(0, int(data.get("cursor", 0)))
	for pair in data.get("waypoints", []):
		if pair is Array and pair.size() == 2:
			plan.waypoints.append(Vector2i(int(pair[0]), int(pair[1])))
	return plan
