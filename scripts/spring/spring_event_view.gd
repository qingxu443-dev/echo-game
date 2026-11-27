class_name SpringEventView
extends RefCounted

## The event overlay: title, risk label, body, options (or the outcome once one
## has been taken). Drawing and hit-testing share the same rect helpers so the
## button the player sees is the button the click finds.
##
## The panel never resolves anything itself - it only reports which option was
## clicked. Resolution lives in SpringEventCatalog, because whether a choice costs
## 20 花钿 is a rule, not a layout detail.

const P = preload("res://scripts/ui/theme_palette.gd")
const CatalogScript = preload("res://scripts/spring/spring_event_catalog.gd")

const PANEL := Rect2(180.0, 84.0, 920.0, 572.0)
const TITLE_POS := Vector2(216.0, 140.0)
const RISK_POS := Vector2(216.0, 176.0)
const BODY_POS := Vector2(216.0, 216.0)
const OPTION_TOP: float = 268.0
const OPTION_H: float = 62.0
const OPTION_GAP: float = 10.0
const OPTION_LEFT: float = 216.0
const OPTION_WIDTH: float = 848.0
const LOG_TOP: float = 268.0
const CLOSE_BTN := Rect2(468.0, 588.0, 264.0, 44.0)

const ACTION_NONE: String = ""
const ACTION_OPTION: String = "option"
const ACTION_CLOSE: String = "close"


static func option_rect(index: int) -> Rect2:
	return Rect2(OPTION_LEFT, OPTION_TOP + float(index) * (OPTION_H + OPTION_GAP), OPTION_WIDTH, OPTION_H)


static func risk_color(risk: String) -> Color:
	match risk:
		CatalogScript.RISK_SAFE:
			return P.GOLD_LIGHT
		CatalogScript.RISK_UNKNOWN:
			return P.TEXT_MUTED
		CatalogScript.RISK_DANGER:
			return P.WARN
		CatalogScript.RISK_HIGH:
			return P.HP_ENEMY
	return P.TEXT_MUTED


## `result` is empty until an option has been taken. Once it is not, the panel
## switches to the outcome: the log lines and a way out. That mirrors §10.4 - an
## event is resolved once and never re-offered.
static func draw(canvas: CanvasItem, run, event_id: StringName, result: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_rect(Rect2(Vector2.ZERO, P.VIEW_SIZE), P.OVERLAY_SCRIM, true)
	canvas.draw_rect(PANEL, P.OVERLAY_BG, true)
	canvas.draw_rect(PANEL, P.GOLD, false, 2.0)

	canvas.draw_string(font, TITLE_POS, CatalogScript.title_of(event_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, P.GOLD_PALE)

	var risk: String = CatalogScript.risk_of(event_id)
	canvas.draw_string(font, RISK_POS, "风险 · %s" % risk, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, risk_color(risk))

	var body: String = CatalogScript.body_of(event_id)
	canvas.draw_string(font, BODY_POS, body, HORIZONTAL_ALIGNMENT_LEFT, OPTION_WIDTH, 16, P.TEXT_BODY)

	if result.is_empty():
		_draw_options(canvas, font, run, event_id)
	else:
		_draw_outcome(canvas, font, result)


static func _draw_options(canvas: CanvasItem, font: Font, run, event_id: StringName) -> void:
	var count: int = CatalogScript.option_count(event_id)
	for index in range(count):
		var rect := option_rect(index)
		var affordable: bool = CatalogScript.can_afford(run, event_id, index)
		var fill: Color = P.BUTTON_BG if affordable else P.PANEL_DISABLED
		canvas.draw_rect(rect, fill, true)
		canvas.draw_rect(rect, P.BUTTON_BORDER if affordable else P.PANEL_BORDER, false, 1.6)
		var label_color: Color = P.BUTTON_TEXT if affordable else P.TEXT_DISABLED
		canvas.draw_string(font, rect.position + Vector2(20.0, 26.0), CatalogScript.option_label(event_id, index), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, label_color)
		var hint: String = CatalogScript.option_hint(event_id, index)
		if not affordable:
			hint = "（条件不足）" + hint
		canvas.draw_string(font, rect.position + Vector2(20.0, 48.0), hint, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40.0, 13, P.TEXT_MUTED)


static func _draw_outcome(canvas: CanvasItem, font: Font, result: Dictionary) -> void:
	var y: float = LOG_TOP
	for line in result.get("log", []):
		canvas.draw_string(font, Vector2(OPTION_LEFT, y), "· %s" % str(line), HORIZONTAL_ALIGNMENT_LEFT, OPTION_WIDTH, 16, P.TEXT_BODY)
		y += 28.0
	if str(result.get("battle", "")) != "":
		canvas.draw_string(font, Vector2(OPTION_LEFT, y + 6.0), "有什么挡在了路上 —— 关闭这一页就会开战。", HORIZONTAL_ALIGNMENT_LEFT, OPTION_WIDTH, 15, P.WARN)

	canvas.draw_rect(CLOSE_BTN, P.BUTTON_BG, true)
	canvas.draw_rect(CLOSE_BTN, P.BUTTON_BORDER, false, 1.6)
	canvas.draw_string(font, CLOSE_BTN.position + Vector2(76.0, 28.0), "离开", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, P.BUTTON_TEXT)


static func hit(position: Vector2, option_count: int, resolved: bool) -> Dictionary:
	if resolved:
		if CLOSE_BTN.has_point(position):
			return {"action": ACTION_CLOSE, "index": -1}
		return {"action": ACTION_NONE, "index": -1}
	for index in range(option_count):
		if option_rect(index).has_point(position):
			return {"action": ACTION_OPTION, "index": index}
	return {"action": ACTION_NONE, "index": -1}
