class_name SpringSaveTransaction
extends RefCounted

## A complete pair of save images is recorded before either destination changes.
## Recovery replaces both destinations with those same images on every retry.
## The caller supplies the permitted paths, and stash writers wait until the
## journal is cleared so recovery cannot replay over a later wallet update.


static func journal_path(atelier_path: String) -> String:
	return atelier_path + ".spring-transaction"


static func is_pending(atelier_path: String) -> bool:
	return FileAccess.file_exists(journal_path(atelier_path))


static func commit(run_path: String, atelier_path: String, run_data: Dictionary, atelier_data: Dictionary) -> bool:
	if not _valid_images(run_data, atelier_data): return false
	var journal := journal_path(atelier_path)
	if is_pending(atelier_path) or not SaveFile.write_json(journal, {
		"version": 1,
		"run_path": run_path,
		"run": run_data,
		"atelier": atelier_data,
	}):
		return false
	return recover(run_path, atelier_path)


static func recover(run_path: String, atelier_path: String) -> bool:
	if not is_pending(atelier_path):
		return true
	var journal := journal_path(atelier_path)
	var file := FileAccess.open(journal, FileAccess.READ)
	if file == null:
		return false
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary or data.get("version") != 1 or data.get("run_path") != run_path:
		return false
	if not data.get("run") is Dictionary or not data.get("atelier") is Dictionary:
		return false
	if not _valid_images(data.run, data.atelier): return false
	if not SaveFile.write_json(run_path, data["run"]) or not SaveFile.write_json(atelier_path, data["atelier"]):
		return false
	return DirAccess.remove_absolute(journal) == OK


## Validate both images before the first destination or new journal is written.
## Replay the original images so supported legacy migrations still run on load.
## CONTRACT: _test_bad_journal_images
## CONTRACT: _test_bad_commit_images
static func _valid_images(run_data: Dictionary, atelier_data: Dictionary) -> bool:
	return SpringRun.from_dict(run_data) != null and not AtelierStash.from_dict(atelier_data).is_empty()
