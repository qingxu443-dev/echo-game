extends RefCounted

const P = preload("res://scripts/ui/theme_palette.gd")
const CollectibleCatalogScript = preload("res://scripts/spring/spring_collectible_catalog.gd")
const BridgeScript = preload("res://scripts/spring/spring_battle_bridge.gd")


static func draw_reward_choices(view) -> void:
	var font := ThemeDB.fallback_font
	view.draw_rect(Rect2(Vector2.ZERO, view.VIEW), P.OVERLAY_SCRIM, true)
	var panel := Rect2(180.0, 140.0, 920.0, 420.0)
	view.draw_rect(panel, P.OVERLAY_BG, true)
	view.draw_rect(panel, P.GOLD, false, 2.0)
	view.draw_string(font, Vector2(216.0, 196.0), "精英战利品 · 三选一", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, P.GOLD_PALE)
	view.draw_string(font, Vector2(216.0, 226.0), "只出现普通与稀有品质；被动藏品不重复，主动消耗品可重复获得。", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.TEXT_MUTED)
	for index in range(view.run.reward_choices.size()):
		var rect := reward_card_rect(index)
		var collectible_id: StringName = view.run.reward_choices[index]
		view.draw_rect(rect, P.PANEL, true)
		view.draw_rect(rect, P.BUTTON_BORDER, false, 1.4)
		view.draw_string(font, rect.position + Vector2(18.0, 30.0), CollectibleCatalogScript.name_of(collectible_id), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 18, P.GOLD_LIGHT)
		view.draw_string(font, rect.position + Vector2(18.0, 56.0), CollectibleCatalogScript.rarity_of(collectible_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.CYAN)
		view.draw_string(font, rect.position + Vector2(18.0, 84.0), CollectibleCatalogScript.desc_of(collectible_id), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 13, P.TEXT_BODY)


static func reward_card_rect(index: int) -> Rect2:
	return Rect2(216.0 + float(index) * 300.0, 260.0, 280.0, 180.0)


static func draw_collectibles(view) -> void:
	view.draw_rect(Rect2(Vector2.ZERO, view.VIEW), P.OVERLAY_SCRIM, true)
	view.draw_rect(view.COLLECTIBLE_PANEL, P.OVERLAY_BG, true)
	view.draw_rect(view.COLLECTIBLE_PANEL, P.GOLD, false, 2.0)
	var font := ThemeDB.fallback_font
	view.draw_string(font, Vector2(336.0, 150.0), "藏品", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, P.GOLD_PALE)
	view.draw_string(font, Vector2(336.0, 178.0), "被动藏品自动生效；主动消耗品可在这里选择使用。", HORIZONTAL_ALIGNMENT_LEFT, 590.0, 13, P.TEXT_MUTED)
	view.draw_rect(view.COLLECTIBLES_CLOSE, P.BUTTON_BG, true)
	view.draw_rect(view.COLLECTIBLES_CLOSE, P.BUTTON_BORDER, false, 1.2)
	view.draw_string(font, view.COLLECTIBLES_CLOSE.position + Vector2(18.0, 23.0), "关闭", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.BUTTON_TEXT)
	var row: int = 0
	for item_id in CollectibleCatalogScript.all_ids():
		var id := StringName(item_id)
		var consumable: bool = CollectibleCatalogScript.is_consumable(id)
		var count: int = int(view.run.collectible_consumables.get(item_id, 0)) if consumable else (1 if view.run.collectibles.has(id) else 0)
		if count <= 0:
			continue
		var y: float = 212.0 + float(row) * 46.0
		view.draw_string(font, Vector2(336.0, y + 16.0), CollectibleCatalogScript.name_of(id), HORIZONTAL_ALIGNMENT_LEFT, 190.0, 15, P.GOLD_LIGHT if consumable else P.TEXT_BODY)
		view.draw_string(font, Vector2(540.0, y + 16.0), CollectibleCatalogScript.desc_of(id), HORIZONTAL_ALIGNMENT_LEFT, 290.0, 12, P.TEXT_MUTED)
		if consumable:
			var use_rect := Rect2(850.0, y - 8.0, 96.0, 30.0)
			view.draw_rect(use_rect, P.BUTTON_BG, true)
			view.draw_rect(use_rect, P.BUTTON_BORDER, false, 1.0)
			view.draw_string(font, use_rect.position + Vector2(30.0, 20.0), "使用 ×%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.BUTTON_TEXT)
		else:
			view.draw_string(font, Vector2(884.0, y + 14.0), "已生效", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.CYAN)
		row += 1
	if row == 0:
		view.draw_string(font, Vector2(336.0, 250.0), "尚未获得藏品。", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.TEXT_MUTED)


static func handle_collectible_tap(view, point: Vector2) -> void:
	if view.COLLECTIBLES_CLOSE.has_point(point):
		view.collectible_open = false
		return
	var row: int = 0
	for item_id in CollectibleCatalogScript.all_ids():
		var id := StringName(item_id)
		var consumable: bool = CollectibleCatalogScript.is_consumable(id)
		var count: int = int(view.run.collectible_consumables.get(item_id, 0)) if consumable else (1 if view.run.collectibles.has(id) else 0)
		if count <= 0:
			continue
		if consumable:
			var use_rect := Rect2(850.0, 204.0 + float(row) * 46.0, 96.0, 30.0)
			if use_rect.has_point(point):
				var used: Dictionary = view.run.use_collectible(id)
				view.status_message = str(used.get("message", ""))
				if bool(used.get("ok", false)):
					view._save()
				return
		row += 1


static func draw_revive_prompt(view) -> void:
	var font := ThemeDB.fallback_font
	view.draw_rect(Rect2(Vector2.ZERO, view.VIEW), P.OVERLAY_SCRIM, true)
	var panel := Rect2(300.0, 240.0, 680.0, 240.0)
	view.draw_rect(panel, P.OVERLAY_BG, true)
	view.draw_rect(panel, P.WARN, false, 2.0)
	view.draw_string(font, Vector2(340.0, 296.0), "这一处失守了", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, P.WARN)
	view.draw_string(font, Vector2(340.0, 330.0), "每个区域可以续行一次：消耗 %d 份补给，回复至三成生命。" % BridgeScript.CONTINUE_SUPPLY_COST, HORIZONTAL_ALIGNMENT_LEFT, 600.0, 14, P.TEXT_BODY)
	view.draw_string(font, Vector2(340.0, 356.0), "现有补给 %d 份。" % view.run.supplies, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.TEXT_MUTED)
	view._draw_button(view.REVIVE_YES, "续行", BridgeScript.can_continue(view.run))
	view._draw_button(view.REVIVE_NO, "结束本局", true)
