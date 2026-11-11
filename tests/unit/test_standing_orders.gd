extends "res://tests/test_case.gd"
## Standing orders: the shop reorders Market items by itself at the normal price.

const F := preload("res://tests/fixtures.gd")

var gs: GameState


func before_each() -> void:
	gs = F.new_game()
	gs.set_order_money_floor(0)
	gs.inventory.remove("food", gs.inventory.count("food"))


func _reload(state: GameState) -> GameState:
	return GameState.from_dict(F.db(), F.rng(99), SaveFile.parse(JSON.stringify(state.to_dict())))


## Ends the day and opens the next one, like the Game autoload does.
func _next_day() -> Dictionary:
	var summary := gs.end_day()
	gs.open_day()
	return summary


func _fry() -> Fish:
	return gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 0))


# --- Setting up -----------------------------------------------------------------

func test_defaults_when_unset() -> void:
	var rule := gs.standing_order("food")
	assert_false(rule["enabled"])
	assert_eq(rule["quantity"], 5)
	assert_eq(rule["reorder_at"], 2)
	assert_eq(gs.pending_quantity("food"), 0)
	assert_eq(gs.standing_orders_active(), 0)


func test_set_and_read_back() -> void:
	assert_true(gs.set_standing_order("food", true, 3, 10))
	var rule := gs.standing_order("food")
	assert_true(rule["enabled"])
	assert_eq(rule["reorder_at"], 3)
	assert_eq(rule["quantity"], 10)
	assert_eq(gs.standing_orders_active(), 1)
	gs.set_standing_order("food", false, 3, 10)
	assert_eq(gs.standing_orders_active(), 0)
	assert_eq(gs.standing_order("food")["quantity"], 10, "a switched-off rule keeps its numbers")


func test_numbers_are_clamped() -> void:
	gs.set_standing_order("food", true, 999, 999)
	assert_eq(gs.standing_order("food")["reorder_at"], 50)
	assert_eq(gs.standing_order("food")["quantity"], 50)
	gs.set_standing_order("food", true, -4, 0)
	assert_eq(gs.standing_order("food")["reorder_at"], 0)
	assert_eq(gs.standing_order("food")["quantity"], 1)


func test_unknown_items_and_fish_are_rejected() -> void:
	assert_false(gs.set_standing_order("nothing", true, 1, 1))
	assert_false(gs.set_standing_order("wild", true, 1, 1), "fish strains are never auto-ordered")
	assert_true(gs.standing_orders.is_empty())


func test_money_floor() -> void:
	assert_eq(F.new_game().order_money_floor, 5, "starts at the data default")
	gs.set_order_money_floor(-10)
	assert_eq(gs.order_money_floor, 0)
	gs.set_order_money_floor(30)
	assert_eq(gs.order_money_floor, 30)


func test_cost_matches_buy_item() -> void:
	gs.set_standing_order("castle", true, 1, 3)
	var before := gs.money
	assert_true(gs.buy_item("castle", 3))
	assert_eq(before - gs.money, gs.standing_order_cost("castle"))
	assert_eq(gs.standing_order_cost("castle"), 24)
	assert_eq(gs.standing_order_cost("nothing"), 0)


# --- Ordering -----------------------------------------------------------------------

func test_orders_when_at_or_below_level() -> void:
	gs.set_standing_order("food", true, 2, 10)
	gs.inventory.add("food", 3)
	assert_eq(gs.process_standing_orders().size(), 0, "3 is above 2")
	gs.inventory.remove("food", 1)
	var placed := gs.process_standing_orders()
	assert_eq(placed.size(), 1, "2 is at the level")
	assert_eq(placed[0], {"item_id": "food", "name": "Food", "quantity": 10, "cost": 20})
	assert_eq(gs.pending_quantity("food"), 10)


func test_payment_path_and_stats() -> void:
	gs.set_standing_order("food", true, 2, 10)
	var money := gs.money
	var spent := gs.stat("total_spent")
	var earned := gs.stat("total_earned")
	gs.process_standing_orders()
	assert_eq(gs.money, money - 20)
	assert_eq(gs.stat("total_spent"), spent + 20)
	assert_eq(gs.stat("total_earned"), earned, "an order is a spend, not an earning")
	assert_eq(gs.day_log["spent"], 20)
	assert_eq(gs.inventory.count("food"), 0, "nothing arrives until morning")


func test_pending_stops_a_second_order() -> void:
	gs.set_standing_order("food", true, 2, 10)
	gs.process_standing_orders()
	var money := gs.money
	assert_eq(gs.process_standing_orders().size(), 0)
	assert_eq(gs.money, money)
	assert_eq(gs.deliveries.size(), 1)


func test_stock_plus_pending_counts() -> void:
	gs.set_standing_order("food", true, 5, 4)
	gs.inventory.add("food", 2)
	assert_eq(gs.process_standing_orders().size(), 1)  # 2 <= 5
	assert_eq(gs.process_standing_orders().size(), 0)  # 2 + 4 = 6 > 5


func test_placed_decorations_do_not_count_as_stock() -> void:
	gs.set_standing_order("fern", true, 0, 2)
	gs.inventory.remove("fern", gs.inventory.count("fern"))
	gs.inventory.add("fern", 1)
	assert_eq(gs.process_standing_orders().size(), 0, "one spare fern is above 0")
	assert_true(gs.place_item(gs.display_tank, 0, "fern"), "placing it uses the last spare, which triggers the check")
	assert_eq(gs.pending_quantity("fern"), 2)


func test_selling_triggers_a_check() -> void:
	gs.set_standing_order("castle", true, 0, 2)
	gs.inventory.add("castle", 1)
	assert_eq(gs.pending_quantity("castle"), 0)
	assert_true(gs.sell_item("castle") > 0)
	assert_eq(gs.pending_quantity("castle"), 2)


func test_insufficient_money_waits_quietly() -> void:
	gs.set_standing_order("food", true, 2, 10)
	gs.money = 15
	assert_eq(gs.process_standing_orders().size(), 0)
	assert_eq(gs.money, 15)
	assert_eq(gs.deliveries.size(), 0)
	gs.money = 20
	gs.set_order_money_floor(0)
	assert_eq(gs.process_standing_orders().size(), 1, "tries again later, exactly enough is fine")
	assert_eq(gs.money, 0, "never debt")


func test_money_floor_blocks_orders() -> void:
	gs.set_standing_order("food", true, 2, 10)
	gs.set_order_money_floor(50)
	gs.money = 69
	assert_eq(gs.process_standing_orders().size(), 0, "would leave $49")
	gs.money = 70
	assert_eq(gs.process_standing_orders().size(), 1, "leaves exactly $50")
	assert_eq(gs.money, 50)


func test_disabled_rules_do_nothing() -> void:
	gs.set_standing_order("food", false, 2, 10)
	assert_eq(gs.process_standing_orders().size(), 0)


func test_multiple_items_in_one_check() -> void:
	gs.set_standing_order("food", true, 2, 10)
	gs.set_standing_order("sand", true, 0, 2)
	gs.inventory.remove("sand", gs.inventory.count("sand"))
	var placed := gs.process_standing_orders()
	assert_eq(placed.size(), 2)
	assert_eq(gs.money, 100 - 20 - 8)


# --- Deliveries ----------------------------------------------------------------------

func test_daytime_order_arrives_next_morning() -> void:
	gs.set_standing_order("food", true, 2, 10)
	gs.process_standing_orders()
	assert_eq(gs.inventory.count("food"), 0)
	_next_day()
	assert_eq(gs.inventory.count("food"), 10)
	assert_eq(gs.pending_quantity("food"), 0)
	assert_eq(gs.stat("items_delivered"), 10)
	assert_eq(gs.last_deliveries, [{"item_id": "food", "name": "Food", "quantity": 10}])


func test_night_order_arrives_next_morning() -> void:
	gs.set_standing_order("food", true, 2, 10)
	var day_before := gs.day
	var summary := gs.end_day()
	assert_eq(gs.day, day_before + 1)
	assert_eq(summary["standing_orders"]["placed"].size(), 1, "noticed at the end of the night")
	assert_eq(summary["standing_orders"]["placed"][0]["cost"], 20)
	assert_eq(summary["log"]["spent"], 20, "shows in the day's Market spending")
	assert_eq(gs.inventory.count("food"), 0)
	gs.open_day()
	assert_eq(gs.inventory.count("food"), 10)
	assert_eq(gs.last_deliveries.size(), 1)


func test_night_food_use_is_noticed() -> void:
	gs.inventory.add("food", 3)
	gs.set_standing_order("food", true, 2, 10)
	_fry()
	var summary := gs.end_day()  # the fry eat one portion: 3 -> 2, which is at the level
	assert_eq(summary["food_used"], 1)
	assert_eq(gs.pending_quantity("food"), 10)


func test_no_summary_block_without_orders() -> void:
	var summary := _next_day()
	assert_false(summary.has("standing_orders"))
	assert_eq(gs.last_deliveries, [])


func test_delivered_stock_is_enough_until_it_runs_low_again() -> void:
	gs.set_standing_order("castle", true, 2, 10)
	gs.inventory.add("castle", 1)
	gs.process_standing_orders()
	_next_day()
	assert_eq(gs.inventory.count("castle"), 11)
	assert_eq(gs.pending_quantity("castle"), 0, "11 is above the level, so no new order")
	for i in 8:
		gs.sell_item("castle")
	assert_eq(gs.pending_quantity("castle"), 0, "3 left is still above the level")
	gs.sell_item("castle")
	assert_eq(gs.inventory.count("castle"), 2)
	assert_eq(gs.pending_quantity("castle"), 10, "2 left is at the level: ordered")


# --- Saving ---------------------------------------------------------------------------

func test_save_round_trip_with_pending_delivery() -> void:
	gs.set_standing_order("food", true, 3, 12)
	gs.set_standing_order("sand", false, 1, 4)
	gs.set_order_money_floor(25)
	gs.process_standing_orders()
	var loaded := _reload(gs)
	assert_eq(loaded.standing_order("food"), gs.standing_order("food"))
	assert_eq(loaded.standing_order("sand"), gs.standing_order("sand"))
	assert_eq(loaded.order_money_floor, 25)
	assert_eq(loaded.pending_quantity("food"), 12)
	assert_eq(loaded.deliveries, gs.deliveries)
	loaded.end_day()
	loaded.open_day()
	assert_eq(loaded.inventory.count("food"), 12)


func test_old_save_loads_with_defaults() -> void:
	var data := SaveFile.parse(JSON.stringify(gs.to_dict()))
	for key in ["standing_orders", "order_money_floor", "deliveries"]:
		data.erase(key)
	var loaded := GameState.from_dict(F.db(), F.rng(5), data)
	assert_true(loaded != null)
	assert_true(loaded.standing_orders.is_empty())
	assert_eq(loaded.order_money_floor, 5, "the data default")
	assert_true(loaded.deliveries.is_empty())
	assert_eq(loaded.process_standing_orders().size(), 0)


func test_save_drops_unknown_items() -> void:
	var data := SaveFile.parse(JSON.stringify(gs.to_dict()))
	data["standing_orders"] = {"ghost": {"enabled": true, "reorder_at": 1, "quantity": 1}}
	data["deliveries"] = [{"item_id": "ghost", "quantity": 3, "arrive_day": 1}]
	var loaded := GameState.from_dict(F.db(), F.rng(5), data)
	assert_true(loaded.standing_orders.is_empty())
	assert_true(loaded.deliveries.is_empty())


# --- Goals, stats and data -------------------------------------------------------------

func test_goal_metrics() -> void:
	assert_eq(gs.goal_value("standing_orders_active"), 0)
	gs.set_standing_order("food", true, 2, 10)
	gs.set_standing_order("sand", true, 2, 10)
	assert_eq(gs.goal_value("standing_orders_active"), 2)
	assert_eq(gs.goal_value("items_delivered"), 0)
	gs.process_standing_orders()
	_next_day()
	assert_eq(gs.goal_value("items_delivered"), 20)


func test_real_data_has_the_goals_and_is_valid() -> void:
	var real := DataDB.load_from_dir("res://data")
	assert_eq(real.errors, [])
	var found := {}
	for g in real.goals:
		found[g["id"]] = g
	assert_eq(found["first_standing_order"]["metric"], "standing_orders_active")
	assert_eq(int(found["first_standing_order"]["reward"]), 20)
	assert_eq(int(found["items_delivered_50"]["target"]), 50)
	assert_eq(int(found["items_delivered_50"]["reward"]), 60)


func test_bad_standing_order_data_is_reported() -> void:
	var economy := F.economy()
	economy["standing_orders"] = {"max_quantity": 0, "max_level": 50, "default_floor": -1, "delivery_days": 1}
	var bad := DataDB.from_dicts([F.species()], F.items(), [F.template()], economy, F.strains(), F.goals(),
		F.upgrades(), [], [], F.reputation(), F.shows(), F.staff())
	assert_true(bad.errors.any(func(e): return "standing_orders" in e and "max_quantity" in e))
	assert_true(bad.errors.any(func(e): return "default_floor" in e))


# --- Food hint -------------------------------------------------------------------------

func test_food_use_hint() -> void:
	for f in gs.inventory.fish_list():
		gs.inventory.remove_fish(f.id)
	assert_eq(gs.food_use_per_night(), 0, "no fry, no food used")
	_fry()
	assert_eq(gs.food_use_per_night(), 1, "fry in holding")
	var tank_fry := F.fish(Fish.FEMALE, "grey", 0, 0)
	gs.inventory.add_fish(tank_fry)
	gs.move_fish(tank_fry.id, Fish.BREEDING)
	assert_eq(gs.food_use_per_night(), 2, "plus the breeding tank")


# --- Staff overlap and a long run ------------------------------------------------------

func test_feeder_and_standing_order_do_not_double_charge() -> void:
	gs.reputation = 100
	gs.hire_staff("feeder")
	gs.money = 100
	gs.set_standing_order("food", true, 2, 10)
	_fry()
	# Day 1: no food, so the order goes out in the morning check... (food 0 <= 2)
	gs.process_standing_orders()
	assert_eq(gs.pending_quantity("food"), 10)
	var spent_before := gs.stat("total_spent")
	var summary := gs.end_day()  # the Feeder buys one portion at the normal price
	assert_eq(summary["food_used"], 1)
	assert_eq(gs.stat("total_spent") - spent_before, 2 + 5, "one portion ($2) plus the wage ($5), no second order")
	assert_eq(gs.pending_quantity("food"), 10)
	gs.open_day()
	assert_eq(gs.inventory.count("food"), 10)
	assert_eq(gs.pending_quantity("food"), 0, "10 is above the level of 2, so nothing more is ordered")


func test_stock_clerk_and_standing_order_both_work() -> void:
	gs.reputation = 100
	gs.hire_staff("stocker")
	gs.money = 100
	gs.set_standing_order("food", true, 1, 8)
	var summary := gs.end_day()
	# The clerk tops up to 5 ($10) and then the stock is above the level, so no order.
	assert_eq(gs.inventory.count("food"), 5)
	assert_false(summary.has("standing_orders"))


func test_sixty_day_loop_money_never_negative() -> void:
	gs.money = 60
	gs.set_order_money_floor(10)
	gs.set_standing_order("food", true, 4, 6)
	gs.set_standing_order("sand", true, 1, 3)
	gs.inventory.add("food", 4)
	var limits := {"food": 4 + 6, "sand": 1 + 3}
	var ordered := 0
	for day_number in 60:
		# A little trade each day, standing in for customers.
		gs.money += 8
		# Fry that need feeding, sold off again by the wholesaler.
		for i in 2:
			gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 0))
		if day_number % 3 == 0 and gs.inventory.count("sand") > 0:
			gs.sell_item("sand")
		_next_day()
		for f in gs.inventory.fish_list():
			gs.sell_fish_wholesale(f.id)
		assert_true(gs.money >= 0, "never in debt (day %d)" % day_number)
		for id in limits:
			assert_true(gs.inventory.count(id) + gs.pending_quantity(id) <= limits[id],
				"%s stays within level + quantity (day %d)" % [id, day_number])
		ordered = gs.stat("items_delivered")
	assert_true(ordered > 0, "deliveries really happened")
