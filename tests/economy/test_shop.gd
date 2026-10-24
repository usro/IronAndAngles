extends TestCase

const F := preload("res://tests/economy/fixtures.gd")

var _shop: Shop
var _player: PlayerState


func before_each() -> void:
	var weapons := {
		&"trebuchet": F.weapon(&"trebuchet", 0, 120.0, 2),
		&"mortar": F.weapon(&"mortar", 900, 80.0, 3),
		&"howitzer": F.weapon(&"howitzer", 100, 200.0, 5, GameConstants.Era.INDUSTRIAL),
	}
	var ammo := {
		&"stone": F.ammo(&"stone", 15),
		&"fire_pot": F.ammo(&"fire_pot", 40),
	}
	var tech := {
		&"early_mortar": F.tech(&"early_mortar", [&"mortar"] as Array[StringName]),
		&"alchemy": F.tech(&"alchemy", [] as Array[StringName], [&"fire_pot"] as Array[StringName]),
	}
	_shop = Shop.new(weapons, ammo, tech)
	_player = F.player(1000)


func test_base_items_are_unlocked() -> void:
	assert_true(_shop.is_weapon_unlocked(_player, &"trebuchet"))
	assert_true(_shop.is_ammo_unlocked(_player, &"stone"))


func test_tech_gated_items_are_locked_until_researched() -> void:
	assert_false(_shop.is_weapon_unlocked(_player, &"mortar"))
	assert_eq(_shop.buy_weapon(_player, &"mortar"), Shop.Status.LOCKED)
	assert_eq(_player.money, 1000)
	_player.unlocked_tech.append(&"early_mortar")
	assert_eq(_shop.buy_weapon(_player, &"mortar"), Shop.Status.OK)
	assert_eq(_player.money, 100)
	assert_true(_player.owned_weapons.has(&"mortar"))
	assert_eq(_player.weapon_health[&"mortar"], 80.0)


func test_later_era_items_are_locked() -> void:
	assert_eq(_shop.buy_weapon(_player, &"howitzer"), Shop.Status.LOCKED)
	_player.current_era = GameConstants.Era.INDUSTRIAL
	assert_eq(_shop.buy_weapon(_player, &"howitzer"), Shop.Status.OK)


func test_unaffordable_weapon_is_refused() -> void:
	_player.unlocked_tech.append(&"early_mortar")
	_player.money = 899
	assert_eq(_shop.buy_weapon(_player, &"mortar"), Shop.Status.UNAFFORDABLE)
	assert_eq(_player.money, 899)
	assert_false(_player.owned_weapons.has(&"mortar"))


func test_owned_weapon_cannot_be_bought_twice() -> void:
	_shop.buy_weapon(_player, &"trebuchet")
	assert_eq(_shop.buy_weapon(_player, &"trebuchet"), Shop.Status.ALREADY_OWNED)


func test_unknown_item() -> void:
	assert_eq(_shop.buy_weapon(_player, &"railgun"), Shop.Status.UNKNOWN_ITEM)
	assert_eq(_shop.buy_ammo(_player, &"nope", 1), Shop.Status.UNKNOWN_ITEM)


func test_ammo_costs_the_stock_fee() -> void:
	# 10 x 15 x 0.25 = 37.5 -> 38
	assert_eq(_shop.ammo_price(&"stone", 10), 38)
	assert_eq(_shop.buy_ammo(_player, &"stone", 10), Shop.Status.OK)
	assert_eq(_player.money, 962)
	assert_eq(_player.ammo_count(&"stone"), 10)


func test_ammo_refusals() -> void:
	assert_eq(_shop.buy_ammo(_player, &"fire_pot", 1), Shop.Status.LOCKED)
	assert_eq(_shop.buy_ammo(_player, &"stone", 0), Shop.Status.INVALID_AMOUNT)
	_player.money = 37
	assert_eq(_shop.buy_ammo(_player, &"stone", 10), Shop.Status.UNAFFORDABLE)
	assert_eq(_player.ammo_count(&"stone"), 0)
	assert_eq(_player.money, 37)


func test_repair_math() -> void:
	_shop.buy_weapon(_player, &"trebuchet")
	_player.weapon_health[&"trebuchet"] = 70.5  # 49.5 missing -> 50 hp billed at 2
	assert_near(_shop.missing_health(_player, &"trebuchet"), 49.5)
	assert_eq(_shop.repair_cost(_player, &"trebuchet"), 100)
	assert_eq(_shop.repair_cost(_player, &"trebuchet", 10.0), 20)
	assert_eq(_shop.repair(_player, &"trebuchet"), Shop.Status.OK)
	assert_eq(_player.money, 900)
	assert_eq(_player.weapon_health[&"trebuchet"], 120.0)
	assert_eq(_shop.repair(_player, &"trebuchet"), Shop.Status.NOTHING_TO_REPAIR)


func test_partial_repair() -> void:
	_shop.buy_weapon(_player, &"trebuchet")
	_player.weapon_health[&"trebuchet"] = 20.0
	assert_eq(_shop.repair(_player, &"trebuchet", 30.0), Shop.Status.OK)
	assert_eq(_player.weapon_health[&"trebuchet"], 50.0)
	assert_eq(_player.money, 940)
	assert_eq(_shop.repair(_player, &"trebuchet", 500.0), Shop.Status.OK, "clamped to missing health")
	assert_eq(_player.weapon_health[&"trebuchet"], 120.0)
	assert_eq(_player.money, 800)


func test_unaffordable_repair_is_refused() -> void:
	_shop.buy_weapon(_player, &"trebuchet")
	_player.weapon_health[&"trebuchet"] = 0.0
	_player.money = 100
	assert_eq(_shop.repair(_player, &"trebuchet"), Shop.Status.UNAFFORDABLE)
	assert_eq(_player.weapon_health[&"trebuchet"], 0.0)
	assert_eq(_shop.affordable_repair_hp(_player, &"trebuchet"), 50.0)
	assert_eq(_shop.repair(_player, &"trebuchet", 50.0), Shop.Status.OK)
	assert_eq(_player.money, 0)


func test_cannot_repair_unowned() -> void:
	assert_eq(_shop.repair(_player, &"mortar"), Shop.Status.NOT_OWNED)
