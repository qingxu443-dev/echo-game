extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not ProjectSettings.load_resource_pack(args[0], true):
		push_error("Cannot mount exported Windows package")
		quit(1)
		return
	var files: Array[String] = []
	_collect("res://", files)
	files.sort()
	for path in files:
		for forbidden in ["res://tests/", "res://assets/actors/raw/", "res://tools/", "res://docs/", "res://build/", "res://dist/"]:
			if path.begins_with(forbidden):
				push_error("Forbidden source content in package: " + path)
				quit(1)
				return
	if not ResourceLoader.exists("res://scenes/menu/main_menu.tscn"):
		push_error("Package has no main menu resource")
		quit(1)
		return
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify({"files": files, "count": files.size()}, "\t"))
	file.close()
	print("PACKAGE_CONTENT_OK files=%d" % files.size())
	quit(0)

func _collect(path: String, files: Array[String]) -> void:
	for name in DirAccess.get_files_at(path):
		files.append(path.path_join(name))
	for directory in DirAccess.get_directories_at(path):
		_collect(path.path_join(directory), files)
