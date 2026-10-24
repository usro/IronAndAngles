extends TestCase

const F := preload("res://tests/economy/fixtures.gd")


func _result(victory: bool, payout: int, ammo_spent: int) -> BattleResult:
	var r := BattleResult.new()
	r.contract_id = &"siege"
	r.victory = victory
	r.payout_earned = payout
	r.ammo_spent = ammo_spent
	return r


func test_profit_and_margin() -> void:
	var report := Settlement.report(_result(true, 1500, 150), 450, {})
	assert_eq(report.net_profit(), 900)
	assert_near(report.margin(), 0.6)


func test_defeat_is_a_loss() -> void:
	var report := Settlement.report(_result(false, 0, 90), 300, {})
	assert_eq(report.net_profit(), -390)
	assert_eq(report.margin(), 0.0)


func test_repairs_for_damage_taken() -> void:
	var r := _result(true, 1000, 100)
	r.damage_taken = {&"trebuchet": 10.2}
	var report := Settlement.report(r, 200, {&"trebuchet": F.weapon(&"trebuchet", 0, 120.0, 2)})
	assert_eq(report.repair_cost, 22)
	assert_eq(report.net_after_repairs(), 678)
	assert_eq(report.summary_lines().size(), 5)
