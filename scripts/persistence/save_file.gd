class_name SaveFile
extends RefCounted


## Write alongside the destination so a failed write never truncates the last save.
static func write_json(path: String, data: Dictionary) -> bool:
	var temporary_path := "%s.%d.%d.tmp" % [path, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	var written := file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	written = written and file.get_error() == OK
	file.close()
	if written and DirAccess.rename_absolute(temporary_path, path) == OK:
		return true
	DirAccess.remove_absolute(temporary_path)
	return false
