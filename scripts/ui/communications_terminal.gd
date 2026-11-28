extends Control

const MailServiceScript = preload("res://scripts/meta/communications_mail_service.gd")
const FragmentCatalogScript = preload("res://scripts/fragments/fragment_catalog.gd")
const LOBBY_SCENE := "res://scenes/lobby/lobby.tscn"

var mailbox: Dictionary = {}
var category := "inbox"
var reward_filter := "all"
var selected_mail_id := ""
var pending_attachment_id := ""
var main_picker_open := false
var pending_main_stats: Array[String] = []
var main_picker_index := 0
var main_picker_complete := false
var notice := ""
var mouse_position := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mailbox = MailServiceScript.load_mailbox()
	var mails := _mails()
	if not mails.is_empty():
		selected_mail_id = str(mails[0].get("id", ""))
		_open_selected_mail()
	queue_redraw()


func _sx() -> float:
	return maxf(1.0, size.x) / 1280.0


func _sy() -> float:
	return maxf(1.0, size.y) / 720.0


func _rect(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(x * _sx(), y * _sy(), w * _sx(), h * _sy())


func _back_rect() -> Rect2:
	return _rect(28, 24, 112, 42)


func _tab_rect(index: int) -> Rect2:
	return _rect(48 + index * 152, 106, 140, 42)


func _mail_rect(index: int) -> Rect2:
	var start_y := 198 if category == "rewards" else 170
	var row_height := 72 if category == "rewards" else 78
	return _rect(48, start_y + index * row_height, 420, 68)


func _reward_filter_rect(index: int) -> Rect2:
	return _rect(48 + index * 100, 162, 92, 28)


func _attachment_rect(index: int) -> Rect2:
	return _rect(550, 365 + index * 66, 660, 56)


func _claim_rect(index: int) -> Rect2:
	return _rect(1085, 365 + index * 66, 112, 56)


func _main_option_rect(index: int) -> Rect2:
	return _rect(310 + (index % 4) * 170, 290 + int(index / 4) * 62, 150, 48)


func _main_previous_rect() -> Rect2:
	return _rect(310, 465, 130, 42)


func _main_confirm_rect() -> Rect2:
	return _rect(770, 465, 160, 42)


func _main_cancel_rect() -> Rect2:
	return _rect(950, 465, 120, 42)


func _claim_all_rect() -> Rect2:
	return _rect(1010, 625, 190, 52)


func _mails() -> Array[Dictionary]:
	var result := MailServiceScript.all_mails(mailbox, category)
	if category != "rewards" or reward_filter == "all":
		return result
	var filtered: Array[Dictionary] = []
	var now := int(Time.get_unix_time_from_system())
	for mail in result:
		var attachments: Array = mail.get("attachments", [])
		var pending := false
		var claimed := not attachments.is_empty()
		for attachment in attachments:
			if not bool(attachment.get("claimed", false)):
				pending = true
				claimed = false
		var expiry := int(mail.get("expires_at", 0))
		var has_live_pending := pending and (expiry <= 0 or expiry > now)
		match reward_filter:
			"pending":
				if has_live_pending: filtered.append(mail)
			"claimed":
				if claimed: filtered.append(mail)
			"expiring":
				if expiry > now and expiry - now <= 259200: filtered.append(mail)
	return filtered


func _selected_mail() -> Dictionary:
	for mail in mailbox.get("mails", []):
		if str(mail.get("id", "")) == selected_mail_id:
			return mail
	return {}


func _open_selected_mail() -> void:
	if selected_mail_id.is_empty():
		return
	MailServiceScript.mark_read(mailbox, selected_mail_id)
	mailbox = MailServiceScript.load_mailbox()
	notice = ""


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var sx := _sx()
	var sy := _sy()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#11151b"), true)
	draw_rect(_rect(0, 0, 1280, 86), Color(0.07, 0.09, 0.12, 0.98), true)
	draw_line(Vector2(0, 86 * sy), Vector2(size.x, 86 * sy), Color("#b89b67", 0.55), 1.5)
	_draw_button(font, _back_rect(), "← 返回")
	draw_string(font, Vector2(172 * sx, 53 * sy), "通讯终端", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(26 * sy), Color("#f0e5cf"))
	draw_string(font, Vector2(900 * sx, 48 * sy), "未读 %d   ·   待领取 %d" % [MailServiceScript.unread_count(mailbox), MailServiceScript.pending_attachment_count(mailbox)], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(13 * sy), Color("#c4b28c"))
	var tabs := [
		{"id": "inbox", "name": "收件箱"},
		{"id": "announcements", "name": "公告"},
		{"id": "rewards", "name": "奖励"},
		{"id": "archive", "name": "归档"},
	]
	for index in range(tabs.size()):
		_draw_button(font, _tab_rect(index), str(tabs[index].name), category == str(tabs[index].id))
	if category == "rewards":
		var filter_ids := ["all", "pending", "claimed", "expiring"]
		var filter_names := ["全部", "待领取", "已领取", "即将过期"]
		for index in range(filter_ids.size()):
			_draw_button(font, _reward_filter_rect(index), filter_names[index], reward_filter == filter_ids[index])
	_draw_mail_list(font)
	_draw_mail_detail(font)
	if main_picker_open:
		_draw_main_picker(font)
	if not notice.is_empty():
		var nr := _rect(500, 680, 720, 28)
		draw_rect(nr, Color(0.30, 0.18, 0.12, 0.92), true)
		draw_rect(nr, Color("#d6a56e"), false, 1.0)
		draw_string(font, nr.position + Vector2(12 * sx, 19 * sy), notice, HORIZONTAL_ALIGNMENT_LEFT, nr.size.x - 24 * sx, roundi(11 * sy), Color("#f4dfc5"))


func _draw_button(font: Font, rect: Rect2, label: String, active: bool = false) -> void:
	var sx := _sx()
	var sy := _sy()
	draw_rect(rect, Color("#2b3038") if active else Color("#1b222b"), true)
	draw_rect(rect, Color("#d8bd83") if active else Color("#6d7884"), false, 1.3)
	draw_string(font, rect.position + Vector2(10 * sx, rect.size.y * 0.62), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 20 * sx, roundi(13 * sy), Color("#f2e8d5"))


func _draw_mail_list(font: Font) -> void:
	var sx := _sx()
	var sy := _sy()
	var panel := _rect(36, 158, 445, 510)
	draw_rect(panel, Color("#171e26"), true)
	draw_rect(panel, Color("#647582"), false, 1.0)
	var mails := _mails()
	for index in range(mini(6, mails.size())):
		var mail: Dictionary = mails[index]
		var rect := _mail_rect(index)
		var active := str(mail.get("id", "")) == selected_mail_id
		draw_rect(rect, Color("#293641") if active else Color("#1d252e"), true)
		draw_rect(rect, Color("#c6a66b") if active else Color("#53616d"), false, 1.2)
		var unread := not bool(mail.get("read", false))
		var marker := Color("#e6c27b") if unread else Color("#7b8791")
		draw_circle(rect.position + Vector2(16 * sx, 18 * sy), 4 * sy, marker)
		draw_string(font, rect.position + Vector2(30 * sx, 24 * sy), str(mail.get("title", "无标题")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 46 * sx, roundi(15 * sy), Color("#f0e5d2"))
		var status := "永久有效" if int(mail.get("expires_at", 0)) == 0 else "限时邮件"
		var pending := 0
		for attachment in mail.get("attachments", []):
			if not bool(attachment.get("claimed", false)):
				pending += 1
		var tail := "%s  ·  %s  ·  待领取 %d" % [str(mail.get("sender", "")), status, pending]
		draw_string(font, rect.position + Vector2(30 * sx, 48 * sy), tail, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 46 * sx, roundi(10 * sy), Color("#9eacb8"))
	if mails.is_empty():
		draw_string(font, Vector2(72 * sx, 220 * sy), "这里暂时没有邮件。", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(16 * sy), Color("#9eacb8"))


func _draw_mail_detail(font: Font) -> void:
	var sx := _sx()
	var sy := _sy()
	var panel := _rect(500, 158, 740, 510)
	draw_rect(panel, Color("#171e26"), true)
	draw_rect(panel, Color("#647582"), false, 1.0)
	var mail := _selected_mail()
	if mail.is_empty():
		draw_string(font, Vector2(540 * sx, 220 * sy), "选择一封邮件查看详情。", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(16 * sy), Color("#9eacb8"))
		return
	draw_string(font, Vector2(540 * sx, 200 * sy), str(mail.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, 650 * sx, roundi(24 * sy), Color("#f2e6d1"))
	draw_string(font, Vector2(540 * sx, 230 * sy), "发件人：%s   ·   永久有效" % str(mail.get("sender", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12 * sy), Color("#b9a67f"))
	var lines := str(mail.get("body", "")).split("\n")
	for index in range(mini(4, lines.size())):
		draw_string(font, Vector2(540 * sx, (270 + index * 22) * sy), str(lines[index]), HORIZONTAL_ALIGNMENT_LEFT, 650 * sx, roundi(12 * sy), Color("#d7d9d8"))
	var attachments: Array = mail.get("attachments", [])
	if not attachments.is_empty():
		draw_string(font, Vector2(540 * sx, 350 * sy), "奖励附件", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(15 * sy), Color("#d8bd83"))
		for index in range(mini(4, attachments.size())):
			var attachment: Dictionary = attachments[index]
			var rect := _attachment_rect(index)
			draw_rect(rect, Color("#202a34"), true)
			draw_rect(rect, Color("#6d8291"), false, 1.0)
			var status := "已领取" if bool(attachment.get("claimed", false)) else "待领取"
			draw_string(font, rect.position + Vector2(14 * sx, 34 * sy), "%s  ×%d  ·  %s" % [str(attachment.get("name", "奖励")), int(attachment.get("quantity", 0)), status], HORIZONTAL_ALIGNMENT_LEFT, 510 * sx, roundi(13 * sy), Color("#e8e0d3"))
			_draw_button(font, _claim_rect(index), "已领取" if bool(attachment.get("claimed", false)) else "领取", bool(attachment.get("claimed", false)))
		_draw_button(font, _claim_all_rect(), "一键领取", false)
	_draw_button(font, _rect(540, 615, 130, 42), "归档邮件", false)
	_draw_button(font, _rect(690, 615, 130, 42), "删除邮件", false)
	if bool(mail.get("local_test_mail", false)):
		draw_string(font, Vector2(1040 * sx, 200 * sy), "本地测试邮件", HORIZONTAL_ALIGNMENT_LEFT, 160 * sx, roundi(10 * sy), Color("#7fa9b5"))


func _draw_main_picker(font: Font) -> void:
	var sx := _sx()
	var sy := _sy()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.82), true)
	var panel := _rect(245, 180, 790, 370)
	draw_rect(panel, Color("#1b242d"), true)
	draw_rect(panel, Color("#d3b67c"), false, 1.5)
	var title := "10 件普通大型模块的主词条已全部选择" if main_picker_complete else "选择第 %d / 10 件大型模块的主词条" % (main_picker_index + 1)
	draw_string(font, Vector2(290 * sx, 225 * sy), title, HORIZONTAL_ALIGNMENT_LEFT, 690 * sx, roundi(20 * sy), Color("#f0e5cf"))
	draw_string(font, Vector2(290 * sx, 252 * sy), "每件模块分别选择主词条；副词条仍从其余六种属性中独立随机。", HORIZONTAL_ALIGNMENT_LEFT, 690 * sx, roundi(11 * sy), Color("#aeb9c4"))
	for index in range(FragmentCatalogScript.STAT_KEYS.size()):
		var stat := FragmentCatalogScript.STAT_KEYS[index]
		var rect := _main_option_rect(index)
		var active := not main_picker_complete and pending_main_stats.size() > main_picker_index and pending_main_stats[main_picker_index] == stat
		_draw_button(font, rect, FragmentCatalogScript.stat_name(stat), active)
	var chosen_count := 0
	var counts := {}
	for stat in pending_main_stats:
		if not stat.is_empty():
			chosen_count += 1
			counts[stat] = int(counts.get(stat, 0)) + 1
	var summary_parts: Array[String] = []
	for stat in FragmentCatalogScript.STAT_KEYS:
		if int(counts.get(stat, 0)) > 0:
			summary_parts.append("%s×%d" % [FragmentCatalogScript.stat_name(stat), int(counts[stat])])
	var summary := "已选择 %d / 10 件：%s" % [chosen_count, "、".join(summary_parts)]
	draw_string(font, Vector2(290 * sx, 430 * sy), summary, HORIZONTAL_ALIGNMENT_LEFT, 700 * sx, roundi(10 * sy), Color("#d7c69e"))
	if main_picker_index > 0 or main_picker_complete:
		_draw_button(font, _main_previous_rect(), "上一步", false)
	if main_picker_complete:
		_draw_button(font, _main_confirm_rect(), "确认领取", true)
	_draw_button(font, _main_cancel_rect(), "取消", false)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_position = event.position
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_click(event.position)
		accept_event()


func _handle_click(position: Vector2) -> void:
	if main_picker_open:
		if _main_cancel_rect().has_point(position):
			main_picker_open = false
			pending_attachment_id = ""
			pending_main_stats.clear()
			main_picker_complete = false
			queue_redraw()
			return
		if _main_previous_rect().has_point(position) and (main_picker_index > 0 or main_picker_complete):
			if main_picker_complete:
				main_picker_complete = false
				main_picker_index = 9
			else:
				main_picker_index = maxi(0, main_picker_index - 1)
			queue_redraw()
			return
		if main_picker_complete and _main_confirm_rect().has_point(position):
			var chosen_stats := pending_main_stats.duplicate()
			main_picker_open = false
			if pending_attachment_id == "__all__":
				_claim_all(chosen_stats)
			else:
				_claim_one(pending_attachment_id, chosen_stats)
			pending_attachment_id = ""
			pending_main_stats.clear()
			main_picker_complete = false
			queue_redraw()
			return
		if not main_picker_complete:
			for index in range(FragmentCatalogScript.STAT_KEYS.size()):
				if _main_option_rect(index).has_point(position):
					pending_main_stats[main_picker_index] = FragmentCatalogScript.STAT_KEYS[index]
					if main_picker_index < 9:
						main_picker_index += 1
					else:
						main_picker_complete = true
					queue_redraw()
					return
		return
	if _back_rect().has_point(position):
		SceneTravel.change(get_tree(), LOBBY_SCENE)
		return
	if category == "rewards":
		var filter_ids := ["all", "pending", "claimed", "expiring"]
		for index in range(filter_ids.size()):
			if _reward_filter_rect(index).has_point(position):
				reward_filter = filter_ids[index]
				var filtered_mails := _mails()
				selected_mail_id = str(filtered_mails[0].get("id", "")) if not filtered_mails.is_empty() else ""
				_open_selected_mail()
				queue_redraw()
				return
	var categories := ["inbox", "announcements", "rewards", "archive"]
	for index in range(categories.size()):
		if _tab_rect(index).has_point(position):
			category = categories[index]
			var mails := _mails()
			selected_mail_id = str(mails[0].get("id", "")) if not mails.is_empty() else ""
			_open_selected_mail()
			queue_redraw()
			return
	var mails := _mails()
	for index in range(mini(6, mails.size())):
		if _mail_rect(index).has_point(position):
			selected_mail_id = str(mails[index].get("id", ""))
			_open_selected_mail()
			queue_redraw()
			return
	var mail := _selected_mail()
	var attachments: Array = mail.get("attachments", [])
	for index in range(mini(4, attachments.size())):
		if _claim_rect(index).has_point(position) and not bool(attachments[index].get("claimed", false)):
			var kind := str(attachments[index].get("kind", ""))
			var id := str(attachments[index].get("id", ""))
			if kind == "ordinary_large":
				pending_attachment_id = id
				pending_main_stats.clear()
				for _i in range(10):
					pending_main_stats.append("")
				main_picker_index = 0
				main_picker_complete = false
				main_picker_open = true
			else:
				_claim_one(id, [])
			queue_redraw()
			return
	if _claim_all_rect().has_point(position) and not attachments.is_empty():
		var needs_choice := false
		for attachment in attachments:
			if not bool(attachment.get("claimed", false)) and str(attachment.get("kind", "")) == "ordinary_large":
				needs_choice = true
				break
		if needs_choice:
			pending_attachment_id = "__all__"
			pending_main_stats.clear()
			for _i in range(10):
				pending_main_stats.append("")
			main_picker_index = 0
			main_picker_complete = false
			main_picker_open = true
		else:
			_claim_all([])
		queue_redraw()
		return
	if _rect(540, 615, 130, 42).has_point(position) and not mail.is_empty():
		if MailServiceScript.archive_mail(mailbox, selected_mail_id):
			mailbox = MailServiceScript.load_mailbox()
			category = "archive"
			notice = "邮件已归档。"
		queue_redraw()
		return
	if _rect(690, 615, 130, 42).has_point(position) and not mail.is_empty():
		var delete_result := MailServiceScript.delete_mail(mailbox, selected_mail_id)
		notice = str(delete_result.get("message", "删除失败。"))
		if bool(delete_result.get("ok", false)):
			mailbox = MailServiceScript.load_mailbox()
			var remaining := _mails()
			selected_mail_id = str(remaining[0].get("id", "")) if not remaining.is_empty() else ""
		queue_redraw()


func _claim_one(attachment_id: String, main_stats: Array[String]) -> void:
	var result := MailServiceScript.claim_attachment(mailbox, selected_mail_id, attachment_id, MailServiceScript.DEFAULT_SLOT_ID, main_stats)
	notice = str(result.get("message", "领取失败。"))
	mailbox = MailServiceScript.load_mailbox()


func _claim_all(main_stats: Array[String] = []) -> void:
	var result := MailServiceScript.claim_all(mailbox, selected_mail_id, MailServiceScript.DEFAULT_SLOT_ID, main_stats)
	notice = "成功领取 %d / %d 份附件。" % [int(result.get("succeeded", 0)), int(result.get("total", 0))]
	mailbox = MailServiceScript.load_mailbox()
