class_name BattleOverlayInput
extends RefCounted

const P = preload("res://scripts/ui/theme_palette.gd")
const TOGGLE_RECT := Rect2(24, 232, 284, 32)


static func select_movement(view) -> void:
	if view.controller.phase != BattleController.BattlePhase.PLAYER: return
	view.selected_skill = -1
	view.fx.move_actor_id = view.controller.active_character_id
	view.status_message = "已选中当前角色：绿区可移动，最多两格；通常消耗 1 AP。右键取消。"
	view.queue_redraw()


static func handle(view, position: Vector2) -> bool:
	if TOGGLE_RECT.has_point(position):
		view.fx.attack_tiles_visible = not view.fx.attack_tiles_visible
		view.status_message = "攻击地块预告已%s；敌人移动意图与伤害结算保持原样。" % ("显示" if view.fx.attack_tiles_visible else "隐藏")
		view.queue_redraw()
		return true
	if view.controller.phase != BattleController.BattlePhase.PLAYER: return false
	var current: int = view.controller.party_order.find(view.controller.active_character_id)
	if current >= 0 and PartyPortraitView.card_rect(current).has_point(position):
		select_movement(view)
		return true
	if view.selected_skill >= 0: return false
	var hero = view.controller.get_active_character()
	if hero == null or not hero.is_alive(): return false
	var foot: Vector2 = view.fx.actor_visual_pos.get(hero.actor_id, P.cell_center(hero.cell))
	var body := Rect2(foot + Vector2(-18, -P.STANDEE_HEIGHT + 7), Vector2(36, P.STANDEE_HEIGHT - 7))
	if P.cell_at(position) == hero.cell or body.has_point(position):
		select_movement(view)
		return true
	return false


static func draw_button(canvas: CanvasItem, visible: bool) -> void:
	canvas.draw_rect(TOGGLE_RECT, P.BUTTON_BG, true)
	canvas.draw_rect(TOGGLE_RECT, BoardOverlayRegion.ATTACK_LINE if visible else P.BUTTON_BORDER, false, 1.4)
	canvas.draw_string(ThemeDB.fallback_font, TOGGLE_RECT.position + Vector2(12, 21), "攻击地块：%s  ·  点击%s" % ["显示" if visible else "隐藏", "隐藏" if visible else "显示"], HORIZONTAL_ALIGNMENT_LEFT, TOGGLE_RECT.size.x - 24, 13, P.TEXT_FAINT)
