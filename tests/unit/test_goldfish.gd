extends "res://tests/test_case.gd"
## The goldfish tank: plain goldfish sold at a fixed price, restocked from the
## Market, breeding by themselves every few nights. They never leave the tank.

const F := preload("res://tests/fixtures.gd")

const RULES := {
	"price": 2, "restock_cost": 1, "capacity": 20, "starting": 6,
	"days_between_broods": 4, "brood_size": [3, 4], "min_to_breed": 2,
}

var gs: GameState


func before_each() -> void:
	var db := F.db()
	db.economy["goldfish_tank"] = RULES.duplicate(true)
	db.economy["customers"]["wants"]["goldfish"] = 0.5
	db.items["flakes"] = {"id": "flakes", "name": "Growth Flakes", "category": "food", "cost": 4, "price": 8,
		"tags": [], "growth_days": 2}
	gs = GameState.new_game(db, F.rng())
	gs.inventory.add("food", 50)


func _nights(n: int) -> Array:
	var born := []
	for i in n:
		var summary := gs.end_day()
		born.append(summary["goldfish_born"])
		gs.open_day()
	return born


func test_new_game_starts_with_a_stocked_goldfish_tank() -> void:
	assert_eq(gs.goldfish, 6)
	assert_eq(gs.goldfish_price(), 2)


func test_game_without_goldfish_rules_has_none() -> void:
	var plain := F.new_game()
	assert_eq(plain.goldfish, 0)
	assert_eq(plain.goldfish_buy_blocker(1), "The goldfish tank is full.")


func test_buying_costs_a_dollar_each() -> void:
	var money := gs.money
	assert_true(gs.buy_goldfish(5))
	assert_eq(gs.goldfish, 11)
	assert_eq(gs.money, money - 5)


func test_cannot_overfill_the_tank() -> void:
	assert_false(gs.buy_goldfish(15))
	assert_eq(gs.goldfish_buy_blocker(15), "There's only room for 14 more.")
	assert_true(gs.buy_goldfish(14))
	assert_eq(gs.goldfish_buy_blocker(1), "The goldfish tank is full.")


func test_cannot_buy_without_money() -> void:
	gs.money = 2
	assert_eq(gs.goldfish_buy_blocker(3), "Not enough money.")
	assert_false(gs.buy_goldfish(3))
	assert_eq(gs.goldfish, 6)


func test_homegrown_market_closure_stops_goldfish_restocks() -> void:
	var db := F.db()
	db.economy["goldfish_tank"] = RULES.duplicate(true)
	db.challenges = [{"id": "homegrown", "name": "H", "description": "", "rules": {"market_fish_until_day": 0}}]
	var hg := GameState.new_game(db, F.rng(), {"challenge_id": "homegrown"})
	assert_eq(hg.goldfish_buy_blocker(1), "The Market has stopped selling fish.")


func test_selling_one_earns_two_dollars() -> void:
	var money := gs.money
	assert_eq(gs.sell_goldfish(), 2)
	assert_eq(gs.goldfish, 5)
	assert_eq(gs.money, money + 2)
	assert_eq(gs.stat("goldfish_sold"), 1)


func test_cannot_sell_from_an_empty_tank() -> void:
	gs.goldfish = 0
	assert_eq(gs.sell_goldfish(), 0)


func test_they_breed_every_four_nights_three_or_four_at_a_time() -> void:
	var born := _nights(8)
	assert_eq(born[0] + born[1] + born[2], 0, "nothing for the first three nights")
	assert_between(born[3], 3, 4)
	assert_eq(born[4] + born[5] + born[6], 0)
	assert_between(born[7], 3, 4)
	assert_eq(gs.goldfish, 6 + born[3] + born[7])


func test_countdown_to_the_next_brood() -> void:
	assert_eq(gs.goldfish_nights_until_brood(), 4)
	_nights(1)
	assert_eq(gs.goldfish_nights_until_brood(), 3)


func test_one_goldfish_alone_does_not_breed() -> void:
	gs.goldfish = 1
	assert_eq(gs.goldfish_nights_until_brood(), -1)
	assert_eq(_nights(5), [0, 0, 0, 0, 0])
	assert_eq(gs.goldfish, 1)


func test_broods_stop_at_the_tank_capacity() -> void:
	gs.goldfish = 19
	var born := _nights(4)
	assert_eq(born[3], 1)
	assert_eq(gs.goldfish, 20)


func test_a_goldfish_customer_buys_one_at_the_counter() -> void:
	gs.customer = {"name": "Sam", "kind": "goldfish", "waited": 0.0, "patience": 60.0}
	assert_eq(gs.customer_price(), 2)
	assert_eq(gs.customer_blocker(), "")
	assert_eq(gs.serve_customer(), 2)
	assert_eq(gs.goldfish, 5)


func test_goldfish_customer_turned_away_when_sold_out() -> void:
	gs.goldfish = 0
	gs.customer = {"name": "Sam", "kind": "goldfish", "waited": 0.0, "patience": 60.0}
	assert_eq(gs.customer_blocker(), "The goldfish tank is empty.")
	assert_eq(gs.serve_customer(), 0)


func test_goldfish_customers_only_come_while_there_are_goldfish() -> void:
	var rules: Dictionary = gs.db.economy["customers"]
	var rng := F.rng()
	var seen := 0
	for i in 300:
		if Customers.make_walk_in({"goldfish_for_sale": true}, rules, rng)["kind"] == "goldfish":
			seen += 1
	assert_eq(seen, 300, "the only thing for sale")
	for i in 100:
		assert_ne(Customers.make_walk_in({"goldfish_for_sale": false}, rules, rng)["kind"], "goldfish")


func test_goldfish_are_a_rare_want_beside_other_stock() -> void:
	var rules: Dictionary = gs.db.economy["customers"]
	var rng := F.rng()
	var seen := 0
	for i in 1000:
		if Customers.make_walk_in({"goldfish_for_sale": true, "items_in_stock": ["sand"]}, rules, rng)["kind"] == "goldfish":
			seen += 1
	assert_between(seen, 100, 350, "much less often than shelf items")


func test_goldfish_tank_is_saved_and_loaded() -> void:
	gs.goldfish = 9
	gs.goldfish_nights = 2
	var loaded := GameState.from_dict(gs.db, F.rng(), gs.to_dict())
	assert_eq(loaded.goldfish, 9)
	assert_eq(loaded.goldfish_nights, 2)


func test_they_eat_one_regular_food_a_night() -> void:
	var food := gs.inventory.count("food")
	_nights(1)
	assert_eq(gs.inventory.count("food"), food - 1)


func test_they_never_eat_growth_or_breeding_food() -> void:
	gs.inventory.remove("food", gs.inventory.count("food"))
	gs.inventory.add("flakes", 5)
	var summary := gs.end_day()
	assert_eq(gs.inventory.count("flakes"), 5)
	assert_true(summary["goldfish_unfed"])


func test_unfed_goldfish_do_not_count_down_to_a_brood() -> void:
	gs.inventory.remove("food", gs.inventory.count("food"))
	assert_eq(_nights(6), [0, 0, 0, 0, 0, 0])
	assert_eq(gs.goldfish_nights_until_brood(), 4)


func test_auto_feeder_feeds_them_for_free() -> void:
	gs.upgrades["feeder"] = 1
	var food := gs.inventory.count("food")
	assert_eq(gs.goldfish_food_use(), 0)
	_nights(4)
	assert_eq(gs.inventory.count("food"), food)
	assert_true(gs.goldfish > 6)


func test_food_forecast_counts_the_goldfish_tank() -> void:
	var before := gs.food_use_per_night()
	gs.goldfish = 0
	assert_eq(gs.food_use_per_night(), before - 1)


func test_older_save_gets_a_stocked_goldfish_tank() -> void:
	var d := gs.to_dict()
	d.erase("goldfish")
	d.erase("goldfish_nights")
	var loaded := GameState.from_dict(gs.db, F.rng(), d)
	assert_eq(loaded.goldfish, 6)
	assert_eq(loaded.goldfish_nights, 0)


func test_goldfish_are_drawn_as_gold_guppies() -> void:
	var db := DataDB.load_from_dir("res://data")
	var real := GameState.new_game(db, F.rng())
	var species := real.goldfish_look_species()
	assert_eq(species.get("id"), "guppy")
	var f := real.goldfish_look_fish(3)
	assert_eq(f.species_id, "guppy")
	assert_eq(f.get_trait("variety"), "gold")
	assert_true(species["sprites"]["varieties"].has("gold"), "the gold guppy has its own sprite")
	assert_true(f.age_days >= int(species["days_to_adult"]), "drawn full size")


func test_goldfish_without_a_look_have_no_look_species() -> void:
	assert_eq(gs.goldfish_look_species(), {})
