class_name BattleRewards
extends RefCounted

## Called by the owning mode, never by the battle rules themselves.
static func settle(battle, spring_mode: bool, path: String = AtelierStash.SAVE_PATH) -> bool:
	if spring_mode or battle.ledger.rewards_settled:
		return true
	if battle.phase != battle.BattlePhase.FINISHED:
		return false
	if battle.battle_result not in ["victory", "defeat"]:
		return false
	var amount: int = 30 if battle.battle_result == "victory" else 15
	var skipped := path == AtelierStash.SAVE_PATH and DisplayServer.get_name() == "headless"
	if not skipped and AtelierStash.award_shards(amount, path) <= 0:
		return false
	battle.ledger.rewards_settled = true
	return true
