extends "res://tests/test_case.gd"
## Shop expansion: the second display tank and the shopfront upgrades.
## Uses the real data (prices, levels and upgrades are what the player sees).

var db: DataDB
var gs: GameState


func before_each() -> void:
	db = DataDB.load_from_dir("res://data")
	gs = GameState.new_game(db, _rng(5))
	_reach_level(4)
	gs.money = 20000


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


## Sets reputation to the first point total of the 1-based `level`.
func _reach_level(level: int) -> void:
	gs.reputation = int(gs.reputation_levels()[level - 1]["points"])


## A grown-up copy of the first starting fish, placed in holding.
func _adult(stars: int = 3) -> Fish:
	var proto: Fish = gs.inventory.fish_list()[0]
	var f := Fish.from_dict(proto.to_dict())
	f.id = 0
	f.location = Fish.HOLDING
	f.favorite = false
	f.stars = stars
	f.age_days = int(db.species[f.species_id]["days_to_adult"])
	return gs.inventory.add_fish(f)


func _own_second_display() -> void:
	assert_true(gs.buy_upgrade("second_display"))


# --- Buying the second display

func test_second_display_needs_reputation_level_four() -> void:
	gs.reputation = 0
	assert_eq(gs.upgrade_blocker("second_display"), "Reach '%s' first." % gs.unlock_level_name("second_display"))
	assert_false(gs.buy_upgrade("second_display"))
	assert_eq(gs.money, 20000)
	assert_eq(gs.unlock_level_name("second_display"), gs.reputation_levels()[3]["name"])
	_reach_level(4)
	assert_eq(gs.upgrade_blocker("second_display"), "")


func test_second_display_needs_1500_dollars() -> void:
	gs.money = 1499
	assert_eq(gs.upgrade_blocker("second_display"), "You need $1 more.")
	assert_false(gs.buy_upgrade("second_display"))
	gs.money = 1500
	assert_true(gs.buy_upgrade("second_display"))
	assert_eq(gs.money, 0)


func test_buying_it_creates_an_empty_tank_of_the_starting_type() -> void:
	assert_true(gs.display_tank_2 == null)
	_own_second_display()
	assert_true(gs.display_tank_2 != null)
	assert_eq(gs.display_tank_2.tank_item_id, db.economy["starting_state"]["display_tank"])
	assert_true(gs.display_tank_2.placed_item_ids().is_empty())
	assert_true(gs.display_tank_2.fish_ids.is_empty())
	assert_eq(gs.tank_at(Fish.DISPLAY2), gs.display_tank_2)
	assert_true(Fish.is_display(Fish.DISPLAY2) and Fish.is_display(Fish.DISPLAY))
	assert_false(Fish.is_display("breeding"))


func test_it_cannot_be_installed_before_it_is_bought() -> void:
	gs.inventory.add("tank_20l")
	assert_false(gs.install_display_tank("tank_20l", Fish.DISPLAY2))


# --- Fish on both tanks

func test_fish_move_in_and_out_with_capacity() -> void:
	var f := _adult()
	assert_false(gs.can_move_fish(f.id, Fish.DISPLAY2), "no tank yet")
	_own_second_display()
	var cap := gs.display_tank_2.capacity
	assert_true(gs.move_fish(f.id, Fish.DISPLAY2))
	assert_eq(f.location, Fish.DISPLAY2)
	assert_true(f.id in gs.display_tank_2.fish_ids)
	assert_true(gs.move_fish(f.id, Fish.HOLDING))
	assert_false(f.id in gs.display_tank_2.fish_ids)
	for i in cap:
		assert_true(gs.move_fish(_adult().id, Fish.DISPLAY2))
	assert_false(gs.can_move_fish(f.id, Fish.DISPLAY2), "full")
	assert_true(gs.move_blocker(f.id, Fish.DISPLAY2).begins_with("That tank is full"))


func test_fry_cannot_go_on_the_second_display() -> void:
	_own_second_display()
	var f := _adult()
	f.age_days = 0
	assert_false(gs.can_move_fish(f.id, Fish.DISPLAY2))


func test_both_tanks_count_for_fish_for_sale_and_appeal() -> void:
	_own_second_display()
	var a := _adult(4)
	var b := _adult(4)
	gs.move_fish(a.id, Fish.DISPLAY)
	var before := gs.shop_appeal()
	gs.move_fish(b.id, Fish.DISPLAY2)
	assert_true(b in gs.fish_for_sale())
	assert_true(a in gs.fish_for_sale())
	assert_true(b in gs.fish_for_customers())
	# On display counts fully, in holding only partly.
	var weights: Dictionary = db.economy["customers"]["appeal"]
	var per_fish := Customers.fish_appeal(b, db.species[b.species_id], db.economy["customers"])
	assert_almost(gs.shop_appeal() - before, per_fish * (float(weights["display_weight"]) - float(weights["holding_weight"])), 0.001)
	assert_eq(gs.display_fish().size(), 2)


func test_looks_use_the_better_tank_plus_half_the_other() -> void:
	assert_almost(Customers.combined_looks(60, 40, db.economy["customers"]), 80.0)
	assert_almost(Customers.combined_looks(40, 60, db.economy["customers"]), 80.0)
	assert_almost(Customers.combined_looks(50, 0, db.economy["customers"]), 50.0)
	var one := gs.display_looks()
	assert_almost(one, float(gs.tank_aesthetics(gs.display_tank)))
	_own_second_display()
	gs.inventory.add("fine_sand")
	assert_true(gs.set_substrate(gs.display_tank_2, "fine_sand"))
	var l1 := gs.tank_aesthetics(gs.display_tank)
	var l2 := gs.tank_aesthetics(gs.display_tank_2)
	assert_almost(gs.display_looks(), maxi(l1, l2) + mini(l1, l2) * 0.5)
	assert_true(gs.display_looks() >= one)


func test_goal_display_looks_is_the_best_of_the_two() -> void:
	_own_second_display()
	gs.inventory.add("fine_sand")
	gs.set_substrate(gs.display_tank_2, "fine_sand")
	gs.display_tank.take_substrate()
	for i in gs.display_tank.slot_count():
		gs.display_tank.take(i)
	assert_eq(gs.goal_value("display_looks"), gs.tank_aesthetics(gs.display_tank_2))


# --- Tank customers

func test_a_tank_customer_can_buy_display_two_and_it_is_not_replaced_for_free() -> void:
	_own_second_display()
	gs.sell_display_tank(false)  # clear display 1 so only display 2 is decorated
	gs.inventory.add("fine_sand")
	gs.inventory.add("java_fern")
	assert_true(gs.set_substrate(gs.display_tank_2, "fine_sand"))
	assert_true(gs.place_item(gs.display_tank_2, 0, "java_fern"))
	assert_eq(gs.tank_customer_location(), Fish.DISPLAY2)
	var f := _adult()
	gs.move_fish(f.id, Fish.DISPLAY2)
	var price := gs.tank_price(gs.display_tank_2, true)
	gs.customer = {"kind": "tank", "with_fish": true, "tank_location": Fish.DISPLAY2, "name": "Mabel",
		"waited": 0.0, "patience": 60.0}
	assert_eq(gs.customer_price(), price)
	var money := gs.money
	assert_eq(gs.serve_customer(), price)
	assert_eq(gs.money, money + price)
	assert_true(gs.display_tank_2 == null)
	assert_false(gs.inventory.has_fish(f.id), "the fish went with the tank")
	assert_true(gs.has_second_display(), "the expansion is still owned")
	# Mirrors display tank 1: set up a spare tank from stock to use it again.
	gs.inventory.add("tank_20l")
	assert_true(gs.install_display_tank("tank_20l", Fish.DISPLAY2))
	assert_true(gs.display_tank_2 != null and gs.display_tank_2.placed_item_ids().is_empty())


func test_the_better_looking_tank_is_the_one_for_sale() -> void:
	_own_second_display()
	assert_eq(gs.tank_customer_location(), Fish.DISPLAY, "only the starter tank is decorated")
	gs.inventory.add("fine_sand", 1)
	for id in ["slate_stack", "slate_stack", "slate_stack", "java_fern", "java_fern", "vallisneria", "vallisneria"]:
		gs.inventory.add(id)
	gs.set_substrate(gs.display_tank_2, "fine_sand")
	for i in 6:
		gs.place_item(gs.display_tank_2, i, ["slate_stack", "java_fern", "vallisneria"][i % 3])
	if gs.tank_aesthetics(gs.display_tank_2) > gs.tank_aesthetics(gs.display_tank):
		assert_eq(gs.tank_customer_location(), Fish.DISPLAY2)
	else:
		assert_eq(gs.tank_customer_location(), Fish.DISPLAY)


func test_a_new_customer_remembers_which_tank_it_wants() -> void:
	_own_second_display()
	gs.sell_display_tank(false)
	gs.inventory.add("java_fern")
	gs.place_item(gs.display_tank_2, 0, "java_fern")
	var found := false
	for i in 200:
		var c := gs._new_customer()
		if c["kind"] == "tank":
			found = true
			assert_eq(c["tank_location"], Fish.DISPLAY2)
	assert_true(found, "a tank customer came in 200 tries")


func test_selling_the_second_tank_is_a_fair_price_not_a_loop() -> void:
	_own_second_display()
	var empty_price := gs.tank_price(gs.display_tank_2, false)
	assert_true(empty_price < 1500, "the expansion itself is never refunded")
	var money := gs.money
	assert_eq(gs.sell_display_tank(false, Fish.DISPLAY2), empty_price)
	assert_eq(gs.money, money + empty_price)
	assert_eq(gs.sell_display_tank(false, Fish.DISPLAY2), 0, "nothing left to sell")


# --- Shopfront upgrades

func test_expansion_upgrades_are_grouped_and_chained() -> void:
	var ids: Array = []
	for id in db.upgrade_order:
		if db.upgrades[id].get("group", "") == "expansion":
			ids.append(id)
	assert_eq(ids.size(), 5)
	assert_eq(db.upgrades["fresh_paint"]["requires"], "window_display")
	assert_eq(db.upgrades["striped_awning"]["requires"], "fresh_paint")
	assert_eq(db.upgrades["neon_sign"]["requires"], "striped_awning")
	assert_eq(db.upgrades["reading_corner"]["requires_level"], 3)
	assert_eq(db.upgrades.size(), 15)


func test_shopfront_upgrades_change_customer_speed_and_patience() -> void:
	for id in ["shop_sign", "window_display"]:
		gs.buy_upgrade(id)
	var base := gs.customer_speed()
	assert_eq(gs.upgrade_blocker("striped_awning"), "Buy the Fresh Paint & Planters first.")
	assert_true(gs.buy_upgrade("fresh_paint"))
	assert_almost(gs.customer_speed() - base, 0.15)
	assert_true(gs.buy_upgrade("striped_awning"))
	assert_almost(gs.upgrade_effect("patience"), 0.25)
	assert_almost(gs.customer_speed() - base, 0.25)
	assert_true(gs.buy_upgrade("neon_sign"))
	assert_almost(gs.customer_speed() - base, 0.45)
	assert_almost(gs.upgrade_effect("collector_chance"), 1.0)


func test_collectors_come_twice_as_often_with_the_neon_sign() -> void:
	var star := _adult(5)
	star.paid = 0
	var ctx := {"fish_for_sale": [star], "species_db": db.species, "items_in_stock": [], "all_items": [],
		"wishable": [], "tank_for_sale": false, "can_take_request": false, "collector_fish": [star]}
	var rules: Dictionary = db.economy["customers"]
	var plain := 0
	var boosted := 0
	var r1 := _rng(11)
	var r2 := _rng(11)
	for i in 2000:
		ctx["collector_mult"] = 1.0
		if Customers.make_walk_in(ctx, rules, r1)["kind"] == "collector":
			plain += 1
		ctx["collector_mult"] = 2.0
		if Customers.make_walk_in(ctx, rules, r2)["kind"] == "collector":
			boosted += 1
	assert_true(boosted > plain * 1.25, "more collectors with the multiplier (%d vs %d)" % [boosted, plain])
	# The state passes the multiplier from the upgrade.
	for id in ["shop_sign", "window_display", "fresh_paint", "striped_awning", "neon_sign"]:
		assert_true(gs.buy_upgrade(id), id)
	assert_almost(1.0 + gs.upgrade_effect("collector_chance"), 2.0)


func test_reading_corner_needs_level_three_and_raises_regular_visits() -> void:
	gs.reputation = 0
	assert_eq(gs.upgrade_blocker("reading_corner"), "Reach shop level 3 (%s) first." % gs.reputation_levels()[2]["name"])
	_reach_level(3)
	assert_eq(gs.upgrade_blocker("reading_corner"), "")
	var base := gs.regular_visit_chance()
	assert_almost(base, float(db.regulars["rules"]["visit_chance"]))
	assert_true(gs.buy_upgrade("reading_corner"))
	assert_almost(gs.regular_visit_chance(), base * 1.5)


func test_regular_visits_are_capped() -> void:
	db.regulars["rules"]["visit_chance"] = 0.5
	gs.upgrades["reading_corner"] = 1
	assert_almost(gs.regular_visit_chance(), 0.6)


# --- Goals

func test_new_goals_and_the_all_upgrades_total() -> void:
	assert_eq(db.goals.size(), 57)
	var goal := {}
	for g in db.goals:
		if g["id"] == "all_upgrades":
			goal = g
	assert_eq(int(goal["target"]), db.upgrades.size())
	assert_eq(gs.goal_value("second_display"), 0)
	assert_eq(gs.goal_value("expansions"), 0)
	_own_second_display()
	assert_eq(gs.goal_value("second_display"), 1)
	assert_eq(gs.goal_value("expansions"), 1)
	for id in db.upgrade_order:
		gs.reputation = 5000
		gs.buy_upgrade(id)
	assert_eq(gs.goal_value("expansions"), 5)
	assert_eq(gs.goal_value("upgrades"), db.upgrades.size())
	gs.check_goals()
	assert_true(gs.completed_goals.has("grand_opening"))
	assert_true(gs.completed_goals.has("main_street_star"))
	assert_true(gs.completed_goals.has("all_upgrades"))


# --- Saving

func test_second_display_survives_a_save() -> void:
	_own_second_display()
	var f := _adult()
	gs.move_fish(f.id, Fish.DISPLAY2)
	gs.inventory.add("java_fern")
	gs.place_item(gs.display_tank_2, 1, "java_fern")
	var loaded := GameState.from_dict(db, _rng(9), SaveFile.parse(JSON.stringify(gs.to_dict())))
	assert_true(loaded.display_tank_2 != null)
	assert_true(loaded.has_second_display())
	assert_eq(loaded.display_tank_2.placed_item_ids(), gs.display_tank_2.placed_item_ids())
	assert_eq(loaded.inventory.get_fish(f.id).location, Fish.DISPLAY2)
	assert_true(f.id in loaded.display_tank_2.fish_ids)
	assert_eq(loaded.goal_value("second_display"), 1)


func test_a_sold_second_tank_stays_gone_after_loading() -> void:
	_own_second_display()
	gs.sell_display_tank(false, Fish.DISPLAY2)
	var loaded := GameState.from_dict(db, _rng(9), SaveFile.parse(JSON.stringify(gs.to_dict())))
	assert_true(loaded.display_tank_2 == null)
	assert_true(loaded.has_second_display())


func test_an_old_save_loads_without_a_second_tank() -> void:
	var d := gs.to_dict()
	d.erase("display_tank_2")
	var loaded := GameState.from_dict(db, _rng(9), SaveFile.parse(JSON.stringify(d)))
	assert_true(loaded.display_tank_2 == null)
	assert_false(loaded.has_second_display())
	assert_true(loaded.display_tank != null)
