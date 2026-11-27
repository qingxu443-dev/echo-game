class_name SpringPlace
extends RefCounted

## One point on the 春之境 map (设计汇总 2026-11-26 §9).
##
## A place carries only what the map itself needs: where it sits and what kind
## of thing it is. Which battle, which event or which shop stock it holds is
## resolved by the run, because the same template must put the same things in the
## same cells on every run (「Boss坐标在对应模板中固定，不是每局开局随机」), while the
## identity of the random event is drawn per run.

enum Kind { BATTLE, ELITE, BOSS, EVENT, SHOP, HIDDEN }

var id: StringName
var kind: Kind
var cell: Vector2i
var title_zh: String
## For BATTLE / ELITE: the encounter id (B001, E-B001). For EVENT: the event id.
## For the random-event slot this stays empty until the run draws one.
var payload: StringName
## §9.4: one-shot places stay on the map with a finished marker; shops may be
## entered again with their stock and purchase records intact.
var one_shot: bool = true


static func create(p_id: StringName, p_kind: Kind, p_cell: Vector2i, p_title: String, p_payload: StringName = &"", p_one_shot: bool = true) -> SpringPlace:
	var place := SpringPlace.new()
	place.id = p_id
	place.kind = p_kind
	place.cell = p_cell
	place.title_zh = p_title
	place.payload = p_payload
	place.one_shot = p_one_shot
	return place


func kind_label_zh() -> String:
	match kind:
		Kind.BATTLE:
			return "战斗"
		Kind.ELITE:
			return "精英"
		Kind.BOSS:
			return "首领"
		Kind.EVENT:
			return "事件"
		Kind.SHOP:
			return "商店"
		Kind.HIDDEN:
			return "隐秘"
	return "未知"


## Single glyph used by the map grid. Kept here rather than in the view so the
## tests can assert what the player will see without loading a scene.
func glyph() -> String:
	match kind:
		Kind.BATTLE:
			return "战"
		Kind.ELITE:
			return "精"
		Kind.BOSS:
			return "王"
		Kind.EVENT:
			return "事"
		Kind.SHOP:
			return "商"
		Kind.HIDDEN:
			return "隐"
	return "?"


func is_combat() -> bool:
	return kind == Kind.BATTLE or kind == Kind.ELITE or kind == Kind.BOSS
