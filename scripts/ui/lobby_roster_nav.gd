class_name LobbyRosterNav
extends RefCounted

const OverlayScript = preload("res://scripts/ui/roster_manager_overlay.gd")

var overlay
var hover_roster: bool = false
var hover_squads: bool = false

func install(view: Control) -> void:
	overlay = OverlayScript.new()
	view.add_child(overlay)

func _roster_rect(view) -> Rect2:
	return Rect2(936.0 * view._sx(), 68.0 * view._sy(), 150.0 * view._sx(), 38.0 * view._sy())

func _squads_rect(view) -> Rect2:
	return Rect2(1096.0 * view._sx(), 68.0 * view._sy(), 156.0 * view._sx(), 38.0 * view._sy())

func update_hover(view, point: Vector2) -> void:
	if overlay != null and overlay.visible:
		return
	var next_roster := _roster_rect(view).has_point(point)
	var next_squads := _squads_rect(view).has_point(point)
	if next_roster != hover_roster or next_squads != hover_squads:
		hover_roster = next_roster
		hover_squads = next_squads
		view.queue_redraw()

func handle_key(event: InputEvent) -> bool:
	if overlay == null or not overlay.visible or not event is InputEventKey or not event.pressed or event.echo:
		return false
	if event.keycode == KEY_ESCAPE:
		overlay.hide()
	return true

func handle_click(view, point: Vector2) -> bool:
	if overlay != null and overlay.visible:
		return true
	if view.prep_open or view.map_selector_open:
		return false
	if _roster_rect(view).has_point(point):
		overlay.open_characters()
		return true
	if _squads_rect(view).has_point(point):
		overlay.open_squads()
		return true
	return false

func draw(view, font: Font, sx: float, sy: float) -> void:
	var compact_labels := view.size.x < 700.0
	var entries := [
		{"rect": _roster_rect(view), "label": "角色" if compact_labels else "角色总览", "hover": hover_roster},
		{"rect": _squads_rect(view), "label": "编队" if compact_labels else "队伍编成", "hover": hover_squads},
	]
	for entry in entries:
		var rect: Rect2 = entry["rect"]
		var hovered: bool = bool(entry["hover"])
		var border := Color("#8fc7dc") if hovered else Color(0.72, 0.78, 0.82, 0.48)
		view.draw_rect(rect, Color(0.08, 0.12, 0.16, 0.88) if hovered else Color(0.07, 0.09, 0.12, 0.74), true)
		view.draw_rect(rect, border, false, 1.2)
		var label := str(entry["label"])
		var font_size := roundi(12.0 * sy)
		var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		view.draw_string(font, Vector2(rect.get_center().x - label_width * 0.5, rect.position.y + rect.size.y * 0.62), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#e5f4fa") if hovered else Color("#d9d4ca"))
