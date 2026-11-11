extends "res://tests/test_case.gd"
## Fish names and favourites: naming rules, the favourites cap, and the
## promise that a favourite is never sold or handed to a customer.

const F := preload("res://tests/fixtures.gd")

var gs: GameState


func before_each() -> void:
	gs = F.new_game()


func _male() -> Fish:
	return gs.inventory.fish_list().filter(func(f): return f.sex == Fish.MALE)[0]


func _female() -> Fish:
	return gs.inventory.fish_list().filter(func(f): return f.sex == Fish.FEMALE)[0]


## A shop with no fish, where customers always want something.
func _empty_shop(wants_collector: float = 1.0) -> GameState:
	var economy := F.economy()
	economy["customers"]["wants"]["collector"] = wants_collector
	var state := GameState.new_game(DataDB.from_dicts([F.species()], F.items(), [F.template()],
		economy, F.strains(), F.goals(), F.upgrades()), F.rng())
	for f in state.inventory.fish_list():
		state.inventory.remove_fish(f.id)
	return state


func _reload(state: GameState) -> GameState:
	return GameState.from_dict(F.db(), F.rng(99), SaveFile.parse(JSON.stringify(state.to_dict())))


# --- Names

func test_rename_trims_and_stores() -> void:
	var f := _male()
	assert_true(gs.rename_fish(f.id, "  Bubbles \t"))
	assert_eq(f.nickname, "Bubbles")


func test_rename_truncates_to_16_characters() -> void:
	var f := _male()
	gs.rename_fish(f.id, "Sir Reginald Fishington the Third")
	assert_eq(f.nickname.length(), 16)
	assert_eq(f.nickname, "Sir Reginald Fis")


func test_rename_strips_control_characters() -> void:
	var f := _male()
	gs.rename_fish(f.id, "Bu\nbb\u0007les\r")
	assert_eq(f.nickname, "Bubbles")


func test_empty_name_clears_it() -> void:
	var f := _male()
	gs.rename_fish(f.id, "Bubbles")
	assert_true(gs.rename_fish(f.id, "   "))
	assert_eq(f.nickname, "")


func test_rename_unknown_fish_fails() -> void:
	assert_false(gs.rename_fish(9999, "Ghost"))
	assert_false(gs.set_favorite(9999, true))


func test_fry_can_be_named() -> void:
	var fry := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 0))
	assert_true(gs.rename_fish(fry.id, "Tiny"))
	assert_eq(fry.nickname, "Tiny")


func test_fish_named_counts_only_new_names() -> void:
	var f := _male()
	gs.rename_fish(f.id, "Bubbles")
	assert_eq(gs.stat("fish_named"), 1)
	gs.rename_fish(f.id, "Bubs")
	assert_eq(gs.stat("fish_named"), 1, "renaming is not a new pet")
	gs.rename_fish(f.id, "")
	gs.rename_fish(f.id, "Again")
	assert_eq(gs.stat("fish_named"), 2, "a name from nothing counts")
	gs.rename_fish(_female().id, "")
	assert_eq(gs.stat("fish_named"), 2, "an empty name is not a name")


func test_title_shows_the_nickname_with_the_variety() -> void:
	var f := _male()
	var plain := gs.fish_title(f)
	assert_eq(plain, gs.fish_display_name(f))
	gs.rename_fish(f.id, "Bubbles")
	assert_eq(gs.fish_title(f), "Bubbles (%s)" % gs.fish_display_name(f))


func test_records_include_the_name() -> void:
	var f := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 5))
	gs.rename_fish(f.id, "Bubbles")
	var variety := gs.fish_display_name(f)
	gs.sell_fish(f.id)
	assert_true("Bubbles (%s)" % variety in gs.records["best_sale"]["what"])
	assert_true("Bubbles (%s)" % variety in gs.records["rarest_sold"]["what"])


func test_best_bred_record_includes_the_name() -> void:
	var fry := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 0))
	gs.rename_fish(fry.id, "Tiny")
	fry.location = Fish.HOLDING
	gs.inventory.add("food", 20)
	for i in 10:
		gs.end_day()
		gs.open_day()
		if gs.is_adult(fry):
			break
	assert_true(gs.is_adult(fry))
	assert_true("Tiny" in gs.records["best_bred"]["what"])
	assert_eq(fry.nickname, "Tiny", "growing up keeps the name")


# --- Favourites

func test_favorite_toggles_and_counts() -> void:
	var f := _male()
	assert_eq(gs.favorite_count(), 0)
	assert_true(gs.set_favorite(f.id, true))
	assert_true(f.favorite)
	assert_eq(gs.favorite_count(), 1)
	assert_true(gs.set_favorite(f.id, false))
	assert_eq(gs.favorite_count(), 0)


func test_favorites_are_capped_with_a_reason() -> void:
	assert_eq(gs.favorite_max(), 3)
	var fish := []
	for i in 4:
		fish.append(gs.inventory.add_fish(F.fish(Fish.MALE)))
	for i in 3:
		assert_true(gs.set_favorite(fish[i].id, true))
	assert_eq(gs.favorite_blocker(fish[3].id), "You can keep up to 3 favourites.")
	assert_false(gs.set_favorite(fish[3].id, true))
	assert_false(fish[3].favorite)
	assert_true(gs.set_favorite(fish[0].id, false), "un-favouriting always works")
	assert_eq(gs.favorite_blocker(fish[3].id), "")
	assert_true(gs.set_favorite(fish[3].id, true))


func test_cannot_favourite_a_fish_in_an_order_tank() -> void:
	gs.accept_request(gs.make_request())
	assert_true(gs.start_order_tank(0))
	var f := _male()
	assert_true(gs.move_fish(f.id, Fish.order_location(gs.orders[0]["id"])))
	assert_eq(gs.favorite_blocker(f.id), "Take it out of the order tank first")
	assert_false(gs.set_favorite(f.id, true))


func test_a_favourite_cannot_be_moved_into_an_order_tank() -> void:
	gs.accept_request(gs.make_request())
	gs.start_order_tank(0)
	var f := _male()
	gs.set_favorite(f.id, true)
	var loc := Fish.order_location(gs.orders[0]["id"])
	assert_ne(gs.move_blocker(f.id, loc), "")
	assert_false(gs.move_fish(f.id, loc))


# --- Every way a fish leaves for money skips favourites

func test_favourite_is_not_for_sale() -> void:
	var f := gs.inventory.add_fish(F.fish(Fish.MALE))
	assert_true(f in gs.fish_for_sale())
	gs.set_favorite(f.id, true)
	assert_false(f in gs.fish_for_sale())
	assert_false(f in gs.fish_for_customers())


func test_cannot_sell_a_favourite_at_the_counter_or_wholesale() -> void:
	var f := gs.inventory.add_fish(F.fish(Fish.MALE))
	gs.set_favorite(f.id, true)
	var money := gs.money
	assert_eq(gs.sell_fish(f.id), 0)
	assert_eq(gs.sell_fish_wholesale(f.id), 0)
	assert_eq(gs.money, money)
	assert_true(gs.inventory.has_fish(f.id))


func test_a_walk_in_never_asks_for_a_favourite() -> void:
	var state := _empty_shop(0.0)
	var f := state.inventory.add_fish(F.fish(Fish.MALE))
	state.set_favorite(f.id, true)
	for i in 200:
		var kind: String = state._new_customer()["kind"]
		assert_ne(kind, "fish", "nothing to offer")


func test_customer_waiting_for_a_fish_that_becomes_a_favourite() -> void:
	var f := gs.inventory.add_fish(F.fish(Fish.MALE))
	gs.customer = {"kind": "fish", "fish_id": f.id, "name": "Mabel", "waited": 0.0, "patience": 60.0}
	assert_eq(gs.customer_blocker(), "")
	gs.set_favorite(f.id, true)
	assert_ne(gs.customer_blocker(), "")
	assert_eq(gs.serve_customer(), 0)
	assert_true(gs.inventory.has_fish(f.id))
	assert_false(gs.customer_can_breed_order())


func test_collectors_never_buy_a_favourite() -> void:
	var state := _empty_shop(1000.0)
	var f := state.inventory.add_fish(F.fish(Fish.MALE, "grey", 5))
	assert_eq(state.collector_fish(), [f])
	state.set_favorite(f.id, true)
	assert_false(state.is_collector_fish(f))
	assert_eq(state.collector_fish(), [])
	var collectors := 0
	for i in 200:
		var c: Dictionary = state._new_customer()
		if c["kind"] in ["collector", "fish"]:
			collectors += 1
	assert_eq(collectors, 0, "200 customers, none asked for the favourite")
	state.customer = {"kind": "collector", "fish_id": f.id, "name": "Wren", "waited": 0.0, "patience": 60.0}
	assert_ne(state.customer_blocker(), "")
	assert_eq(state.serve_customer(), 0)
	assert_eq(state.stat("collector_sales"), 0)
	assert_true(state.inventory.has_fish(f.id))


func test_serving_200_customers_sells_no_favourites() -> void:
	var state := _empty_shop(1.0)
	var keepers := []
	for i in 3:
		var f := state.inventory.add_fish(F.fish(Fish.MALE, "grey", 5))
		state.set_favorite(f.id, true)
		keepers.append(f)
	for i in 200:
		state._customer_leaves()
		state.customer = state._new_customer()
		state.serve_customer()
	for f in keepers:
		assert_true(state.inventory.has_fish(f.id))
	assert_eq(state.stat("fish_sold"), 0)


func test_backorders_never_hand_over_a_favourite() -> void:
	var f := _male()
	gs.set_favorite(f.id, true)
	var order := {"name": "Mabel", "species_id": f.species_id, "sex": f.sex, "traits": f.traits.duplicate(),
		"price": 20, "due_day": 1, "source": "bred"}
	gs.backorders.append(order)
	assert_eq(gs.backorder_fish(order), null)
	assert_ne(gs.backorder_blocker(0), "")
	assert_eq(gs.fulfil_backorder(0), 0)
	assert_true(gs.inventory.has_fish(f.id))
	gs.set_favorite(f.id, false)
	assert_eq(gs.backorder_fish(order), f, "un-favourite and it is available again")


func test_a_favourite_in_the_display_tank_stays_when_the_tank_is_sold() -> void:
	var f := _male()
	gs.move_fish(f.id, Fish.DISPLAY)
	var with_fish := gs.tank_price(gs.display_tank, true)
	var without := gs.tank_price(gs.display_tank, false)
	assert_true(with_fish > without)
	gs.set_favorite(f.id, true)
	assert_eq(gs.tank_price(gs.display_tank, true), without, "a favourite adds nothing to the price")
	gs.sell_display_tank(true)
	assert_true(gs.inventory.has_fish(f.id))
	assert_eq(f.location, Fish.HOLDING)


func test_a_favourite_is_not_handed_over_with_the_display_tank_for_an_order() -> void:
	gs.accept_request(gs.make_request())
	gs.place_item(gs.display_tank, 2, "fern")
	var f := _male()
	gs.move_fish(f.id, Fish.DISPLAY)
	gs.set_favorite(f.id, true)
	var result := gs.deliver_order(0)
	assert_false(result.is_empty())
	assert_true(gs.inventory.has_fish(f.id))
	assert_eq(f.location, Fish.HOLDING)


func test_a_favourite_still_breeds() -> void:
	var m := _male()
	var w := _female()
	gs.set_favorite(m.id, true)
	gs.set_favorite(w.id, true)
	gs.move_fish(m.id, Fish.BREEDING)
	gs.move_fish(w.id, Fish.BREEDING)
	var before := gs.inventory.fish_list().size()
	for i in 12:
		gs.end_day()
		gs.open_day()
	assert_true(gs.inventory.fish_list().size() > before, "fry were born")
	assert_true(m.favorite and w.favorite)
	assert_eq(gs.breeding_group_fish().size(), 2, "both are still the breeding pair")


func test_a_favourite_can_be_on_display() -> void:
	var f := _male()
	gs.set_favorite(f.id, true)
	assert_true(gs.move_fish(f.id, Fish.DISPLAY))
	assert_true(gs.move_fish(f.id, Fish.BREEDING))


# --- Goals

func test_the_new_goals_follow_their_metrics() -> void:
	assert_eq(gs.goal_value("fish_named"), 0)
	assert_eq(gs.goal_value("favorites"), 0)
	gs.rename_fish(_male().id, "Bubbles")
	gs.set_favorite(_male().id, true)
	assert_eq(gs.goal_value("fish_named"), 1)
	assert_eq(gs.goal_value("favorites"), 1)


func test_real_data_has_the_name_goals_and_favourites_cap() -> void:
	var db := DataDB.load_from_dir("res://data")
	assert_eq(db.errors, [] as Array[String])
	assert_eq(db.goals.size(), 49)
	var ids := db.goals.map(func(g): return g["id"])
	assert_true("first_name" in ids and "favorites_5" in ids)
	assert_eq(int(db.economy["favorites"]["max"]), 24)


func test_economy_needs_a_favourites_cap() -> void:
	var economy := F.economy()
	economy.erase("favorites")
	var db := DataDB.from_dicts([F.species()], F.items(), [F.template()], economy, F.strains(), F.goals(), F.upgrades())
	assert_false(db.errors.is_empty())


# --- Saving

func test_names_and_favourites_survive_save_and_load() -> void:
	var f := _male()
	gs.rename_fish(f.id, "Bubbles")
	gs.set_favorite(f.id, true)
	gs.move_fish(f.id, Fish.BREEDING)
	var loaded := _reload(gs)
	var back := loaded.inventory.get_fish(f.id)
	assert_eq(back.nickname, "Bubbles")
	assert_true(back.favorite)
	assert_eq(back.location, Fish.BREEDING)
	assert_eq(loaded.stat("fish_named"), 1)
	assert_eq(loaded.favorite_count(), 1)


func test_an_old_fish_without_the_keys_loads_plain() -> void:
	var d := _male().to_dict()
	d.erase("nickname")
	d.erase("favorite")
	var f := Fish.from_dict(d)
	assert_eq(f.nickname, "")
	assert_false(f.favorite)
