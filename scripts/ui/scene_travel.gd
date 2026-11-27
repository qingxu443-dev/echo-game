class_name SceneTravel
extends RefCounted


static func change(tree: SceneTree, path: String, title: String = "回声流转") -> Error:
	if not ResourceLoader.exists(path): return ERR_FILE_NOT_FOUND
	var shell := tree.root.get_node_or_null("GameShell")
	if shell != null and shell.animations_enabled:
		return shell.travel(path, title)
	return tree.change_scene_to_file(path)


static func reveal(scene: Node, title: String) -> void:
	var shell := scene.get_node_or_null("/root/GameShell")
	if shell != null: shell.reveal(title)


static func intercept(scene: Node, event: InputEvent) -> bool:
	var shell := scene.get_node_or_null("/root/GameShell")
	return shell != null and shell.intercept(event)


static func sound(scene: Node, cue: String) -> void:
	var shell := scene.get_node_or_null("/root/GameShell")
	if shell != null: shell.audio.play_cue(cue)
