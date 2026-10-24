class_name CampaignGoal
extends RefCounted
## The campaign's finish line: win GOAL_WINS contracts in the Experimental era. Reaching it shows the
## ending once (PlayerState.campaign_complete); the campaign can continue afterwards.

const GOAL_ERA := GameConstants.Era.EXPERIMENTAL
const GOAL_WINS := 3


static func progress(player: PlayerState) -> int:
	return int(player.era_victories.get(str(GOAL_ERA), 0))


static func is_met(player: PlayerState) -> bool:
	return progress(player) >= GOAL_WINS


## True once, right after the goal is first reached: marks it complete so it won't fire again.
static func claim_ending(player: PlayerState) -> bool:
	if player.campaign_complete or not is_met(player):
		return false
	player.campaign_complete = true
	return true


static func describe(player: PlayerState) -> String:
	if player.campaign_complete:
		return "CAMPAIGN COMPLETE"
	return "GOAL  %d / %d  %s-ERA CONTRACTS" % [mini(progress(player), GOAL_WINS), GOAL_WINS,
		GameConstants.era_name(GOAL_ERA).to_upper()]


static func total_victories(player: PlayerState) -> int:
	var n := 0
	for k in player.era_victories:
		n += int(player.era_victories[k])
	return n
