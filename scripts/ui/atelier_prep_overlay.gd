class_name AtelierPrepOverlay
extends RefCounted

## Full-screen Atelier Alchemy Prep overlay: unlimited shard-funded brewing
## with grouped bag chips (click to refund) and 6 open tactical recipes.

const AtelierStashScript = preload("res://scripts/meta/atelier_stash.gd")


static func back_rect(sz: Vector2) -> Rect2:
	var sx: float = maxf(1.0, sz.x) / 1280.0
	var sy: float = maxf(1.0, sz.y) / 720.0
	return Rect2(44.0 * sx, 34.0 * sy, 148.0 * sx, 44.0 * sy)


static func chip_rect(sz: Vector2, index: int) -> Rect2:
	var sx: float = maxf(1.0, sz.x) / 1280.0
	var sy: float = maxf(1.0, sz.y) / 720.0
	var col: int = index % 3
	var row: int = index / 3
	var w: float = 356.0 * sx
	var h: float = 42.0 * sy
	var gx: float = 26.0 * sx
	var gy: float = 12.0 * sy
	var start_x: float = (sz.x - (w * 3.0 + gx * 2.0)) * 0.5
	return Rect2(start_x + float(col) * (w + gx), 132.0 * sy + float(row) * (h + gy), w, h)


static func recipe_card_rect(sz: Vector2, index: int) -> Rect2:
	var sx: float = maxf(1.0, sz.x) / 1280.0
	var sy: float = maxf(1.0, sz.y) / 720.0
	var col: int = index % 3
	var row: int = index / 3
	var w: float = 356.0 * sx
	var h: float = 162.0 * sy
	var gx: float = 26.0 * sx
	var gy: float = 22.0 * sy
	var start_x: float = (sz.x - (w * 3.0 + gx * 2.0)) * 0.5
	return Rect2(start_x + float(col) * (w + gx), 292.0 * sy + float(row) * (h + gy), w, h)


static func handle_click(sz: Vector2, pos: Vector2, state: Dictionary) -> Dictionary:
	if back_rect(sz).has_point(pos):
		return {"close": true, "message": ""}
	var groups := AtelierStashScript.grouped_loadout(state)
	for i in range(groups.size()):
		if chip_rect(sz, i).has_point(pos):
			var res := AtelierStashScript.unpack_and_refund(state, str(groups[i]["id"]))
			return {"close": false, "message": str(res.get("message", ""))}
	for idx in range(AtelierStashScript.RECIPES.size()):
		if recipe_card_rect(sz, idx).has_point(pos):
			var r: Dictionary = AtelierStashScript.RECIPES[idx]
			var res := AtelierStashScript.buy_and_pack(state, str(r["id"]))
			return {"close": false, "message": str(res.get("message", ""))}
	return {"close": false, "message": ""}


static func draw(canvas: CanvasItem, font: Font, sz: Vector2, state: Dictionary, notice: String, mouse_pos: Vector2) -> void:
	var sx: float = maxf(1.0, sz.x) / 1280.0
	var sy: float = maxf(1.0, sz.y) / 720.0

	canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.055, 0.085, 0.94), true)
	for gx in range(1, 10):
		canvas.draw_line(Vector2(float(gx) * 128.0 * sx, 0.0), Vector2(float(gx) * 128.0 * sx, sz.y), Color(0.84, 0.72, 0.48, 0.03), 1.0)

	# Header bar
	var br := back_rect(sz)
	var hb: bool = br.has_point(mouse_pos)
	canvas.draw_rect(br, Color(0.22, 0.20, 0.17, 0.94) if hb else Color(0.11, 0.12, 0.16, 0.92), true)
	canvas.draw_rect(br, Color("#e8c882") if hb else Color(0.84, 0.72, 0.48, 0.65), false, 1.6)
	canvas.draw_string(font, br.position + Vector2(22.0 * sx, 28.0 * sy), "← 返回工坊", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(15.0 * sy), Color("#fbf2df"))

	canvas.draw_string(font, Vector2(br.end.x + 28.0 * sx, 56.0 * sy), "黄昏工坊  ·  炼金补给台", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(24.0 * sy), Color("#f8ecd4"))
	canvas.draw_string(font, Vector2(br.end.x + 28.0 * sx, 77.0 * sy), "ATELIER PREP  ·  消耗工坊残晶不限量调配道具带入战斗（局内按 B 使用 · 出征前退回全额返晶）", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.5 * sy), Color("#9ea2ad"))

	# Top-right Atelier Shards counter
	var shards: int = int(state.get("shards", 0))
	var shard_box := Rect2(sz.x - 266.0 * sx, 34.0 * sy, 222.0 * sx, 44.0 * sy)
	canvas.draw_rect(shard_box, Color(0.14, 0.13, 0.18, 0.95), true)
	canvas.draw_rect(shard_box, Color("#d4b77b"), false, 1.5)
	canvas.draw_string(font, shard_box.position + Vector2(16.0 * sx, 28.0 * sy), "工坊残晶  ·  %d" % shards, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(16.0 * sy), Color("#f4dc9e"))

	# Section 1: Unlimited grouped Expedition Bag
	var loadout: Array = state.get("loadout", [])
	var groups := AtelierStashScript.grouped_loadout(state)
	canvas.draw_string(font, Vector2(80.0 * sx, 118.0 * sy), "已调配出征行囊  （共 %d 件 · 不限数量 · 点击任意胶囊退回 1 件并全额返还残晶）" % loadout.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14.0 * sy), Color("#e6d5b2"))
	if groups.is_empty():
		var empty_r := Rect2(80.0 * sx, 134.0 * sy, sz.x - 160.0 * sx, 84.0 * sy)
		canvas.draw_rect(empty_r, Color(0.08, 0.09, 0.12, 0.80), true)
		canvas.draw_rect(empty_r, Color(0.55, 0.56, 0.62, 0.42), false, 1.2)
		canvas.draw_string(font, empty_r.position + Vector2(0.0, 48.0 * sy), "出征行囊为空 —— 点击下方任意配方即可消耗残晶调配装入，无数量上限", HORIZONTAL_ALIGNMENT_CENTER, empty_r.size.x, roundi(13.5 * sy), Color("#8a8f9a"))
	else:
		for i in range(groups.size()):
			var g: Dictionary = groups[i]
			var r: Dictionary = g["recipe"]
			var cr := chip_rect(sz, i)
			var acc := Color(str(r.get("accent", "#d4b77b")))
			var hov := cr.has_point(mouse_pos)
			canvas.draw_rect(cr, Color(0.16, 0.18, 0.23, 0.96) if hov else Color(0.11, 0.13, 0.18, 0.94), true)
			canvas.draw_rect(Rect2(cr.position, Vector2(6.0 * sx, cr.size.y)), acc, true)
			canvas.draw_rect(cr, acc if hov else Color(acc.r, acc.g, acc.b, 0.65), false, 1.7 if hov else 1.2)
			canvas.draw_string(font, cr.position + Vector2(18.0 * sx, 26.0 * sy), "%s  ×%d" % [str(r["name"]), int(g["count"])], HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 120.0 * sx, roundi(15.0 * sy), Color("#fbf3e4"))
			canvas.draw_string(font, Vector2(cr.end.x - 112.0 * sx, cr.position.y + 25.0 * sy), "−1 退 +%d晶" % int(r["cost"]), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.5 * sy), Color("#f2a494") if hov else Color("#9da2ac"))

	# Section 2: 6 Open Alchemy Recipes
	canvas.draw_string(font, Vector2(80.0 * sx, 274.0 * sy), "工坊炼金台  ·  全部配方开放调配（春之境胜 +35~80 晶 / 教学胜 +30 晶 / 败 +15~20 保底）", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14.0 * sy), Color("#e6d5b2"))
	for idx in range(AtelierStashScript.RECIPES.size()):
		var r: Dictionary = AtelierStashScript.RECIPES[idx]
		var cr := recipe_card_rect(sz, idx)
		var rid: String = str(r["id"])
		var acc := Color(str(r.get("accent", "#d4b77b")))
		var cost: int = int(r.get("cost", 0))
		var can_buy: bool = shards >= cost
		var packed: int = AtelierStashScript.count_in_loadout(state, rid)
		var hovered := cr.has_point(mouse_pos)
		var bg := Color(0.14, 0.16, 0.21, 0.96) if (hovered and can_buy) else Color(0.11, 0.12, 0.17, 0.94)
		canvas.draw_rect(cr, bg, true)
		canvas.draw_rect(Rect2(cr.position, Vector2(cr.size.x, 5.0 * sy)), acc, true)
		canvas.draw_rect(cr, acc if hovered else Color(acc.r, acc.g, acc.b, 0.55), false, 2.0 if hovered else 1.2)

		canvas.draw_string(font, cr.position + Vector2(18.0 * sx, 34.0 * sy), "[%s]  %s" % [str(r["tag"]), str(r["name"])], HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 90.0 * sx, roundi(16.5 * sy), Color("#fbf3e4"))
		if packed > 0:
			canvas.draw_string(font, Vector2(cr.end.x - 74.0 * sx, cr.position.y + 33.0 * sy), "已装 ×%d" % packed, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.5 * sy), acc)
		canvas.draw_string(font, cr.position + Vector2(18.0 * sx, 68.0 * sy), str(r["desc"]), HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 34.0 * sx, roundi(12.5 * sy), Color("#ceccc4"))

		var btn := Rect2(cr.position.x + 18.0 * sx, cr.end.y - 46.0 * sy, cr.size.x - 36.0 * sx, 32.0 * sy)
		canvas.draw_rect(btn, Color(acc.r * 0.34, acc.g * 0.34, acc.b * 0.34, 0.95) if can_buy else Color(0.15, 0.14, 0.16, 0.85), true)
		canvas.draw_rect(btn, acc if can_buy else Color("#625e5c"), false, 1.4)
		var btn_txt := "＋ 调配 1 件 · %d 工坊残晶" % cost if can_buy else "残晶不足（需 %d 晶）" % cost
		canvas.draw_string(font, btn.position + Vector2(0.0, 21.0 * sy), btn_txt, HORIZONTAL_ALIGNMENT_CENTER, btn.size.x, roundi(13.0 * sy), Color("#fff8ea") if can_buy else Color("#8c837d"))

	var foot := notice if not notice.is_empty() else "提示：有残晶即可无限调配带入下一局；点击行囊胶囊可随时无损退款，卡关时尽情备足补给！"
	canvas.draw_string(font, Vector2(44.0 * sx, sz.y - 24.0 * sy), foot, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.5 * sy), Color("#e8c882") if not notice.is_empty() else Color("#9598a0"))
