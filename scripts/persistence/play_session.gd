class_name PlaySession
extends RefCounted

const MAP_UI: Array[String] = ["selected_cell", "confirm_end", "shop_open", "shop_tab", "shop_sell_page", "shop_message", "status_message"]


static func save(scene: Node) -> bool:
	if scene.has_method("_current_level"):
		return SessionSave.write(BattleSession.capture(scene))
	if scene.get("run") == null or not scene._save(): return false
	var ui: Dictionary = {}
	for key in MAP_UI: ui[key] = scene.get(key)
	return SessionSave.write({"scene": "map", "run": scene.run.to_dict(), "ui": ui})


static func restore_map(scene: Node, data: Dictionary) -> bool:
	if data.get("scene", "") != "map" or not SessionSave.valid(data): return false
	scene.run = SpringRun.from_dict(data.run)
	for key in MAP_UI:
		if data.get("ui", {}).has(key): scene.set(key, data.ui[key])
	return scene.run != null
