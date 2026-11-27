class_name SpringShopView
extends RefCounted

## 春日行商 overlay (设计汇总 2026-11-26 §7): buy / sell / service in one panel.
##
## Same contract as the event panel: draw what the shop object says, report which
## row was clicked, and let SpringShop decide whether the trade is legal. The view
## never moves coins - if it did, a mis-click could take money without goods.

const P = preload("res://scripts/ui/theme_palette.gd")
const ShopScript = preload("res://scripts/spring/spring_shop.gd")

const PANEL := Rect2(140.0, 68.0, 1000.0, 596.0)
const TITLE_POS := Vector2(176.0, 118.0)
const CLOSE_BTN := Rect2(1032.0, 84.0, 84.0, 34.0)
const TAB_TOP: float = 134.0
const TAB_W: float = 140.0
const TAB_H: float = 34.0
const TAB_GAP: float = 8.0
const TAB_LEFT: float = 176.0
const ROW_TOP: float = 196.0
const ROW_H: float = 62.0
const ROW_GAP: float = 8.0
const ROW_LEFT: float = 176.0
const ROW_WIDTH: float = 928.0
const ROWS_PER_PAGE: int = 6
const FOOTER_Y: float = 592.0
const REFRESH_BTN := Rect2(176.0, 592.0, 240.0, 44.0)
const PAGE_PREV_BTN := Rect2(700.0, 592.0, 100.0, 44.0)
const PAGE_NEXT_BTN := Rect2(808.0, 592.0, 100.0, 44.0)
const ACTION_BTN := Rect2(960.0, 592.0, 144.0, 44.0)

const TAB_BUY: int = 0
const TAB_SELL: int = 1
const TAB_SERVICE: int = 2
const TAB_LABELS: Array[String] = ["购买", "出售", "服务"]

const ACTION_NONE: String = ""
const ACTION_CLOSE: String = "close"
const ACTION_TAB: String = "tab"
const ACTION_BUY: String = "buy"
const ACTION_SELL: String = "sell"
const ACTION_REFRESH: String = "refresh"
const ACTION_SERVICE: String = "service"
const ACTION_PAGE_PREV: String = "page_prev"
const ACTION_PAGE_NEXT: String = "page_next"


static func tab_rect(index: int) -> Rect2:
	return Rect2(TAB_LEFT + float(index) * (TAB_W + TAB_GAP), TAB_TOP, TAB_W, TAB_H)


static func row_rect(index: int) -> Rect2:
	return Rect2(ROW_LEFT, ROW_TOP + float(index) * (ROW_H + ROW_GAP), ROW_WIDTH, ROW_H)


static func draw(canvas: CanvasItem, shop, run, tab: int, sell_page: int, message: String) -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_rect(Rect2(Vector2.ZERO, P.VIEW_SIZE), P.OVERLAY_SCRIM, true)
	canvas.draw_rect(PANEL, P.OVERLAY_BG, true)
	canvas.draw_rect(PANEL, P.GOLD, false, 2.0)

	canvas.draw_string(font, TITLE_POS, "春日行商", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, P.GOLD_PALE)
	canvas.draw_string(font, Vector2(560.0, 118.0), "花钿 %d   补给 %d   残页 %d" % [run.coins, run.supplies, run.memory_pages], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.GOLD_LIGHT)
	if shop != null and not is_equal_approx(shop.price_multiplier, 1.0):
		var tag: String = "行情：%d%%" % int(round(shop.price_multiplier * 100.0))
		canvas.draw_string(font, Vector2(820.0, 118.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.CYAN)

	canvas.draw_rect(CLOSE_BTN, P.BUTTON_BG, true)
	canvas.draw_rect(CLOSE_BTN, P.BUTTON_BORDER, false, 1.4)
	canvas.draw_string(font, CLOSE_BTN.position + Vector2(18.0, 23.0), "离开", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.BUTTON_TEXT)

	for index in range(TAB_LABELS.size()):
		var rect := tab_rect(index)
		var active: bool = index == tab
		canvas.draw_rect(rect, P.BUTTON_BG if active else P.PANEL_DISABLED, true)
		canvas.draw_rect(rect, P.BUTTON_BORDER if active else P.PANEL_BORDER, false, 1.4)
		canvas.draw_string(font, rect.position + Vector2(44.0, 23.0), TAB_LABELS[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.BUTTON_TEXT if active else P.TEXT_MUTED)

	match tab:
		TAB_BUY:
			_draw_buy(canvas, font, shop, run)
		TAB_SELL:
			_draw_sell(canvas, font, run, sell_page)
		TAB_SERVICE:
			_draw_service(canvas, font, shop, run)

	if not message.is_empty():
		canvas.draw_string(font, Vector2(176.0, 566.0), message, HORIZONTAL_ALIGNMENT_LEFT, 928.0, 15, P.TEXT_BODY)


static func _draw_buy(canvas: CanvasItem, font: Font, shop, run) -> void:
	if shop == null:
		canvas.draw_string(font, Vector2(ROW_LEFT, ROW_TOP + 30.0), "货架还是空的。", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.TEXT_DIM)
		return
	for index in range(mini(ROWS_PER_PAGE, shop.stock.size())):
		var entry: Dictionary = shop.stock[index]
		var rect := row_rect(index)
		var remaining: int = int(entry.get("remaining", 0))
		var price: int = int(entry.get("price", 0))
		var affordable: bool = remaining > 0 and run.coins >= price
		canvas.draw_rect(rect, P.PANEL if remaining > 0 else P.PANEL_DISABLED, true)
		canvas.draw_rect(rect, P.PANEL_BORDER if remaining > 0 else P.PANEL_BORDER_DISABLED, false, 1.2)
		canvas.draw_string(font, rect.position + Vector2(18.0, 26.0), str(entry.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, 620.0, 17, P.TEXT if remaining > 0 else P.TEXT_DISABLED)
		canvas.draw_string(font, rect.position + Vector2(18.0, 48.0), str(entry.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, 620.0, 12, P.TEXT_MUTED)
		var price_label: String = "%d 花钿" % price
		if remaining <= 0:
			price_label = "已售完"
		canvas.draw_string(font, rect.position + Vector2(680.0, 28.0), price_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.GOLD_LIGHT if affordable else P.TEXT_DISABLED)
		canvas.draw_string(font, rect.position + Vector2(680.0, 50.0), "余 %d" % remaining, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.TEXT_MUTED)
		if remaining > 0:
			var buy_rect := Rect2(rect.position.x + rect.size.x - 128.0, rect.position.y + 14.0, 108.0, 34.0)
			canvas.draw_rect(buy_rect, P.BUTTON_BG if affordable else P.BUTTON_BG_DISABLED, true)
			canvas.draw_rect(buy_rect, P.BUTTON_BORDER if affordable else P.PANEL_BORDER, false, 1.2)
			canvas.draw_string(font, buy_rect.position + Vector2(36.0, 23.0), "买入", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.BUTTON_TEXT if affordable else P.TEXT_DISABLED)

	_draw_button(canvas, font, REFRESH_BTN, "刷新货架（%d 花钿）" % shop.refresh_cost(), run.coins >= shop.refresh_cost())


static func _draw_sell(canvas: CanvasItem, font: Font, run, page: int) -> void:
	var bag: Array = run.battle_backpack()
	if bag.is_empty():
		canvas.draw_string(font, Vector2(ROW_LEFT, ROW_TOP + 30.0), "背包里没有可以出售的东西。战利品会随战斗回来。", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.TEXT_DIM)
		return
	var pages: int = maxi(1, int(ceil(float(bag.size()) / float(ROWS_PER_PAGE))))
	var current: int = clampi(page, 0, pages - 1)
	var start: int = current * ROWS_PER_PAGE
	for offset in range(ROWS_PER_PAGE):
		var index: int = start + offset
		if index >= bag.size():
			break
		var item: Dictionary = bag[index]
		var rect := row_rect(offset)
		var price: int = ShopScript.sell_price(item)
		canvas.draw_rect(rect, P.PANEL, true)
		canvas.draw_rect(rect, P.PANEL_BORDER, false, 1.2)
		canvas.draw_string(font, rect.position + Vector2(18.0, 26.0), str(item.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, 620.0, 17, P.TEXT)
		canvas.draw_string(font, rect.position + Vector2(18.0, 48.0), str(item.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, 620.0, 12, P.TEXT_MUTED)
		canvas.draw_string(font, rect.position + Vector2(680.0, 30.0), "%d 花钿" % price, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.GOLD_LIGHT)
		var sell_rect := Rect2(rect.position.x + rect.size.x - 128.0, rect.position.y + 14.0, 108.0, 34.0)
		canvas.draw_rect(sell_rect, P.BUTTON_BG, true)
		canvas.draw_rect(sell_rect, P.BUTTON_BORDER, false, 1.2)
		canvas.draw_string(font, sell_rect.position + Vector2(36.0, 23.0), "卖出", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.BUTTON_TEXT)

	canvas.draw_string(font, Vector2(PAGE_PREV_BTN.position.x - 120.0, FOOTER_Y + 28.0), "第 %d / %d 页" % [current + 1, pages], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.TEXT_MUTED)
	_draw_button(canvas, font, PAGE_PREV_BTN, "上一页", current > 0)
	_draw_button(canvas, font, PAGE_NEXT_BTN, "下一页", current < pages - 1)


static func _draw_service(canvas: CanvasItem, font: Font, shop, run) -> void:
	if shop == null:
		return
	var rect := row_rect(0)
	var used: bool = shop.services_done.has(ShopScript.SERVICE_REST)
	var full: bool = run.hero_health >= run.hero_max_health
	var enabled: bool = not used and not full and run.coins >= ShopScript.SERVICE_REST_COST
	canvas.draw_rect(rect, P.PANEL if enabled else P.PANEL_DISABLED, true)
	canvas.draw_rect(rect, P.PANEL_BORDER, false, 1.2)
	canvas.draw_string(font, rect.position + Vector2(18.0, 26.0), ShopScript.service_label(ShopScript.SERVICE_REST), HORIZONTAL_ALIGNMENT_LEFT, 620.0, 17, P.TEXT if enabled else P.TEXT_DISABLED)
	var note: String = "生命 %d / %d" % [run.hero_health, run.hero_max_health]
	if used:
		note = "这次已经疗养过了。"
	elif full:
		note = "生命已满。"
	canvas.draw_string(font, rect.position + Vector2(18.0, 48.0), note, HORIZONTAL_ALIGNMENT_LEFT, 620.0, 12, P.TEXT_MUTED)
	var action_rect := Rect2(rect.position.x + rect.size.x - 128.0, rect.position.y + 14.0, 108.0, 34.0)
	canvas.draw_rect(action_rect, P.BUTTON_BG if enabled else P.BUTTON_BG_DISABLED, true)
	canvas.draw_rect(action_rect, P.BUTTON_BORDER if enabled else P.PANEL_BORDER, false, 1.2)
	canvas.draw_string(font, action_rect.position + Vector2(36.0, 23.0), "疗养", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.BUTTON_TEXT if enabled else P.TEXT_DISABLED)


static func _draw_button(canvas: CanvasItem, font: Font, rect: Rect2, label: String, enabled: bool) -> void:
	canvas.draw_rect(rect, P.BUTTON_BG if enabled else P.BUTTON_BG_DISABLED, true)
	canvas.draw_rect(rect, P.BUTTON_BORDER if enabled else P.PANEL_BORDER, false, 1.3)
	canvas.draw_string(font, rect.position + Vector2(18.0, 28.0), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 14, P.BUTTON_TEXT if enabled else P.TEXT_DISABLED)


static func hit(position: Vector2, shop, run, tab: int, sell_page: int) -> Dictionary:
	if CLOSE_BTN.has_point(position):
		return {"action": ACTION_CLOSE, "index": -1}
	for index in range(TAB_LABELS.size()):
		if tab_rect(index).has_point(position):
			return {"action": ACTION_TAB, "index": index}

	match tab:
		TAB_BUY:
			if shop != null:
				if REFRESH_BTN.has_point(position):
					return {"action": ACTION_REFRESH, "index": -1}
				for index in range(mini(ROWS_PER_PAGE, shop.stock.size())):
					var entry: Dictionary = shop.stock[index]
					if int(entry.get("remaining", 0)) <= 0:
						continue
					var row := row_rect(index)
					var buy_rect := Rect2(row.position.x + row.size.x - 128.0, row.position.y + 14.0, 108.0, 34.0)
					if buy_rect.has_point(position):
						return {"action": ACTION_BUY, "index": index}
		TAB_SELL:
			var bag: Array = run.battle_backpack()
			var pages: int = maxi(1, int(ceil(float(bag.size()) / float(ROWS_PER_PAGE))))
			var current: int = clampi(sell_page, 0, pages - 1)
			if PAGE_PREV_BTN.has_point(position) and current > 0:
				return {"action": ACTION_PAGE_PREV, "index": -1}
			if PAGE_NEXT_BTN.has_point(position) and current < pages - 1:
				return {"action": ACTION_PAGE_NEXT, "index": -1}
			var start: int = current * ROWS_PER_PAGE
			for offset in range(ROWS_PER_PAGE):
				var index: int = start + offset
				if index >= bag.size():
					break
				var row := row_rect(offset)
				var sell_rect := Rect2(row.position.x + row.size.x - 128.0, row.position.y + 14.0, 108.0, 34.0)
				if sell_rect.has_point(position):
					return {"action": ACTION_SELL, "index": index}
		TAB_SERVICE:
			var service_row := row_rect(0)
			var action_rect := Rect2(service_row.position.x + service_row.size.x - 128.0, service_row.position.y + 14.0, 108.0, 34.0)
			if action_rect.has_point(position):
				return {"action": ACTION_SERVICE, "index": 0}
	return {"action": ACTION_NONE, "index": -1}
