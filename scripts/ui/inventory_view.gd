class_name InventoryView
extends RefCounted

## Toggleable Equipment & Backpack overlay (hotkey B or top-left button).
## - Click an equipped weapon/armor slot to unequip back to backpack.
## - Click a backpack item to equip (weapon/armor), use (consumable), or activate (skill upgrade).

const P = preload("res://scripts/ui/theme_palette.gd")
const LootCatalogScript = preload("res://scripts/battle/loot_catalog.gd")

const PANEL_RECT := Rect2(190.0, 96.0, 900.0, 520.0)
const CLOSE_BTN := Rect2(968.0, 112.0, 102.0, 32.0)
const WEAPON_SLOT_RECT := Rect2(220.0, 178.0, 240.0, 104.0)
const ARMOR_SLOT_RECT := Rect2(220.0, 300.0, 240.0, 104.0)

const ACTION_CLOSE: String = "close"
const ACTION_UNEQUIP_WEAPON: String = "unequip_weapon"
const ACTION_UNEQUIP_ARMOR: String = "unequip_armor"
const ACTION_BAG_PREFIX: String = "bag:"
const ACTION_PAGE_PREV: String = "page_prev"
const ACTION_PAGE_NEXT: String = "page_next"

## Cards the panel can show at once: 2 columns x 4 rows. Anything beyond that is
## paged rather than dropped, so a long run's 9th+ item stays reachable.
const PAGE_SIZE: int = 8
const PAGE_PREV_RECT := Rect2(492.0, 588.0, 96.0, 26.0)
const PAGE_NEXT_RECT := Rect2(964.0, 588.0, 96.0, 26.0)


static func bag_card_rect(index: int) -> Rect2:
	var col: int = index % 2
	var row: int = index / 2
	var w: float = 276.0
	var h: float = 92.0
	var gap_x: float = 16.0
	var gap_y: float = 12.0
	return Rect2(
		492.0 + float(col) * (w + gap_x),
		178.0 + float(row) * (h + gap_y),
		w,
		h
	)


static func draw(canvas: CanvasItem, run_state, hero, page: int = 0) -> void:
	if run_state == null:
		return
	var font := ThemeDB.fallback_font
	canvas.draw_rect(Rect2(Vector2.ZERO, P.VIEW_SIZE), P.OVERLAY_SCRIM, true)
	canvas.draw_rect(PANEL_RECT, P.OVERLAY_BG, true)
	canvas.draw_rect(PANEL_RECT, P.GOLD, false, 2.0)

	canvas.draw_string(font, PANEL_RECT.position + Vector2(30.0, 40.0), "装备与背包", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, P.GOLD_PALE)
	canvas.draw_string(font, PANEL_RECT.position + Vector2(174.0, 38.0), "穿脱实时生效 · 战局结束全部清空", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.TEXT_MUTED)

	# Close button
	canvas.draw_rect(CLOSE_BTN, P.BUTTON_BG, true)
	canvas.draw_rect(CLOSE_BTN, P.BUTTON_BORDER, false, 1.5)
	canvas.draw_string(font, CLOSE_BTN.position + Vector2(16.0, 21.0), "关闭 [B]", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.BUTTON_TEXT)

	# Left column: Equipment slots + live stats
	canvas.draw_string(font, Vector2(220.0, 166.0), "当前装备（点击可卸下）", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.GOLD)
	_draw_equip_slot(canvas, font, WEAPON_SLOT_RECT, "武器槽", run_state.equipped_weapon, P.GOLD_LIGHT)
	_draw_equip_slot(canvas, font, ARMOR_SLOT_RECT, "护甲槽", run_state.equipped_armor, P.CYAN)

	var stat_rect := Rect2(220.0, 424.0, 240.0, 164.0)
	canvas.draw_rect(stat_rect, P.PANEL, true)
	canvas.draw_rect(stat_rect, P.PANEL_BORDER, false, 1.2)
	canvas.draw_string(font, stat_rect.position + Vector2(14.0, 26.0), "瑟弗林当前属性", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.TEXT)
	var hp_now: int = hero.health if hero != null else run_state.hero_health
	var hp_max: int = hero.max_health if hero != null else run_state.effective_max_health()
	canvas.draw_string(font, stat_rect.position + Vector2(14.0, 56.0), "生命  %d / %d" % [hp_now, hp_max], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.HP_PLAYER)
	canvas.draw_string(font, stat_rect.position + Vector2(14.0, 82.0), "攻击  %d" % run_state.effective_attack(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.GOLD_PALE)
	canvas.draw_string(font, stat_rect.position + Vector2(14.0, 108.0), "防御  %d" % run_state.effective_defense(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.TEXT_BODY)
	canvas.draw_string(font, stat_rect.position + Vector2(14.0, 134.0), "魔抗  %d   撞击 %d" % [run_state.effective_magic_resistance(), run_state.collision_damage()], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.CYAN)

	# Right column: Backpack items
	var count: int = run_state.backpack.size()
	canvas.draw_string(font, Vector2(492.0, 166.0), "背包物品 (%d) · 点击穿戴 / 使用" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.GOLD)
	if count == 0:
		canvas.draw_string(font, Vector2(492.0, 224.0), "背包空空如也。走到遗迹宝箱旁 1 格点击即可免费开箱！", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.TEXT_DIM)
		return

	var pages: int = maxi(1, int(ceil(float(count) / float(PAGE_SIZE))))
	var current: int = clampi(page, 0, pages - 1)
	var start: int = current * PAGE_SIZE
	var shown: int = mini(PAGE_SIZE, count - start)
	for i in range(shown):
		_draw_bag_card(canvas, font, bag_card_rect(i), run_state.backpack[start + i])

	if pages > 1:
		_draw_page_controls(canvas, font, current, pages)


static func _draw_page_controls(canvas: CanvasItem, font: Font, page: int, pages: int) -> void:
	if page > 0:
		canvas.draw_rect(PAGE_PREV_RECT, P.BUTTON_BG, true)
		canvas.draw_rect(PAGE_PREV_RECT, P.BUTTON_BORDER, false, 1.2)
		canvas.draw_string(font, PAGE_PREV_RECT.position + Vector2(14.0, 18.0), "上一页", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.BUTTON_TEXT)
	if page < pages - 1:
		canvas.draw_rect(PAGE_NEXT_RECT, P.BUTTON_BG, true)
		canvas.draw_rect(PAGE_NEXT_RECT, P.BUTTON_BORDER, false, 1.2)
		canvas.draw_string(font, PAGE_NEXT_RECT.position + Vector2(14.0, 18.0), "下一页", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.BUTTON_TEXT)
	var label := "%d / %d" % [page + 1, pages]
	var lw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	canvas.draw_string(font, Vector2(776.0 - lw * 0.5, 605.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.TEXT_MUTED)


static func _draw_equip_slot(canvas: CanvasItem, font: Font, rect: Rect2, title: String, item: Dictionary, accent: Color) -> void:
	canvas.draw_rect(rect, P.PANEL, true)
	canvas.draw_rect(rect, accent if not item.is_empty() else P.PANEL_BORDER, false, 1.8 if not item.is_empty() else 1.2)
	canvas.draw_string(font, rect.position + Vector2(12.0, 22.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, accent)
	if item.is_empty():
		canvas.draw_string(font, rect.position + Vector2(12.0, 56.0), "空槽位", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.TEXT_DISABLED)
		return
	canvas.draw_string(font, rect.position + Vector2(12.0, 48.0), str(item.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, P.TEXT)
	canvas.draw_string(font, rect.position + Vector2(12.0, 72.0), str(item.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 12, P.TEXT_BODY)
	canvas.draw_string(font, rect.position + Vector2(12.0, 93.0), "[点击卸下回背包]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.TEXT_DIM)


static func _draw_bag_card(canvas: CanvasItem, font: Font, rect: Rect2, item: Dictionary) -> void:
	var kind: String = str(item.get("kind", ""))
	var accent := P.GOLD_LIGHT
	var action_hint := "点击穿戴"
	match kind:
		LootCatalogScript.KIND_ARMOR:
			accent = P.CYAN
			action_hint = "点击穿戴"
		LootCatalogScript.KIND_CONSUMABLE:
			accent = P.HP_PLAYER
			action_hint = "点击使用"
		LootCatalogScript.KIND_SKILL_UPGRADE:
			accent = P.RING_MARK
			action_hint = "点击激活"
	canvas.draw_rect(rect, P.PANEL, true)
	canvas.draw_rect(rect, accent, false, 1.5)
	canvas.draw_rect(Rect2(rect.position, Vector2(5.0, rect.size.y)), accent, true)
	canvas.draw_string(font, rect.position + Vector2(14.0, 22.0), str(item.get("kind_zh", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, accent)
	canvas.draw_string(font, rect.position + Vector2(rect.size.x - 62.0, 22.0), action_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.TEXT_DIM)
	canvas.draw_string(font, rect.position + Vector2(14.0, 46.0), str(item.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.TEXT)
	canvas.draw_string(font, rect.position + Vector2(14.0, 72.0), str(item.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 12, P.TEXT_BODY)


static func hit(position: Vector2, bag_count: int, page: int = 0) -> String:
	if CLOSE_BTN.has_point(position) or not PANEL_RECT.has_point(position):
		return ACTION_CLOSE
	if WEAPON_SLOT_RECT.has_point(position):
		return ACTION_UNEQUIP_WEAPON
	if ARMOR_SLOT_RECT.has_point(position):
		return ACTION_UNEQUIP_ARMOR
	var pages: int = maxi(1, int(ceil(float(bag_count) / float(PAGE_SIZE))))
	var current: int = clampi(page, 0, pages - 1)
	if pages > 1:
		if current > 0 and PAGE_PREV_RECT.has_point(position):
			return ACTION_PAGE_PREV
		if current < pages - 1 and PAGE_NEXT_RECT.has_point(position):
			return ACTION_PAGE_NEXT
	var start: int = current * PAGE_SIZE
	var shown: int = mini(PAGE_SIZE, bag_count - start)
	for i in range(shown):
		if bag_card_rect(i).has_point(position):
			return ACTION_BAG_PREFIX + str(start + i)
	return ""
