class_name EnemyActorFactory
extends RefCounted

## Shared profile reader for encounter enemies and phase-two reinforcements.
static func create(
	profile: EnemyDefinition, actor_id: String, cell: Vector2i,
	health_override: int = -1, stat_multiplier: float = 1.0
) -> BattleActor:
	var base_health: int = profile.health if health_override < 0 else health_override
	var health := maxi(1, roundi(base_health * stat_multiplier))
	var actor := BattleActor.new(
		actor_id, "enemy", cell, health, String(profile.archetype_id),
		roundi(profile.attack * stat_multiplier), roundi(profile.defense * stat_multiplier),
		roundi(profile.magic_resistance * stat_multiplier)
	)
	actor.glyph = profile.glyph
	actor.display_name_zh = profile.display_name_zh
	actor.skill_charge_max = 3
	actor.move_steps = profile.move_steps
	actor.tier = profile.tier
	actor.ward_shield = profile.ward_shield
	actor.skill_damage = profile.skill_damage
	actor.ward_stance_percent = profile.ward_stance_percent
	actor.ward_stance_node_bonus = profile.ward_stance_node_bonus
	actor.basic_attack_multiplier = profile.basic_attack_multiplier
	actor.interruptible_skill = profile.interruptible_skill
	actor.curse_defense_down = profile.curse_defense_down
	return actor
