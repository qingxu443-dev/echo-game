class_name AtelierPrepOverlay
extends RefCounted

## Full-screen "黄昏补给商行" (Dusk Supply Shop) overlay:
##   - Top bar: back button, shop crest, and shard balance badge.
##   - Left showcase (64%): 2x3 merchant shelves with bespoke vector item icons.
##   - Right sidebar (32%): selected item details (+1 / x3 buy) & packed bag list.

const AtelierStashScript = preload("res://scripts/meta/atelier_stash.gd")

static var selected_index: int = 0


static func back_rect(sz: Vector2) -> Rect2:
	var sx := maxf(1.0, sz.x) / 1280.0; var sy := maxf(1.0, sz.y) / 720.0
	return Rect2(40.0 * sx, 28.0 * sy, 140.0 * sx, 42.0 * sy)


static func shelf_card_rect(sz: Vector2, index: int) -> Rect2:
	var sx := maxf(1.0, sz.x) / 1280.0; var sy := maxf(1.0, sz.y) / 720.0
	var col := index % 3; var row := index / 3
	var w := 248.0 * sx; var h := 248.0 * sy; var gx := 18.0 * sx; var gy := 18.0 * sy
	return Rect2(40.0 * sx + float(col) * (w + gx), 146.0 * sy + float(row) * (h + gy), w, h)


static func card_quick_buy_rect(cr: Rect2, sx: float, sy: float) -> Rect2:
	return Rect2(cr.end.x - 54.0 * sx, cr.end.y - 40.0 * sy, 42.0 * sx, 28.0 * sy)


static func sidebar_rect(sz: Vector2) -> Rect2:
	var sx := maxf(1.0, sz.x) / 1280.0; var sy := maxf(1.0, sz.y) / 720.0
	return Rect2(842.0 * sx, 108.0 * sy, 398.0 * sx, 570.0 * sy)


static func buy_one_rect(sz: Vector2) -> Rect2:
	var sx := maxf(1.0, sz.x) / 1280.0; var sy := maxf(1.0, sz.y) / 720.0
	var sb := sidebar_rect(sz)
	return Rect2(sb.position.x + 20.0 * sx, sb.position.y + 244.0 * sy, 266.0 * sx, 42.0 * sy)


static func buy_three_rect(sz: Vector2) -> Rect2:
	var sx := maxf(1.0, sz.x) / 1280.0; var sy := maxf(1.0, sz.y) / 720.0
	var sb := sidebar_rect(sz)
	return Rect2(sb.position.x + 296.0 * sx, sb.position.y + 244.0 * sy, 82.0 * sx, 42.0 * sy)


static func bag_row_refund_rect(sz: Vector2, row_idx: int) -> Rect2:
	var sx := maxf(1.0, sz.x) / 1280.0; var sy := maxf(1.0, sz.y) / 720.0
	var sb := sidebar_rect(sz)
	var y := sb.position.y + 340.0 * sy + float(row_idx) * 34.0 * sy
	return Rect2(sb.end.x - 74.0 * sx, y + 3.0 * sy, 54.0 * sx, 24.0 * sy)


static func handle_click(sz: Vector2, pos: Vector2, state: Dictionary) -> Dictionary:
	var sx := maxf(1.0, sz.x) / 1280.0; var sy := maxf(1.0, sz.y) / 720.0
	if back_rect(sz).has_point(pos):
		return {"close": true, "message": ""}
	for idx in range(AtelierStashScript.RECIPES.size()):
		var cr := shelf_card_rect(sz, idx)
		if cr.has_point(pos):
			selected_index = idx
			if card_quick_buy_rect(cr, sx, sy).has_point(pos):
				var res := AtelierStashScript.buy_and_pack(state, str(AtelierStashScript.RECIPES[idx]["id"]), AtelierStashScript.SAVE_PATH, 1)
				return {"close": false, "message": str(res.get("message", ""))}
			return {"close": false, "message": ""}
	var sel_r: Dictionary = AtelierStashScript.RECIPES[clampi(selected_index, 0, AtelierStashScript.RECIPES.size() - 1)]
	if buy_one_rect(sz).has_point(pos):
		var res1 := AtelierStashScript.buy_and_pack(state, str(sel_r["id"]), AtelierStashScript.SAVE_PATH, 1)
		return {"close": false, "message": str(res1.get("message", ""))}
	if buy_three_rect(sz).has_point(pos):
		var res3 := AtelierStashScript.buy_and_pack(state, str(sel_r["id"]), AtelierStashScript.SAVE_PATH, 3)
		return {"close": false, "message": str(res3.get("message", ""))}
	var groups := AtelierStashScript.grouped_loadout(state)
	for i in range(groups.size()):
		if bag_row_refund_rect(sz, i).has_point(pos):
			var rres := AtelierStashScript.unpack_and_refund(state, str(groups[i]["id"]))
			return {"close": false, "message": str(rres.get("message", ""))}
	return {"close": false, "message": ""}


static func draw(canvas: CanvasItem, font: Font, sz: Vector2, state: Dictionary, notice: String, mouse_pos: Vector2) -> void:
	var sx := maxf(1.0, sz.x) / 1280.0; var sy := maxf(1.0, sz.y) / 720.0
	selected_index = clampi(selected_index, 0, AtelierStashScript.RECIPES.size() - 1)
	var shards: int = int(state.get("shards", 0))

	# Opaque twilight stone shop backdrop (zero bleed-through from hub behind)
	canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color("#101219"), true)
	canvas.draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(sz.x, 0), Vector2(sz.x, 220.0 * sy), Vector2(0, 220.0 * sy)]),
		PackedColorArray([Color(0.22, 0.17, 0.12, 0.36), Color(0.14, 0.14, 0.20, 0.24), Color(0.10, 0.11, 0.15, 0.0), Color(0.10, 0.11, 0.15, 0.0)])
	)
	canvas.draw_line(Vector2(0.0, 88.0 * sy), Vector2(sz.x, 88.0 * sy), Color(0.84, 0.72, 0.48, 0.32), 1.2)

	# Top navigation & shop header
	var br := back_rect(sz)
	var hb := br.has_point(mouse_pos)
	canvas.draw_rect(br, Color(0.23, 0.20, 0.16, 0.96) if hb else Color(0.13, 0.14, 0.19, 0.95), true)
	canvas.draw_rect(br, Color("#e8c882") if hb else Color(0.84, 0.72, 0.48, 0.55), false, 1.5)
	canvas.draw_string(font, br.position + Vector2(20.0 * sx, 27.0 * sy), "← 返回大厅", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14.5 * sy), Color("#fbf2df"))

	canvas.draw_string(font, Vector2(br.end.x + 26.0 * sx, 50.0 * sy), "黄昏补给商行", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(24.0 * sy), Color("#faedd4"))
	canvas.draw_string(font, Vector2(br.end.x + 26.0 * sx, 71.0 * sy), "DUSK SUPPLY SHOP", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.0 * sy), Color("#9d988c"))

	# Top-right shard wallet pill
	var wallet := Rect2(sz.x - 244.0 * sx, 28.0 * sy, 204.0 * sx, 42.0 * sy)
	canvas.draw_rect(wallet, Color(0.14, 0.13, 0.17, 0.98), true)
	canvas.draw_rect(wallet, Color("#d4b77b"), false, 1.4)
	_draw_shard_gem(canvas, wallet.position + Vector2(24.0 * sx, 21.0 * sy), 8.0 * sy)
	canvas.draw_string(font, wallet.position + Vector2(42.0 * sx, 27.0 * sy), "残晶  %d" % shards, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(16.0 * sy), Color("#f5dea0"))

	# Left section header
	canvas.draw_string(font, Vector2(40.0 * sx, 128.0 * sy), "常备炼金商品", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(16.0 * sy), Color("#e6d5b2"))
	canvas.draw_string(font, Vector2(154.0 * sx, 128.0 * sy), "点击查看详情 · 点 +1 快捷购入", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.0 * sy), Color("#848894"))

	# 2x3 Merchant Shelf Cards
	for idx in range(AtelierStashScript.RECIPES.size()):
		_draw_shelf_card(canvas, font, sz, idx, state, shards, mouse_pos, sx, sy)

	# Right Sidebar: Selected Item Inspector + Packed Bag
	_draw_sidebar(canvas, font, sz, state, shards, notice, mouse_pos, sx, sy)


static func _draw_shelf_card(canvas: CanvasItem, font: Font, sz: Vector2, idx: int, state: Dictionary, shards: int, mouse_pos: Vector2, sx: float, sy: float) -> void:
	var r: Dictionary = AtelierStashScript.RECIPES[idx]
	var cr := shelf_card_rect(sz, idx)
	var acc := Color(str(r.get("accent", "#d4b77b")))
	var sel := (idx == selected_index)
	var hov := cr.has_point(mouse_pos)
	var cost: int = int(r["cost"])
	var can_buy := shards >= cost
	var owned := AtelierStashScript.count_in_loadout(state, str(r["id"]))

	if sel:
		canvas.draw_rect(cr.grow(3.0 * sx), Color(acc.r, acc.g, acc.b, 0.14), true)
	canvas.draw_rect(cr, Color(0.15, 0.17, 0.23, 1.0) if (sel or hov) else Color(0.12, 0.13, 0.18, 1.0), true)
	canvas.draw_rect(Rect2(cr.position, Vector2(cr.size.x, 4.0 * sy)), acc, true)
	canvas.draw_rect(cr, acc if sel else Color(acc.r, acc.g, acc.b, 0.45 if hov else 0.25), false, 2.0 if sel else 1.2)

	# Tag badge (top-left) & owned count (top-right)
	var tag_r := Rect2(cr.position.x + 14.0 * sx, cr.position.y + 14.0 * sy, 46.0 * sx, 20.0 * sy)
	canvas.draw_rect(tag_r, Color(acc.r * 0.24, acc.g * 0.24, acc.b * 0.26, 0.95), true)
	canvas.draw_string(font, tag_r.position + Vector2(0.0, 14.0 * sy), str(r["tag"]), HORIZONTAL_ALIGNMENT_CENTER, tag_r.size.x, roundi(11.0 * sy), acc)
	if owned > 0:
		canvas.draw_string(font, Vector2(cr.position.x + 14.0 * sx, cr.position.y + 29.0 * sy), "已备 ×%d" % owned, HORIZONTAL_ALIGNMENT_RIGHT, cr.size.x - 28.0 * sx, roundi(11.5 * sy), Color("#f5dea0"))

	# Center icon frame
	var ic_center := Vector2(cr.get_center().x, cr.position.y + 92.0 * sy)
	canvas.draw_circle(ic_center, 36.0 * sy, Color(acc.r, acc.g, acc.b, 0.09))
	canvas.draw_arc(ic_center, 36.0 * sy, 0.0, TAU, 28, Color(acc.r, acc.g, acc.b, 0.35), 1.2)
	_draw_item_icon(canvas, str(r.get("icon", "potion")), ic_center, 24.0 * sy, acc)

	# Name & concise effect line
	canvas.draw_string(font, Vector2(cr.position.x + 14.0 * sx, cr.position.y + 156.0 * sy), str(r["name"]), HORIZONTAL_ALIGNMENT_CENTER, cr.size.x - 28.0 * sx, roundi(16.5 * sy), Color("#fbf3e4"))
	canvas.draw_string(font, Vector2(cr.position.x + 14.0 * sx, cr.position.y + 180.0 * sy), str(r.get("brief", r["desc"])), HORIZONTAL_ALIGNMENT_CENTER, cr.size.x - 28.0 * sx, roundi(11.5 * sy), Color("#a8a9b0"))

	# Bottom price bar + quick +1 button
	canvas.draw_line(Vector2(cr.position.x + 14.0 * sx, cr.end.y - 48.0 * sy), Vector2(cr.end.x - 14.0 * sx, cr.end.y - 48.0 * sy), Color(0.50, 0.52, 0.58, 0.25), 1.0)
	_draw_shard_gem(canvas, Vector2(cr.position.x + 26.0 * sx, cr.end.y - 26.0 * sy), 6.5 * sy)
	canvas.draw_string(font, Vector2(cr.position.x + 40.0 * sx, cr.end.y - 20.0 * sy), "%d" % cost, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(16.0 * sy), Color("#f5dea0") if can_buy else Color("#7d7874"))
	var qbtn := card_quick_buy_rect(cr, sx, sy)
	var qh := qbtn.has_point(mouse_pos)
	canvas.draw_rect(qbtn, Color(acc.r * 0.45, acc.g * 0.45, acc.b * 0.45, 0.96) if (can_buy and qh) else (Color(0.20, 0.22, 0.28, 0.95) if can_buy else Color(0.14, 0.14, 0.17, 0.80)), true)
	canvas.draw_rect(qbtn, acc if can_buy else Color("#4a4c52"), false, 1.2)
	canvas.draw_string(font, qbtn.position + Vector2(0.0, 19.0 * sy), "+1", HORIZONTAL_ALIGNMENT_CENTER, qbtn.size.x, roundi(12.5 * sy), Color("#fff6e4") if can_buy else Color("#66686e"))


static func _draw_sidebar(canvas: CanvasItem, font: Font, sz: Vector2, state: Dictionary, shards: int, notice: String, mouse_pos: Vector2, sx: float, sy: float) -> void:
	var sb := sidebar_rect(sz)
	var r: Dictionary = AtelierStashScript.RECIPES[selected_index]
	var acc := Color(str(r.get("accent", "#d4b77b")))
	var cost: int = int(r["cost"])

	canvas.draw_rect(sb, Color(0.115, 0.125, 0.17, 1.0), true)
	canvas.draw_rect(sb, Color(0.84, 0.72, 0.48, 0.42), false, 1.4)

	# Selected item preview header
	var ic_box := Rect2(sb.position.x + 20.0 * sx, sb.position.y + 20.0 * sy, 76.0 * sx, 76.0 * sy)
	canvas.draw_rect(ic_box, Color(0.08, 0.09, 0.13, 1.0), true)
	canvas.draw_rect(ic_box, acc, false, 1.5)
	_draw_item_icon(canvas, str(r.get("icon", "potion")), ic_box.get_center(), 26.0 * sy, acc)

	var tx := ic_box.end.x + 16.0 * sx
	canvas.draw_string(font, Vector2(tx, sb.position.y + 44.0 * sy), str(r["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(20.0 * sy), Color("#fbf3e4"))
	canvas.draw_string(font, Vector2(tx, sb.position.y + 68.0 * sy), "分类：%s   ·   单价 %d 残晶" % [str(r["tag"]), cost], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.0 * sy), acc)
	canvas.draw_string(font, Vector2(tx, sb.position.y + 90.0 * sy), "当前行囊已备：%d 件" % AtelierStashScript.count_in_loadout(state, str(r["id"])), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.0 * sy), Color("#c9c6be"))

	# Flavor quote + clean effect box
	canvas.draw_multiline_string(font, Vector2(sb.position.x + 20.0 * sx, sb.position.y + 124.0 * sy), "「%s」" % str(r.get("flavor", "")), HORIZONTAL_ALIGNMENT_LEFT, sb.size.x - 40.0 * sx, roundi(11.5 * sy), 2, Color("#9d9a92"))
	var eff_box := Rect2(sb.position.x + 20.0 * sx, sb.position.y + 150.0 * sy, sb.size.x - 40.0 * sx, 78.0 * sy)
	canvas.draw_rect(eff_box, Color(0.085, 0.095, 0.13, 1.0), true)
	canvas.draw_rect(Rect2(eff_box.position, Vector2(4.0 * sx, eff_box.size.y)), acc, true)
	canvas.draw_string(font, eff_box.position + Vector2(14.0 * sx, 22.0 * sy), "使用效果", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.5 * sy), acc)
	canvas.draw_multiline_string(font, eff_box.position + Vector2(14.0 * sx, 44.0 * sy), str(r["desc"]), HORIZONTAL_ALIGNMENT_LEFT, eff_box.size.x - 26.0 * sx, roundi(13.0 * sy), 2, Color("#e9e6de"))

	# Buy x1 & Buy x3 buttons
	var b1 := buy_one_rect(sz); var b3 := buy_three_rect(sz)
	var can1 := shards >= cost; var can3 := shards >= cost * 3
	canvas.draw_rect(b1, Color(0.38, 0.28, 0.16, 1.0) if (can1 and b1.has_point(mouse_pos)) else (Color(0.28, 0.21, 0.13, 1.0) if can1 else Color(0.15, 0.15, 0.18, 1.0)), true)
	canvas.draw_rect(b1, Color("#e8c882") if can1 else Color("#52545c"), false, 1.5)
	canvas.draw_string(font, b1.position + Vector2(0.0, 27.0 * sy), "购入 1 件  (%d 残晶)" % cost if can1 else "残晶不足", HORIZONTAL_ALIGNMENT_CENTER, b1.size.x, roundi(14.0 * sy), Color("#fff5df") if can1 else Color("#7a7c84"))

	canvas.draw_rect(b3, Color(0.26, 0.22, 0.18, 1.0) if (can3 and b3.has_point(mouse_pos)) else (Color(0.18, 0.16, 0.15, 1.0) if can3 else Color(0.14, 0.14, 0.17, 1.0)), true)
	canvas.draw_rect(b3, Color("#d4b77b") if can3 else Color("#4a4c52"), false, 1.3)
	canvas.draw_string(font, b3.position + Vector2(0.0, 27.0 * sy), "×3", HORIZONTAL_ALIGNMENT_CENTER, b3.size.x, roundi(14.0 * sy), Color("#f5dea0") if can3 else Color("#6a6c74"))

	# Packed Bag Manifest
	canvas.draw_line(Vector2(sb.position.x + 20.0 * sx, sb.position.y + 304.0 * sy), Vector2(sb.end.x - 20.0 * sx, sb.position.y + 304.0 * sy), Color(0.55, 0.54, 0.50, 0.30), 1.0)
	var loadout: Array = state.get("loadout", [])
	var groups := AtelierStashScript.grouped_loadout(state)
	canvas.draw_string(font, Vector2(sb.position.x + 20.0 * sx, sb.position.y + 328.0 * sy), "随行行囊  (%d 件)" % loadout.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14.0 * sy), Color("#e6d5b2"))
	if groups.is_empty():
		canvas.draw_string(font, Vector2(sb.position.x + 20.0 * sx, sb.position.y + 364.0 * sy), "尚未购置随行补给。", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.5 * sy), Color("#7d818c"))
	else:
		for i in range(groups.size()):
			var g: Dictionary = groups[i]
			var gr: Dictionary = g["recipe"]
			var ga := Color(str(gr.get("accent", "#d4b77b")))
			var ry := sb.position.y + 340.0 * sy + float(i) * 34.0 * sy
			canvas.draw_rect(Rect2(sb.position.x + 20.0 * sx, ry, sb.size.x - 40.0 * sx, 30.0 * sy), Color(0.09, 0.10, 0.14, 0.95), true)
			canvas.draw_rect(Rect2(sb.position.x + 20.0 * sx, ry, 4.0 * sx, 30.0 * sy), ga, true)
			canvas.draw_string(font, Vector2(sb.position.x + 34.0 * sx, ry + 20.0 * sy), "%s  ×%d" % [str(gr["name"]), int(g["count"])], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(13.0 * sy), Color("#ece8de"))
			var rb := bag_row_refund_rect(sz, i)
			var rh := rb.has_point(mouse_pos)
			canvas.draw_rect(rb, Color(0.32, 0.16, 0.16, 0.95) if rh else Color(0.18, 0.15, 0.16, 0.90), true)
			canvas.draw_rect(rb, Color("#e89284") if rh else Color("#6e5e5c"), false, 1.0)
			canvas.draw_string(font, rb.position + Vector2(0.0, 16.5 * sy), "退还", HORIZONTAL_ALIGNMENT_CENTER, rb.size.x, roundi(11.0 * sy), Color("#ffd8d0") if rh else Color("#b6aba8"))

	# Clean footer note / feedback toast
	var foot := notice if not notice.is_empty() else "出征时自动装入背包 · 战斗中按 [B] 键使用"
	canvas.draw_string(font, Vector2(sb.position.x + 20.0 * sx, sb.end.y - 14.0 * sy), foot, HORIZONTAL_ALIGNMENT_LEFT, sb.size.x - 36.0 * sx, roundi(11.5 * sy), Color("#e8c882") if not notice.is_empty() else Color("#808592"))


static func _draw_shard_gem(canvas: CanvasItem, center: Vector2, r: float) -> void:
	var pts := PackedVector2Array([center + Vector2(0, -r), center + Vector2(r * 0.78, 0), center + Vector2(0, r), center + Vector2(-r * 0.78, 0)])
	canvas.draw_colored_polygon(pts, Color("#f2d07e"))
	canvas.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color("#fff3cf"), 1.2, true)


static func _draw_item_icon(canvas: CanvasItem, kind: String, c: Vector2, r: float, col: Color) -> void:
	match kind:
		"potion":
			canvas.draw_circle(c + Vector2(0, r * 0.25), r * 0.62, Color(col.r, col.g, col.b, 0.85))
			canvas.draw_rect(Rect2(c + Vector2(-r * 0.22, -r * 0.72), Vector2(r * 0.44, r * 0.45)), Color("#d8e4e0"), true)
			canvas.draw_rect(Rect2(c + Vector2(-r * 0.30, -r * 0.84), Vector2(r * 0.60, r * 0.18)), Color("#b88c52"), true)
			canvas.draw_circle(c + Vector2(-r * 0.20, r * 0.15), r * 0.16, Color(1, 1, 1, 0.55))
		"hourglass":
			var top := PackedVector2Array([c + Vector2(-r * 0.55, -r * 0.75), c + Vector2(r * 0.55, -r * 0.75), c])
			var bot := PackedVector2Array([c, c + Vector2(r * 0.55, r * 0.75), c + Vector2(-r * 0.55, r * 0.75)])
			canvas.draw_colored_polygon(top, Color(col.r, col.g, col.b, 0.45)); canvas.draw_colored_polygon(bot, Color(col.r, col.g, col.b, 0.85))
			canvas.draw_line(c + Vector2(-r * 0.65, -r * 0.78), c + Vector2(r * 0.65, -r * 0.78), Color("#e6c982"), 2.4)
			canvas.draw_line(c + Vector2(-r * 0.65, r * 0.78), c + Vector2(r * 0.65, r * 0.78), Color("#e6c982"), 2.4)
		"talisman":
			var sh := PackedVector2Array([c + Vector2(0, -r * 0.82), c + Vector2(r * 0.65, -r * 0.40), c + Vector2(r * 0.50, r * 0.45), c + Vector2(0, r * 0.85), c + Vector2(-r * 0.50, r * 0.45), c + Vector2(-r * 0.65, -r * 0.40)])
			canvas.draw_colored_polygon(sh, Color(col.r * 0.35, col.g * 0.32, col.b * 0.25, 0.95))
			canvas.draw_polyline(PackedVector2Array([sh[0], sh[1], sh[2], sh[3], sh[4], sh[5], sh[0]]), col, 2.2, true)
			_draw_shard_gem(canvas, c, r * 0.34)
		"bomb":
			canvas.draw_circle(c + Vector2(0, r * 0.16), r * 0.62, Color("#3a2b2c"))
			canvas.draw_arc(c + Vector2(0, r * 0.16), r * 0.62, 0.0, TAU, 24, col, 2.2)
			canvas.draw_line(c + Vector2(0, -r * 0.44), c + Vector2(r * 0.32, -r * 0.82), Color("#e6c982"), 2.0)
			canvas.draw_circle(c + Vector2(r * 0.36, -r * 0.84), r * 0.18, Color("#ffb86c"))
		"sachet":
			canvas.draw_circle(c + Vector2(0, r * 0.18), r * 0.58, Color(col.r * 0.45, col.g * 0.55, col.b * 0.52, 0.95))
			canvas.draw_arc(c + Vector2(0, r * 0.18), r * 0.58, 0.0, TAU, 22, col, 2.0)
			canvas.draw_line(c + Vector2(-r * 0.32, -r * 0.42), c + Vector2(r * 0.32, -r * 0.42), Color("#f2d07e"), 2.4)
			canvas.draw_line(c + Vector2(0, r * 0.76), c + Vector2(0, r * 0.98), Color("#f2d07e"), 2.2)
		_:
			for k in range(5):
				var ang: float = -PI * 0.5 + float(k) * TAU / 5.0
				canvas.draw_circle(c + Vector2(cos(ang), sin(ang)) * r * 0.42, r * 0.32, Color(col.r, col.g, col.b, 0.90))
			canvas.draw_circle(c, r * 0.20, Color("#fff5e6"))
