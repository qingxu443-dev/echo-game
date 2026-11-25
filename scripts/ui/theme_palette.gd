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

const BOARD_LIGHT := Color("#292c31")
const BOARD_DARK := Color("#24272c")
const BOARD_LINE := Color("#45484c")
const BLOCKED_FILL := Color("#101114")
const BLOCKED_LINE := Color("#55504a")

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
const RING_MELEE := Color("#e3a35d")
const RING_WAIT := Color("#8c8b84")
const RING_TARGET := Color(0.95, 0.85, 0.55, 0.55)
## Ally-target rings: green so a shield target can never be mistaken for an
## enemy in reach.
const RING_ALLY := Color(0.56, 0.78, 0.60, 0.70)
const MARK_LABEL := Color("#e6c9f2")

const TELEGRAPH_PULSE_FILL := Color(0.48, 0.35, 0.72, 0.24)
const TELEGRAPH_PULSE_LINE := Color("#b49adf")
const TELEGRAPH_PULSE_MARK := Color("#eee4ff")
const TELEGRAPH_SHOT_FILL := Color(0.20, 0.55, 0.72, 0.22)
const TELEGRAPH_SHOT_LINE := Color("#78c7df")
const TELEGRAPH_SHOT_MARK := Color("#d7f5ff")
const TELEGRAPH_CHARGE_FILL := Color(0.65, 0.12, 0.10, 0.24)
const TELEGRAPH_CHARGE_LINE := Color("#e36a5e")
const TELEGRAPH_CHARGE_MARK := Color("#ffd7cb")
const TELEGRAPH_PURSUIT_FILL := Color(0.75, 0.61, 0.31, 0.22)
const TELEGRAPH_PURSUIT_LINE := Color("#c5a45c")

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

const LEFT_COLUMN_X: float = 48.0

const SKILL_PANEL_X: float = 940.0
const SKILL_PANEL_W: float = 300.0
const SKILL_FIRST_Y: float = 112.0
const SKILL_BTN_H: float = 50.0
const SKILL_BTN_STEP: float = 54.0
const END_TURN_RECT := Rect2(940.0, 620.0, 300.0, 60.0)

const SETTLEMENT_RECT := Rect2(330.0, 210.0, 620.0, 330.0)
const RESTART_BTN := Rect2(390.0, 464.0, 220.0, 52.0)
const NEXT_BTN := Rect2(640.0, 464.0, 220.0, 52.0)

const ULTIMATE_ENERGY_MAX: int = 5
const OATH_VOW_MAX: int = 3


## Board geometry. Static so the input layer and the renderer cannot disagree.
static func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(BOARD_ORIGIN + Vector2(cell) * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE))


static func cell_center(cell: Vector2i) -> Vector2:
	return cell_rect(cell).position + Vector2(CELL_SIZE * 0.5, CELL_SIZE * 0.5)


static func cell_at(position: Vector2) -> Vector2i:
	var grid_position := (position - BOARD_ORIGIN) / CELL_SIZE
	return Vector2i(floori(grid_position.x), floori(grid_position.y))


static func is_inside_board(cell: Vector2i, grid_size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y
