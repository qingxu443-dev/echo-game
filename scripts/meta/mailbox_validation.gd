class_name MailboxValidation
extends RefCounted

const VERSION := 1
const ACCOUNT_ID := "local-player"


static func valid(data: Dictionary) -> bool:
	if not whole(data.get("version")) or data.version != VERSION or data.get("account_id") != ACCOUNT_ID: return false
	if not data.get("mails") is Array or not data.get("claim_ledger", {}) is Dictionary: return false
	if not _ids(data.get("announced_ids", [])): return false
	var mails := {}
	for mail in data.mails:
		if not mail is Dictionary or not _text(mail.get("id")) or mails.has(mail.id): return false
		mails[mail.id] = true
		for field in ["title", "sender", "type", "body"]:
			if not mail.get(field, "") is String: return false
		for field in ["received_at", "expires_at"]:
			if not whole(mail.get(field, 0)): return false
		for field in ["important", "pinned", "locked", "read", "archived", "local_test_mail"]:
			if not mail.get(field, false) is bool: return false
		if not mail.get("attachments", []) is Array: return false
		var attachments := {}
		for item in mail.get("attachments", []):
			if not item is Dictionary or not _text(item.get("id")) or attachments.has(item.id): return false
			attachments[item.id] = true
			if item.get("kind") not in ["small", "medium", "ordinary_large", "fixed_large"]: return false
			if not item.get("name", "") is String or not whole(item.get("quantity")) or item.quantity <= 0: return false
			if item.kind == "fixed_large" and item.quantity != 10: return false
			if not item.get("claimed", false) is bool or not whole(item.get("claimed_at", 0)): return false
			if not item.get("target_slot_id", "") is String or not _ids(item.get("instance_ids", [])): return false
	for key in data.get("claim_ledger", {}):
		var row: Variant = data.claim_ledger[key]
		if not _text(key) or not row is Dictionary: return false
		for field in ["mail_id", "attachment_id", "target_slot_id"]:
			if not _text(row.get(field)): return false
		if key != str(row.mail_id) + ":" + str(row.attachment_id): return false
		if not whole(row.get("claimed_at")) or not _ids(row.get("instance_ids")): return false
	return true


static func whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value < 9.223372036854775e18 and float(value) == floorf(float(value))


static func _text(value: Variant) -> bool:
	return value is String and not value.is_empty()


static func _ids(values: Variant) -> bool:
	if not values is Array: return false
	var seen := {}
	for value in values:
		if not _text(value) or seen.has(value): return false
		seen[value] = true
	return true
