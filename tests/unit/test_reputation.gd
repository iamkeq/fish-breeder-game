extends "res://tests/test_case.gd"
## Shop reputation: points, levels, effects, unlocks, and what feeds it.

const F := preload("res://tests/fixtures.gd")

var gs: GameState


func before_each() -> void:
	gs = F.new_game()


func _male() -> Fish:
	return gs.inventory.fish_list().filter(func(f): return f.sex == Fish.MALE)[0]


func _female() -> Fish:
	return gs.inventory.fish_list().filter(func(f): return f.sex == Fish.FEMALE)[0]


func _sell_to_walk_in(f: Fish) -> void:
	gs.move_fish(f.id, Fish.DISPLAY)
	gs.customer = {"kind": "fish", "fish_id": f.id, "name": "Mabel", "waited": 0.0, "patience": 60.0}
	gs.serve_customer()


# --- Where points come from

func test_a_new_shop_starts_at_level_one() -> void:
	assert_eq(gs.reputation, 0)
	assert_eq(gs.reputation_level(), 0)
	assert_eq(gs.reputation_level_name(), "Start")


func test_a_walk_in_sale_pays_one_point_plus_the_star_bonus() -> void:
	_sell_to_walk_in(_male())  # 2 stars: 1 + 1
	assert_eq(gs.reputation, 2)
	_sell_to_walk_in(_female())  # 4 stars: 1 + 4
	assert_eq(gs.reputation, 7)


func test_item_sales_earn_the_plain_sale_point() -> void:
	gs.customer = {"kind": "item", "item_id": "fern", "name": "Mabel", "waited": 0.0, "patience": 60.0}
	gs.serve_customer()
	assert_eq(gs.reputation, 1)


func test_a_failed_sale_earns_nothing() -> void:
	gs.customer = {"kind": "item", "item_id": "castle", "name": "Mabel", "waited": 0.0, "patience": 60.0}
	assert_eq(gs.serve_customer(), 0, "none in stock")
	assert_eq(gs.reputation, 0)


func test_buying_and_wholesale_never_earn_reputation() -> void:
	gs.money = 1000
	gs.buy_item("castle")
	gs.buy_item("fern")
	gs.sell_fish_wholesale(_male().id)
	assert_eq(gs.reputation, 0)


func test_a_special_order_pays_ten() -> void:
	gs.accept_request(gs.make_request())
	gs.place_item(gs.display_tank, 2, "fern")
	gs.move_fish(_male().id, Fish.DISPLAY)
	assert_false(gs.deliver_order(0).is_empty())
	assert_eq(gs.reputation, 10)


func test_a_back_order_pays_four_and_no_sale_point() -> void:
	gs.customer = {"kind": "wish_item", "item_id": "castle", "name": "Jun", "waited": 0.0, "patience": 60.0}
	gs.backorder_customer()
	gs.buy_item("castle")
	assert_eq(gs.reputation, 0)
	gs.fulfil_backorder(0)
	assert_eq(gs.reputation, 4)


func test_a_collector_pays_sale_and_collector_points() -> void:
	var f := F.fish(Fish.MALE, "grey", 5)
	gs.inventory.add_fish(f)
	gs.move_fish(f.id, Fish.DISPLAY)
	gs.customer = {"kind": "collector", "fish_id": f.id, "name": "Wren", "waited": 0.0, "patience": 60.0}
	assert_true(gs.serve_customer() > 0)
	assert_eq(gs.reputation, 1 + 6 + 6, "sale + 5-star bonus + collector sale")


func test_goals_pay_reputation_once() -> void:
	gs.money = 1000
	gs.buy_breeding_tank()
	var reached := gs.check_goals()
	assert_true(reached.size() >= 1)
	assert_eq(gs.reputation, 5 * reached.size())
	var before := gs.reputation
	gs.check_goals()
	assert_eq(gs.reputation, before)


func test_first_recipe_and_mutation_pay_once() -> void:
	var species: Dictionary = gs.db.species["guppy"]
	var summary := {"discoveries": [], "book_bonuses": []}
	gs._discover(summary, "recipe", species, "body_color", "red", ["grey", "orange"])
	assert_eq(gs.reputation, 3)
	gs._discover(summary, "recipe", species, "body_color", "red", ["orange", "grey"])
	assert_eq(gs.reputation, 3, "same recipe again: nothing")
	gs._discover(summary, "mutation", species, "body_color", "red", ["grey", "orange"])
	assert_eq(gs.reputation, 11)


func test_award_reputation_multiplies() -> void:
	gs.award_reputation("order_delivered", 3)
	assert_eq(gs.reputation, 30)
	gs.award_reputation("nonsense")
	assert_eq(gs.reputation, 30)


# --- Levels

func test_level_thresholds_and_progress() -> void:
	gs.reputation = 19
	assert_eq(gs.reputation_level(), 0)
	gs.reputation = 20
	assert_eq(gs.reputation_level(), 1)
	assert_eq(gs.reputation_level_name(), "Known")
	assert_eq(gs.reputation_next(), {"name": "Liked", "points": 60})
	assert_eq(gs.reputation_progress(), 0.0)
	gs.reputation = 40
	assert_eq(gs.reputation_progress(), 0.5)


func test_the_top_level_has_no_next() -> void:
	gs.reputation = 5000
	assert_eq(gs.reputation_level(), 3)
	assert_eq(gs.reputation_next(), {})
	assert_eq(gs.reputation_progress(), 1.0)


func test_effects_add_up_across_levels() -> void:
	assert_eq(gs.reputation_effect("extra_customers"), 0)
	gs.reputation = 20
	assert_eq(gs.reputation_effect("extra_customers"), 1)
	gs.reputation = 60
	assert_eq(gs.reputation_effect("extra_customers"), 3)
	assert_eq(gs.reputation_effect("extra_orders"), 1)
	assert_eq(gs.reputation_effect("nothing"), 0)


func test_unlocks_hold_for_the_level_and_every_level_above() -> void:
	assert_false(gs.has_unlock("lab"))
	gs.reputation = 20
	assert_true(gs.has_unlock("lab"))
	assert_false(gs.has_unlock("fish_show"))
	gs.reputation = 100
	assert_true(gs.has_unlock("lab"), "still unlocked at higher levels")
	assert_true(gs.has_unlock("fish_show"))
	assert_false(gs.has_unlock("unknown_id"))


func test_extra_orders_raise_max_orders() -> void:
	assert_eq(gs.max_orders(), 2)
	gs.reputation = 60
	assert_eq(gs.max_orders(), 3)
	gs.buy_upgrade("desk")
	assert_eq(gs.max_orders(), 5, "stacks with the upgrade")


func test_extra_customers_speed_up_arrivals() -> void:
	assert_eq(gs.customer_speed(), 1.0)
	gs.reputation = 20
	assert_eq(gs.customer_speed(), 1.1)
	gs.reputation = 60
	assert_eq(gs.customer_speed(), 1.3)
	gs.money = 1000
	gs.buy_upgrade("sign")
	assert_eq(gs.customer_speed(), 2.3, "adds to upgrades")


func test_arrival_wait_is_shorter_with_reputation() -> void:
	var total_plain := 0.0
	var total_famous := 0.0
	for i in 40:
		gs.reputation = 0
		gs._customer_leaves()
		total_plain += gs.minutes_to_customer
		gs.reputation = 60
		gs._customer_leaves()
		total_famous += gs.minutes_to_customer
	assert_true(total_famous < total_plain)
	assert_true(gs.minutes_to_customer >= float(gs.db.economy["customers"]["min_interval_minutes"]), "floor still applies")


# --- Goal metric and summary

func test_reputation_level_goal_uses_the_one_based_level() -> void:
	assert_eq(gs.goal_value("reputation_level"), 1)
	gs.reputation = 60
	assert_eq(gs.goal_value("reputation_level"), 3)


func test_a_goal_can_chain_into_a_reputation_goal() -> void:
	gs.db.goals.append({"id": "lvl2", "name": "L2", "description": "", "metric": "reputation_level",
		"target": 2, "reward": 7})
	gs.db.goals.append({"id": "tank1", "name": "T1", "description": "", "metric": "breeding_tanks",
		"target": 1, "reward": 1})
	gs.reputation = 16  # one goal (5) takes it to 21, which is level 2
	var reached := gs.check_goals()
	var ids := reached.map(func(g): return g["id"])
	assert_true("lvl2" in ids, "chained in the same call, and it ended")


func test_end_day_reports_level_ups_and_points() -> void:
	var s := gs.end_day()
	assert_eq(s["reputation"]["gained"], 0)
	gs.open_day()
	gs.reputation += 25
	s = gs.end_day()
	assert_eq(s["reputation"]["gained"], 25)
	assert_eq(s["reputation"]["before_level"], 0)
	assert_eq(s["reputation"]["after_level"], 1)
	assert_eq(s["reputation"]["level_name"], "Known")


func test_take_level_up_fires_once() -> void:
	assert_eq(gs.take_level_up(), -1)
	gs.reputation = 20
	assert_eq(gs.take_level_up(), 1)
	assert_eq(gs.take_level_up(), -1)
	gs.reputation = 60
	assert_eq(gs.take_level_up(), 2)


func test_the_night_summary_marks_a_level_up_as_told() -> void:
	gs.reputation = 20
	gs.end_day()
	assert_eq(gs.take_level_up(), -1, "the summary already said so")


# --- Real data

func test_real_reputation_data_is_valid() -> void:
	var db := DataDB.load_from_dir("res://data")
	assert_eq(db.errors, [] as Array[String])
	var levels: Array = db.reputation["levels"]
	assert_eq(levels.size(), 7)
	var all_unlocks := []
	for lv in levels:
		all_unlocks.append_array(lv["unlocks"])
	for id in ["lab", "fish_show", "staff", "gallery_wall"]:
		assert_true(id in all_unlocks, id)
