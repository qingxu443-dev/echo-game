class_name LobbyRosterNav
extends RefCounted

const OverlayScript = preload("res://scripts/ui/roster_manager_overlay.gd")
const MailServiceScript = preload("res://scripts/meta/communications_mail_service.gd")
const COMMUNICATIONS_SCENE_PATH := "res://scenes/lobby/communications_terminal.tscn"

var overlay
var hover_roster: bool = false
var hover_fragments: bool = false
var hover_squads: bool = false
var hover_communications: bool = false
var mail_unread_count: int = 0
var mail_pending_count: int = 0


func install(view: Control) -> void:
	overlay = OverlayScript.new()
	view.add_child(overlay)


func _roster_rect(view) -> Rect2:
	return Rect2(936.0 * view._sx(), 68.0 * view._sy(), 72.0 * view._sx(), 38.0 * view._sy())


func _fragment_rect(view) -> Rect2:
	return Rect2(1016.0 * view._sx(), 68.0 * view._sy(), 72.0 * view._sx(), 38.0 * view._sy())


func _squads_rect(view) -> Rect2:
	return Rect2(1096.0 * view._sx(), 68.0 * view._sy(), 72.0 * view._sx(), 38.0 * view._sy())


func _communications_rect(view) -> Rect2:
	return Rect2(1176.0 * view._sx(), 68.0 * view._sy(), 72.0 * view._sx(), 38.0 * view._sy())


func announce_new_mail(view) -> void:
	var mailbox := MailServiceScript.load_mailbox()
	mail_unread_count = MailServiceScript.unread_count(mailbox)
	mail_pending_count = MailServiceScript.pending_attachment_count(mailbox)
	var notice := MailServiceScript.consume_new_mail_notice(mailbox)
	if int(notice.get("count", 0)) > 0:
		view._show_dialogue("通讯终端", "收到 %d 封新邮件，其中 %d 份待领取奖励。" % [int(notice.count), int(notice.pending)], 8.0)
	view.queue_redraw()


func update_hover(view, point: Vector2) -> void:
	if overlay != null and overlay.visible:
		return
	var next_roster := _roster_rect(view).has_point(point)
	var next_fragments := _fragment_rect(view).has_point(point)
	var next_squads := _squads_rect(view).has_point(point)
	var next_communications := _communications_rect(view).has_point(point)
	if next_roster != hover_roster or next_fragments != hover_fragments or next_squads != hover_squads or next_communications != hover_communications:
		hover_roster = next_roster
		hover_fragments = next_fragments
		hover_squads = next_squads
		hover_communications = next_communications
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
	if _fragment_rect(view).has_point(point):
		overlay.open_fragments()
		return true
	if _squads_rect(view).has_point(point):
		overlay.open_squads()
		return true
	if _communications_rect(view).has_point(point):
		var error := SceneTravel.change(view.get_tree(), COMMUNICATIONS_SCENE_PATH, "通讯终端")
		if error != OK:
			view.status_notice = "通讯终端无法打开。"
			view.queue_redraw()
		return true
	return false


func draw(view, font: Font, sx: float, sy: float) -> void:
	var entries := [
		{"rect": _roster_rect(view), "label": "角色", "hover": hover_roster},
		{"rect": _fragment_rect(view), "label": "残片", "hover": hover_fragments},
		{"rect": _squads_rect(view), "label": "编队", "hover": hover_squads},
		{"rect": _communications_rect(view), "label": "通讯", "hover": hover_communications},
	]
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var rect: Rect2 = entry["rect"]
		var hovered: bool = bool(entry["hover"])
		var border := Color("#e2c17f") if hovered or index == 3 else Color(0.72, 0.78, 0.82, 0.48)
		view.draw_rect(rect, Color(0.08, 0.12, 0.16, 0.88) if hovered else Color(0.07, 0.09, 0.12, 0.74), true)
		view.draw_rect(rect, border, false, 1.2)
		var label := str(entry["label"])
		var font_size := roundi(12.0 * sy)
		var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		view.draw_string(font, Vector2(rect.get_center().x - label_width * 0.5, rect.position.y + rect.size.y * 0.52), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#f3e8d2") if hovered else Color("#d9d4ca"))
		if index == 3:
			var count_text := "未读%d · 待领%d" % [mail_unread_count, mail_pending_count]
			view.draw_string(font, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.88), count_text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, roundi(7.0 * sy), Color("#e2c17f"))
