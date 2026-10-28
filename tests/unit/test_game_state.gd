extends "res://tests/test_case.gd"

const F := preload("res://tests/fixtures.gd")

var gs: GameState


func before_each() -> void:
	gs = F.new_game()


func _male() -> Fish:
	return gs.inventory.fish_list().filter(func(f): return f.sex == Fish.MALE)[0]


func _female() -> Fish:
	return gs.inventory.fish_list().filter(func(f): return f.sex == Fish.FEMALE)[0]


func _pair_in_breeding_tank() -> void:
	gs.move_fish(_male().id, Fish.BREEDING)
	gs.move_fish(_female().id, Fish.BREEDING)


func _fry() -> Array:
	return gs.inventory.fish_list(Fish.BREEDING).filter(func(f): return not gs.is_adult(f))


# --- Setup

func test_new_game_uses_starting_state() -> void:
	assert_eq(gs.money, 100)
	assert_eq(gs.day, 1)
	assert_eq(gs.inventory.count("stone"), 2)
	assert_eq(gs.inventory.fish_list(Fish.HOLDING).size(), 2)
	assert_true(gs.is_adult(_male()), "starting fish are adults")
	assert_ne(gs.display_tank, null)
	assert_eq(gs.display_tank.capacity, 4)
	assert_eq(gs.breeding_tank.capacity, 8)
	assert_true(gs.clock.is_open)


func test_starting_layout_and_fish_locations() -> void:
	var economy := F.economy()
	economy["starting_state"]["display_tank_layout"] = {"substrate": "sand", "slots": ["wood", "", "fern"]}
	for f in economy["starting_state"]["fish"]:
		f["location"] = Fish.BREEDING
	var g := GameState.new_game(DataDB.from_dicts([F.species()], F.items(), [F.template()], economy), F.rng())
	assert_eq(g.display_tank.placed_item_ids(), ["sand", "wood", "fern"])
	assert_eq(g.inventory.count("sand"), 1, "starter layout is free, not taken from stock")
	assert_eq(g.breeding_tank.fish_ids.size(), 2)
	assert_eq(g.inventory.fish_list(Fish.BREEDING).size(), 2)


func test_bad_starting_layout_is_reported() -> void:
	var economy := F.economy()
	economy["starting_state"]["display_tank_layout"] = {"substrate": "stone", "slots": ["sand"]}
	var db := DataDB.from_dicts([F.species()], F.items(), [F.template()], economy)
	assert_has(db.errors, "economy/starting_state: layout substrate 'stone' is not a substrate")
	assert_has(db.errors, "economy/starting_state: layout item 'sand' can't go in a slot")


# --- Buying

func test_buy_item_costs_money_and_adds_stock() -> void:
	assert_true(gs.buy_item("stone", 3))
	assert_eq(gs.money, 94)
	assert_eq(gs.inventory.count("stone"), 5)


func test_cannot_buy_without_money() -> void:
	gs.money = 1
	assert_false(gs.buy_item("castle"))
	assert_eq(gs.money, 1)
	assert_eq(gs.inventory.count("castle"), 0)


func test_strain_costs_come_from_traits_and_stars() -> void:
	assert_eq(gs.strain_cost("wild"), 6, "2 stars: customers pay 8, the Market charges 70%")
	assert_eq(gs.strain_cost("orange"), 7, "3 stars: 10 * 0.7")
	assert_eq(gs.strain_cost("red_delta"), 24, "4 stars, two rare traits: 34 * 0.7")


func test_strains_are_grouped_by_tier_cheapest_first() -> void:
	assert_eq(gs.market_tiers().size(), 2)
	assert_eq(gs.strains_in_tier(1), ["wild", "orange"])
	assert_eq(gs.strains_in_tier(2), ["red_delta"])
	assert_eq(gs.strains_in_tier(9), [])


func test_buy_strain() -> void:
	var f := gs.buy_strain("red_delta", Fish.FEMALE)
	assert_ne(f, null)
	assert_eq(gs.money, 100 - 24)
	assert_eq(f.sex, Fish.FEMALE)
	assert_eq(f.stars, 4)
	assert_eq(f.traits["body_color"], "red")
	assert_eq(f.traits["tail_shape"], "delta")
	assert_eq(f.traits["pattern"], "plain", "unfixed traits are random common values")
	assert_eq(f.location, Fish.HOLDING)
	assert_true(gs.is_adult(f))
	assert_eq(gs.fish_display_name(f), "Red Delta")
	assert_true(gs.inventory.has_fish(f.id))


func test_cannot_buy_strain_without_money() -> void:
	gs.money = 20
	assert_eq(gs.buy_strain("red_delta", Fish.MALE), null)
	assert_eq(gs.money, 20)
	assert_eq(gs.inventory.fish_list().size(), 2)


func test_buy_strain_rejects_bad_input() -> void:
	assert_eq(gs.buy_strain("nope", Fish.MALE), null)
	assert_eq(gs.buy_strain("wild", "robot"), null)
	assert_eq(gs.money, 100)


func test_home_bred_fish_use_species_name() -> void:
	assert_eq(gs.fish_display_name(_male()), "Guppy")


# --- Selling

func test_sell_item() -> void:
	assert_eq(gs.sell_item("stone"), 5)
	assert_eq(gs.money, 105)
	assert_eq(gs.earned_today, 5)
	assert_eq(gs.inventory.count("stone"), 1)


func test_cannot_sell_what_you_dont_have() -> void:
	assert_eq(gs.sell_item("castle"), 0)
	assert_eq(gs.money, 100)


func test_sell_adult_fish() -> void:
	var m := _male()
	gs.move_fish(m.id, Fish.DISPLAY)
	assert_eq(gs.sell_fish(m.id), 8, "2 stars: 10 * 0.8")
	assert_false(gs.inventory.has_fish(m.id))
	assert_eq(gs.display_tank.fish_ids, [])


func test_cannot_sell_fry() -> void:
	var fry := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 1))
	assert_eq(gs.sell_fish(fry.id), 0)
	assert_true(gs.inventory.has_fish(fry.id))


func test_wholesale_pays_less_than_customers() -> void:
	var f := _female()  # 4 stars: customers pay 15
	assert_eq(gs.fish_price(f), 15)
	assert_eq(gs.wholesale_price(f), 6, "40% of 15")
	gs.move_fish(f.id, Fish.BREEDING)
	assert_eq(gs.sell_fish_wholesale(f.id), 6)
	assert_eq(gs.money, 106)
	assert_false(gs.inventory.has_fish(f.id))
	assert_eq(gs.breeding_tank.fish_ids, [], "removed from its tank")


func test_fry_can_be_sold_wholesale_for_a_token_price() -> void:
	var fry := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 1))
	gs.move_fish(fry.id, Fish.BREEDING)
	assert_eq(gs.sell_fish(fry.id), 0, "customers don't buy fry")
	assert_eq(gs.sell_fish_wholesale(fry.id), 1)
	assert_false(gs.inventory.has_fish(fry.id))


func test_wholesale_unknown_fish_does_nothing() -> void:
	assert_eq(gs.sell_fish_wholesale(999), 0)
	assert_eq(gs.money, 100)


func test_sell_display_tank_with_fish() -> void:
	gs.set_substrate(gs.display_tank, "sand")
	var m := _male()
	gs.move_fish(m.id, Fish.DISPLAY)
	var expected := gs.tank_price(gs.display_tank, true)
	assert_eq(gs.sell_display_tank(true), expected)
	assert_eq(gs.display_tank, null)
	assert_false(gs.inventory.has_fish(m.id))
	assert_eq(gs.inventory.count("sand"), 0, "decor leaves with the tank")


func test_sell_display_tank_without_fish_keeps_them() -> void:
	var m := _male()
	gs.move_fish(m.id, Fish.DISPLAY)
	var with_fish := gs.tank_price(gs.display_tank, true)
	var without := gs.tank_price(gs.display_tank, false)
	assert_true(with_fish > without)
	assert_eq(gs.sell_display_tank(false), without)
	assert_true(gs.inventory.has_fish(m.id))
	assert_eq(m.location, Fish.HOLDING)


func test_install_new_display_tank_from_stock() -> void:
	assert_false(gs.install_display_tank("tank"), "stand is occupied")
	gs.sell_display_tank(false)
	assert_true(gs.install_display_tank("tank"))
	assert_eq(gs.inventory.count("tank"), 0)
	gs.sell_display_tank(false)
	assert_false(gs.install_display_tank("tank"), "none left in stock")


# --- Aquascaping

func test_place_item_uses_stock() -> void:
	assert_true(gs.place_item(gs.display_tank, 0, "fern"))
	assert_eq(gs.inventory.count("fern"), 1)
	assert_eq(gs.display_tank.slots[0], "fern")


func test_cannot_place_without_stock() -> void:
	assert_false(gs.place_item(gs.display_tank, 0, "castle"))
	assert_eq(gs.display_tank.slots[0], "")


func test_replacing_an_item_returns_the_old_one() -> void:
	gs.place_item(gs.display_tank, 0, "fern")
	assert_true(gs.place_item(gs.display_tank, 0, "stone"))
	assert_eq(gs.inventory.count("fern"), 2)
	assert_eq(gs.inventory.count("stone"), 1)


func test_take_item_returns_it_to_stock() -> void:
	gs.place_item(gs.display_tank, 3, "stone")
	assert_true(gs.take_item(gs.display_tank, 3))
	assert_eq(gs.inventory.count("stone"), 2)
	assert_false(gs.take_item(gs.display_tank, 3))


func test_substrate_uses_stock() -> void:
	assert_true(gs.set_substrate(gs.display_tank, "sand"))
	assert_eq(gs.inventory.count("sand"), 0)
	assert_false(gs.set_substrate(gs.display_tank, "stone"), "rocks aren't substrate")
	assert_true(gs.take_substrate(gs.display_tank))
	assert_eq(gs.inventory.count("sand"), 1)


# --- Moving fish

func test_move_fish_between_places() -> void:
	var m := _male()
	assert_true(gs.move_fish(m.id, Fish.BREEDING))
	assert_eq(gs.breeding_tank.fish_ids, [m.id])
	assert_true(gs.move_fish(m.id, Fish.DISPLAY))
	assert_eq(gs.breeding_tank.fish_ids, [])
	assert_eq(gs.display_tank.fish_ids, [m.id])
	assert_true(gs.move_fish(m.id, Fish.HOLDING))
	assert_eq(gs.display_tank.fish_ids, [])


func test_fry_cannot_go_on_display() -> void:
	var fry := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 0))
	assert_false(gs.move_fish(fry.id, Fish.DISPLAY))
	assert_true(gs.move_fish(fry.id, Fish.BREEDING))


func test_move_blocker_explains_why() -> void:
	var fry := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 0))
	assert_eq(gs.move_blocker(fry.id, Fish.DISPLAY), "Fry stay in the back room until they grow up.")
	assert_eq(gs.move_blocker(fry.id, Fish.HOLDING), "Already there.")
	assert_eq(gs.move_blocker(fry.id, Fish.BREEDING), "")
	gs.sell_display_tank(false)
	assert_eq(gs.move_blocker(_male().id, Fish.DISPLAY), "There's no tank on display.")
	assert_false(gs.can_move_fish(_male().id, Fish.DISPLAY))


func test_tank_capacity_is_respected() -> void:
	for i in 4:
		var f := gs.inventory.add_fish(F.fish(Fish.MALE))
		assert_true(gs.move_fish(f.id, Fish.DISPLAY))
	assert_false(gs.move_fish(_male().id, Fish.DISPLAY), "display tank holds 4")


# --- Night: breeding and growth

func test_pair_breeds_every_other_night() -> void:
	_pair_in_breeding_tank()
	assert_eq(gs.end_day()["fry_born"], 0, "night 1")
	var s := gs.end_day()
	assert_between(s["fry_born"], 2, 4, "night 2")
	assert_eq(_fry().size(), s["fry_born"])
	assert_eq(gs.day, 3)


func test_nights_until_brood_counts_down() -> void:
	assert_eq(gs.nights_until_brood(), -1, "no pair yet")
	_pair_in_breeding_tank()
	assert_eq(gs.nights_until_brood(), 2)
	gs.end_day()
	assert_eq(gs.nights_until_brood(), 1)
	gs.end_day()
	assert_eq(gs.nights_until_brood(), 2, "resets after a brood")


func test_food_count() -> void:
	assert_eq(gs.food_count(), 2)
	gs.inventory.add("food", 3)
	assert_eq(gs.food_count(), 5)


func test_no_breeding_without_a_pair() -> void:
	gs.move_fish(_male().id, Fish.BREEDING)
	for i in 4:
		assert_eq(gs.end_day()["fry_born"], 0)


func test_fry_grow_into_adults_when_fed() -> void:
	gs.inventory.add("food", 10)
	_pair_in_breeding_tank()
	gs.end_day()
	gs.end_day()
	var fry := _fry()
	assert_false(fry.is_empty())
	for i in 3:
		gs.end_day()
	for f in fry:
		assert_true(gs.is_adult(f))
		assert_between(f.stars, 1, 5)
		assert_true(f.fed_every_night)


func test_unfed_fry_pause_but_never_die() -> void:
	gs.inventory.remove("food", gs.inventory.count("food"))
	var fry := gs.inventory.add_fish(F.fish(Fish.FEMALE, "grey", 0, 0))
	gs.move_fish(fry.id, Fish.BREEDING)
	var s := gs.end_day()
	assert_eq(s["fry_unfed"], 1)
	assert_eq(fry.age_days, 0)
	assert_false(fry.fed_every_night)
	assert_true(gs.inventory.has_fish(fry.id))
	gs.inventory.add("food", 1)
	gs.end_day()
	assert_eq(fry.age_days, 1, "grows again once there's food")


func test_food_is_only_used_when_there_are_fry() -> void:
	_pair_in_breeding_tank()
	assert_eq(gs.end_day()["food_used"], 0)
	assert_eq(gs.inventory.count("food"), 2)


func test_brood_is_capped_by_tank_capacity() -> void:
	gs.inventory.add("food", 50)
	_pair_in_breeding_tank()
	for i in 20:
		gs.end_day()
	assert_true(gs.breeding_tank.fish_ids.size() <= 8)
	assert_eq(gs.inventory.fish_list(Fish.BREEDING).size(), gs.breeding_tank.fish_ids.size())


# --- Requests

func test_accept_is_limited_by_max_orders() -> void:
	assert_true(gs.accept_request(gs.make_request()))
	assert_true(gs.accept_request(gs.make_request()))
	assert_false(gs.accept_request(gs.make_request()), "max 2 orders in fixtures")


func test_deliver_order_pays_and_removes_tank() -> void:
	gs.accept_request(gs.make_request())
	gs.place_item(gs.display_tank, 2, "fern")
	var m := _male()
	gs.move_fish(m.id, Fish.DISPLAY)
	var preview := gs.preview_delivery(0)
	var result := gs.deliver_order(0)
	assert_eq(result["payout"], preview["payout"])
	assert_eq(gs.money, 100 + result["payout"])
	assert_true(result["payout"] >= result["tank_value"] + 25)
	assert_eq(gs.display_tank, null)
	assert_eq(gs.orders.size(), 0)
	assert_false(gs.inventory.has_fish(m.id))


func test_cannot_deliver_without_a_tank() -> void:
	gs.accept_request(gs.make_request())
	gs.sell_display_tank(false)
	assert_eq(gs.deliver_order(0), {})
	assert_eq(gs.orders.size(), 1)


# --- Customers

func _wait_for_customer() -> void:
	for i in 100:
		if gs.tick_customers(5.0):
			return


func test_first_customer_arrives_soon_after_opening() -> void:
	assert_true(gs.customer.is_empty())
	assert_false(gs.tick_customers(5.0))
	assert_true(gs.tick_customers(5.0), "first customer after 10 minutes")
	assert_false(gs.customer.is_empty())


func test_no_customers_while_closed() -> void:
	gs.end_day()
	assert_false(gs.tick_customers(500.0))
	assert_true(gs.customer.is_empty())


func test_customers_leave_after_their_patience_runs_out() -> void:
	_wait_for_customer()
	assert_false(gs.tick_customers(30.0))
	assert_true(gs.tick_customers(30.0), "patience is 60 minutes in fixtures")
	assert_true(gs.customer.is_empty())
	assert_true(gs.minutes_to_customer > 0.0)


func test_serving_a_fish_customer() -> void:
	var m := _male()
	gs.move_fish(m.id, Fish.DISPLAY)
	gs.customer = {"kind": "fish", "fish_id": m.id, "name": "Mabel", "waited": 0.0, "patience": 60.0}
	assert_eq(gs.customer_price(), 8)
	assert_eq(gs.serve_customer(), 8)
	assert_eq(gs.money, 108)
	assert_true(gs.customer.is_empty())
	assert_false(gs.inventory.has_fish(m.id))


func test_serving_an_item_customer() -> void:
	gs.customer = {"kind": "item", "item_id": "fern", "name": "Mabel", "waited": 0.0, "patience": 60.0}
	assert_eq(gs.serve_customer(), 6)
	assert_eq(gs.inventory.count("fern"), 1)


func test_serving_a_tank_customer() -> void:
	gs.place_item(gs.display_tank, 0, "fern")
	var value := gs.tank_price(gs.display_tank, true)
	gs.customer = {"kind": "tank", "with_fish": true, "name": "Mabel", "waited": 0.0, "patience": 60.0}
	assert_eq(gs.serve_customer(), value)
	assert_eq(gs.display_tank, null)


func test_cannot_serve_when_the_thing_is_gone() -> void:
	gs.customer = {"kind": "item", "item_id": "castle", "name": "Mabel", "waited": 0.0, "patience": 60.0}
	assert_eq(gs.customer_blocker(), "That's out of stock now.")
	assert_eq(gs.serve_customer(), 0)
	assert_false(gs.customer.is_empty(), "they wait; the player can say no")
	gs.decline_customer()
	assert_true(gs.customer.is_empty())
	assert_eq(gs.money, 100, "declining costs nothing")


func test_request_customer_accept_adds_an_order() -> void:
	gs.customer = {"kind": "request", "request": gs.make_request(), "name": "Mabel", "waited": 0.0, "patience": 60.0}
	assert_eq(gs.serve_customer(), 0, "requests are accepted, not sold")
	assert_true(gs.accept_customer_request())
	assert_eq(gs.orders.size(), 1)
	assert_true(gs.customer.is_empty())


func test_cancel_order() -> void:
	gs.accept_request(gs.make_request())
	assert_true(gs.cancel_order(0))
	assert_eq(gs.orders.size(), 0)
	assert_false(gs.cancel_order(0))


func test_shop_appeal_grows_with_better_fish() -> void:
	var before := gs.shop_appeal()
	gs.buy_strain("red_delta", Fish.MALE)
	assert_true(gs.shop_appeal() > before)


# --- Day cycle

func test_end_day_summary_and_new_day() -> void:
	gs.sell_item("stone")
	var s := gs.end_day()
	assert_eq(s["day"], 1)
	assert_eq(s["earned"], 5)
	assert_false(gs.clock.is_open)
	gs.open_day()
	assert_eq(gs.earned_today, 0)
	assert_eq(gs.day, 2)
	assert_eq(gs.clock.time_string(), "09:00")


# --- Back-orders

func _wish_item(item_id: String) -> void:
	gs.customer = {"kind": "wish_item", "item_id": item_id, "name": "Jun", "waited": 0.0, "patience": 60.0}


func test_backorder_an_item_at_a_discount() -> void:
	_wish_item("castle")
	assert_true(gs.customer_can_backorder())
	assert_eq(gs.customer_price(), 14, "15 less 10%")
	assert_eq(gs.serve_customer(), 0, "can't sell what you don't have")
	assert_true(gs.backorder_customer())
	assert_true(gs.customer.is_empty())
	assert_eq(gs.backorders.size(), 1)
	assert_eq(gs.backorder_blocker(0), "Not in stock yet. Buy it in the Market.")
	assert_eq(gs.fulfil_backorder(0), 0)
	gs.buy_item("castle")  # costs 8
	assert_eq(gs.backorder_blocker(0), "")
	assert_eq(gs.fulfil_backorder(0), 14)
	assert_eq(gs.money, 100 - 8 + 14)
	assert_eq(gs.inventory.count("castle"), 0)
	assert_eq(gs.backorders.size(), 0)


func test_sold_out_item_can_be_backordered() -> void:
	gs.customer = {"kind": "item", "item_id": "sand", "name": "Jun", "waited": 0.0, "patience": 60.0}
	assert_false(gs.customer_can_backorder(), "it's in stock: just sell it")
	gs.inventory.remove("sand")
	assert_true(gs.customer_can_backorder())
	assert_true(gs.backorder_customer())


func test_backorder_a_strain_fish() -> void:
	gs.customer = {"kind": "wish_fish", "strain_id": "orange", "sex": Fish.FEMALE, "name": "Jun", "waited": 0.0, "patience": 60.0}
	assert_eq(gs.customer_price(), 9, "3-star orange sells for 10, less 10%")
	gs.backorder_customer()
	assert_ne(gs.backorder_blocker(0), "")
	# A home-bred fish that matches counts too, but never one in the breeding tank.
	var bred := gs.inventory.add_fish(F.fish(Fish.FEMALE, "orange", 3))
	gs.move_fish(bred.id, Fish.BREEDING)
	assert_ne(gs.backorder_blocker(0), "", "breeding fish are off limits")
	gs.move_fish(bred.id, Fish.HOLDING)
	assert_eq(gs.fulfil_backorder(0), 9)
	assert_false(gs.inventory.has_fish(bred.id))


func test_backorder_list_has_a_limit() -> void:
	for i in 2:
		_wish_item("castle")
		assert_true(gs.backorder_customer())
	_wish_item("castle")
	assert_false(gs.customer_can_backorder())
	assert_eq(gs.customer_blocker(), "Your back-order list is full.")


func test_cancel_backorder() -> void:
	_wish_item("castle")
	gs.backorder_customer()
	assert_true(gs.cancel_backorder(0))
	assert_false(gs.cancel_backorder(0))


# --- Day log and summary

func test_day_log_tracks_sales_and_spending() -> void:
	gs.sell_item("stone")
	gs.sell_item("stone")
	gs.sell_fish_wholesale(_male().id)
	gs.buy_item("castle")
	var s := gs.end_day()
	var log: Dictionary = s["log"]
	assert_eq(log["money_start"], 100)
	assert_eq(log["sales"]["item"], [2, 10])
	assert_eq(log["sales"]["wholesale"], [1, 3])
	assert_eq(log["spent"], 8)
	assert_eq(s["money_end"], 100 + 10 + 3 - 8)


func test_day_log_resets_each_morning() -> void:
	gs.sell_item("stone")
	gs.end_day()
	gs.open_day()
	assert_eq(gs.day_log["sales"], {})
	assert_eq(gs.day_log["money_start"], 105)


func test_served_and_walked_out_customers_are_counted() -> void:
	gs.customer = {"kind": "item", "item_id": "fern", "name": "Mabel", "waited": 0.0, "patience": 60.0}
	gs.serve_customer()
	gs.customer = {"kind": "item", "item_id": "fern", "name": "Mabel", "waited": 0.0, "patience": 60.0}
	gs.tick_customers(61.0)
	assert_eq(gs.day_log["served"], 1)
	assert_eq(gs.day_log["walked_out"], 1)


func test_summary_lists_new_fry_and_mutations() -> void:
	var species: Dictionary = gs.db.species["guppy"]
	species["mutation_chance"] = 1.0  # every trait mutates
	_pair_in_breeding_tank()
	gs.end_day()
	var s := gs.end_day()
	assert_eq(s["born_ids"].size(), s["fry_born"])
	assert_true(s["mutations"].size() >= s["fry_born"], "every fry has rare traits its parents lack")
	var m: Dictionary = s["mutations"][0]
	assert_true(Genetics.is_rare(species, m["trait"], m["value"]))
	assert_eq(s["fry_in_tank"], s["fry_born"])
	assert_eq(s["nights_until_brood"], 2)


func test_summary_lists_grown_fish() -> void:
	gs.inventory.add("food", 10)
	var fry := gs.inventory.add_fish(F.fish(Fish.FEMALE, "grey", 0, 2))
	fry.parent_stars = 3.0
	gs.move_fish(fry.id, Fish.BREEDING)
	var s := gs.end_day()
	assert_eq(s["grown_ids"], [fry.id])
	assert_between(fry.stars, 2, 4)


# --- Multiple breeding tanks

func test_breeding_locations() -> void:
	assert_eq(Fish.breeding_location(0), "breeding")
	assert_eq(Fish.breeding_location(2), "breeding3")
	assert_eq(Fish.breeding_index("breeding"), 0)
	assert_eq(Fish.breeding_index("breeding4"), 3)
	assert_eq(Fish.breeding_index("breeding1"), -1, "the first tank is plain 'breeding'")
	assert_eq(Fish.breeding_index("display"), -1)
	assert_true(Fish.is_breeding("breeding2"))
	assert_false(Fish.is_breeding("holding"))


func test_start_with_one_breeding_tank_and_buy_more() -> void:
	assert_eq(gs.breeding_tanks.size(), 1)
	assert_eq(gs.next_breeding_tank_cost(), 20)
	assert_true(gs.buy_breeding_tank())
	assert_eq(gs.money, 80)
	assert_eq(gs.next_breeding_tank_cost(), 30)
	assert_true(gs.buy_breeding_tank())
	assert_true(gs.buy_breeding_tank())
	assert_eq(gs.breeding_tanks.size(), 4)
	assert_eq(gs.money, 100 - 20 - 30 - 40)
	assert_eq(gs.next_breeding_tank_cost(), -1, "four is the most")
	assert_false(gs.buy_breeding_tank())
	assert_eq(gs.breeding_tanks[3].capacity, 8)


func test_cannot_buy_a_tank_without_money() -> void:
	gs.money = 5
	assert_false(gs.buy_breeding_tank())
	assert_eq(gs.breeding_tanks.size(), 1)


func test_cannot_move_into_a_tank_you_dont_have() -> void:
	assert_eq(gs.move_blocker(_male().id, "breeding2"), "You don't have that breeding tank yet.")
	gs.buy_breeding_tank()
	assert_true(gs.move_fish(_male().id, "breeding2"))
	assert_eq(gs.breeding_tanks[1].fish_ids, [_male().id])
	assert_eq(_male().location, "breeding2")


func test_fish_in_different_tanks_never_breed() -> void:
	gs.inventory.add("food", 20)
	gs.buy_breeding_tank()
	gs.move_fish(_female().id, Fish.BREEDING)
	gs.move_fish(_male().id, "breeding2")
	assert_eq(gs.nights_until_brood(0), -1)
	assert_eq(gs.nights_until_brood(1), -1)
	for i in 6:
		assert_eq(gs.end_day()["fry_born"], 0, "separated, so no fry")


func test_each_tank_breeds_its_own_pair() -> void:
	gs.buy_breeding_tank()
	var red := gs.inventory.add_fish(F.fish(Fish.MALE, "orange", 3))
	var red_f := gs.inventory.add_fish(F.fish(Fish.FEMALE, "orange", 3))
	_pair_in_breeding_tank()                      # grey female x orange male in tank 1
	gs.move_fish(red.id, "breeding2")             # orange x orange in tank 2
	gs.move_fish(red_f.id, "breeding2")
	gs.end_day()
	var s := gs.end_day()
	var tank2: Array = gs.tank_fish(gs.breeding_tanks[1]).filter(func(f): return not gs.is_adult(f))
	assert_true(tank2.size() >= 2, "tank 2 had its own brood")
	for fry in tank2:
		assert_eq(fry.location, "breeding2")
		assert_eq(fry.traits["body_color"] in ["orange", "red"], true, "only tank 2's parents (plus mutations)")
	assert_eq(s["brood_outlook"].size(), 2)
	assert_eq(s["fry_in_tank"], gs.breeding_fish().filter(func(f): return not gs.is_adult(f)).size())


func test_each_tank_with_fry_uses_its_own_food() -> void:
	gs.inventory.remove("food", gs.inventory.count("food"))
	gs.inventory.add("food", 1)
	gs.buy_breeding_tank()
	var a := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 0))
	var b := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 0))
	gs.move_fish(a.id, Fish.BREEDING)
	gs.move_fish(b.id, "breeding2")
	var s := gs.end_day()
	assert_eq(s["food_used"], 1, "only one portion left")
	assert_eq(s["fry_unfed"], 1, "the second tank went hungry, but its fry are fine")
	assert_eq(a.age_days + b.age_days, 1)


func test_breeding_fish_counts_every_tank_for_appeal() -> void:
	gs.buy_breeding_tank()
	gs.move_fish(_male().id, "breeding2")
	assert_eq(gs.breeding_fish().size(), 1)


# --- Breed-to-order

func _koi_customer() -> Fish:
	# A 4-star red-delta that a customer pays 34 for, but that cost you 51
	# (Market fish normally cost less than customers pay; this one was pricey).
	gs.money = 500
	var f := gs.buy_strain("red_delta", Fish.FEMALE)
	f.paid = 51
	gs.move_fish(f.id, Fish.DISPLAY)
	gs.customer = {"kind": "fish", "fish_id": f.id, "name": "Priya", "waited": 0.0, "patience": 60.0}
	return f


func test_bought_fish_remember_what_you_paid() -> void:
	gs.money = 500
	var f := gs.buy_strain("red_delta", Fish.MALE)
	assert_eq(gs.fish_paid(f), 24)
	assert_eq(gs.fish_paid(_male()), 0, "starting and bred fish cost nothing")


func test_breed_option_only_when_selling_would_lose_money() -> void:
	var f := _koi_customer()
	assert_eq(gs.customer_price(), 34)
	assert_true(gs.customer_can_breed_order(), "34 is less than the 51 paid")
	gs.customer = {"kind": "fish", "fish_id": _male().id, "name": "Priya", "waited": 0.0, "patience": 60.0}
	assert_false(gs.customer_can_breed_order(), "a free fish is never sold at a loss")
	gs.customer = {"kind": "item", "item_id": "fern", "name": "Priya", "waited": 0.0, "patience": 60.0}
	assert_false(gs.customer_can_breed_order())
	assert_true(gs.inventory.has_fish(f.id))


func test_breed_order_keeps_your_fish_and_waits_two_to_three_days() -> void:
	var f := _koi_customer()
	assert_true(gs.breed_order_for_customer())
	assert_true(gs.customer.is_empty())
	assert_true(gs.inventory.has_fish(f.id), "you keep the original to breed from")
	var order: Dictionary = gs.backorders[0]
	assert_eq(order["price"], 34)
	assert_eq(order["sex"], Fish.FEMALE)
	assert_eq(order["traits"], {"body_color": "red", "tail_shape": "delta", "pattern": "plain"})
	assert_between(order["due_day"], gs.day + 2, gs.day + 3)
	assert_eq(gs.backorder_blocker(0), "They'll come back for it on Day %d." % order["due_day"])


func test_breed_order_is_collected_with_a_matching_bred_fish() -> void:
	var original := _koi_customer()
	gs.breed_order_for_customer()
	gs.day = gs.backorders[0]["due_day"]
	assert_ne(gs.backorder_blocker(0), "", "the fish you kept doesn't count")
	# Breed: the kept fish and a male make a pair; a grown fry in the same tank matches.
	gs.move_fish(original.id, Fish.BREEDING)
	gs.move_fish(_male().id, Fish.BREEDING)
	var bred := gs.inventory.add_fish(F.fish(Fish.FEMALE, "red", 2, 3, "delta"))
	gs.move_fish(bred.id, Fish.BREEDING)
	assert_eq(gs.backorder_fish(gs.backorders[0]), bred, "the grown fry, not the breeding mother")
	var money := gs.money
	assert_eq(gs.fulfil_backorder(0), 34)
	assert_eq(gs.money, money + 34)
	assert_false(gs.inventory.has_fish(bred.id))
	assert_true(gs.inventory.has_fish(original.id))


func test_breeding_pair_is_never_handed_over() -> void:
	var original := _koi_customer()
	gs.breed_order_for_customer()
	gs.day = gs.backorders[0]["due_day"]
	gs.move_fish(original.id, Fish.BREEDING)
	gs.move_fish(_male().id, Fish.BREEDING)
	assert_eq(gs.backorder_fish(gs.backorders[0]), null)
	assert_eq(gs.backorder_blocker(0), "No matching adult yet. Breed one (the breeding pair itself is never handed over).")


func test_wrong_sex_or_look_does_not_match() -> void:
	_koi_customer()
	gs.breed_order_for_customer()
	gs.day = gs.backorders[0]["due_day"]
	for f in gs.inventory.fish_list(Fish.DISPLAY):
		gs.move_fish(f.id, Fish.HOLDING)
		gs.sell_fish_wholesale(f.id)
	gs.inventory.add_fish(F.fish(Fish.MALE, "red", 3, 3, "delta"))
	gs.inventory.add_fish(F.fish(Fish.FEMALE, "red", 3, 3, "round"))
	assert_eq(gs.backorder_fish(gs.backorders[0]), null)


# --- Closed for restock

func test_restocking_runs_time_faster_and_stops_customers() -> void:
	assert_eq(gs.time_scale(), 1.0)
	assert_true(gs.set_restocking(true))
	assert_eq(gs.time_scale(), 4.0)
	assert_false(gs.tick_customers(500.0), "nobody comes in while closed for restock")
	assert_true(gs.customer.is_empty())
	gs.set_restocking(false)
	assert_eq(gs.time_scale(), 1.0)


func test_restocking_sends_a_waiting_customer_home() -> void:
	gs.customer = {"kind": "item", "item_id": "fern", "name": "Mabel", "waited": 0.0, "patience": 60.0}
	gs.set_restocking(true)
	assert_true(gs.customer.is_empty())
	assert_eq(gs.money, 100, "no penalty")


func test_restocking_stays_on_across_days() -> void:
	gs.set_restocking(true)
	gs.end_day()
	gs.open_day()
	assert_true(gs.restocking)


func test_restock_can_be_switched_off_in_data() -> void:
	gs.db.economy["clock"]["restock_speed"] = 0
	assert_false(gs.set_restocking(true))
	assert_false(gs.restocking)
