extends "res://tests/framework/test_case.gd"

var run_path := "user://transaction_validation_run_%d.json" % OS.get_process_id()
var stash_path := "user://transaction_validation_stash_%d.json" % OS.get_process_id()


func _run() -> void:
	_test_bad_journal_images()
	_test_bad_commit_images()
	_test_wallet_read_and_write()
	_test_non_json_wallet_values()
	await _test_map_refuses_bad_recovery()
	_test_valid_recovery()
	_cleanup()


func _wallet() -> Dictionary:
	return {"shards": 105, "loadout": ["item_dusk_potion"]}


func _images() -> Dictionary:
	var run := SpringRun.begin(3)
	run.coins = 37
	return {"version": 1, "run_path": run_path, "run": run.to_dict(), "atelier": {"shards": 140, "loadout": []}}


func _seed() -> void:
	_cleanup()
	_check(SpringRun.begin(1).save_to_file(run_path) and SaveFile.write_json(stash_path, _wallet()), "seed two valid old destinations")


func _cleanup() -> void:
	for path in [run_path, stash_path, SpringSaveTransaction.journal_path(stash_path)]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)


func _corruptions() -> Array:
	return [
		["run", "hero", []], ["run", "template_id", 99], ["run", "version", SpringRun.SAVE_VERSION + 1],
		["atelier", "shards", "140"], ["atelier", "shards", -1], ["atelier", "shards", 1.5],
		["atelier", "loadout", "item_dusk_potion"], ["atelier", "loadout", ["item_dusk_potion", "unknown_paid_item"]],
		["atelier", "loadout", [27]],
	]


func _broken(row: Array) -> Dictionary:
	var data := _images()
	data[row[0]][row[1]] = row[2]
	return data


func _test_bad_journal_images() -> void:
	for row in _corruptions():
		_seed()
		var old_run := FileAccess.get_file_as_string(run_path)
		var old_wallet := FileAccess.get_file_as_string(stash_path)
		var journal := SpringSaveTransaction.journal_path(stash_path)
		SaveFile.write_json(journal, _broken(row))
		var old_record := FileAccess.get_file_as_string(journal)
		_check(not SpringSaveTransaction.recover(run_path, stash_path), "reject malformed recovery image: " + str(row))
		_check(FileAccess.get_file_as_string(run_path) == old_run and FileAccess.get_file_as_string(stash_path) == old_wallet, "neither valid destination is overwritten")
		_check(FileAccess.get_file_as_string(journal) == old_record, "retain invalid recovery record for diagnosis")
		var wallet := _wallet()
		_check(not AtelierStash.buy_and_pack(wallet, "item_echo_hourglass", stash_path).ok and wallet == _wallet(), "pending damaged transaction still blocks later wallet writes")


func _test_bad_commit_images() -> void:
	for row in _corruptions():
		_seed()
		var data := _broken(row)
		var old_run := FileAccess.get_file_as_string(run_path)
		var old_wallet := FileAccess.get_file_as_string(stash_path)
		_check(not SpringSaveTransaction.commit(run_path, stash_path, data.run, data.atelier), "reject malformed commit image: " + str(row))
		_check(not SpringSaveTransaction.is_pending(stash_path), "invalid new data does not create a recovery lock")
		_check(FileAccess.get_file_as_string(run_path) == old_run and FileAccess.get_file_as_string(stash_path) == old_wallet, "invalid commit preserves both destinations")


func _test_wallet_read_and_write() -> void:
	for row in _corruptions():
		if row[0] != "atelier": continue
		_seed()
		var wallet: Dictionary = _broken(row).atelier
		var before := FileAccess.get_file_as_string(stash_path)
		_check(not AtelierStash.save_state(wallet, stash_path) and FileAccess.get_file_as_string(stash_path) == before, "wallet writer rejects invalid new state")
		SaveFile.write_json(stash_path, wallet)
		before = FileAccess.get_file_as_string(stash_path)
		_check(AtelierStash.read_state(stash_path).is_empty(), "wallet reader rejects malformed resources or paid item IDs")
		_check(AtelierStash.claim_loadout(stash_path).get("ok") == false and FileAccess.get_file_as_string(stash_path) == before, "invalid wallet cannot claim a partial pack or overwrite the evidence")


func _test_valid_recovery() -> void:
	_seed()
	var data := _images()
	data.run.version = 2
	data.run.hero.carry_max_health = 3600
	SaveFile.write_json(SpringSaveTransaction.journal_path(stash_path), data)
	_check(SpringSaveTransaction.recover(run_path, stash_path), "valid legacy run can complete recovery")
	var restored := SpringRun.load_from_file(run_path)
	_check(restored != null and restored.coins == 37 and restored.carry_max_health == 0, "normal loader retains legacy migration semantics")
	_check(AtelierStash.read_state(stash_path) == data.atelier and not SpringSaveTransaction.is_pending(stash_path), "valid recovery writes the intended wallet and clears its journal")
	var before := FileAccess.get_file_as_string(stash_path)
	_check(SpringSaveTransaction.recover(run_path, stash_path) and FileAccess.get_file_as_string(stash_path) == before, "completed recovery is idempotent")
	SaveFile.write_json(stash_path, {"shards": 105.0, "loadout": ["item_dusk_potion"]})
	_check(AtelierStash.read_state(stash_path) == _wallet(), "integral JSON floats remain compatible")
	SaveFile.write_json(stash_path, {})
	_check(AtelierStash.read_state(stash_path) == {"shards": AtelierStash.STARTING_SHARDS, "loadout": []}, "legacy missing wallet fields retain their defaults")


func _test_non_json_wallet_values() -> void:
	for value in [NAN, INF, -INF, 9223372036854775808.0, true]:
		_seed()
		var before := FileAccess.get_file_as_string(stash_path)
		_check(not AtelierStash.save_state({"shards": value, "loadout": []}, stash_path), "reject nonfinite, overflowing or boolean shards before JSON encoding")
		_check(FileAccess.get_file_as_string(stash_path) == before, "invalid in-memory shards preserve the old wallet")
	_check(AtelierStash.from_dict({"shards": 0, "loadout": []}) == {"shards": 0, "loadout": []}, "empty paid pack and zero shards remain valid")
	_check(not AtelierStash.from_dict({"shards": 9223372036854775807, "loadout": []}).is_empty(), "integer validation does not round the int64 endpoint to an overflowing float")


func _test_map_refuses_bad_recovery() -> void:
	_seed()
	var old_run := FileAccess.get_file_as_string(run_path)
	var old_wallet := FileAccess.get_file_as_string(stash_path)
	var data := _images()
	data.atelier.loadout = ["unknown_paid_item"]
	SaveFile.write_json(SpringSaveTransaction.journal_path(stash_path), data)
	var map = load("res://scenes/spring/spring_map.tscn").instantiate()
	map.save_path = run_path
	map.atelier_save_path = stash_path
	root.add_child(map)
	_check(map.run == null and map.status_message.contains("恢复"), "normal map entry stops with a recovery diagnostic")
	_check(FileAccess.get_file_as_string(run_path) == old_run and FileAccess.get_file_as_string(stash_path) == old_wallet and SpringSaveTransaction.is_pending(stash_path), "scene entry preserves both old saves and the damaged journal")
	map.queue_free()
	await process_frame
