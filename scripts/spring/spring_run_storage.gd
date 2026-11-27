class_name SpringRunStorage
extends RefCounted


## Starts a new expedition only after the inventory transfer is durably recorded.
static func start(p_seed: int, hard_mode: bool, path: String, atelier_path: String) -> SpringRun:
	# A failed load must never authorize overwriting an existing checkpoint.
	if FileAccess.file_exists(path) and SpringRun.load_from_file(path) == null:
		return null
	var fresh := SpringRun.begin(p_seed, hard_mode)
	if atelier_path == AtelierStash.SAVE_PATH and DisplayServer.get_name() == "headless":
		return fresh if fresh.save_to_file(path) else null
	var stash := AtelierStash.read_state(atelier_path)
	if stash.is_empty():
		return null
	for item in AtelierStash.packed_items(stash):
		fresh.add_battle_item(item)
	stash["loadout"] = []
	if not SpringSaveTransaction.commit(path, atelier_path, fresh.to_dict(), stash):
		return null
	return fresh


static func settle(run: SpringRun, path: String, atelier_path: String, shards: int) -> bool:
	if atelier_path == AtelierStash.SAVE_PATH and DisplayServer.get_name() == "headless":
		return run.save_to_file(path)
	var stash := AtelierStash.read_state(atelier_path)
	if stash.is_empty():
		return false
	stash["shards"] = int(stash["shards"]) + shards
	return SpringSaveTransaction.commit(path, atelier_path, run.to_dict(), stash)
