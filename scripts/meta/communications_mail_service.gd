class_name CommunicationsMailService
extends RefCounted

const SAVE_PATH := "user://communications_mailbox.json"
const JOURNAL_PATH := "user://communications_claim.transaction"
const VERSION := 1
const LOCAL_ACCOUNT_ID := "local-player"
const DEFAULT_SLOT_ID := "default"
const FragmentCatalogScript = preload("res://scripts/fragments/fragment_catalog.gd")
const FragmentStoreScript = preload("res://scripts/fragments/fragment_store.gd")
const SaveFileScript = preload("res://scripts/persistence/save_file.gd")
const AtelierStashScript = preload("res://scripts/meta/atelier_stash.gd")
const SpringSaveTransactionScript = preload("res://scripts/persistence/spring_save_transaction.gd")
static var fragment_path_override: String = ""
static var journal_path_override: String = ""
static var save_slots_override: Array[Dictionary] = []


static func journal_path() -> String:
	return journal_path_override if not journal_path_override.is_empty() else JOURNAL_PATH


static func fragment_path_for_slot(slot_id: String) -> String:
	var safe_id := slot_id.strip_edges().to_lower()
	if safe_id.is_empty():
		return ""
	for character in safe_id:
		if not (character in "abcdefghijklmnopqrstuvwxyz0123456789_-"):
			return ""
	if safe_id == DEFAULT_SLOT_ID:
		return fragment_path_override if not fragment_path_override.is_empty() else FragmentStoreScript.SAVE_PATH
	return "user://save_slots/%s/fragments.json" % safe_id


static func available_save_slots() -> Array[Dictionary]:
	if not save_slots_override.is_empty():
		var override_slots: Array[Dictionary] = []
		for slot in save_slots_override:
			override_slots.append(slot.duplicate(true))
		return override_slots
	# The current build has one profile slot. A missing or corrupt AtelierStash
	# is not treated as a valid destination; claiming rewards must not create a
	# replacement save or silently redirect them.
	var valid := FileAccess.file_exists(AtelierStashScript.SAVE_PATH)
	valid = valid and not SpringSaveTransactionScript.is_pending(AtelierStashScript.SAVE_PATH)
	if valid:
		valid = not AtelierStashScript.read_state(AtelierStashScript.SAVE_PATH).is_empty()
	return [{"id": DEFAULT_SLOT_ID, "name": "当前存档", "valid": valid}]


static func _default_mailbox() -> Dictionary:
	return {
		"version": VERSION,
		"account_id": LOCAL_ACCOUNT_ID,
		"mails": [{
			"id": "mail_fragment_supply_001",
			"title": "残片补给计划",
			"sender": "ECHO 指挥部",
			"type": "reward",
			"received_at": int(Time.get_unix_time_from_system()),
			"expires_at": 0,
			"important": true,
			"pinned": true,
			"locked": false,
			"read": false,
			"archived": false,
			"local_test_mail": true,
			"body": "指挥官：\n\n为协助你熟悉残片构筑，指挥部准备了一批模块补给。请在通讯终端中领取，并前往残片中心配置。\n\n本邮件为本地测试邮件，不代表正式在线服务器发信。奖励永久有效，可随时领取。",
			"attachments": [
				{"id": "fragment_small_10", "kind": "small", "name": "小型模块补给", "quantity": 10, "claimed": false, "claimed_at": 0, "target_slot_id": "", "instance_ids": []},
				{"id": "fragment_medium_10", "kind": "medium", "name": "中型模块补给", "quantity": 10, "claimed": false, "claimed_at": 0, "target_slot_id": "", "instance_ids": []},
				{"id": "fragment_large_10", "kind": "ordinary_large", "name": "大型模块补给", "quantity": 10, "claimed": false, "claimed_at": 0, "target_slot_id": "", "instance_ids": []},
				{"id": "fragment_fixed_large_10", "kind": "fixed_large", "name": "指定主词条大型模块补给", "quantity": 10, "claimed": false, "claimed_at": 0, "target_slot_id": "", "instance_ids": []}
			]
		}],
		"announced_ids": [],
		"claim_ledger": {}
	}


static func _ensure_directory(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var directory := absolute.get_base_dir()
	return DirAccess.make_dir_recursive_absolute(directory) == OK or DirAccess.dir_exists_absolute(directory)


static func recover_transaction() -> bool:
	if not FileAccess.file_exists(journal_path()):
		return true
	var file := FileAccess.open(journal_path(), FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1:
		return false
	var mailbox_path := str(parsed.get("mailbox_path", ""))
	var store_path := str(parsed.get("store_path", ""))
	var mailbox_data: Variant = parsed.get("mailbox", null)
	var store_data: Variant = parsed.get("store", null)
	if mailbox_path.is_empty() or store_path.is_empty() or not mailbox_data is Dictionary or not store_data is Dictionary:
		return false
	if not _ensure_directory(store_path):
		return false
	if not SaveFileScript.write_json(store_path, store_data):
		return false
	if not SaveFileScript.write_json(mailbox_path, mailbox_data):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(journal_path())) == OK


static func load_mailbox(path: String = SAVE_PATH) -> Dictionary:
	if not recover_transaction():
		return {}
	if not FileAccess.file_exists(path):
		var seeded := _default_mailbox()
		if path != SAVE_PATH or DisplayServer.get_name() != "headless":
			if not SaveFileScript.write_json(path, seeded):
				return {}
		return seeded
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or int(parsed.get("version", 0)) != VERSION:
		return {}
	if str(parsed.get("account_id", "")) != LOCAL_ACCOUNT_ID or not parsed.get("mails", []) is Array:
		return {}
	if not parsed.get("claim_ledger", {}) is Dictionary:
		return {}
	if not parsed.has("claim_ledger"):
		parsed["claim_ledger"] = {}
	# Existing local saves keep their seeded mail body. Migrate the retired
	# class salutation so returning players do not continue seeing the old role.
	var migrated_mail := false
	for mail in parsed["mails"]:
		if not mail is Dictionary or str(mail.get("id", "")) != "mail_fragment_supply_001":
			continue
		var body := str(mail.get("body", ""))
		if body.begins_with("守誓者："):
			mail["body"] = body.replace("守誓者：", "指挥官：")
			migrated_mail = true
	if migrated_mail and (path != SAVE_PATH or DisplayServer.get_name() != "headless"):
		SaveFileScript.write_json(path, parsed)
	return parsed


static func save_mailbox(mailbox: Dictionary, path: String = SAVE_PATH) -> bool:
	if path == SAVE_PATH and DisplayServer.get_name() == "headless":
		return true
	if not mailbox.get("mails", []) is Array or not mailbox.get("claim_ledger", {}) is Dictionary or str(mailbox.get("account_id", "")) != LOCAL_ACCOUNT_ID:
		return false
	return SaveFileScript.write_json(path, mailbox)


static func all_mails(mailbox: Dictionary, category: String = "inbox") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mail in mailbox.get("mails", []):
		if not mail is Dictionary:
			continue
		var archived := bool(mail.get("archived", false))
		var kind := str(mail.get("type", "normal"))
		var include := false
		match category:
			"inbox":
				include = not archived
			"announcements":
				include = not archived and kind in ["announcement", "announcement_reward"]
			"rewards":
				include = not archived and kind in ["reward", "announcement_reward"]
			"archive":
				include = archived
		if include:
			result.append(mail.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_pinned := bool(a.get("pinned", false))
		var b_pinned := bool(b.get("pinned", false))
		if a_pinned != b_pinned:
			return a_pinned
		return int(a.get("received_at", 0)) > int(b.get("received_at", 0))
	)
	return result


static func unread_count(mailbox: Dictionary) -> int:
	var count := 0
	for mail in mailbox.get("mails", []):
		if not bool(mail.get("read", false)):
			count += 1
	return count


static func pending_attachment_count(mailbox: Dictionary) -> int:
	var count := 0
	for mail in mailbox.get("mails", []):
		for attachment in mail.get("attachments", []):
			if not bool(attachment.get("claimed", false)) and _is_attachment_live(mail, attachment):
				count += 1
	return count


static func _is_attachment_live(mail: Dictionary, attachment: Dictionary) -> bool:
	var expiry := int(mail.get("expires_at", 0))
	return expiry <= 0 or int(Time.get_unix_time_from_system()) <= expiry


static func mark_read(mailbox: Dictionary, mail_id: String, path: String = SAVE_PATH) -> bool:
	for mail in mailbox.get("mails", []):
		if str(mail.get("id", "")) == mail_id:
			mail["read"] = true
			return save_mailbox(mailbox, path)
	return false


static func archive_mail(mailbox: Dictionary, mail_id: String, path: String = SAVE_PATH) -> bool:
	for mail in mailbox.get("mails", []):
		if str(mail.get("id", "")) == mail_id:
			mail["archived"] = true
			return save_mailbox(mailbox, path)
	return false


static func delete_mail(mailbox: Dictionary, mail_id: String, path: String = SAVE_PATH) -> Dictionary:
	for index in range(mailbox.get("mails", []).size()):
		var mail: Dictionary = mailbox.mails[index]
		if str(mail.get("id", "")) != mail_id:
			continue
		for attachment in mail.get("attachments", []):
			if not bool(attachment.get("claimed", false)) and _is_attachment_live(mail, attachment):
				return {"ok": false, "message": "邮件仍有未领取奖励，不能删除。"}
		mailbox.mails.remove_at(index)
		return {"ok": save_mailbox(mailbox, path), "message": "邮件已删除。"}
	return {"ok": false, "message": "找不到该邮件。"}


static func _generate_attachment(attachment: Dictionary, rng: RandomNumberGenerator, ordinary_main_stats: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var quantity := int(attachment.get("quantity", 0))
	match str(attachment.get("kind", "")):
		"small":
			for _i in range(quantity):
				result.append(FragmentCatalogScript.create_small(rng))
		"medium":
			for _i in range(quantity):
				result.append(FragmentCatalogScript.create_medium(rng))
		"ordinary_large":
			if ordinary_main_stats.size() != quantity:
				return []
			for main_stat in ordinary_main_stats:
				if not FragmentCatalogScript.STAT_KEYS.has(main_stat):
					return []
				result.append(FragmentCatalogScript.create_large(main_stat, rng))
		"fixed_large":
			if quantity != 10:
				return []
			result.append_array(FragmentCatalogScript.create_fixed_large_bundle(rng))
	return result


static func claim_attachment(mailbox: Dictionary, mail_id: String, attachment_id: String, target_slot_id: String = DEFAULT_SLOT_ID, ordinary_main_stats: Array[String] = [], path: String = SAVE_PATH, seed_override: int = -1) -> Dictionary:
	if not recover_transaction():
		return {"ok": false, "message": "上一次奖励交易尚未恢复，请稍后重试。"}
	var claim_key := "%s:%s" % [mail_id, attachment_id]
	var claim_ledger: Dictionary = mailbox.get("claim_ledger", {})
	if claim_ledger.has(claim_key):
		return {"ok": false, "message": "该邮件附件已有领取记录，不能重复发放。"}
	var slots := available_save_slots()
	var slot_valid := false
	for slot in slots:
		if str(slot.id) == target_slot_id and bool(slot.valid):
			slot_valid = true
			break
	if not slot_valid:
		return {"ok": false, "message": "目标存档不可用，奖励没有领取。"}
	var mail_index := -1
	var attachment_index := -1
	for mi in range(mailbox.get("mails", []).size()):
		var mail: Dictionary = mailbox.mails[mi]
		if str(mail.get("id", "")) != mail_id:
			continue
		mail_index = mi
		for ai in range(mail.get("attachments", []).size()):
			if str(mail.attachments[ai].get("id", "")) == attachment_id:
				attachment_index = ai
				break
		break
	if mail_index < 0 or attachment_index < 0:
		return {"ok": false, "message": "找不到邮件附件。"}
	var mail: Dictionary = mailbox.mails[mail_index]
	var attachment: Dictionary = mail.attachments[attachment_index]
	if bool(attachment.get("claimed", false)):
		return {"ok": false, "message": "这份附件已经领取，不能重复发放。"}
	if not _is_attachment_live(mail, attachment):
		return {"ok": false, "message": "奖励已过期，无法领取。"}
	if str(attachment.get("kind", "")) == "ordinary_large":
		if ordinary_main_stats.size() != int(attachment.get("quantity", 0)):
			return {"ok": false, "message": "请为每件普通大型模块分别选择主词条。"}
		for main_stat in ordinary_main_stats:
			if not FragmentCatalogScript.STAT_KEYS.has(main_stat):
				return {"ok": false, "message": "普通大型模块的主词条选择不完整。"}
	var store_path := fragment_path_for_slot(target_slot_id)
	if store_path.is_empty() or not _ensure_directory(store_path):
		return {"ok": false, "message": "目标存档目录不可用。"}
	var store = FragmentStoreScript.load_store(store_path)
	if store == null:
		return {"ok": false, "message": "残片存档损坏，奖励没有领取。"}
	var rng := RandomNumberGenerator.new()
	if seed_override >= 0:
		rng.seed = seed_override
	else:
		rng.randomize()
	var generated := _generate_attachment(attachment, rng, ordinary_main_stats)
	if generated.size() != int(attachment.get("quantity", 0)) or not store.add_modules(generated):
		return {"ok": false, "message": "模块生成或库存校验失败，奖励没有领取。"}
	var ids: Array[String] = []
	for module in generated:
		ids.append(str(module.instance_id))
	var claimed_at := int(Time.get_unix_time_from_system())
	attachment["claimed"] = true
	attachment["claimed_at"] = claimed_at
	attachment["target_slot_id"] = target_slot_id
	attachment["instance_ids"] = ids
	mail["read"] = true
	var next_mailbox := mailbox.duplicate(true)
	next_mailbox.mails[mail_index] = mail
	var next_ledger: Dictionary = next_mailbox.get("claim_ledger", {}).duplicate(true)
	next_ledger[claim_key] = {"mail_id": mail_id, "attachment_id": attachment_id, "target_slot_id": target_slot_id, "instance_ids": ids.duplicate(), "claimed_at": claimed_at}
	next_mailbox["claim_ledger"] = next_ledger
	var next_store := store.to_dict()
	next_store["revision"] = int(next_store.get("revision", 0)) + 1
	var journal := {
		"version": 1,
		"mailbox_path": path,
		"store_path": store_path,
		"mailbox": next_mailbox,
		"store": next_store,
	}
	if not SaveFileScript.write_json(journal_path(), journal):
		return {"ok": false, "message": "奖励交易记录写入失败，未发放奖励。"}
	if not recover_transaction():
		return {"ok": false, "message": "奖励正在等待安全恢复，请勿重复操作。"}
	mailbox.clear()
	mailbox.merge(next_mailbox, true)
	return {"ok": true, "message": "已领取 %s ×%d。" % [str(attachment.get("name", "奖励")), generated.size()], "instance_ids": ids, "slot_id": target_slot_id}


static func consume_new_mail_notice(mailbox: Dictionary, path: String = SAVE_PATH) -> Dictionary:
	var announced: Array = mailbox.get("announced_ids", [])
	var fresh: Array[Dictionary] = []
	for mail in mailbox.get("mails", []):
		var mail_id := str(mail.get("id", ""))
		if mail_id.is_empty() or announced.has(mail_id):
			continue
		fresh.append(mail)
		announced.append(mail_id)
	var pending := 0
	for mail in fresh:
		for attachment in mail.get("attachments", []):
			if not bool(attachment.get("claimed", false)) and _is_attachment_live(mail, attachment):
				pending += 1
	mailbox["announced_ids"] = announced
	if not fresh.is_empty():
		save_mailbox(mailbox, path)
	return {"count": fresh.size(), "pending": pending}


static func claim_all(mailbox: Dictionary, mail_id: String, target_slot_id: String = DEFAULT_SLOT_ID, ordinary_main_stats: Array[String] = [], path: String = SAVE_PATH, seed_base: int = -1) -> Dictionary:
	var pending: Array[String] = []
	for mail in mailbox.get("mails", []):
		if str(mail.get("id", "")) != mail_id:
			continue
		for attachment in mail.get("attachments", []):
			if not bool(attachment.get("claimed", false)):
				pending.append(str(attachment.get("id", "")))
	var results: Array[Dictionary] = []
	var succeeded := 0
	for index in range(pending.size()):
		var seed := -1 if seed_base < 0 else seed_base + index
		var result := claim_attachment(mailbox, mail_id, pending[index], target_slot_id, ordinary_main_stats, path, seed)
		results.append(result)
		if bool(result.get("ok", false)):
			succeeded += 1
	return {"ok": succeeded == pending.size(), "succeeded": succeeded, "total": pending.size(), "results": results}
