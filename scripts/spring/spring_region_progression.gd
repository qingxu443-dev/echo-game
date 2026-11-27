class_name SpringRegionProgression
extends RefCounted

## Region order and unlock gate for the seasonal exploration flow.
## Summer is intentionally not unlocked in this build; adding content alone must
## not silently make the next region playable.

const REGION_SPRING: StringName = &"spring"
const REGION_SUMMER: StringName = &"summer"

const REGION_NAMES := {
	"spring": "春之境",
	"summer": "夏之境",
}

const NEXT_REGION := {
	"spring": "summer",
}

## Returns the next-region decision without mutating the current run.
## The caller supplies the player's unlocked region ids; this prototype only
## grants access to 春之境.
static func resolve_next(region_id: StringName, unlocked_region_ids: Array = []) -> Dictionary:
	var next_id := StringName(str(NEXT_REGION.get(String(region_id), "")))
	if next_id == &"":
		return {
			"from_region": region_id,
			"next_region": &"",
			"next_region_name": "",
			"status": "complete",
			"can_enter": false,
		}

	var unlocked: bool = unlocked_region_ids.has(next_id)
	return {
		"from_region": region_id,
		"next_region": next_id,
		"next_region_name": str(REGION_NAMES.get(String(next_id), String(next_id))),
		"status": "available" if unlocked else "locked",
		"can_enter": unlocked,
	}
