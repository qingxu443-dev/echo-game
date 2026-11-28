class_name SpringVitality
extends RefCounted


static func unscaled_maximum(run) -> int:
	var carried: int = run.carry_max_health
	var row: Dictionary = run.party_vitals.get(run.hero_character_id, {})
	# #120/#121 snapshots can have a scaled carry alongside a known raw base.
	# Only that explicit provenance permits normalization; never guess an old
	# authored/equipment cap from the currently installed module percentage.
	if int(row.get("base_max_health", 0)) > 0 and carried == int(row.get("max_health", -1)):
		carried = int(row.base_max_health)
	return maxi(1, maxi(run.hero_base_max_health + run.bonus_max_health + SpringRelicCatalog.total_bonus(run.relics, "max_health"), carried))


static func effective_maximum(run) -> int:
	var core := unscaled_maximum(run)
	var row: Dictionary = run.party_vitals.get(run.hero_character_id, {})
	if int(row.get("base_max_health", 0)) <= 0: return core
	if int(row.base_max_health) == core: return maxi(1, int(row.max_health))
	return _scaled(run, core)


static func _scaled(run, core: int) -> int:
	var store = FragmentStore.load_store()
	var percent: float = store.total_bonus(run.hero_character_id, "health") if store != null else 0.0
	return maxi(1, roundi(float(core) * (1.0 + percent / 100.0)))


## CONTRACT: _test_fragment_vitality_full_flow
static func sync(run, allow_revive: bool = false) -> void:
	if not run.party_vitals.has(run.hero_character_id): return
	var row: Dictionary = run.party_vitals[run.hero_character_id]
	if int(row.get("base_max_health", 0)) > 0 and run.carry_max_health == int(row.get("max_health", -1)):
		run.carry_max_health = int(row.base_max_health)
	var core := unscaled_maximum(run)
	var maximum := _scaled(run, core)
	var previous := maxi(1, int(row.get("max_health", core)))
	var previous_base := int(row.get("base_max_health", core))
	# A module-only change preserves the wounded ratio. Map max-health effects
	# already apply their own explicit heal and must not receive another one.
	if maximum != previous and previous_base == core:
		run.hero_health = roundi(float(run.hero_health) * float(maximum) / float(previous))
	row["base_max_health"] = core
	row["max_health"] = maximum
	run.hero_max_health = maximum
	if int(row.get("health", 0)) > 0 or allow_revive:
		run.hero_health = clampi(run.hero_health, 0, maximum)
		row["health"] = run.hero_health
	else:
		run.hero_health = 0


static func change_bonus(run, amount: int) -> void:
	if amount == 0: return
	sync(run)
	run.bonus_max_health = maxi(0, run.bonus_max_health + amount)
	if amount > 0: run.hero_health += amount
	run.hero_health = clampi(run.hero_health, 1 if run.hero_health > 0 else 0, effective_maximum(run))
	sync(run)
