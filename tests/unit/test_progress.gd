extends "res://tests/test_case.gd"
## Saving and loading, goals, and shop upgrades.

const F := preload("res://tests/fixtures.gd")

var gs: GameState


func before_each() -> void:
	gs = F.new_game()


func _male() -> Fish:
	return gs.inventory.fish_list().filter(func(f): return f.sex == Fish.MALE)[0]


func _female() -> Fish:
	return gs.inventory.fish_list().filter(func(f): return f.sex == Fish.FEMALE)[0]


## Saves to JSON text and loads it back, like the real save file does.
func _reload(state: GameState) -> GameState:
	return GameState.from_dict(F.db(), F.rng(99), SaveFile.parse(JSON.stringify(state.to_dict())))


# --- Saving

func test_normalize_turns_whole_floats_into_ints() -> void:
	var v = SaveFile.normalize({"a": 3.0, "b": 2.5, "c": [1.0, "x", {"d": 7.0}]})
	assert_true(v["a"] is int)
	assert_true(v["b"] is float)
	assert_true(v["c"][0] is int)
	assert_true(v["c"][2]["d"] is int)


func test_a_busy_game_survives_save_and_load() -> void:
	gs.money = 500
	gs.move_fish(_male().id, Fish.BREEDING)
	gs.move_fish(_female().id, Fish.BREEDING)
	gs.buy_breeding_tank()
	gs.buy_upgrade("racks")
	gs.buy_strain("red_delta", Fish.MALE)
	gs.accept_request(gs.make_request())
	gs.start_order_tank(0)
	gs.backorders.append({"name": "Mabel", "item_id": "wood", "price": 11})
	gs.sell_fish(gs.buy_strain("wild", Fish.MALE).id)
	for i in 4:
		gs.end_day()
		gs.open_day()
	gs.check_goals()

	var loaded := _reload(gs)
	assert_true(loaded != null, "loads")
	assert_eq(JSON.stringify(SaveFile.normalize(loaded.to_dict())), JSON.stringify(SaveFile.normalize(gs.to_dict())), "same data after a round trip")
	assert_eq(loaded.day, gs.day)
	assert_eq(loaded.money, gs.money)
	assert_eq(loaded.breeding_tanks.size(), 2)
	assert_eq(loaded.breeding_tank.capacity, gs.breeding_tank.capacity)
	assert_eq(loaded.inventory.fish_list().size(), gs.inventory.fish_list().size())
	assert_eq(loaded.tank_fish(loaded.breeding_tank).size(), gs.tank_fish(gs.breeding_tank).size())
	assert_true(loaded.order_tank(0) != null, "the order tank is kept")
	assert_true(loaded.has_upgrade("racks"))
	assert_true(loaded.is_goal_done("first_sale"))
	assert_true(loaded.clock.is_open, "the day is open after loading")


func test_loaded_game_keeps_playing() -> void:
	gs.move_fish(_male().id, Fish.BREEDING)
	gs.move_fish(_female().id, Fish.BREEDING)
	var loaded := _reload(gs)
	var pair := loaded.breeding_pair()
	assert_eq(pair.size(), 2, "the pair is still together")
	loaded.end_day()
	loaded.open_day()
	var summary := loaded.end_day()
	assert_true(summary["fry_born"] > 0, "they breed after loading")
	var newest: Fish = loaded.inventory.fish_list()[-1]
	assert_true(newest.id > pair[0].id and newest.id > pair[1].id, "new fish get fresh ids")


func test_food_choices_are_saved_and_old_saves_default() -> void:
	assert_true(gs.set_food_choice(Fish.HOLDING, "food"))
	var d := gs.to_dict()
	assert_true(d.has("tank_food"))
	d.erase("tank_food")
	var loaded := GameState.from_dict(F.db(), F.rng(99), SaveFile.parse(JSON.stringify(d)))
	assert_eq(loaded.food_choice(Fish.BREEDING), "food")
	assert_eq(loaded.food_choice(Fish.HOLDING), "food")


func test_save_from_another_version_is_refused() -> void:
	var data := gs.to_dict()
	data["version"] = 999
	assert_true(GameState.from_dict(F.db(), F.rng(), data) == null)
	assert_true(GameState.from_dict(F.db(), F.rng(), {}) == null)


func test_fish_from_a_missing_tank_wait_in_holding() -> void:
	var data := gs.to_dict()
	data["fish"][0]["location"] = "breeding3"
	var loaded := GameState.from_dict(F.db(), F.rng(), data)
	assert_eq(loaded.inventory.fish_list()[0].location, Fish.HOLDING)


func test_save_file_round_trip_on_disk() -> void:
	var path := "user://test_save_%d.json" % randi()
	assert_true(SaveFile.write(path, gs.to_dict()))
	var loaded := GameState.from_dict(F.db(), F.rng(), SaveFile.read(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_true(loaded != null)
	assert_eq(loaded.money, gs.money)
	assert_eq(SaveFile.read("user://no_such_save.json"), {})


# --- Goals

func test_goal_pays_its_reward_once() -> void:
	var money := gs.money
	assert_eq(gs.check_goals(), [], "nothing reached yet")
	var price := gs.sell_fish(_male().id)
	var reached := gs.check_goals()
	assert_eq(reached.size(), 1)
	assert_eq(reached[0]["id"], "first_sale")
	assert_eq(gs.money, money + price + 10)
	assert_true(gs.is_goal_done("first_sale"))
	gs.sell_fish(_female().id)
	assert_eq(gs.check_goals().filter(func(g): return g["id"] == "first_sale"), [], "not paid twice")


func test_goal_progress_is_capped_at_the_target() -> void:
	var goal: Dictionary = gs.db.goals[1]  # own 2 breeding tanks
	assert_eq(gs.goal_progress(goal), 1)
	gs.buy_breeding_tank()
	gs.buy_breeding_tank()
	assert_eq(gs.goal_progress(goal), 2)


func test_best_day_goal_counts_todays_earnings() -> void:
	gs._earn(60, "fish")
	assert_eq(gs.goal_value("best_day"), 60)
	gs.end_day()
	assert_true(gs.is_goal_done("good_day"), "checked at the end of the day")
	gs.open_day()
	assert_eq(gs.goal_value("best_day"), 60, "the record is kept")


func test_end_of_day_summary_lists_goals_reached_today() -> void:
	gs.sell_fish(_male().id)
	var summary := gs.end_day()
	assert_eq(summary["goals"].size(), 1)
	assert_eq(summary["goals"][0]["name"], "First sale")
	assert_eq(summary["money_end"], gs.money)


func test_goal_rewards_are_not_sales() -> void:
	gs.sell_fish(_male().id)
	var earned := gs.earned_today
	gs.check_goals()
	assert_eq(gs.earned_today, earned, "rewards don't count as money earned today")


# --- Upgrades

func test_buying_an_upgrade_costs_money_once() -> void:
	var money := gs.money
	assert_true(gs.buy_upgrade("sign"))
	assert_eq(gs.money, money - 40)
	assert_true(gs.has_upgrade("sign"))
	assert_false(gs.buy_upgrade("sign"), "can't buy it twice")
	assert_eq(gs.upgrade_blocker("sign"), "Already bought.")


func test_upgrade_needs_money_and_its_earlier_tier() -> void:
	assert_eq(gs.upgrade_blocker("big_sign"), "Buy the Sign first.")
	gs.money = 3
	assert_eq(gs.upgrade_blocker("bench"), "You need $2 more.")
	assert_false(gs.buy_upgrade("bench"))


func test_upgrade_effects_add_up() -> void:
	assert_eq(gs.upgrade_effect("customer_speed"), 0.0)
	gs.buy_upgrade("sign")
	gs.buy_upgrade("big_sign")
	assert_eq(gs.upgrade_effect("customer_speed"), 2.0)


func test_order_desk_raises_both_limits() -> void:
	assert_eq(gs.max_orders(), 2)
	assert_eq(gs.max_backorders(), 2)
	gs.buy_upgrade("desk")
	assert_eq(gs.max_orders(), 4)
	assert_eq(gs.max_backorders(), 5)


func test_racks_enlarge_every_breeding_tank() -> void:
	gs.buy_breeding_tank()
	gs.buy_upgrade("racks")
	assert_eq(gs.breeding_tanks[0].capacity, 12)
	assert_eq(gs.breeding_tanks[1].capacity, 12)
	gs.buy_breeding_tank()
	assert_eq(gs.breeding_tanks[2].capacity, 12, "new tanks too")


func test_auto_feeder_feeds_without_food() -> void:
	gs.buy_upgrade("feeder")
	gs.inventory.remove("food", 2)
	var fry := F.fish(Fish.MALE, "grey", 0, 0)
	gs.inventory.add_fish(fry)
	var summary := gs.end_day()
	assert_eq(fry.age_days, 1, "grew without any food")
	assert_eq(summary["food_used"], 0)
	assert_eq(summary["fry_unfed"], 0)


func test_premium_food_gives_better_stars() -> void:
	gs.buy_upgrade("premium")
	for i in 20:
		var fry := F.fish(Fish.MALE, "grey", 0, 2)
		fry.parent_stars = 3.0
		gs.inventory.add_fish(fry)
		gs.inventory.add("food")
		gs.end_day()
		gs.open_day()
		assert_eq(fry.stars, 4, "the fixture's premium odds always nudge up")


func test_wholesale_contract_pays_more() -> void:
	var f := _female()
	var before := gs.wholesale_price(f)
	gs.buy_upgrade("contract")
	assert_eq(gs.wholesale_price(f), roundi(gs.fish_price(f) * 0.5))
	assert_true(gs.wholesale_price(f) > before)
	assert_true(gs.wholesale_price(f) < gs.fish_price(f), "still less than a customer pays")


func test_heaters_shorten_the_wait_between_broods() -> void:
	gs.move_fish(_male().id, Fish.BREEDING)
	gs.move_fish(_female().id, Fish.BREEDING)
	assert_eq(gs.nights_until_brood(), 2)
	gs.buy_upgrade("heaters")
	assert_eq(gs.nights_until_brood(), 1)
	assert_true(gs.end_day()["fry_born"] > 0, "a brood on the first night")


func test_bench_makes_customers_wait_longer() -> void:
	gs.buy_upgrade("bench")
	assert_eq(gs._new_customer()["patience"], 90.0)


func test_signs_bring_customers_sooner() -> void:
	var plain := F.new_game(7)
	plain._customer_leaves()
	var signed := F.new_game(7)
	signed.buy_upgrade("sign")
	signed._customer_leaves()
	assert_almost(signed.minutes_to_customer, plain.minutes_to_customer / 2.0)


func test_real_data_goals_and_upgrades_are_valid() -> void:
	var db := DataDB.load_from_dir("res://data")
	assert_eq(db.errors, [] as Array[String])
	assert_true(db.goals.size() >= 20)
	assert_eq(db.upgrade_order.size(), db.upgrades.size())
	var top: Dictionary = db.goals.filter(func(g): return g["id"] == "all_upgrades")[0]
	assert_eq(int(top["target"]), db.upgrades.size(), "the 'every upgrade' goal matches the upgrade count")


func test_names_and_favourites_round_trip_in_a_full_save() -> void:
	var f := _male()
	gs.rename_fish(f.id, "Bubbles")
	gs.set_favorite(f.id, true)
	var loaded := _reload(gs)
	var back := loaded.inventory.get_fish(f.id)
	assert_eq(back.nickname, "Bubbles")
	assert_true(back.favorite)
	assert_eq(loaded.stat("fish_named"), 1)
	assert_eq(JSON.stringify(SaveFile.normalize(loaded.to_dict())), JSON.stringify(SaveFile.normalize(gs.to_dict())))


func test_reputation_round_trips() -> void:
	gs.reputation = 77
	var loaded := _reload(gs)
	assert_eq(loaded.reputation, 77)
	assert_eq(loaded.reputation_level(), 2)


func test_an_old_save_without_reputation_gets_a_back_fill() -> void:
	gs.stats["fish_sold"] = 10
	gs.stats["orders_delivered"] = 2
	gs.stats["backorders_filled"] = 3
	var d: Dictionary = SaveFile.parse(JSON.stringify(gs.to_dict()))
	d.erase("reputation")
	var loaded := GameState.from_dict(F.db(), F.rng(99), d)
	assert_eq(loaded.reputation, 10 + 20 + 12)
	d["reputation"] = 5
	assert_eq(GameState.from_dict(F.db(), F.rng(99), d).reputation, 5, "a present key is never back-filled")


func test_an_old_save_without_names_loads() -> void:
	var d: Dictionary = SaveFile.parse(JSON.stringify(gs.to_dict()))
	for fish_data in d["fish"]:
		fish_data.erase("nickname")
		fish_data.erase("favorite")
	var loaded := GameState.from_dict(F.db(), F.rng(99), d)
	assert_true(loaded != null)
	for f in loaded.inventory.fish_list():
		assert_eq(f.nickname, "")
		assert_false(f.favorite)


func test_regulars_progress_is_saved_and_old_saves_load() -> void:
	gs.regulars_state["mrs_pike"] = {"met": true, "visits": 3, "loyalty": 7, "purchases": 4, "last_day": 2}
	var loaded := _reload(gs)
	assert_eq(loaded.regulars_state["mrs_pike"], {"met": true, "visits": 3, "loyalty": 7, "purchases": 4, "last_day": 2})
	var old := SaveFile.parse(JSON.stringify(gs.to_dict()))
	old.erase("regulars_state")
	assert_eq(GameState.from_dict(F.db(), F.rng(99), old).regulars_state, {})
