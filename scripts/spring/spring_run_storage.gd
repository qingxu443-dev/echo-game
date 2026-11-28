class_name SpringRunStorage
extends RefCounted


## Starts a new expedition only after the inventory transfer is durably recorded.
static func start(p_seed: int, hard_mode: bool, path: String, atelier_path: String) -> SpringRun:
	# A failed load must never authorize overwriting an existing checkpoint.
	if FileAccess.file_exists(path):
		var existing := SpringRun.load_from_file(path)
		if existing == null or not existing.pending_battle_settlement.is_empty():
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


static func settle(run: SpringRun, path: String, atelier_path: String, shards: int, settlement_id: String = "") -> bool:
	if SpringSaveTransaction.is_pending(atelier_path):
		if not SpringSaveTransaction.recover(path, atelier_path):
			return false
		var recovered := SpringRun.load_from_file(path)
		if recovered != null:
			run.settled_battle_ids = recovered.settled_battle_ids.duplicate()
	var already_settled := not settlement_id.is_empty() and run.settled_battle_ids.has(settlement_id)
	var run_image: Dictionary = run.to_dict()
	if not settlement_id.is_empty() and not already_settled:
		var settled_ids: Array = run_image.get("settled_battle_ids", []).duplicate()
		settled_ids.append(settlement_id)
		run_image["settled_battle_ids"] = settled_ids
	if atelier_path == AtelierStash.SAVE_PATH and DisplayServer.get_name() == "headless":
		if not SaveFile.write_json(path, run_image):
			return false
		if not settlement_id.is_empty() and not already_settled:
			run.settled_battle_ids.append(settlement_id)
		return true
	var stash := AtelierStash.read_state(atelier_path)
	if stash.is_empty():
		return false
	if not already_settled:
		stash["shards"] = int(stash["shards"]) + shards
	if not SpringSaveTransaction.commit(path, atelier_path, run_image, stash):
		return false
	if not settlement_id.is_empty() and not already_settled:
		run.settled_battle_ids.append(settlement_id)
	return true
