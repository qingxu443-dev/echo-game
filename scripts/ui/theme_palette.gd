class_name UiPalette
extends RefCounted

## Every colour and every hard-coded coordinate the battle UI uses.
##
## Kept in one file so a theme change or a resolution adaptation is a single
## edit instead of a search across six draw functions. Values are unchanged from
## the pre-split view: this file names them, it does not redesign them.

# --- colours -----------------------------------------------------------------

const BG := Color("#17191d")
const TEXT := Color("#e4dfd3")
const TEXT_STRONG := Color("#d9d4c8")
const TEXT_DIM := Color("#9b9a94")
const TEXT_MUTED := Color("#aaa79e")
const TEXT_FAINT := Color("#c7c2b6")
const TEXT_BODY := Color("#b9b7ad")
const TEXT_ON_DARK := Color("#17191d")
const TEXT_DISABLED := Color("#6b6a66")
const TEXT_HINT := Color("#8c8b84")

const GOLD := Color("#c5a45c")
const GOLD_LIGHT := Color("#d4b77b")
const GOLD_PALE := Color("#e4d2aa")
const CYAN := Color("#8fc7dc")
const WARN := Color("#d58b78")

const BOARD_LIGHT := Color("#2e3239")
const BOARD_DARK := Color("#252930")
const BOARD_LINE := Color("#464b54")
const BOARD_SIDE_LEFT := Color("#1c2026")
const BOARD_SIDE_RIGHT := Color("#13161b")
const BLOCKED_FILL := Color("#3a3835")
const BLOCKED_LEFT := Color("#262523")
const BLOCKED_RIGHT := Color("#1a1918")
const BLOCKED_LINE := Color("#655e54")

const HOVER_FILL := Color(0.92, 0.84, 0.62, 0.16)
const HOVER_LINE := Color(0.95, 0.87, 0.64, 0.72)
const MOVE_FILL := Color(0.18, 0.78, 0.58, 0.24)
const MOVE_LINE := Color(0.42, 0.94, 0.74, 0.88)
const MOVE_GUIDE_FILL := Color(0.20, 0.90, 0.66, 0.34)
const MOVE_GUIDE_LINE := Color(0.68, 1.00, 0.86, 0.98)
const SHADOW_COLOR := Color(0.02, 0.03, 0.05, 0.48)
const HP_BG := Color(0.08, 0.09, 0.11, 0.85)
const HP_PLAYER := Color("#6cb878")
const HP_ENEMY := Color("#cf5c52")
const HP_SHIELD := Color("#78c3e0")

const PLAYER_BODY := Color("#a8a08b")
const PLAYER_OUTLINE := Color("#e7d7ae")
const ENEMY_BODY := Color("#873f3b")
const ENEMY_OUTLINE := Color("#d58b78")
## §12: a downed body keeps its cell, so the token stays on the board - dimmed,
## not removed, because an empty cell that refuses movement reads as a bug.
const PLAYER_BODY_DOWNED := Color("#3c3b35")
const PLAYER_OUTLINE_DOWNED := Color("#6d6a5f")
const DOWNED_MARK := Color("#a39e8f")

const RING_SHIELD := Color("#7fb8d8")
## Which party member the player is commanding. Two identical tokens otherwise
## leave no way to tell who a move or skill will come from.
const RING_ACTIVE := Color("#e4d2aa")
const RING_GUARD := Color("#e0b25c")
const RING_MARK := Color("#c98be0")
## Sakura's petal mark. Pink so it cannot be confused with the purple
## Judgment Mark ring, and clearly visible: the mark drives her automatic
## follow-up, so the player must see who carries it.
const RING_PETAL := Color("#e89ab0")
const RING_MELEE := Color("#ff4d4f")
const RING_WAIT := Color("#8c8b84")
const RING_TARGET := Color(0.95, 0.85, 0.55, 0.55)
## Ally-target rings: green so a shield target can never be mistaken for an
## enemy in reach.
const RING_ALLY := Color(0.56, 0.78, 0.60, 0.70)
const MARK_LABEL := Color("#e6c9f2")
const PETAL_LABEL := Color("#f7d9e2")

const TELEGRAPH_PULSE_FILL := Color(0.66, 0.24, 0.92, 0.42)
const TELEGRAPH_PULSE_LINE := Color("#df9eff")
const TELEGRAPH_PULSE_MARK := Color("#f8e8ff")
const TELEGRAPH_SHOT_FILL := Color(0.18, 0.44, 0.96, 0.42)
const TELEGRAPH_SHOT_LINE := Color("#66a6ff")
const TELEGRAPH_SHOT_MARK := Color("#dceaff")
const TELEGRAPH_CHARGE_FILL := Color(0.92, 0.14, 0.16, 0.44)
const TELEGRAPH_CHARGE_LINE := Color("#ff5252")
const TELEGRAPH_CHARGE_MARK := Color("#ffe6df")
const TELEGRAPH_PURSUIT_FILL := Color(0.76, 0.82, 0.92, 0.14)
const TELEGRAPH_PURSUIT_LINE := Color(0.84, 0.90, 0.98, 0.72)

## §11.1 deployment zone. Gold because it is a choice, not a reachable tile:
## the cyan move fill means "you can walk here this turn", and during deployment
## there is no turn yet.
const DEPLOY_FILL := Color(0.86, 0.72, 0.40, 0.16)
const DEPLOY_LINE := Color(0.92, 0.80, 0.52, 0.55)
const DEPLOY_ACTIVE_FILL := Color(0.96, 0.82, 0.46, 0.34)
const DEPLOY_ACTIVE_LINE := Color(1.00, 0.92, 0.68, 0.92)

## Ground hazards (凋零 / 残春). Flat and low-saturation on purpose: they are
## terrain the player stands on, not a telegraph for a hit that has not landed
## yet, so they must never read as "this will hit you this turn".
const HAZARD_BLIGHT_FILL := Color(0.26, 0.13, 0.31, 0.66)
const HAZARD_BLIGHT_LINE := Color(0.66, 0.44, 0.80, 0.95)
const HAZARD_SPRING_FILL := Color(0.97, 0.56, 0.62, 0.46)
const HAZARD_SPRING_LINE := Color(1.00, 0.78, 0.82, 0.96)

const PANEL := Color("#262a2f")
const PANEL_SELECTED := Color("#3a3f46")
const PANEL_DISABLED := Color("#1e2124")
const PANEL_BORDER := Color("#45484c")
const PANEL_BORDER_DISABLED := Color("#33363a")

const BUTTON_BG := Color("#4b4030")
const BUTTON_BG_DISABLED := Color("#2a2d31")
const BUTTON_BORDER := Color("#c4a66c")
const BUTTON_TEXT := Color("#f0e5d0")

const OVERLAY_BG := Color("#1b1e22")
const OVERLAY_SCRIM := Color(0.03, 0.04, 0.05, 0.72)

# --- layout ------------------------------------------------------------------

const VIEW_SIZE := Vector2(1280.0, 720.0)

const CELL_SIZE: float = 64.0
const BOARD_ORIGIN := Vector2(384.0, 72.0)

## 2.5D Isometric projection geometry (larger 8x8 diamond centered above the
## bottom portrait card & horizontal skill bar).
const ISO_TILE_W: float = 80.0
const ISO_TILE_H: float = 44.0
const ISO_TILE_DEPTH: float = 16.0
const ISO_OBSTACLE_H: float = 26.0
const ISO_ORIGIN := Vector2(640.0, 146.0)

const LEFT_COLUMN_X: float = 24.0

## Bottom horizontal skill bar & right-bottom End Turn button
const SKILL_FIRST_X: float = 328.0
const SKILL_BAR_Y: float = 608.0
const SKILL_BTN_W: float = 172.0
const SKILL_BTN_H: float = 84.0
const SKILL_BTN_GAP: float = 12.0
const END_TURN_RECT := Rect2(1072.0, 608.0, 184.0, 84.0)

## Bottom-left portrait card (portrait + HP bar underneath)
const PORTRAIT_CARD_RECT := Rect2(24.0, 540.0, 284.0, 152.0)
const TOP_LEFT_RECT := Rect2(24.0, 20.0, 284.0, 102.0)
const CAM_LEFT_BTN := Rect2(24.0, 130.0, 138.0, 32.0)
const CAM_RIGHT_BTN := Rect2(170.0, 130.0, 138.0, 32.0)
const BAG_BTN := Rect2(24.0, 190.0, 284.0, 34.0)
const GUIDE_BANNER_RECT := Rect2(332.0, 20.0, 616.0, 52.0)
const ORDER_CARD_RECT := Rect2(972.0, 20.0, 284.0, 144.0)
const ENEMY_INFO_RECT := Rect2(972.0, 178.0, 284.0, 224.0)

## Legacy aliases kept so external scripts never break on missing constants
const SKILL_PANEL_X: float = SKILL_FIRST_X
const SKILL_PANEL_W: float = SKILL_BTN_W
const SKILL_FIRST_Y: float = SKILL_BAR_Y
const SKILL_BTN_STEP: float = SKILL_BTN_W + SKILL_BTN_GAP

const SETTLEMENT_RECT := Rect2(330.0, 210.0, 620.0, 330.0)
const RESTART_BTN := Rect2(390.0, 464.0, 220.0, 52.0)
const NEXT_BTN := Rect2(640.0, 464.0, 220.0, 52.0)

const OATH_VOW_MAX: int = 3

## Active corner camera quadrant (0..3 -> 4 diagonal corner views around the 8x8 board).
static var camera_quadrant: int = 0
static var board_grid_size: Vector2i = Vector2i(8, 8)

const CAMERA_LABELS: Array[String] = ["东南机位", "西南机位", "西北机位", "东北机位"]


static func rotate_camera(step: int) -> void:
	camera_quadrant = posmod(camera_quadrant + step, 4)


static func camera_label() -> String:
	return "%s (%d/4)" % [CAMERA_LABELS[camera_quadrant], camera_quadrant + 1]


static func view_grid_size() -> Vector2i:
	return board_grid_size if camera_quadrant % 2 == 0 else Vector2i(board_grid_size.y, board_grid_size.x)


static func to_view_cell(cell: Vector2i) -> Vector2i:
	var lx: int = board_grid_size.x - 1
	var ly: int = board_grid_size.y - 1
	match camera_quadrant:
		1:
			return Vector2i(cell.y, lx - cell.x)
		2:
			return Vector2i(lx - cell.x, ly - cell.y)
		3:
			return Vector2i(ly - cell.y, cell.x)
		_:
			return cell


static func from_view_cell(vcell: Vector2i) -> Vector2i:
	var lx: int = board_grid_size.x - 1
	var ly: int = board_grid_size.y - 1
	match camera_quadrant:
		1:
			return Vector2i(lx - vcell.y, vcell.x)
		2:
			return Vector2i(lx - vcell.x, ly - vcell.y)
		3:
			return Vector2i(vcell.y, ly - vcell.x)
		_:
			return vcell


## 2.5D Isometric board geometry. Static so the input layer and the renderer
## cannot disagree: cell_at(cell_center(c)) == c for every cell in all 4 cameras.
static func cell_center(cell: Vector2i) -> Vector2:
	var vc := to_view_cell(cell)
	var half_w := ISO_TILE_W * 0.5
	var half_h := ISO_TILE_H * 0.5
	return Vector2(
		ISO_ORIGIN.x + float(vc.x - vc.y) * half_w,
		ISO_ORIGIN.y + float(vc.x + vc.y + 1) * half_h
	)


static func view_cell_diamond(vc: Vector2i, inset: float = 0.0, y_offset: float = 0.0) -> PackedVector2Array:
	var half_w := ISO_TILE_W * 0.5
	var half_h := ISO_TILE_H * 0.5
	var c := Vector2(
		ISO_ORIGIN.x + float(vc.x - vc.y) * half_w,
		ISO_ORIGIN.y + float(vc.x + vc.y + 1) * half_h + y_offset
	)
	var hw := maxf(2.0, half_w - inset)
	var hh := maxf(2.0, half_h - inset * (ISO_TILE_H / ISO_TILE_W))
	return PackedVector2Array([
		Vector2(c.x, c.y - hh),
		Vector2(c.x + hw, c.y),
		Vector2(c.x, c.y + hh),
		Vector2(c.x - hw, c.y),
	])


static func cell_diamond(cell: Vector2i, inset: float = 0.0, y_offset: float = 0.0) -> PackedVector2Array:
	return view_cell_diamond(to_view_cell(cell), inset, y_offset)


static func cell_rect(cell: Vector2i) -> Rect2:
	var c := cell_center(cell)
	return Rect2(c - Vector2(ISO_TILE_W * 0.5, ISO_TILE_H * 0.5), Vector2(ISO_TILE_W, ISO_TILE_H))


static func cell_at(position: Vector2) -> Vector2i:
	var half_w := ISO_TILE_W * 0.5
	var half_h := ISO_TILE_H * 0.5
	var dx := (position.x - ISO_ORIGIN.x) / half_w
	var dy := (position.y - ISO_ORIGIN.y) / half_h
	var vc := Vector2i(floori((dx + dy) * 0.5), floori((dy - dx) * 0.5))
	return from_view_cell(vc)


static func is_inside_board(cell: Vector2i, grid_size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


## Standee sprite render height. Owned here with the other hard-coded UI
## dimensions so the threat labels and the actor renderer cannot disagree.
const STANDEE_HEIGHT: float = 96.0


## Shared isometric draw primitives: every board layer (terrain, objects,
## threat) draws through these two, so a closed diamond or an ellipse always
## takes the same pixels no matter which layer drew it.
static func draw_polyline_closed(canvas: CanvasItem, pts: PackedVector2Array, color: Color, width: float) -> void:
	if pts.size() < 2:
		return
	var closed := PackedVector2Array(pts)
	closed.append(pts[0])
	canvas.draw_polyline(closed, color, width, true)


static func draw_iso_ellipse(canvas: CanvasItem, center: Vector2, rx: float, ry: float, color: Color, filled: bool, width: float = 2.0) -> void:
	var segs := 28
	var pts := PackedVector2Array()
	for i in range(segs):
		var a := (float(i) / float(segs)) * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	if filled:
		canvas.draw_colored_polygon(pts, color)
	else:
		draw_polyline_closed(canvas, pts, color, width)
