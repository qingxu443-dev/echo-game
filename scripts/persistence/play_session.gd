class_name PlaySession
extends RefCounted

const MAP_UI: Array[String] = ["selected_cell", "confirm_end", "shop_open", "shop_tab", "shop_sell_page", "shop_message", "status_message"]
static var last_error := ""


static func save(scene: Node) -> bool:
	last_error = ""
	if scene.has_method("_current_level"):
		var saved := SessionSave.write(BattleSession.capture(scene))
		if not saved: last_error = SessionSave.last_write_error
		return saved
	if scene.get("run") == null or not scene._save():
		last_error = "地图进度未能保存，当前旅程仍保留，请查看日志后重试。"
		return false
	var ui: Dictionary = {}
	for key in MAP_UI: ui[key] = scene.get(key)
	var saved := SessionSave.write({"scene": "map", "run": scene.run.to_dict(), "ui": ui})
	if not saved: last_error = SessionSave.last_write_error
	return saved


static func restore_map(scene: Node, data: Dictionary) -> bool:
	if data.get("scene", "") != "map" or not SessionSave.valid(data): return false
	scene.run = SpringRun.from_dict(data.run)
	for key in MAP_UI:
		if data.get("ui", {}).has(key): scene.set(key, data.ui[key])
	return scene.run != null
