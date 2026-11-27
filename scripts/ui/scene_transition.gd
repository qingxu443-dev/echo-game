class_name SceneTransition
extends Control

var coverage: float = 0.0
var elapsed: float = 0.0
var title: String = "回声流转"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


func _draw() -> void:
	if coverage <= 0.001: return
	var a := clampf(coverage, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.032, 0.045, a))
	var center := size * 0.5
	var ink := Color(UiPalette.GOLD_LIGHT, a)
	var radius := 32.0 + sin(elapsed * 1.6) * 2.0
	var points := PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, 0), center + Vector2(0, radius), center + Vector2(-radius, 0), center + Vector2(0, -radius)])
	draw_polyline(points, ink, 1.2, true)
	draw_arc(center, 43.0, elapsed * 0.65, elapsed * 0.65 + PI * 1.3, 48, Color(UiPalette.CYAN, a * 0.6), 1.0, true)
	for side in [-1.0, 1.0]:
		draw_line(center + Vector2(side * 70.0, 0), center + Vector2(side * 210.0, 0), Color(ink, a * 0.35), 1.0)
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	draw_string(font, center + Vector2(-width * 0.5, 92), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(UiPalette.TEXT, a))
	draw_string(font, center + Vector2(-72, 126), "E C H O  /  JOURNEY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UiPalette.GOLD, a * 0.7))
