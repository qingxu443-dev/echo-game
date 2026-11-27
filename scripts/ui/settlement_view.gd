class_name SettlementView
extends RefCounted

## End-of-battle overlay:
## - On victory with a next stage: opens every Relic Chest that survived on the
##   map (0..N), displays the claimed loot (already placed in the backpack),
##   and offers direct access to Equipment/Backpack before entering next stage.
## - On final victory or defeat: shows full summary and Restart Run button.

const P = preload("res://scripts/ui/theme_palette.gd")
const LootCatalogScript = preload("res://scripts/battle/loot_catalog.gd")

const ACTION_RESTART: String = "restart"
const ACTION_NEXT: String = "next"
const ACTION_OPEN_BAG: String = "open_bag"

const CHEST_PANEL_RECT := Rect2(220.0, 126.0, 840.0, 468.0)
const CHEST_BAG_BTN := Rect2(370.0, 520.0, 240.0, 50.0)
const CHEST_NEXT_BTN := Rect2(660.0, 520.0, 240.0, 50.0)


static func draw(canvas: CanvasItem, controller, level, has_next: bool, claimed_loot: Array[Dictionary] = []) -> void:
	var font := ThemeDB.fallback_font
	var won: bool = controller.battle_result == "victory"

	canvas.draw_rect(Rect2(Vector2.ZERO, P.VIEW_SIZE), P.OVERLAY_SCRIM, true)

	if won and has_next:
		_draw_chest_settlement(canvas, font, controller, level, claimed_loot)
		return

	canvas.draw_rect(P.SETTLEMENT_RECT, P.OVERLAY_BG, true)
	canvas.draw_rect(P.SETTLEMENT_RECT, P.BUTTON_BORDER, false, 2.0)

	var title := "章节通关 · 胜利！" if won else "战败 · 回声消散"
	canvas.draw_string(font, Vector2(370.0, 262.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, P.GOLD_PALE if won else P.WARN)

	var level_name: String = "—" if level == null else str(level.display_name_zh)
	_row(canvas, font, 296.0, "关卡", level_name)
	_row(canvas, font, 324.0, "回合数", "%d" % controller.turn_number)
	_row(canvas, font, 352.0, "造成伤害", "%d" % controller.damage_dealt)
	_row(canvas, font, 380.0, "承受伤害", "%d" % controller.damage_taken)
	_row(canvas, font, 408.0, "击败敌人", "%d" % controller.enemies_defeated)

	var hero = controller.get_active_character()
	var health_label := "—" if hero == null else "%d / %d" % [hero.health, hero.max_health]
	_row(canvas, font, 436.0, "剩余生命", health_label)

	_button(canvas, font, P.RESTART_BTN, "重新开局")
	if won:
		_button(canvas, font, P.NEXT_BTN, "开启新一局")


static func _draw_chest_settlement(canvas: CanvasItem, font: Font, controller, level, claimed_loot: Array[Dictionary]) -> void:
	var rect := CHEST_PANEL_RECT
	canvas.draw_rect(rect, P.OVERLAY_BG, true)
	canvas.draw_rect(rect, P.GOLD, false, 2.2)

	var level_name: String = "—" if level == null else str(level.display_name_zh)
	canvas.draw_string(font, rect.position + Vector2(36.0, 48.0), "胜利 · %s" % level_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, P.GOLD_PALE)

	var hero = controller.get_active_character()
	var hp_str: String = "" if hero == null else "剩余生命 %d / %d（跨关继承）" % [hero.health, hero.max_health]
	canvas.draw_string(font, rect.position + Vector2(36.0, 82.0), "回合 %d   |   造成伤害 %d   |   %s" % [controller.turn_number, controller.damage_dealt, hp_str], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.TEXT_MUTED)

	var total_chests: int = controller.beacons.size()
	var kept_count: int = claimed_loot.size()
	var chest_header: String = "保住遗迹宝箱：%d / %d（战利品已自动收入背包）" % [kept_count, total_chests]
	canvas.draw_string(font, rect.position + Vector2(36.0, 128.0), chest_header, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, P.GOLD_LIGHT if kept_count > 0 else P.WARN)

	if claimed_loot.is_empty():
		var empty_rect := Rect2(rect.position.x + 36.0, rect.position.y + 162.0, rect.size.x - 72.0, 160.0)
		canvas.draw_rect(empty_rect, P.PANEL_DISABLED, true)
		canvas.draw_rect(empty_rect, P.PANEL_BORDER, false, 1.2)
		canvas.draw_string(font, empty_rect.position + Vector2(210.0, 86.0), "本关宝箱均已被怪物拆毁，未获得战利品。", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, P.WARN)
	else:
		var card_h: float = 178.0
		var gap: float = 28.0
		# The panel is 840 wide (768 usable). Cards shrink to share one row instead
		# of running off the right edge: at 3+ chests a fixed 360-wide card would
		# push the row past the panel and get clipped.
		var usable_w: float = rect.size.x - 72.0
		var card_w: float = minf(360.0, (usable_w - float(kept_count - 1) * gap) / float(kept_count))
		var total_w: float = float(kept_count) * card_w + float(kept_count - 1) * gap
		var start_x: float = rect.position.x + (rect.size.x - total_w) * 0.5
		var y: float = rect.position.y + 158.0
		for i in range(kept_count):
			_draw_loot_card(canvas, font, Rect2(start_x + float(i) * (card_w + gap), y, card_w, card_h), claimed_loot[i])

	_button(canvas, font, CHEST_BAG_BTN, "装备 / 背包 [B]")
	_button(canvas, font, CHEST_NEXT_BTN, "进入下一关")


static func _draw_loot_card(canvas: CanvasItem, font: Font, card: Rect2, item: Dictionary) -> void:
	var kind: String = str(item.get("kind", ""))
	var accent := P.GOLD_LIGHT
	match kind:
		LootCatalogScript.KIND_ARMOR:
			accent = P.CYAN
		LootCatalogScript.KIND_CONSUMABLE:
			accent = P.HP_PLAYER
		LootCatalogScript.KIND_SKILL_UPGRADE:
			accent = P.RING_MARK
	canvas.draw_rect(card, P.PANEL, true)
	canvas.draw_rect(card, accent, false, 2.0)
	canvas.draw_rect(Rect2(card.position, Vector2(card.size.x, 6.0)), accent, true)
	canvas.draw_string(font, card.position + Vector2(18.0, 36.0), str(item.get("kind_zh", "战利品")), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, accent)
	canvas.draw_string(font, card.position + Vector2(18.0, 72.0), str(item.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, P.TEXT)
	_draw_wrapped(canvas, font, str(item.get("desc", "")), card.position + Vector2(18.0, 108.0), card.size.x - 36.0, 14, P.TEXT_BODY, 3)


static func hit(position: Vector2, won: bool, has_next: bool = false) -> String:
	if won and has_next:
		if CHEST_BAG_BTN.has_point(position):
			return ACTION_OPEN_BAG
		if CHEST_NEXT_BTN.has_point(position):
			return ACTION_NEXT
		return ""
	if P.RESTART_BTN.has_point(position):
		return ACTION_RESTART
	if won and P.NEXT_BTN.has_point(position):
		return ACTION_NEXT
	return ""


static func _row(canvas: CanvasItem, font: Font, y: float, label: String, value: String) -> void:
	canvas.draw_string(font, Vector2(390.0, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.TEXT_DIM)
	var value_width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	canvas.draw_string(font, Vector2(910.0 - value_width, y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, P.TEXT)


static func _button(canvas: CanvasItem, font: Font, rect: Rect2, label: String) -> void:
	canvas.draw_rect(rect, P.BUTTON_BG, true)
	canvas.draw_rect(rect, P.BUTTON_BORDER, false, 2.0)
	var text_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	canvas.draw_string(font, rect.position + Vector2((rect.size.x - text_width) * 0.5, 32.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, P.BUTTON_TEXT)


static func _draw_wrapped(canvas: CanvasItem, font: Font, text: String, pos: Vector2, max_width: float, size: int, color: Color, max_lines: int) -> void:
	var lines: Array[String] = []
	var current := ""
	for i in range(text.length()):
		var ch := text.substr(i, 1)
		var trial := current + ch
		if current != "" and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_width:
			lines.append(current)
			current = ch
		else:
			current = trial
	if current != "":
		lines.append(current)
	var y := pos.y
	for i in range(mini(lines.size(), max_lines)):
		canvas.draw_string(font, Vector2(pos.x, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		y += float(size) + 6.0
