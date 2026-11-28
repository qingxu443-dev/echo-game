class_name PartyLoadout
extends RefCounted

## Shared backpack, independent worn equipment and character stat bases.
const FIELDS: Array[String] = [
	"base_max_health", "base_attack", "base_defense", "base_magic_resistance",
	"bonus_max_health", "hero_max_health", "hero_health", "equipped_weapon", "equipped_armor", "initialized",
]


## CONTRACT: _test_stage_healing_and_restart
static func capture(battle) -> void:
	var state = battle.run_state
	if state == null or not battle.single_active_party: return
	var actor = battle.get_active_character()
	if actor == null: return
	state.hero_health = actor.health
	state.hero_max_health = actor.max_health
	state.party_owner_id = actor.actor_id
	var row := {}
	for key in FIELDS:
		var value: Variant = state.get(key)
		row[key] = value.duplicate(true) if value is Dictionary else value
	state.party_loadouts[actor.actor_id] = row


static func select_role(battle, actor_id: String) -> void:
	var state = battle.run_state
	if state == null: return
	var row: Dictionary = state.party_loadouts.get(actor_id, {})
	for key in FIELDS:
		if row.has(key): state.set(key, row[key].duplicate(true) if row[key] is Dictionary else row[key])
	state.party_owner_id = actor_id


static func prepare_actor(battle, actor, index: int) -> void:
	var state = battle.run_state
	if state == null: return
	if not state.initialized: state.reset(actor.max_health, actor.attack, actor.defense, actor.magic_resistance)
	if state.party_owner_id.is_empty(): state.party_owner_id = actor.actor_id
	var row: Dictionary = state.party_loadouts.get(actor.actor_id, {})
	var role := RunState.new()
	role.reset(actor.max_health, actor.attack, actor.defense, actor.magic_resistance)
	if actor.actor_id == state.party_owner_id:
		# Legacy carry belongs to its declared owner, never to every teammate.
		for key in FIELDS: role.set(key, state.get(key))
	else:
		for key in ["base_max_health", "base_attack", "base_defense", "base_magic_resistance", "bonus_max_health", "equipped_weapon", "equipped_armor"]:
			if row.has(key): role.set(key, row[key].duplicate(true) if row[key] is Dictionary else row[key])
		role.hero_health = role.effective_max_health()
	role.apply_to_actor(actor)
	var updated := {}
	for key in FIELDS:
		var value: Variant = role.get(key)
		updated[key] = value.duplicate(true) if value is Dictionary else value
	if not row.is_empty():
		updated.hero_health = row.get("hero_health", actor.health)
		updated.hero_max_health = row.get("hero_max_health", actor.max_health)
	state.party_loadouts[actor.actor_id] = updated
	if index == 0: battle.active_character_id = actor.actor_id


static func restore_health(battle, saved: Dictionary) -> void:
	for actor_id in saved:
		var actor = battle.actors.get(str(actor_id))
		if actor == null or actor.team != "player": continue
		var row: Dictionary = saved[actor_id]
		var hp := int(row.get("health", actor.health))
		if battle.run_state != null and battle.run_state.party_retired.has(str(actor_id)): hp = 0
		var saved_max := maxi(1, int(row.get("max_health", actor.max_health)))
		var saved_base := int(row.get("base_max_health", 0))
		var base_max := unscaled_max_health(actor)
		var fragment_pct := float(actor.fragment_bonuses.get("health", 0.0))
		# New saves carry the unscaled base, and the rebuilt actor already has the
		# current modules applied. Old saves do not: a positive module bonus with a
		# saved maximum equal to the unscaled base means the row predates the
		# module. In both cases the actor's maximum wins and HP keeps its ratio.
		# Without that evidence the row stays authoritative, because it may hold an
		# authored or equipment-granted cap the loadout cannot reconstruct.
		var actor_owns_max := saved_base > 0 or (fragment_pct > 0.0 and saved_max == base_max)
		if actor_owns_max and saved_max != actor.max_health:
			hp = roundi(float(hp) * float(actor.max_health) / float(saved_max))
		elif not actor_owns_max:
			actor.max_health = saved_max
		actor.health = clampi(hp, 0, actor.max_health)
		if actor.health <= 0: PartyRotation.retire(battle, actor)
	PartyRotation.ensure_active(battle)
	capture(battle)
	if battle.get_defender() == null: battle._check_battle_end()


static func adopt_actor(battle, actor) -> void:
	var state = battle.run_state
	if state == null: return
	var role := RunState.new()
	role.reset(_unscaled(actor, "health", actor.max_health), _unscaled(actor, "attack", actor.attack),
		_unscaled(actor, "defense", actor.defense), _unscaled(actor, "magic_resistance", actor.magic_resistance))
	if state.party_owner_id.is_empty(): state.party_owner_id = battle.active_character_id
	if actor.actor_id == state.party_owner_id:
		for key in FIELDS: role.set(key, state.get(key))
	role.hero_health = actor.health
	role.hero_max_health = actor.max_health
	var row := {}
	for key in FIELDS:
		var value: Variant = role.get(key)
		row[key] = value.duplicate(true) if value is Dictionary else value
	state.party_loadouts[actor.actor_id] = row


static func _unscaled(actor, stat: String, value: int) -> int:
	return roundi(float(value) / (1.0 + float(actor.fragment_bonuses.get(stat, 0.0)) / 100.0))


## Maximum before the character's currently equipped health modules. Persisted
## with the party snapshot so a later encounter can tell a stale cap from a
## module-scaled one, and so unequipping can reclaim the bonus symmetrically.
static func unscaled_max_health(actor) -> int:
	return _unscaled(actor, "health", actor.max_health)


## Plain map JSON loses int/float distinctions. Normalize only known integer
## fields, only when their values are finite, integral and safely representable.
## SessionCodec snapshots retain their original strict typed validation.
## CONTRACT: _test_json_roundtrip_and_award
static func canonical_json_carry(carry: Dictionary) -> Dictionary:
	var result := carry.duplicate(true)
	var roles: Variant = result.get("party_loadouts", {})
	if not roles is Dictionary: return result
	var schema: Script = RunState
	for row in roles.values():
		if not row is Dictionary: continue
		for property in schema.get_script_property_list():
			var key := str(property.name)
			if key in FIELDS and property.type == TYPE_INT and row.has(key): row[key] = _json_integer(row[key])
		for slot in ["equipped_weapon", "equipped_armor"]:
			var item: Variant = row.get(slot, {})
			if not item is Dictionary: continue
			for key in ["max_health", "attack", "defense", "magic_resistance"]:
				if item.has(key): item[key] = _json_integer(item[key])
	return result


static func _json_integer(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floorf(value) and value >= -9.223372036854775e18 and value < 9.223372036854775e18: return int(value)
	return value


## CONTRACT: _test_all_catalog_equipment_roundtrips
static func carry_error(carry: Dictionary, json_numbers: bool = false) -> String:
	if json_numbers: carry = canonical_json_carry(carry)
	if not carry.get("single_active_party", false) is bool: return "single_active_party: expected bool"
	if not carry.get("party_owner_id", "") is String: return "party_owner_id: expected String"
	if not str(carry.get("party_owner_id", "")).is_empty() and not CharacterCatalog.has_definition(str(carry.party_owner_id)): return "party_owner_id: unknown character"
	if not carry.get("party_loadouts", {}) is Dictionary: return "party_loadouts: expected Dictionary"
	if not carry.get("party_retired", []) is Array: return "party_retired: expected Array"
	for actor_id in carry.get("party_retired", []):
		if not actor_id is String or not CharacterCatalog.has_definition(actor_id): return "party_retired: unknown character"
	for actor_id in carry.get("party_loadouts", {}):
		if not actor_id is String or not CharacterCatalog.has_definition(actor_id): return "party_loadouts: unknown character"
		var row: Variant = carry.party_loadouts[actor_id]
		if not row is Dictionary: return "party_loadouts: invalid row"
		for key in row:
			if not key in FIELDS: return "party_loadouts: unknown field"
		var error := SessionCodec.fields_error(RunState, row)
		if not error.is_empty(): return "party_loadouts." + error
		for key in ["base_max_health", "base_attack", "base_defense", "base_magic_resistance", "bonus_max_health", "hero_max_health", "hero_health"]:
			if int(row.get(key, 0)) < 0: return "party_loadouts: negative stat"
		if int(row.get("hero_health", 0)) > int(row.get("hero_max_health", 2147483647)): return "party_loadouts: HP exceeds maximum"
		for key in ["equipped_weapon", "equipped_armor"]:
			var item: Dictionary = row.get(key, {})
			if not item.is_empty() and str(item.get("kind", "")) != key.trim_prefix("equipped_"): return "party_loadouts: invalid equipment"
			for stat in ["max_health", "attack", "defense", "magic_resistance"]:
				# Item values are signed modifiers (dusk blade trades defense for
				# attack). Only final actor stats and vitality are nonnegative.
				if item.has(stat) and not item[stat] is int: return "party_loadouts: invalid equipment stat"
	return ""
