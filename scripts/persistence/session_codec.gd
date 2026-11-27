class_name SessionCodec
extends RefCounted

## JSON-only codec. Objects, scripts and callables are never deserialized.
static func encode(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2I: return {"$": "v2i", "x": value.x, "y": value.y}
		TYPE_VECTOR2: return {"$": "v2", "x": value.x, "y": value.y}
		TYPE_COLOR: return {"$": "color", "v": value.to_html()}
		TYPE_STRING_NAME: return {"$": "name", "v": str(value)}
		TYPE_INT: return {"$": "int", "v": str(value)} # RNG state is a full 64-bit integer.
		TYPE_ARRAY:
			var items: Array = []
			for item in value: items.append(encode(item))
			return items
		TYPE_DICTIONARY:
			var entries: Array = []
			for key in value: entries.append([encode(key), encode(value[key])])
			return {"$": "dict", "v": entries}
		TYPE_NIL, TYPE_BOOL, TYPE_FLOAT, TYPE_STRING: return value
	return null


static func decode(value: Variant, depth: int = 0) -> Variant:
	if depth > 40: return null
	if value is Array:
		var items: Array = []
		for item in value: items.append(decode(item, depth + 1))
		return items
	if not value is Dictionary: return value
	if value.get("$", "") in ["v2i", "v2"]:
		for key in ["x", "y"]:
			if not value.get(key) is int and not value.get(key) is float: return null
	match value.get("$", ""):
		"v2i": return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
		"v2": return Vector2(float(value.get("x", 0)), float(value.get("y", 0)))
		"color": return Color.from_string(str(value.get("v", "")), Color.WHITE)
		"name": return StringName(str(value.get("v", "")))
		"int": return str(value.get("v", "0")).to_int()
		"dict":
			var result: Dictionary = {}
			if not value.get("v", []) is Array: return result
			for pair in value.get("v", []):
				if not pair is Array or pair.size() != 2: return {}
				var key: Variant = decode(pair[0], depth + 1)
				if key == null or key is Array or key is Dictionary: return {}
				result[key] = decode(pair[1], depth + 1)
			return result
	return null


static func fields(object: Object, excluded: Array[String] = []) -> Dictionary:
	var result: Dictionary = {}
	for property in object.get_script().get_script_property_list():
		var key := str(property.name)
		if key in excluded or key == "script": continue
		var value: Variant = object.get(key)
		if value is Object or value is Callable or value is Signal: continue
		result[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return result


static func apply_fields(object: Object, values: Dictionary) -> void:
	# Only existing script data fields can be restored; never set Node properties.
	for property in object.get_script().get_script_property_list():
		var key := str(property.name)
		if key == "script" or not values.has(key): continue
		var current: Variant = object.get(key)
		if current is Object or current is Callable or current is Signal: continue
		var value: Variant = values[key]
		if current is Array and value is Array:
			current.assign(value)
		elif typeof(current) == typeof(value) or (current == null and value == null):
			object.set(key, value)
		elif typeof(current) == TYPE_STRING_NAME and value is String:
			object.set(key, StringName(value))
