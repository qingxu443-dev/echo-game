class_name InputRouter
extends RefCounted

## Turns raw input into the handful of intentions the battle view understands.
##
## Three device paths - touch, mouse and keyboard - collapse into one vocabulary
## here, so the view never branches on event classes. That is also the seam an
## Android build needs: a new device only adds a branch in translate().
##
## Returned dictionaries:
##   {"action": "tap", "position": Vector2}
##   {"action": "skill", "index": int}
##   {"action": "cancel"}
##   {"action": "end_turn"}
##   {"action": "switch"}
##   {} for anything irrelevant

const ACTION_TAP: String = "tap"
const ACTION_SKILL: String = "skill"
const ACTION_CANCEL: String = "cancel"
const ACTION_END_TURN: String = "end_turn"
const ACTION_SWITCH: String = "switch"


static func translate(event: InputEvent) -> Dictionary:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			return {"action": ACTION_TAP, "position": touch.position}
		return {}

	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if not click.pressed:
			return {}
		if click.button_index == MOUSE_BUTTON_LEFT:
			return {"action": ACTION_TAP, "position": click.position}
		if click.button_index == MOUSE_BUTTON_RIGHT:
			return {"action": ACTION_CANCEL}
		return {}

	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return {}
		match key.keycode:
			KEY_1:
				return {"action": ACTION_SKILL, "index": 0}
			KEY_2:
				return {"action": ACTION_SKILL, "index": 1}
			KEY_3:
				return {"action": ACTION_SKILL, "index": 2}
			KEY_4:
				return {"action": ACTION_SKILL, "index": 3}
			KEY_5:
				return {"action": ACTION_SKILL, "index": 4}
			KEY_6:
				return {"action": ACTION_SKILL, "index": 5}
			KEY_ESCAPE:
				return {"action": ACTION_CANCEL}
			KEY_ENTER, KEY_SPACE:
				return {"action": ACTION_END_TURN}
			KEY_TAB:
				return {"action": ACTION_SWITCH}

	return {}
