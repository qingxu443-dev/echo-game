class_name AtelierPrepOverlay
extends RefCounted

## Full-screen Atelier Alchemy Prep overlay for unlocking recipes with meta
## shards and packing up to 3 starting consumables into the expedition loadout.

const AtelierStashScript = preload("res://scripts/meta/atelier_stash.gd")


static func back_rect(sz: Vector2) -> Rect2:
	var sx: float = maxf(1.0, sz.x) / 1280.0
	var sy: float = maxf(1.0, sz.y) / 720.0
	return Rect2(44.0 * sx, 34.0 * sy, 148.0 * sx, 44.0 * sy)


static func loadout_slot_rect(sz: Vector2, index: int) -> Rect2:
	var sx: float = maxf(1.0, sz.x) / 1280.0
	var sy: float = maxf(1.0, sz.y) / 720.0
	var w: float = 340.0 * sx
	var gap: float = 28.0 * sx
	var total: float = w * 3.0 + gap * 2.0
	var start_x: float = (sz.x - total) * 0.5
	return Rect2(start_x + float(index) * (w + gap), 132.0 * sy, w, 98.0 * sy)


static func recipe_card_rect(sz: Vector2, index: int) -> Rect2:
	var sx: float = maxf(1.0, sz.x) / 1280.0
	var sy: float = maxf(1.0, sz.y) / 720.0
	var col: int = index % 3
	var row: int = index / 3
	var w: float = 356.0 * sx
	var h: float = 162.0 * sy
	var gx: float = 26.0 * sx
	var gy: float = 22.0 * sy
	var total_w: float = w * 3.0 + gx * 2.0
	var start_x: float = (sz.x - total_w) * 0.5
	return Rect2(start_x + float(col) * (w + gx), 292.0 * sy + float(row) * (h + gy), w, h)


static func handle_click(sz: Vector2, pos: Vector2, state: Dictionary) -> Dictionary:
	if back_rect(sz).has_point(pos):
		return {"close": true, "message": ""}
	var loadout: Array = state.get("loadout", [])
	for i in range(AtelierStashScript.MAX_LOADOUT):
		if loadout_slot_rect(sz, i).has_point(pos):
			if i < loadout.size():
				var res := AtelierStashScript.remove_from_loadout(state, i)
				return {"close": false, "message": str(res.get("message", ""))}
			return {"close": false, "message": "点击下方已解锁的炼金配方即可装入此槽位。"}
	for idx in range(AtelierStashScript.RECIPES.size()):
		if recipe_card_rect(sz, idx).has_point(pos):
			var r: Dictionary = AtelierStashScript.RECIPES[idx]
			var rid: String = str(r["id"])
			if AtelierStashScript.is_unlocked(state, rid):
				var res := AtelierStashScript.add_to_loadout(state, rid)
				return {"close": false, "message": str(res.get("message", ""))}
			var ures := AtelierStashScript.unlock_recipe(state, rid)
			return {"close": false, "message": str(ures.get("message", ""))}
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

	canvas.draw_string(font, Vector2(br.end.x + 28.0 * sx, 56.0 * sy), "黄昏工坊  ·  炼金战备台", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(24.0 * sy), Color("#f8ecd4"))
	canvas.draw_string(font, Vector2(br.end.x + 28.0 * sx, 77.0 * sy), "ATELIER PREP  ·  解锁配方并配置最多 3 件战术道具带入战斗（局内按 B 打开背包使用）", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.5 * sy), Color("#9ea2ad"))

	# Top-right Atelier Shards counter
	var shard_box := Rect2(sz.x - 266.0 * sx, 34.0 * sy, 222.0 * sx, 44.0 * sy)
	canvas.draw_rect(shard_box, Color(0.14, 0.13, 0.18, 0.95), true)
	canvas.draw_rect(shard_box, Color("#d4b77b"), false, 1.5)
	canvas.draw_string(font, shard_box.position + Vector2(16.0 * sx, 28.0 * sy), "工坊残晶  ·  %d" % int(state.get("shards", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(16.0 * sy), Color("#f4dc9e"))

	# Section 1: 3-slot Expedition Loadout
	var loadout: Array = state.get("loadout", [])
	canvas.draw_string(font, Vector2(96.0 * sx, 118.0 * sy), "出征行囊  (%d / %d)  ·  点击槽位可卸下" % [loadout.size(), AtelierStashScript.MAX_LOADOUT], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14.0 * sy), Color("#e6d5b2"))
	for i in range(AtelierStashScript.MAX_LOADOUT):
		var sr := loadout_slot_rect(sz, i)
		var hovered := sr.has_point(mouse_pos)
		if i < loadout.size():
			var r := AtelierStashScript.recipe_by_id(str(loadout[i]))
			var acc := Color(str(r.get("accent", "#d4b77b")))
			canvas.draw_rect(sr, Color(0.15, 0.17, 0.22, 0.96) if hovered else Color(0.11, 0.13, 0.18, 0.94), true)
			canvas.draw_rect(Rect2(sr.position, Vector2(6.0 * sx, sr.size.y)), acc, true)
			canvas.draw_rect(sr, acc if hovered else Color(acc.r, acc.g, acc.b, 0.65), false, 1.8 if hovered else 1.3)
			canvas.draw_string(font, sr.position + Vector2(20.0 * sx, 30.0 * sy), "槽位 %d · %s" % [i + 1, str(r.get("name", ""))], HORIZONTAL_ALIGNMENT_LEFT, sr.size.x - 90.0 * sx, roundi(16.0 * sy), Color("#fbf3e4"))
			canvas.draw_string(font, sr.position + Vector2(20.0 * sx, 56.0 * sy), str(r.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, sr.size.x - 32.0 * sx, roundi(11.5 * sy), Color("#c2c0b8"))
			canvas.draw_string(font, Vector2(sr.end.x - 68.0 * sx, sr.position.y + 28.0 * sy), "× 卸下", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.5 * sy), Color("#e89a8c") if hovered else Color("#8f949e"))
		else:
			canvas.draw_rect(sr, Color(0.08, 0.09, 0.12, 0.80), true)
			canvas.draw_rect(sr, Color(0.55, 0.56, 0.62, 0.45), false, 1.2)
			canvas.draw_string(font, sr.position + Vector2(0.0, 54.0 * sy), "空行囊槽位 %d（点击下方配方装入）" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, roundi(13.0 * sy), Color("#7a7e88"))

	# Section 2: 6 Alchemy Recipes
	canvas.draw_string(font, Vector2(80.0 * sx, 274.0 * sy), "工坊炼金配方  ·  战斗结算可获得工坊残晶（胜 +35~80，败 +20 保底）", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14.0 * sy), Color("#e6d5b2"))
	var shards: int = int(state.get("shards", 0))
	for idx in range(AtelierStashScript.RECIPES.size()):
		var r: Dictionary = AtelierStashScript.RECIPES[idx]
		var cr := recipe_card_rect(sz, idx)
		var rid: String = str(r["id"])
		var unlocked := AtelierStashScript.is_unlocked(state, rid)
		var acc := Color(str(r.get("accent", "#d4b77b")))
		var hovered := cr.has_point(mouse_pos)
		var bg := Color(0.14, 0.16, 0.21, 0.96) if (hovered and unlocked) else (Color(0.11, 0.12, 0.17, 0.94) if unlocked else Color(0.09, 0.095, 0.13, 0.90))
		canvas.draw_rect(cr, bg, true)
		canvas.draw_rect(Rect2(cr.position, Vector2(cr.size.x, 5.0 * sy)), acc if unlocked else Color(acc.r, acc.g, acc.b, 0.40), true)
		canvas.draw_rect(cr, acc if hovered else Color(acc.r, acc.g, acc.b, 0.55 if unlocked else 0.28), false, 2.0 if hovered else 1.2)

		canvas.draw_string(font, cr.position + Vector2(18.0 * sx, 34.0 * sy), "[%s]  %s" % [str(r["tag"]), str(r["name"])], HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 32.0 * sx, roundi(16.5 * sy), Color("#fbf3e4") if unlocked else Color("#b6b3aa"))
		canvas.draw_string(font, cr.position + Vector2(18.0 * sx, 68.0 * sy), str(r["desc"]), HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 34.0 * sx, roundi(12.5 * sy), Color("#ceccc4") if unlocked else Color("#8f8d88"))

		var btn := Rect2(cr.position.x + 18.0 * sx, cr.end.y - 46.0 * sy, cr.size.x - 36.0 * sx, 32.0 * sy)
		if unlocked:
			var full: bool = loadout.size() >= AtelierStashScript.MAX_LOADOUT
			canvas.draw_rect(btn, Color(0.16, 0.18, 0.22, 0.85) if full else Color(acc.r * 0.34, acc.g * 0.34, acc.b * 0.34, 0.94), true)
			canvas.draw_rect(btn, Color("#666a72") if full else acc, false, 1.3)
			canvas.draw_string(font, btn.position + Vector2(0.0, 21.0 * sy), "行囊已满" if full else "＋ 装入出征行囊", HORIZONTAL_ALIGNMENT_CENTER, btn.size.x, roundi(13.0 * sy), Color("#8a8d94") if full else Color("#fff8ea"))
		else:
			var cost: int = int(r.get("cost", 0))
			var can_buy: bool = shards >= cost
			canvas.draw_rect(btn, Color(0.32, 0.24, 0.14, 0.96) if can_buy else Color(0.15, 0.14, 0.16, 0.85), true)
			canvas.draw_rect(btn, Color("#e8c882") if can_buy else Color("#665f5a"), false, 1.4)
			canvas.draw_string(font, btn.position + Vector2(0.0, 21.0 * sy), "解锁配方 · %d 工坊残晶" % cost, HORIZONTAL_ALIGNMENT_CENTER, btn.size.x, roundi(13.0 * sy), Color("#fff1ce") if can_buy else Color("#8c837d"))

	# Footer status notice
	var foot := notice if not notice.is_empty() else "提示：出征前装入行囊的道具会在新开「春之境」或「教学遗迹」时自动带入局内背包（战斗内按 B 使用）。"
	canvas.draw_string(font, Vector2(44.0 * sx, sz.y - 24.0 * sy), foot, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.5 * sy), Color("#e8c882") if not notice.is_empty() else Color("#9598a0"))
