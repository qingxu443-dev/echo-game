class_name BoardObjectsView
extends RefCounted

## The world-object layer of the 2.5D board: everything that stands on the
## slabs and must sort by isometric depth - ruin pillars, relic chests,
## standee actors with procedural idle/hit animation, dropped loot beams and
## the per-actor status rings / HP bars / badges.
##
## Depends only on the palette (projection + shared draw primitives) and the
## threat layer's danger query; nothing here draws telegraphs.

const IntentScript = preload("res://scripts/battle/battle_intent.gd")
const P = preload("res://scripts/ui/theme_palette.gd")
const BoardThreatViewScript = preload("res://scripts/ui/board_threat_view.gd")

const ACTOR_SPRITE_DIR: String = "res://assets/actors/"

static var _sprite_cache: Dictionary = {}


# --- composition ----------------------------------------------------------------

## One entry pass per frame: collect every depth participant, sort, draw.
static func draw_depth_sorted_objects(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	var items: Array = []

	for cell in controller.blocked_cells:
		if not P.is_inside_board(cell, controller.grid_size):
			continue
		var vc := P.to_view_cell(cell)
		items.append({
			"kind": "obstacle",
			"cell": cell,
			"depth": float(vc.x + vc.y) - 0.1,
		})

	for b_cell in controller.beacons:
		var b: Dictionary = controller.beacons[b_cell]
		if int(b.get("health", 0)) <= 0:
			continue
		var vc := P.to_view_cell(b_cell)
		items.append({
			"kind": "beacon",
			"cell": b_cell,
			"beacon": b,
			"depth": float(vc.x + vc.y) - 0.05,
		})

	var actor_positions: Dictionary = fx_state.get("actor_pos", {})
	for actor_id in controller.actors:
		var actor = controller.actors[actor_id]
		if not actor.is_alive() and not actor.is_downed():
			continue
		var screen_pos: Vector2 = actor_positions.get(actor_id, P.cell_center(actor.cell))
		# Depth sort by visual ground Y so mid-hop actors sort cleanly too
		var depth_val: float = (screen_pos.y - P.ISO_ORIGIN.y) / (P.ISO_TILE_H * 0.5)
		items.append({
			"kind": "actor",
			"actor_id": String(actor_id),
			"actor": actor,
			"pos": screen_pos,
			"depth": depth_val,
		})

	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["depth"]) < float(b["depth"])
	)

	for item in items:
		if item["kind"] == "obstacle":
			_draw_obstacle_pillar(canvas, item["cell"])
		elif item["kind"] == "beacon":
			if str(item["beacon"].get("kind", "")) == "ward_node":
				_draw_ward_node(canvas, controller, item["cell"], item["beacon"], fx_state)
			else:
				_draw_relic_beacon(canvas, controller, item["cell"], item["beacon"], fx_state)
		else:
			_draw_single_actor(canvas, controller, item["actor_id"], item["actor"], item["pos"], fx_state)


## Ground-level loot beams for items dropped on the field; drawn before the
## standees so loot never hides a body.
static func draw_dropped_loot(canvas: CanvasItem, controller, fx_state: Dictionary) -> void:
	if controller.dropped_loot.is_empty():
		return
	var t: float = float(fx_state.get("time", 0.0))
	var bob: float = sin(t * 4.2) * 3.0
	var font := ThemeDB.fallback_font
	for cell in controller.dropped_loot:
		var items: Array = controller.dropped_loot[cell]
		if items.is_empty():
			continue
		var c := P.cell_center(cell)
		# Golden beacon beam + floating equipment diamond on the ground
		var pts := P.cell_diamond(cell, 10.0)
		canvas.draw_colored_polygon(pts, Color(0.95, 0.80, 0.38, 0.28))
		P.draw_polyline_closed(canvas, pts, P.GOLD_PALE, 2.0)
		var gem_c := c + Vector2(0.0, -14.0 + bob)
		var gem := PackedVector2Array([
			gem_c + Vector2(0.0, -9.0),
			gem_c + Vector2(8.0, 0.0),
			gem_c + Vector2(0.0, 9.0),
			gem_c + Vector2(-8.0, 0.0),
		])
		canvas.draw_colored_polygon(gem, P.GOLD_LIGHT)
		P.draw_polyline_closed(canvas, gem, Color.WHITE, 1.4)
		var label: String = "掉落: " + str(items[0].get("name", "装备"))
		var sz := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		var lpos := Vector2(c.x - sz.x * 0.5, c.y - 28.0 + bob)
		canvas.draw_rect(Rect2(lpos.x - 4.0, lpos.y - 10.0, sz.x + 8.0, 14.0), Color(0.06, 0.07, 0.09, 0.85), true)
		canvas.draw_string(font, lpos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, P.GOLD_PALE)


# --- static scenery --------------------------------------------------------------

static func _draw_obstacle_pillar(canvas: CanvasItem, cell: Vector2i) -> void:
	var base := P.cell_diamond(cell, 5.0)
	var top := P.cell_diamond(cell, 5.0, -P.ISO_OBSTACLE_H)

	# Left face
	var left_face := PackedVector2Array([base[3], base[2], top[2], top[3]])
	canvas.draw_colored_polygon(left_face, P.BLOCKED_LEFT)
	P.draw_polyline_closed(canvas, left_face, Color(0.11, 0.11, 0.12, 0.9), 1.0)

	# Right face
	var right_face := PackedVector2Array([base[2], base[1], top[1], top[2]])
	canvas.draw_colored_polygon(right_face, P.BLOCKED_RIGHT)
	P.draw_polyline_closed(canvas, right_face, Color(0.08, 0.08, 0.09, 0.9), 1.0)

	# Top cap with subtle inner stone bevel
	canvas.draw_colored_polygon(top, P.BLOCKED_FILL)
	P.draw_polyline_closed(canvas, top, P.BLOCKED_LINE, 1.5)
	var inner_top := P.cell_diamond(cell, 11.0, -P.ISO_OBSTACLE_H)
	P.draw_polyline_closed(canvas, inner_top, Color(0.55, 0.52, 0.46, 0.35), 1.0)


static func _draw_relic_beacon(canvas: CanvasItem, controller, cell: Vector2i, beacon: Dictionary, fx_state: Dictionary) -> void:
	var t: float = float(fx_state.get("time", 0.0))
	var in_danger: bool = BoardThreatViewScript.is_cell_in_danger(controller, cell)
	var base := P.cell_diamond(cell, 10.0)
	var mid := P.cell_diamond(cell, 10.0, -18.0)
	var lid := P.cell_diamond(cell, 11.5, -26.0)

	# 2.5D Relic Chest body (dark iron-bound ancient timber + gold trim)
	var wood_left := Color("#4f3825")
	var wood_right := Color("#382618")
	var lid_top := Color("#6b4d31")
	var trim := P.TELEGRAPH_CHARGE_LINE if in_danger else P.GOLD_LIGHT

	# Left & right lower chest walls
	canvas.draw_colored_polygon(PackedVector2Array([base[3], base[2], mid[2], mid[3]]), wood_left)
	canvas.draw_colored_polygon(PackedVector2Array([base[2], base[1], mid[1], mid[2]]), wood_right)
	# Upper arched lid sides & top
	canvas.draw_colored_polygon(PackedVector2Array([mid[3], mid[2], lid[2], lid[3]]), Color("#5c412a"))
	canvas.draw_colored_polygon(PackedVector2Array([mid[2], mid[1], lid[1], lid[2]]), Color("#432e1d"))
	canvas.draw_colored_polygon(lid, lid_top)

	# Gold metal bands & clasp
	P.draw_polyline_closed(canvas, mid, trim, 1.8)
	P.draw_polyline_closed(canvas, lid, trim, 1.6)
	var clasp := mid[2] + Vector2(0.0, 2.0)
	canvas.draw_rect(Rect2(clasp - Vector2(4.0, 4.0), Vector2(8.0, 9.0)), P.GOLD_PALE, true)
	canvas.draw_rect(Rect2(clasp - Vector2(4.0, 4.0), Vector2(8.0, 9.0)), Color("#2b1f14"), false, 1.0)

	# Subtle warm golden treasure shimmer above the chest
	var glow_alpha: float = 0.25 + 0.20 * sin(t * 3.8)
	var glow_col := Color(1.0, 0.35, 0.30, glow_alpha + 0.15) if in_danger else Color(0.98, 0.84, 0.45, glow_alpha)
	canvas.draw_circle(P.cell_center(cell) + Vector2(0.0, -32.0), 8.0, glow_col)

	# Chest hit-count pips underneath (2 hits to break)
	var pos := P.cell_center(cell) + Vector2(0.0, 13.0)
	var max_hits: int = maxi(1, int(beacon["max_health"]))
	var cur_hits: int = clampi(int(beacon["health"]), 0, max_hits)
	var bar_w: float = 42.0
	var bar_h: float = 6.0
	var gap: float = 4.0
	var seg_w: float = (bar_w - gap * float(max_hits - 1)) / float(max_hits)
	var start_x: float = pos.x - bar_w * 0.5
	canvas.draw_rect(Rect2(start_x - 1.5, pos.y - 1.5, bar_w + 3.0, bar_h + 3.0), P.HP_BG, true)
	for i in range(max_hits):
		var seg := Rect2(start_x + float(i) * (seg_w + gap), pos.y, seg_w, bar_h)
		canvas.draw_rect(seg, P.GOLD_LIGHT if i < cur_hits else Color(0.24, 0.22, 0.19, 0.85), true)


## 春之结界 node (§15.2). Deliberately not a chest: the player has to read
## "this is the thing feeding the boss defense" at a glance, and a wooden crate
## would promise loot that breaks the wrong way.
static func _draw_ward_node(canvas: CanvasItem, controller, cell: Vector2i, node: Dictionary, fx_state: Dictionary) -> void:
	var t: float = float(fx_state.get("time", 0.0))
	var in_danger: bool = BoardThreatViewScript.is_cell_in_danger(controller, cell)
	var plate := P.cell_diamond(cell, 10.0)
	var center := P.cell_center(cell)
	var pulse: float = 0.5 + 0.5 * sin(t * 2.6)
	var glow := P.TELEGRAPH_CHARGE_LINE if in_danger else Color("#5fd8b0")

	# Root plate: a dark socket in the floor, so the crystal reads as anchored.
	canvas.draw_colored_polygon(plate, Color("#1d3a31"))
	P.draw_polyline_closed(canvas, plate, Color("#2f6b58"), 1.2)

	# Breathing halo, then the crystal itself (two halves for a faceted look).
	var halo_center := center + Vector2(0.0, -22.0)
	canvas.draw_circle(halo_center, 14.0 + pulse * 2.5, Color(glow.r, glow.g, glow.b, 0.14))
	canvas.draw_circle(halo_center, 8.5, Color(glow.r, glow.g, glow.b, 0.30))
	var top := center + Vector2(0.0, -42.0)
	var waist := center + Vector2(0.0, -22.0)
	var bottom := center + Vector2(0.0, -12.0)
	var left := center + Vector2(-8.0, -31.0)
	var right := center + Vector2(8.0, -31.0)
	canvas.draw_colored_polygon(PackedVector2Array([top, right, waist, left]), Color("#8ef0cf"))
	canvas.draw_colored_polygon(PackedVector2Array([left, waist, right, bottom]), Color("#3f9c86"))
	P.draw_polyline_closed(canvas, PackedVector2Array([top, right, bottom, left]), Color("#d8fff2"), 1.3)

	# Durability, same bar geometry as the chest so the two read as one family.
	var pos := P.cell_center(cell) + Vector2(0.0, 13.0)
	var bar_w: float = 42.0
	var bar_h: float = 5.0
	var rect := Rect2(pos.x - bar_w * 0.5, pos.y, bar_w, bar_h)
	canvas.draw_rect(rect.grow(1.0), P.HP_BG, true)
	var ratio: float = clampf(float(node.get("health", 0)) / float(maxi(1, int(node.get("max_health", 1)))), 0.0, 1.0)
	if ratio > 0.0:
		canvas.draw_rect(Rect2(rect.position, Vector2(bar_w * ratio, bar_h)), Color("#5fd8b0"), true)
	# Clear overhead nameplate so the player instantly knows why to break it.
	var font := ThemeDB.fallback_font
	var def_bonus: int = int(node.get("ward_defense", 80))
	var tag: String = "击破削防!" if in_danger else ("结界 +%d防" % def_bonus)
	var tag_col := P.GOLD_PALE if in_danger else Color("#b8ffea")
	var tag_box := Rect2(center.x - 38.0, center.y - 62.0, 76.0, 17.0)
	canvas.draw_rect(tag_box, Color(0.06, 0.14, 0.12, 0.86), true)
	canvas.draw_rect(tag_box, glow, false, 1.1)
	canvas.draw_string(font, tag_box.position + Vector2(0.0, 12.5), tag, HORIZONTAL_ALIGNMENT_CENTER, tag_box.size.x, 10, tag_col)


# --- standee actors ----------------------------------------------------------------

static func _draw_single_actor(canvas: CanvasItem, controller, actor_id: String, actor, base_pos: Vector2, fx_state: Dictionary) -> void:
	if actor.is_downed():
		_draw_downed_actor(canvas, actor, base_pos)
		return

	var t: float = float(fx_state.get("time", 0.0))
	var hit_flashes: Dictionary = fx_state.get("hit_flash", {})
	var lunges: Dictionary = fx_state.get("lunge", {})
	var flash: float = clampf(float(hit_flashes.get(actor_id, 0.0)), 0.0, 1.0)
	var lunge_offset: Vector2 = lunges.get(actor_id, Vector2.ZERO)

	# Hit shake + lunge offset
	var shake_x: float = sin(t * 65.0) * 5.0 * flash if flash > 0.01 else 0.0
	var foot_pos: Vector2 = base_pos + lunge_offset + Vector2(shake_x, 0.0)

	# Ground contact shadow (ellipse approximated as stretched polygon)
	P.draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 2.0), 22.0, 11.0, P.SHADOW_COLOR, true)

	# Breathing red danger-pressure filter when standing inside an enemy attack tile
	var in_danger: bool = BoardThreatViewScript.is_cell_in_danger(controller, actor.cell)
	var danger_breath: float = (0.5 + 0.5 * sin(t * 4.4)) if in_danger else 0.0

	# Base status rings on the floor beneath the standee
	if in_danger:
		var dr_col := Color(0.98, 0.26, 0.24, 0.35 + 0.45 * danger_breath)
		P.draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 1.0), 30.0 + 3.0 * danger_breath, 16.0 + 1.5 * danger_breath, dr_col, false, 2.8)
	if actor.team == "player" and actor_id == controller.active_character_id:
		P.draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 1.0), 26.0, 14.0, P.RING_ACTIVE, false, 2.2)
	_draw_floor_status_rings(canvas, controller, actor_id, actor, base_pos)

	# Standee sprite with 4-way isometric facing (front/back + horizontal flip)
	var facing: Dictionary = _compute_facing(controller, actor_id, actor, base_pos, fx_state)
	var use_back: bool = bool(facing["use_back"])
	var flip_h: bool = bool(facing["flip_h"])
	var tex: Texture2D = _resolve_actor_texture(actor, use_back)
	if tex != null:
		var phase: float = float(abs(actor_id.hash() % 100)) * 0.06
		var breathe: float = 1.0 + 0.022 * sin(t * 2.6 + phase)
		var tex_size: Vector2 = tex.get_size()
		var aspect: float = tex_size.x / maxf(1.0, tex_size.y)
		var draw_h: float = P.STANDEE_HEIGHT * breathe
		var draw_w: float = P.STANDEE_HEIGHT * aspect * (2.0 - breathe)
		var top_y: float = foot_pos.y - draw_h + 7.0
		var base_tint := Color.WHITE
		if in_danger:
			# Soft pulsing red oppressive tint on the character inside hazard tiles
			base_tint = Color.WHITE.lerp(Color(1.26, 0.72, 0.70, 1.0), 0.35 + 0.55 * danger_breath)
		var modulate := base_tint.lerp(Color(1.8, 1.75, 1.65, 1.0), flash)
		# Mirror cleanly around the standee's foot center so shadow, feet and HP bar stay aligned
		if flip_h:
			canvas.draw_set_transform(Vector2(foot_pos.x, 0.0), 0.0, Vector2(-1.0, 1.0))
			canvas.draw_texture_rect(tex, Rect2(Vector2(-draw_w * 0.5, top_y), Vector2(draw_w, draw_h)), false, modulate)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			canvas.draw_texture_rect(tex, Rect2(Vector2(foot_pos.x - draw_w * 0.5, top_y), Vector2(draw_w, draw_h)), false, modulate)
	else:
		_draw_fallback_token(canvas, actor, foot_pos + Vector2(0.0, -24.0), flash)

	# Compact HP + shield bar under feet & overhead mark badges
	_draw_compact_hp_bar(canvas, actor, base_pos + Vector2(0.0, 13.0))
	_draw_overhead_badges(canvas, controller, actor_id, foot_pos + Vector2(0.0, -P.STANDEE_HEIGHT + 2.0))


static func _draw_fallback_token(canvas: CanvasItem, actor, center: Vector2, flash: float) -> void:
	var body_color := P.PLAYER_BODY if actor.team == "player" else P.ENEMY_BODY
	var outline := P.PLAYER_OUTLINE if actor.team == "player" else P.ENEMY_OUTLINE
	body_color = body_color.lerp(Color.WHITE, flash * 0.7)
	canvas.draw_circle(center, 18.0, body_color)
	canvas.draw_arc(center, 18.0, 0.0, TAU, 36, outline, 2.5)
	var glyph: String = actor.glyph
	if glyph.is_empty():
		glyph = "锋" if actor.team == "enemy" else "守"
	canvas.draw_string(ThemeDB.fallback_font, center + Vector2(-7.0, 6.0), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, P.TEXT_ON_DARK)


static func _draw_downed_actor(canvas: CanvasItem, actor, base_pos: Vector2) -> void:
	P.draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 2.0), 22.0, 11.0, P.SHADOW_COLOR, true)
	var center := base_pos + Vector2(0.0, -10.0)
	canvas.draw_circle(center, 16.0, P.PLAYER_BODY_DOWNED)
	canvas.draw_arc(center, 16.0, 0.0, TAU, 32, P.PLAYER_OUTLINE_DOWNED, 2.0)
	var glyph: String = actor.glyph if not actor.glyph.is_empty() else "守"
	canvas.draw_string(ThemeDB.fallback_font, center + Vector2(-6.0, 6.0), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.TEXT_DISABLED)
	canvas.draw_line(center + Vector2(-10.0, -10.0), center + Vector2(10.0, 10.0), P.DOWNED_MARK, 2.0)
	canvas.draw_line(center + Vector2(10.0, -10.0), center + Vector2(-10.0, 10.0), P.DOWNED_MARK, 2.0)


static func _draw_floor_status_rings(canvas: CanvasItem, controller, actor_id: String, actor, base_pos: Vector2) -> void:
	if actor.team == "player":
		if actor.shield > 0:
			P.draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 1.0), 23.0, 12.0, P.RING_SHIELD, false, 2.5)
		if controller.statuses.has_status(actor_id, &"absolute_guard"):
			P.draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 1.0), 30.0, 16.0, P.RING_GUARD, false, 2.8)
		return
	if controller.statuses.has_status(actor_id, &"sakura_petal_mark"):
		P.draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 1.0), 27.0, 14.5, P.RING_PETAL, false, 2.5)
	if controller.statuses.has_status(actor_id, &"oathkeeper_mark"):
		P.draw_iso_ellipse(canvas, base_pos + Vector2(0.0, 1.0), 23.0, 12.0, P.RING_MARK, false, 2.5)


static func _draw_overhead_badges(canvas: CanvasItem, controller, actor_id: String, top_pos: Vector2) -> void:
	var tags: Array[Dictionary] = []
	if controller.statuses.has_status(actor_id, &"absolute_guard"):
		tags.append({"text": "守", "color": P.RING_GUARD})
	if controller.statuses.has_status(actor_id, &"oathkeeper_mark"):
		tags.append({"text": "印", "color": P.MARK_LABEL})
	if controller.statuses.has_status(actor_id, &"sakura_petal_mark"):
		tags.append({"text": "香", "color": P.PETAL_LABEL})
	var actor = controller.get_actor(actor_id)
	if actor != null and actor.team == "enemy":
		if actor.armor_layers > 0:
			tags.append({"text": "甲%d" % actor.armor_layers, "color": P.GOLD_PALE})
		elif actor.armor_max > 0 and actor.armor_broken_until_turn >= controller.turn_number:
			tags.append({"text": "破", "color": P.TELEGRAPH_CHARGE_LINE})
		if actor.boss_phase >= 2:
			tags.append({"text": "狂", "color": Color("#ff6b7a")})
		if actor.melee_tolerance > 0:
			tags.append({"text": "怒%d" % actor.melee_tolerance, "color": Color("#ffb347")})
	if tags.is_empty():
		return
	var start_x := top_pos.x - float(tags.size() - 1) * 10.0
	for i in range(tags.size()):
		var p := Vector2(start_x + float(i) * 20.0, top_pos.y)
		canvas.draw_circle(p + Vector2(0.0, -4.0), 9.0, Color(0.08, 0.09, 0.12, 0.85))
		canvas.draw_string(ThemeDB.fallback_font, p + Vector2(-6.0, 1.0), str(tags[i]["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tags[i]["color"])


static func _draw_compact_hp_bar(canvas: CanvasItem, actor, pos: Vector2) -> void:
	var bar_w: float = 42.0
	var bar_h: float = 5.0
	var rect := Rect2(pos.x - bar_w * 0.5, pos.y, bar_w, bar_h)
	canvas.draw_rect(rect.grow(1.0), P.HP_BG, true)
	var ratio: float = clampf(float(actor.health) / float(maxi(1, actor.max_health)), 0.0, 1.0)
	var fill_color := P.HP_PLAYER if actor.team == "player" else P.HP_ENEMY
	if ratio > 0.0:
		canvas.draw_rect(Rect2(rect.position, Vector2(bar_w * ratio, bar_h)), fill_color, true)
	if actor.shield > 0:
		var shield_ratio: float = clampf(float(actor.shield) / float(maxi(1, actor.max_health)), 0.0, 1.0)
		var sh_rect := Rect2(rect.position.x, rect.position.y - 3.0, bar_w * minf(1.0, shield_ratio * 2.5), 2.5)
		canvas.draw_rect(sh_rect, P.HP_SHIELD, true)
	# Enemy AP-driven signature skill charge bar right beneath the HP bar
	if actor.team == "enemy" and actor.skill_charge_max > 0:
		var segs: int = actor.skill_charge_max
		var gap: float = 2.0
		var seg_w: float = (bar_w - gap * float(segs - 1)) / float(segs)
		var full: bool = actor.skill_charge >= segs
		var lit_col := P.TELEGRAPH_CHARGE_LINE if full else P.GOLD_LIGHT
		for i in range(segs):
			var sr := Rect2(rect.position.x + float(i) * (seg_w + gap), rect.end.y + 3.0, seg_w, 3.5)
			canvas.draw_rect(sr, lit_col if i < actor.skill_charge else Color(0.16, 0.18, 0.22, 0.9), true)
	# Melee tolerance bar (2 pips beneath charge bar: glows amber at 1/2 to warn
	# that one more melee hit this turn triggers an immediate counterattack).
	if actor.team == "enemy" and actor.melee_tolerance_max > 0:
		var t_segs: int = actor.melee_tolerance_max
		var t_gap: float = 3.0
		var t_w: float = (bar_w - t_gap * float(t_segs - 1)) / float(t_segs)
		var t_y: float = rect.end.y + 8.5
		for j in range(t_segs):
			var tr := Rect2(rect.position.x + float(j) * (t_w + t_gap), t_y, t_w, 2.8)
			var t_col := Color("#ff9f38") if j < actor.melee_tolerance else Color(0.22, 0.20, 0.18, 0.65)
			canvas.draw_rect(tr, t_col, true)


# --- 4-way facing & sprite loading helpers ---------------------------------------

## Computes whether this standee should use its rear 3/4 sprite and/or mirror
## horizontally so units always face their active target on the isometric board.
static func _compute_facing(controller, actor_id: String, actor, self_pos: Vector2, fx_state: Dictionary) -> Dictionary:
	var target_pos: Vector2 = _find_look_target_pos(controller, actor_id, actor, fx_state)
	var delta: Vector2 = target_pos - self_pos
	var default_faces_right: bool = (actor.team == "player")

	if delta.length_squared() < 4.0:
		return {"use_back": false, "flip_h": false}

	var want_back: bool = delta.y < -6.0
	var want_right: bool = delta.x >= 0.0
	var flip_h: bool = (want_right != default_faces_right)
	return {"use_back": want_back, "flip_h": flip_h}


static func _find_look_target_pos(controller, actor_id: String, actor, fx_state: Dictionary) -> Vector2:
	if actor.team == "player":
		# Face hovered enemy first if the player is inspecting/aiming at one
		if fx_state.has("hover_cell"):
			var hcell: Vector2i = fx_state["hover_cell"]
			for other_id in controller.actors:
				var other = controller.actors[other_id]
				if other.team == "enemy" and other.is_alive() and other.cell == hcell:
					return P.cell_center(other.cell)
		# Otherwise face the nearest living enemy
		var best_dist: int = 999
		var best_pos: Vector2 = P.cell_center(actor.cell) + Vector2(40.0, 20.0)
		for other_id in controller.actors:
			var other = controller.actors[other_id]
			if other.team == "enemy" and other.is_alive():
				var d: int = absi(other.cell.x - actor.cell.x) + absi(other.cell.y - actor.cell.y)
				if d < best_dist:
					best_dist = d
					best_pos = P.cell_center(other.cell)
		return best_pos

	# Enemy: face its active telegraph target cell/actor first
	for intent in controller.intents:
		if intent.source_actor_id == actor_id and intent.state == IntentScript.IntentState.ACTIVE:
			if not intent.target_actor_id.is_empty():
				var t_actor = controller.get_actor(intent.target_actor_id)
				if t_actor != null and t_actor.is_alive():
					return P.cell_center(t_actor.cell)
			if intent.action_id != &"wait" and P.is_inside_board(intent.target_cell, controller.grid_size):
				return P.cell_center(intent.target_cell)

	# Fallback: face nearest living player
	var p_best_dist: int = 999
	var p_best_pos: Vector2 = P.cell_center(actor.cell) + Vector2(-40.0, 20.0)
	for other_id in controller.actors:
		var other = controller.actors[other_id]
		if other.team == "player" and other.is_alive():
			var d: int = absi(other.cell.x - actor.cell.x) + absi(other.cell.y - actor.cell.y)
			if d < p_best_dist:
				p_best_dist = d
				p_best_pos = P.cell_center(other.cell)
	return p_best_pos


static func _resolve_actor_texture(actor, prefer_back: bool = false) -> Texture2D:
	var keys: Array[String] = []
	if actor.team == "player":
		if actor.character_id != &"":
			keys.append(String(actor.character_id))
		keys.append(String(actor.actor_id))
	else:
		keys.append(String(actor.archetype))

	var lookup_keys: Array[String] = []
	if prefer_back:
		for k in keys:
			if not k.is_empty():
				lookup_keys.append(k + "_back")
	for k in keys:
		if not k.is_empty():
			lookup_keys.append(k)

	for key in lookup_keys:
		var tex := _load_cached_texture(ACTOR_SPRITE_DIR + key + ".png")
		if tex != null:
			return tex
	return null


static func _load_cached_texture(path: String) -> Texture2D:
	if _sprite_cache.has(path):
		return _sprite_cache[path]
	var loaded: Texture2D = null
	if ResourceLoader.exists(path, "Texture2D"):
		var res := ResourceLoader.load(path)
		if res is Texture2D:
			loaded = res
	if loaded == null:
		var abs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null and not img.is_empty():
				loaded = ImageTexture.create_from_image(img)
	_sprite_cache[path] = loaded
	return loaded
