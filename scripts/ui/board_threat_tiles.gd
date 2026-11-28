class_name BoardThreatTiles
extends RefCounted

const P = preload("res://scripts/ui/theme_palette.gd")
const STYLES := {
	"charge": [P.TELEGRAPH_CHARGE_FILL, P.TELEGRAPH_CHARGE_LINE],
	"pulse": [P.TELEGRAPH_PULSE_FILL, P.TELEGRAPH_PULSE_LINE],
	"shot": [P.TELEGRAPH_SHOT_FILL, P.TELEGRAPH_SHOT_LINE],
	"blight": [P.HAZARD_BLIGHT_FILL, P.HAZARD_BLIGHT_LINE],
	"spring": [P.HAZARD_SPRING_FILL, P.HAZARD_SPRING_LINE],
}
## One fill/border per tile; short colored corners preserve overlapping types.
const PRIORITY := ["charge", "pulse", "shot", "blight", "spring"]
const ACTION_STYLES := {
	"charged_strike": "charge", "sakura_shock": "charge", "basic_melee": "charge", "shadow_raid": "charge",
	"ground_pulse": "pulse", "echo_bolt": "pulse", "rot_curse": "pulse",
	"aimed_shot": "shot", "light_shot": "shot", "lock_on": "shot", "locked_shot": "shot",
	"blight_field": "blight", "spring_bloom": "spring",
}


static func cells_for(controller, intent) -> Array[Vector2i]:
	if intent.target_mode == BattleIntent.TargetMode.ACTOR_LOCKED:
		var target = controller.get_actor(intent.target_actor_id)
		if target == null or not target.is_alive():
			return []
		return [target.cell]
	if intent.target_mode == BattleIntent.TargetMode.AREA_LOCKED:
		return intent.affected_cells.duplicate()
	return [intent.target_cell]


static func build(controller) -> Dictionary:
	var tiles: Dictionary = {}
	for intent in controller.intents:
		if intent.state != BattleIntent.IntentState.ACTIVE or not ACTION_STYLES.has(intent.action_id):
			continue
		var source = controller.get_actor(intent.source_actor_id)
		if source == null or not source.is_alive():
			continue
		var style: String = ACTION_STYLES[intent.action_id]
		for cell in cells_for(controller, intent):
			if not P.is_inside_board(cell, controller.grid_size):
				continue
			if not tiles.has(cell):
				tiles[cell] = []
			if not tiles[cell].has(style):
				tiles[cell].append(style)
	for cell in tiles:
		var ordered: Array[String] = []
		for style in PRIORITY:
			if tiles[cell].has(style):
				ordered.append(style)
		tiles[cell] = ordered
	return tiles


static func draw(canvas: CanvasItem, controller, time: float) -> void:
	var pulse := 0.94 + 0.06 * sin(time * 3.0)
	var tiles := build(controller)
	for cell in tiles:
		var styles: Array = tiles[cell]
		var fill: Color = STYLES[styles[0]][0]
		var outer := P.cell_diamond(cell, 1.5)
		canvas.draw_colored_polygon(outer, Color(fill.r, fill.g, fill.b, fill.a * pulse * 0.62))
		var primary: Color = STYLES[styles[0]][1]
		P.draw_polyline_closed(canvas, outer, Color(primary.r, primary.g, primary.b, 0.85), 1.4)
		for index in range(1, styles.size()):
			var line: Color = STYLES[styles[index]][1]
			P.draw_corner_marks(canvas, outer, line, 2.4, index - 1)
