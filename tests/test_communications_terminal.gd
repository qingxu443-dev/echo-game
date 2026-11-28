extends "res://tests/framework/test_case.gd"

const MailService = preload("res://scripts/meta/communications_mail_service.gd")
const FragmentCatalogScript = preload("res://scripts/fragments/fragment_catalog.gd")
const FragmentStoreScript = preload("res://scripts/fragments/fragment_store.gd")


func _run() -> void:
	await _test_local_supply_mail_and_claims()
	_test_mail_terminal_scene()


func _test_local_supply_mail_and_claims() -> void:
	var mailbox_path := "user://communications_test_%d.json" % OS.get_process_id()
	var fragment_path := "user://communications_fragments_test_%d.json" % OS.get_process_id()
	var journal_path := "user://communications_journal_test_%d.json" % OS.get_process_id()
	MailService.fragment_path_override = fragment_path
	MailService.journal_path_override = journal_path
	MailService.save_slots_override = [{"id": MailService.DEFAULT_SLOT_ID, "name": "测试存档", "valid": true}]
	var mailbox := MailService.load_mailbox(mailbox_path)
	_check(mailbox.get("account_id", "") == MailService.LOCAL_ACCOUNT_ID, "the local mailbox is account-bound")
	var mails := MailService.all_mails(mailbox, "inbox")
	_check(mails.size() == 1 and mails[0].title == "残片补给计划", "the local test supply mail is seeded")
	var mail: Dictionary = mails[0]
	_check(int(mail.get("expires_at", -1)) == 0, "the supply mail has no expiry and can always be claimed")
	_check(bool(mail.get("local_test_mail", false)), "the local test mail is clearly distinguished from official server mail")
	var attachments: Array = mail.get("attachments", [])
	_check(attachments.size() == 4, "the mail has four independent module attachments")
	var total := 0
	for attachment in attachments:
		total += int(attachment.get("quantity", 0))
	_check(total == 40, "the mail contains exactly forty modules")
	_check(MailService.unread_count(mailbox) == 1 and MailService.pending_attachment_count(mailbox) == 4, "unread and pending-reward counters are separate")
	_check(not MailService.delete_mail(mailbox, str(mail.id), mailbox_path).ok, "an unclaimed reward mail cannot be deleted")
	_check(not MailService.claim_attachment(mailbox, str(mail.id), "fragment_small_10", "missing_slot", "", mailbox_path, 1).ok, "an invalid target save cannot receive rewards")

	var small := MailService.claim_attachment(mailbox, str(mail.id), "fragment_small_10", MailService.DEFAULT_SLOT_ID, [], mailbox_path, 111)
	_check(small.ok and small.instance_ids.size() == 10, "the ten small modules are generated and claimed")
	var duplicate := MailService.claim_attachment(mailbox, str(mail.id), "fragment_small_10", MailService.DEFAULT_SLOT_ID, [], mailbox_path, 222)
	_check(not duplicate.ok, "replaying a claimed attachment cannot generate a second reward")
	var medium := MailService.claim_attachment(mailbox, str(mail.id), "fragment_medium_10", MailService.DEFAULT_SLOT_ID, [], mailbox_path, 333)
	_check(medium.ok and medium.instance_ids.size() == 10, "the ten medium modules are generated and claimed")
	var missing_main := MailService.claim_attachment(mailbox, str(mail.id), "fragment_large_10", MailService.DEFAULT_SLOT_ID, [], mailbox_path, 444)
	_check(not missing_main.ok, "ordinary large modules require the player's main-stat choice")
	var ordinary_main_stats: Array[String] = ["attack", "health", "defense", "crit_rate", "crit_damage", "magic_resistance", "healing_efficiency", "attack", "health", "defense"]
	var ordinary := MailService.claim_attachment(mailbox, str(mail.id), "fragment_large_10", MailService.DEFAULT_SLOT_ID, ordinary_main_stats, mailbox_path, 555)
	_check(ordinary.ok and ordinary.instance_ids.size() == 10, "the ten ordinary large modules are generated after main-stat selection")
	var fixed := MailService.claim_attachment(mailbox, str(mail.id), "fragment_fixed_large_10", MailService.DEFAULT_SLOT_ID, [], mailbox_path, 666)
	_check(fixed.ok and fixed.instance_ids.size() == 10, "the ten fixed-main-stat large modules are generated")

	var store = FragmentStoreScript.load_store(fragment_path)
	_check(store != null and store.modules.size() == 40, "all forty modules are persisted in the selected save slot")
	var ids := {}
	var fixed_counts := {}
	var fixed_ids := {}
	for id in fixed.instance_ids:
		fixed_ids[str(id)] = true
	for module in store.modules:
		ids[str(module.instance_id)] = true
		_check(FragmentCatalogScript.validate_module(module), "every delivered module passes the catalog validator")
		if fixed_ids.has(str(module.instance_id)):
			fixed_counts[str(module.main_stat)] = int(fixed_counts.get(str(module.main_stat), 0)) + 1
	_check(ids.size() == 40, "every reward has an independent unique instance id")
	var ordinary_main_counts := {}
	for id in ordinary.instance_ids:
		var ordinary_module := store.module_by_id(str(id))
		ordinary_main_counts[str(ordinary_module.main_stat)] = int(ordinary_main_counts.get(str(ordinary_module.main_stat), 0)) + 1
	var ordinary_choices_match := true
	for index in range(ordinary.instance_ids.size()):
		var chosen_module := store.module_by_id(str(ordinary.instance_ids[index]))
		ordinary_choices_match = ordinary_choices_match and str(chosen_module.main_stat) == ordinary_main_stats[index]
	_check(ordinary_main_counts.size() == 7 and ordinary_choices_match, "ordinary large modules preserve each independently chosen main stat")
	var expected := {"attack": 2, "health": 2, "defense": 1, "crit_rate": 1, "crit_damage": 1, "magic_resistance": 1, "healing_efficiency": 2}
	var actual_fixed := {}
	for stat in expected:
		actual_fixed[stat] = int(fixed_counts.get(stat, 0))
	_check(actual_fixed == expected, "the fixed large-module attachment keeps the confirmed 2/2/1/1/1/1/2 distribution")
	_check(MailService.pending_attachment_count(mailbox) == 0, "all claimed attachments clear the pending-reward counter")
	_check(mailbox.get("claim_ledger", {}).size() == 4, "each attachment leaves an account-level claim ledger record")
	_check(MailService.claim_all(mailbox, str(mail.id), MailService.DEFAULT_SLOT_ID, [], mailbox_path, 900).total == 0, "one-click claiming cannot repeat previously delivered attachments")
	var persisted := MailService.load_mailbox(mailbox_path)
	_check(MailService.unread_count(persisted) == 0, "reading and claiming the mail persists its read state")
	_check(MailService.all_mails(persisted, "inbox").size() == 1, "the claimed mail remains in the inbox until archived")
	_check(MailService.archive_mail(persisted, str(mail.id), mailbox_path), "a claimed reward mail can be archived")
	_check(MailService.all_mails(MailService.load_mailbox(mailbox_path), "archive").size() == 1, "archiving keeps the mail in the archive")
	_check(MailService.delete_mail(persisted, str(mail.id), mailbox_path).ok, "a fully claimed reward mail can be deleted")
	_check(persisted.get("claim_ledger", {}).size() == 4, "deleting a mail does not delete its claim history")
	persisted.mails.append(mail.duplicate(true))
	_check(MailService.save_mailbox(persisted, mailbox_path), "re-seed a duplicate mail record for the idempotency test")
	var replay_after_delete := MailService.claim_attachment(persisted, str(mail.id), "fragment_small_10", MailService.DEFAULT_SLOT_ID, [], mailbox_path, 1234)
	_check(not replay_after_delete.ok, "a deleted-and-reintroduced mail cannot replay a previously claimed attachment")
	_check(FragmentStoreScript.load_store(fragment_path).modules.size() == 40, "replaying after deletion does not duplicate modules")
	DirAccess.remove_absolute(mailbox_path)
	DirAccess.remove_absolute(fragment_path)
	DirAccess.remove_absolute(journal_path)
	MailService.fragment_path_override = ""
	MailService.journal_path_override = ""
	MailService.save_slots_override = []


func _test_mail_terminal_scene() -> void:
	var scene_path := "res://scenes/lobby/communications_terminal.tscn"
	_check(ResourceLoader.exists(scene_path), "the communications terminal scene is registered")
	var packed: PackedScene = load(scene_path)
	_check(packed != null, "the communications terminal scene loads")
	if packed == null:
		return
	var terminal = packed.instantiate()
	root.add_child(terminal)
	terminal.size = Vector2(1280, 720)
	await process_frame
	_check(not terminal.mailbox.is_empty(), "the terminal loads the account mailbox")
	_check(terminal.selected_mail_id == "mail_fragment_supply_001", "the terminal selects the local supply mail")
	terminal.queue_free()
	await process_frame
