extends "res://tests/framework/test_case.gd"

var prefix := "user://persistence_contract_%d" % OS.get_process_id()
var paths: Array[String] = []


func _run() -> void:
	_test_roster_validation()
	_test_fragment_images()
	_test_mail_recovery_preflight()
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)


func _path(suffix: String) -> String:
	var path := prefix + suffix
	if not paths.has(path): paths.append(path)
	return path


func _test_roster_validation() -> void:
	var image := SpringRun.begin(3).to_dict()
	for roster in [["sakura", "sakura"], ["unknown"], ["sevrin", "dest_lee", "sevrin"]]:
		image.party_character_ids = roster
		_check(SpringRun.from_dict(image) == null, "reject impossible expedition roster before a later encounter: " + str(roster))
	for roster in [[], ["sevrin"], ["dest_lee", "sakura", "sevrin"]]:
		image.party_character_ids = roster
		_check(SpringRun.from_dict(JSON.parse_string(JSON.stringify(image))) != null, "retain legacy empty and all legal roster orders: " + str(roster))
	var path := _path("_run.json")
	var run := SpringRun.begin(3)
	_check(run.save_to_file(path), "seed a readable expedition checkpoint")
	var original := FileAccess.get_file_as_string(path)
	run.party_character_ids.assign(["sakura", "sakura"])
	_check(not run.save_to_file(path) and FileAccess.get_file_as_string(path) == original, "refuse an unreadable live image before replacing the previous save")
	var session_path := _path("_session.json")
	SessionSave.path_override = session_path
	_check(not SessionSave.write({"scene": "battle", "controller": {}, "actors": "bad"}) and SessionSave.last_write_error.contains("校验"), "pause validation failure has an actionable diagnostic without crashing")
	SessionSave.path_override = ""


func _test_fragment_images() -> void:
	var path := _path("_fragments.json")
	var rng := RandomNumberGenerator.new()
	rng.seed = 491
	var modules: Array[Dictionary] = []
	for _i in range(10):
		modules.append(FragmentCatalog.create_small(rng))
		modules.append(FragmentCatalog.create_medium(rng))
		for stat in FragmentCatalog.STAT_KEYS: modules.append(FragmentCatalog.create_large(stat, rng))
	modules.append_array(FragmentCatalog.create_fixed_large_bundle(rng))
	var image := {"version": 1, "revision": 2, "modules": modules, "equipped": {"sevrin": [str(modules[0].instance_id)]}}
	_check(SaveFile.write_json(path, image) and FragmentStore.load_store(path) != null, "all generated module sizes and main stats survive plain disk JSON")
	var base := image.duplicate(true)
	for key in ["version", "revision"]:
		for value in [1.5, "1", true, -1]:
			image = base.duplicate(true)
			image[key] = value
			_check(SaveFile.write_json(path, image) and FragmentStore.load_store(path) == null, "reject coerced module metadata: " + key + "=" + str(value))
	image = base.duplicate(true)
	image.modules[0].capacity = 1.5
	_check(SaveFile.write_json(path, image) and FragmentStore.load_store(path) == null, "fractional capacity must not truncate into a legal module")


func _test_mail_recovery_preflight() -> void:
	var mail_path := _path("_mail.json")
	var store_path := _path("_mail_fragments.json")
	var journal := _path("_claim.transaction")
	CommunicationsMailService.fragment_path_override = store_path
	CommunicationsMailService.journal_path_override = journal
	CommunicationsMailService.save_slots_override = [{"id": "default", "name": "test", "valid": true}]
	var mailbox := CommunicationsMailService.load_mailbox(mail_path)
	var store := FragmentStore.new()
	var base := {"version": 1, "mailbox_path": mail_path, "store_path": store_path, "mailbox": mailbox, "store": store.to_dict()}
	for kind in ["store", "mailbox", "future", "fractional", "path", "receipt"]:
		SaveFile.write_json(mail_path, mailbox)
		SaveFile.write_json(store_path, store.to_dict())
		var old_mail := FileAccess.get_file_as_string(mail_path)
		var old_store := FileAccess.get_file_as_string(store_path)
		var image := base.duplicate(true)
		match kind:
			"store": image.store.modules = [{"bad": "module"}]
			"mailbox": image.mailbox.mails[0].attachments = "broken"
			"future": image.store.version = 2
			"fractional": image.version = 1.5
			"path": image.store_path = mail_path
			"receipt": image.mailbox.claim_ledger["mail_fragment_supply_001:fragment_small_10"] = {"mail_id": "mail_fragment_supply_001", "attachment_id": "fragment_small_10", "target_slot_id": "default", "instance_ids": ["missing-module"], "claimed_at": 1}
		SaveFile.write_json(journal, image)
		_check(not CommunicationsMailService.recover_transaction(mail_path), "reject entire invalid mail transaction before replay: " + kind)
		_check(FileAccess.get_file_as_string(mail_path) == old_mail and FileAccess.get_file_as_string(store_path) == old_store, "invalid mail journal preserves both original files: " + kind)
		_check(FileAccess.file_exists(journal), "invalid mail journal remains available for recovery: " + kind)
		if FileAccess.file_exists(journal): DirAccess.remove_absolute(journal)
	# A real partial transaction must still finish after restart, without re-rolling.
	SaveFile.write_json(mail_path, mailbox)
	SaveFile.write_json(store_path, store.to_dict())
	var rng := RandomNumberGenerator.new()
	rng.seed = 941
	var generated: Array[Dictionary] = [FragmentCatalog.create_small(rng)]
	store.add_modules(generated)
	base.store = store.to_dict()
	SaveFile.write_json(journal, base)
	_check(CommunicationsMailService.recover_transaction(mail_path) and not FileAccess.file_exists(journal), "valid interrupted mail transaction completes")
	var reloaded := FragmentStore.load_store(store_path)
	_check(reloaded != null and reloaded.modules.size() == 1 and str(reloaded.modules[0].instance_id) == str(generated[0].instance_id), "recovery preserves generated module identity")
	_check(CommunicationsMailService.recover_transaction(mail_path) and FragmentStore.load_store(store_path).modules.size() == 1, "completed replay is idempotent")
	# Force failure after the store write and journal creation, then retry from disk.
	var late_dir := prefix + "_late"
	var late_path := late_dir + "/mail.json"
	paths.append(late_path)
	var stale := mailbox.duplicate(true)
	var memory_before := JSON.stringify(mailbox)
	var partial := CommunicationsMailService.claim_attachment(mailbox, "mail_fragment_supply_001", "fragment_small_10", "default", [], late_path, 513)
	_check(not partial.ok and FileAccess.file_exists(journal), "mailbox write failure retains the real claim journal")
	_check(JSON.stringify(mailbox) == memory_before, "a failed transaction does not mark live attachments claimed prematurely")
	var interrupted := FragmentStore.load_store(store_path).to_dict()
	_check(interrupted.modules.size() == 11, "partial claim has durably written the module image once")
	_check(not CommunicationsMailService.recover_transaction(mail_path) and FileAccess.file_exists(journal), "another mailbox cannot consume the interrupted claim")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(late_dir))
	var retry := CommunicationsMailService.claim_attachment(stale, "mail_fragment_supply_001", "fragment_small_10", "default", [], late_path, 614)
	_check(not retry.ok, "retrying the same stale in-memory mail first recovers its receipt instead of paying twice")
	var recovered := CommunicationsMailService.load_mailbox(late_path)
	_check(not recovered.is_empty() and recovered.claim_ledger.size() == 1 and not FileAccess.file_exists(journal), "actual pending claim completes on the correct mailbox after restart")
	_check(JSON.stringify(FragmentStore.load_store(store_path).to_dict()) == JSON.stringify(interrupted), "actual claim recovery keeps module IDs and revision without generating duplicates")
	_check(not CommunicationsMailService.claim_attachment(recovered, "mail_fragment_supply_001", "fragment_small_10", "default", [], late_path, 721).ok, "recovered receipt blocks another claim")
	DirAccess.remove_absolute(late_path)
	DirAccess.remove_absolute(late_dir)
	CommunicationsMailService.fragment_path_override = ""
	CommunicationsMailService.journal_path_override = ""
	CommunicationsMailService.save_slots_override = []
