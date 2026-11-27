class_name BattleSkillInput
extends RefCounted

## Selection is free; only a confirmed legal target executes and pays AP.
static func select(view, index: int) -> void:
	if index < 0 or index >= view.skill_bar.size() or view.controller.phase != BattleController.BattlePhase.PLAYER:
		return
	var skill: Dictionary = view.skill_bar[index]
	if not SkillBarView.is_affordable(view.controller, skill):
		view.selected_skill = -1
		view.status_message = "无法施放「%s」：检查行动点与终极能量。" % skill["name"]
		view.queue_redraw()
		return
	if skill["mode"] == "self":
		view.selected_skill = -1
		cast(view, skill)
		return
	if view.selected_skill == index:
		view._cancel_target_selection()
		return
	view.selected_skill = index
	var target := "地格（可选空地）" if skill["mode"] == "cell" else ("自己或友军" if skill["mode"] == "ally" else "目标敌人")
	view.status_message = "已选择「%s」，点击%s确认后消耗 %d AP；右键取消。" % [skill["name"], target, skill["cost"]]
	view.queue_redraw()


static func cast(view, skill: Dictionary, actor_id: String = "", cell: Vector2i = Vector2i(-1, -1)) -> void:
	var before: int = view.controller.ap.current
	if view.controller.request_skill(StringName(str(skill["id"])), actor_id, cell):
		view.selected_skill = -1
		var cost: int = int(skill["cost"])
		var returned: int = maxi(0, view.controller.ap.current - before + cost)
		view.status_message = "「%s」已生效，消耗 %d AP%s；剩余 %d/%d AP。" % [
			skill["name"], cost, "，击杀返还 %d AP" % returned if returned > 0 else "",
			view.controller.ap.current, view.controller.ap.maximum]
	else:
		view.status_message = "「%s」未能施放：检查行动点、射程、视线与资源；未消耗 AP。" % skill["name"]
	view.queue_redraw()
