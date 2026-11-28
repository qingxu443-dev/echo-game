class_name BoardThreatTiles
extends RefCounted

const P = preload("res://scripts/ui/theme_palette.gd")
## Tags retain action classification for queries; every rendered attack is red.
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


static func draw(canvas: CanvasItem, controller, _time: float) -> void:
	BoardOverlayRegion.draw(canvas, build(controller), BoardOverlayRegion.ATTACK_FILL, BoardOverlayRegion.ATTACK_LINE)


static func draw_boundaries(canvas: CanvasItem, controller) -> void:
	BoardOverlayRegion.draw_boundary(canvas, build(controller), BoardOverlayRegion.ATTACK_LINE, 3.2)
