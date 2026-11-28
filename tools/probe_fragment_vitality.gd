extends SceneTree

## Standalone diagnostic for the remaining cross-encounter health issue.
## It uses only a process-specific fragment file, never the real module store.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "user://fragment_vitality_probe_%d.json" % OS.get_process_id()
	FragmentStore.default_path_override = path
	var store := FragmentStore.load_store(path)
	store.add_modules([{"instance_id": "probe_hp", "size": "small", "capacity": 1, "main_stat": "health", "sub_stat": "", "attributes": {"health": 5.0}, "created_seed": 0}])
	store.install("sakura", 0, "probe_hp")
	if not store.save(): quit(2); return
	var run := SpringRun.begin(3)
	run.party_character_ids.assign(["sakura"])
	run.hero_health = 900
	run.party_vitals = {"sakura": {"health": 900, "max_health": 1800}}
	SpringBattleBridge.prepare(run, &"B001", &"battle_1")
	var view = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(view)
	var actual: int = view.controller.actors.sakura.max_health
	print(JSON.stringify({"scenario": "install 5% health fragment before the next Spring encounter", "expected_maximum": 1890, "actual_maximum": actual}))
	view.queue_free()
	SpringBattleBridge.clear_pending()
	FragmentStore.default_path_override = ""
	DirAccess.remove_absolute(path)
	await process_frame
	quit(0 if actual == 1890 else 1)
