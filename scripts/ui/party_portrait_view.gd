class_name PartyPortraitView
extends RefCounted

const P = preload("res://scripts/ui/theme_palette.gd")
const AREA := Rect2(24, 464, 284, 66)


static func card_rect(index: int) -> Rect2:
	return Rect2(AREA.position + Vector2(index * 97, 0), Vector2(90, 66))


static func hit(controller, position: Vector2) -> String:
	for index in range(controller.party_order.size()):
		if card_rect(index).has_point(position): return controller.party_order[index]
	return ""


static func draw(canvas: CanvasItem, controller) -> void:
	if not controller.single_active_party: return
	var font := ThemeDB.fallback_font
	canvas.draw_string(font, AREA.position + Vector2(0, -7), "队伍轮换 · 点击替补消耗 1 AP  [Tab]", HORIZONTAL_ALIGNMENT_LEFT, AREA.size.x, 11, P.GOLD_PALE)
	for index in range(controller.party_order.size()):
		var actor = controller.get_actor(controller.party_order[index])
		if actor == null: continue
		var rect := card_rect(index)
		var active: bool = actor.actor_id == controller.active_character_id and actor.is_available()
		var retired: bool = not actor.is_available()
		var can_switch: bool = controller.phase == controller.BattlePhase.PLAYER and controller.ap.current >= 1 and not retired
		var tint := Color.WHITE if active else Color(0.55, 0.55, 0.58, 1.0)
		if retired: tint = Color(0.28, 0.26, 0.28, 1)
		canvas.draw_rect(rect, Color("#343027") if active else P.PANEL, true)
		canvas.draw_rect(rect, P.GOLD_LIGHT if active else (P.WARN if retired else P.PANEL_BORDER), false, 1.5)
		var image_rect := Rect2(rect.position + Vector2(5, 5), Vector2(36, 45))
		var portrait_path: String = actor.portrait_path if not actor.portrait_path.is_empty() else "res://assets/actors/portraits/%s.png" % actor.character_id
		var texture := BoardObjectsView._load_cached_texture(portrait_path)
		if texture != null: canvas.draw_texture_rect(texture, image_rect, false, tint)
		else: canvas.draw_string(font, image_rect.position + Vector2(6, 29), actor.glyph, HORIZONTAL_ALIGNMENT_LEFT, 30, 22, tint)
		canvas.draw_string(font, rect.position + Vector2(45, 19), actor.display_name_zh, HORIZONTAL_ALIGNMENT_LEFT, 43, 9 if actor.display_name_zh.length() > 3 else 11, P.TEXT if active else P.TEXT_DIM)
		var label := "上场中" if active else ("已退场" if retired else "1 AP")
		canvas.draw_string(font, rect.position + Vector2(45, 40), label, HORIZONTAL_ALIGNMENT_LEFT, 43, 10, P.GOLD_LIGHT if active or can_switch else P.TEXT_DISABLED)
		var bar := Rect2(rect.position + Vector2(5, 56), Vector2(80, 4))
		canvas.draw_rect(bar, P.HP_BG, true)
		canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(float(actor.health) / maxi(1, actor.max_health), 0, 1), 4)), P.HP_PLAYER * tint, true)
		if retired:
			canvas.draw_line(image_rect.position, image_rect.end, P.WARN, 2)
			canvas.draw_line(Vector2(image_rect.end.x, image_rect.position.y), Vector2(image_rect.position.x, image_rect.end.y), P.WARN, 2)
