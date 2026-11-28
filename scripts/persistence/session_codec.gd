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
	var result := decode_checked(value, depth)
	return result.value if result.ok else null


## A failed nested tag must not masquerade as a legitimate null or empty map.
static func decode_checked(value: Variant, depth: int = 0) -> Dictionary:
	if depth > 40: return {"ok": false}
	if value is Array:
		var items: Array = []
		for item in value:
			var decoded := decode_checked(item, depth + 1)
			if not decoded.ok: return {"ok": false}
			items.append(decoded.value)
		return {"ok": true, "value": items}
	if not value is Dictionary:
		if typeof(value) not in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]: return {"ok": false}
		return {"ok": false} if value is float and not is_finite(value) else {"ok": true, "value": value}
	if value.get("$", "") in ["v2i", "v2"]:
		for key in ["x", "y"]:
			var part: Variant = value.get(key)
			if not (part is int or part is float) or not is_finite(float(part)): return {"ok": false}
			if value["$"] == "v2i":
				if part < -2147483648 or part > 2147483647 or float(part) != floorf(float(part)): return {"ok": false}
			elif absf(float(part)) > 3.402823466e38: return {"ok": false}
	match value.get("$", ""):
		"v2i": return {"ok": true, "value": Vector2i(int(value.x), int(value.y))}
		"v2": return {"ok": true, "value": Vector2(float(value.x), float(value.y))}
		"color":
			if not value.get("v") is String: return {"ok": false}
			var color: String = value.v
			if color.length() != 8 or not color.is_valid_hex_number(false): return {"ok": false}
			return {"ok": true, "value": Color.from_string(color, Color.WHITE)}
		"name":
			if not value.get("v") is String: return {"ok": false}
			return {"ok": true, "value": StringName(value.v)}
		"int":
			if not value.get("v") is String: return {"ok": false}
			var text: String = value.v
			if not text.is_valid_int(): return {"ok": false}
			var digits := text.trim_prefix("-")
			var limit := "9223372036854775808" if text.begins_with("-") else "9223372036854775807"
			if digits.length() > limit.length() or (digits.length() == limit.length() and digits > limit): return {"ok": false}
			var number := text.to_int()
			if str(number) != text: return {"ok": false}
			return {"ok": true, "value": number}
		"dict":
			var result: Dictionary = {}
			if not value.get("v") is Array: return {"ok": false}
			for pair in value.get("v", []):
				if not pair is Array or pair.size() != 2: return {"ok": false}
				var key := decode_checked(pair[0], depth + 1)
				var item := decode_checked(pair[1], depth + 1)
				if not key.ok or not item.ok: return {"ok": false}
				if key.value == null or key.value is Array or key.value is Dictionary or result.has(key.value): return {"ok": false}
				result[key.value] = item.value
			return {"ok": true, "value": result}
	return {"ok": false}


## Validate against the same script data surface used by fields/apply_fields.
## Missing optional fields retain defaults; typed arrays are checked before assign.
static func fields_error(script: Script, values: Dictionary, excluded: Array[String] = []) -> String:
	for property in script.get_script_property_list():
		var key := str(property.name)
		if not values.has(key): continue
		if key in excluded or key == "script": return key + ": field belongs to another container"
		var type: int = property.type
		var value: Variant = values[key]
		if type in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL]: return key + ": not serialized data"
		if type == TYPE_STRING_NAME and value is String: continue
		if typeof(value) != type: return key + ": expected " + type_string(type)
		if value is float and not is_finite(value): return key + ": nonfinite number"
		if type == TYPE_ARRAY and property.hint == PROPERTY_HINT_ARRAY_TYPE:
			var element_type: String = property.hint_string
			for item in value:
				if element_type == "StringName" and item is String: continue
				if type_string(typeof(item)) != element_type: return key + ": expected Array[" + element_type + "]"
	return ""


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
