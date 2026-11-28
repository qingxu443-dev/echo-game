class_name CustomEditorTheme
extends RefCounted


static func panel(fill: Color = Color("#19212b"), border: Color = Color("#394652")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(12)
	return style


static func button(control: Button, primary: bool = false) -> void:
	control.add_theme_stylebox_override("normal", panel(Color("#30332f") if primary else Color("#202b36"), UiPalette.GOLD if primary else Color("#435360")))
	control.add_theme_stylebox_override("hover", panel(Color("#31424a"), UiPalette.GOLD_LIGHT))
	control.add_theme_stylebox_override("pressed", panel(Color("#2c444c"), UiPalette.CYAN))
	control.add_theme_stylebox_override("focus", panel(Color(0, 0, 0, 0), UiPalette.CYAN))
	control.add_theme_color_override("font_color", UiPalette.GOLD_PALE if primary else UiPalette.TEXT)
	control.add_theme_font_size_override("font_size", 15)
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func label(text: String, size: int = 15, color: Color = UiPalette.TEXT) -> Label:
	var control := Label.new()
	control.text = text
	control.add_theme_font_size_override("font_size", size)
	control.add_theme_color_override("font_color", color)
	return control


static func number(value: int, minimum: int, maximum: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = value
	spin.custom_minimum_size = Vector2(110, 34)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.get_line_edit().add_theme_stylebox_override("normal", panel(Color("#121a23")))
	spin.get_line_edit().add_theme_font_size_override("font_size", 15)
	return spin
