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
const ACTION_ROTATE_CAM: String = "rotate_cam"
const ACTION_TOGGLE_BAG: String = "toggle_bag"


const KEY_ACTIONS := {
	"echo_cancel": {"action": ACTION_CANCEL},
	"echo_end_turn": {"action": ACTION_END_TURN},
	"echo_switch": {"action": ACTION_SWITCH},
	"echo_rotate_left": {"action": ACTION_ROTATE_CAM, "step": -1},
	"echo_rotate_right": {"action": ACTION_ROTATE_CAM, "step": 1},
	"echo_inventory": {"action": ACTION_TOGGLE_BAG},
}


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
		if not event.pressed or event.echo:
			return {}
	elif event is InputEventAction:
		if not event.pressed:
			return {}
	else:
		return {}
	for index in range(6):
		if event.is_action_pressed("echo_skill_%d" % (index + 1)):
			return {"action": ACTION_SKILL, "index": index}
	for action in KEY_ACTIONS:
		if event.is_action_pressed(action):
			return KEY_ACTIONS[action].duplicate()
	return {}
