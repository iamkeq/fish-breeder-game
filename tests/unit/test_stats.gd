extends "res://tests/test_case.gd"
## Lifetime counters and personal-best records (the Stats tab).

const F := preload("res://tests/fixtures.gd")

var gs: GameState


func before_each() -> void:
	gs = F.new_game()
	for f in gs.inventory.fish_list():
		gs.inventory.remove_fish(f.id)


func _reload(state: GameState) -> GameState:
	return GameState.from_dict(F.db(), F.rng(99), SaveFile.parse(JSON.stringify(state.to_dict())))


## An adult in holding (for sale).
func _adult(color: String = "grey", stars: int = 3, tail: String = "round") -> Fish:
	return gs.inventory.add_fish(F.fish(Fish.FEMALE, color, stars, 3, tail))


# --- Counters

func test_wholesale_items_and_tanks_are_counted() -> void:
	var f := _adult()
	gs.sell_fish_wholesale(f.id)
	assert_eq(gs.stat("wholesale_sold"), 1)
	assert_eq(gs.stat("fish_sold"), 0, "wholesale is not a customer sale")
	gs.sell_item("fern")
	gs.sell_item("fern")
	assert_eq(gs.stat("items_sold"), 2)
	gs.sell_display_tank(true)
	assert_eq(gs.stat("tanks_sold"), 1)


func test_walked_out_counts_customers_who_lose_patience() -> void:
	gs.customer = {"kind": "item", "item_id": "fern", "name": "Mabel", "waited": 0.0, "patience": 60.0}
	gs.tick_customers(61.0)
	assert_eq(gs.stat("walked_out"), 1)
	gs.customer = {"kind": "item", "item_id": "fern", "name": "Mabel", "waited": 0.0, "patience": 60.0}
	gs.decline_customer()
	assert_eq(gs.stat("walked_out"), 1, "saying no is your choice, not a walk-out")


func test_total_spent_counts_everything_paid() -> void:
	gs.money = 1000
	gs.buy_item("wood")
	gs.buy_strain("orange", Fish.MALE)
	gs.buy_breeding_tank()
	gs.buy_upgrade("bench")
	assert_eq(gs.stat("total_spent"), 6 + gs.strain_cost("orange") + 20 + 5)
	assert_eq(gs.stat("total_spent"), 1000 - gs.money)


func test_growing_up_counts_fish_and_the_best_stars() -> void:
	gs.buy_upgrade("premium")
	gs.inventory.add("food", 5)
	var fry := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 2))
	fry.parent_stars = 3.0
	gs.end_day()
	assert_eq(gs.stat("fish_grown"), 1)
	assert_eq(gs.stat("best_stars_bred"), 4, "the fixture's premium odds nudge a 3 star parent up")
	var weaker := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 2))
	weaker.parent_stars = 1.0
	gs.open_day()
	gs.end_day()
	assert_eq(gs.stat("fish_grown"), 2)
	assert_eq(gs.stat("best_stars_bred"), 4, "only goes up")


func test_bought_fish_do_not_count_as_grown() -> void:
	gs.money = 500
	gs.buy_strain("red_delta", Fish.MALE)
	gs.end_day()
	assert_eq(gs.stat("fish_grown"), 0)
	assert_eq(gs.stat("best_stars_bred"), 0)
	assert_true(gs.records.is_empty() or not gs.records.has("best_bred"))


# --- Records: biggest sale

func test_best_sale_keeps_only_the_biggest() -> void:
	var cheap := _adult("grey", 1)
	var dear := _adult("red", 5, "delta")
	gs.sell_fish(cheap.id)
	var first: Dictionary = gs.records["best_sale"]
	assert_eq(first["amount"], gs.stat("total_earned"))
	assert_eq(first["what"], "★ Guppy")
	assert_eq(first["day"], 1)
	gs.day = 3
	gs.sell_fish(dear.id)
	var best: Dictionary = gs.records["best_sale"]
	assert_true(int(best["amount"]) > int(first["amount"]))
	assert_eq(best["what"], "★★★★★ Guppy")
	assert_eq(best["day"], 3)
	gs.sell_fish(_adult("grey", 1).id)
	assert_eq(gs.records["best_sale"], best, "a smaller sale changes nothing")


func test_a_collector_sale_is_named() -> void:
	var star := _adult("grey", 5)
	var price := gs._sell_to_collector(star.id)
	assert_true(price > 0)
	assert_eq(gs.records["best_sale"]["what"], "★★★★★ Guppy to a collector")
	assert_eq(gs.records["best_sale"]["amount"], price)


func test_a_fish_back_order_is_named_for_its_customer() -> void:
	_adult("red", 5, "delta")
	gs.backorders.append({"name": "Mabel", "species_id": "guppy", "sex": Fish.FEMALE,
		"traits": {"body_color": "red"}, "price": 77, "due_day": 1, "source": "bred"})
	assert_eq(gs.fulfil_backorder(0), 77)
	assert_eq(gs.records["best_sale"]["what"], "★★★★★ Guppy for Mabel")
	assert_eq(gs.records["best_sale"]["amount"], 77)
	assert_eq(gs.records["rarest_sold"]["what"], "★★★★★ Guppy for Mabel")


func test_an_item_back_order_is_a_sale_too() -> void:
	gs.inventory.add("wood")
	gs.backorders.append({"name": "Jun", "item_id": "wood", "price": 11})
	assert_eq(gs.fulfil_backorder(0), 11)
	assert_eq(gs.records["best_sale"]["what"], "Wood for Jun")
	assert_false(gs.records.has("rarest_sold"), "no fish was sold")


func test_an_order_tank_is_named_for_its_customer() -> void:
	gs.accept_request(gs.make_request())
	gs.orders[0]["customer"] = "Rosa"
	assert_true(gs.start_order_tank(0))
	var result := gs.deliver_order(0, true)
	assert_false(result.is_empty())
	assert_eq(gs.records["best_sale"]["what"], "Order tank for Rosa")
	assert_eq(gs.records["best_sale"]["amount"], result["payout"])


func test_a_display_tank_sale_is_named() -> void:
	gs.sell_display_tank(true)
	assert_eq(gs.records["best_sale"]["what"], "Display tank")
	assert_eq(gs.records["best_sale"]["amount"], gs.stat("total_earned"))


func test_an_order_delivery_is_named_for_its_customer() -> void:
	gs.accept_request(gs.make_request())
	gs.orders[0]["customer"] = "Rosa"
	var result := gs.deliver_order(0)
	assert_false(result.is_empty())
	assert_eq(gs.records["best_sale"]["what"], "Display tank for Rosa")
	assert_eq(gs.records["best_sale"]["amount"], result["payout"])


func test_wholesale_and_shelf_items_are_not_records() -> void:
	gs.sell_fish_wholesale(_adult().id)
	gs.sell_item("fern")
	assert_false(gs.records.has("best_sale"))
	assert_false(gs.records.has("rarest_sold"))


# --- Records: rarest fish sold

func test_rarest_sold_goes_by_variety_value_then_stars() -> void:
	gs.sell_fish(_adult("grey", 4).id)
	assert_eq(gs.records["rarest_sold"]["amount"], 100, "plain looks are x1.00")
	gs.sell_fish(_adult("red", 2).id)
	assert_eq(gs.records["rarest_sold"]["amount"], 150, "a rare colour is x1.5")
	gs.sell_fish(_adult("grey", 5).id)
	assert_eq(gs.records["rarest_sold"]["amount"], 150, "5 plain stars don't beat a rarer variety")
	assert_eq(gs.records["rarest_sold"]["what"], "★★ Guppy")
	gs.sell_fish(_adult("red", 1).id)
	assert_eq(gs.records["rarest_sold"]["what"], "★★ Guppy", "same variety, fewer stars")
	gs.day = 4
	gs.sell_fish(_adult("red", 3).id)
	assert_eq(gs.records["rarest_sold"]["what"], "★★★ Guppy", "same variety, more stars wins the tie")
	assert_eq(gs.records["rarest_sold"]["day"], 4)
	gs.sell_fish(_adult("red", 5, "delta").id)
	assert_eq(gs.records["rarest_sold"]["amount"], 225, "two rare looks multiply")


# --- Records: best bred

func test_best_bred_goes_by_stars_then_variety_value() -> void:
	gs.buy_upgrade("premium")
	gs.inventory.add("food", 20)
	var fry := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 2))
	fry.parent_stars = 3.0
	gs.end_day()
	assert_eq(gs.records["best_bred"]["amount"], 4)
	assert_eq(gs.records["best_bred"]["what"], "★★★★ Guppy")
	assert_eq(gs.records["best_bred"]["day"], 1)
	gs.open_day()
	var rarer := gs.inventory.add_fish(F.fish(Fish.MALE, "red", 0, 2))
	rarer.parent_stars = 3.0
	gs.end_day()
	assert_eq(gs.records["best_bred"]["tie"], 150, "a rarer fish of the same stars takes it")
	gs.open_day()
	var plain := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 2))
	plain.parent_stars = 3.0
	gs.end_day()
	assert_eq(gs.records["best_bred"]["tie"], 150, "a plainer one doesn't")
	gs.open_day()
	var weaker := gs.inventory.add_fish(F.fish(Fish.MALE, "red", 0, 2))
	weaker.parent_stars = 1.0
	gs.end_day()
	assert_eq(gs.records["best_bred"]["amount"], 4, "fewer stars never replaces")


# --- Saving

func test_records_and_counters_survive_save_and_load() -> void:
	gs.money = 500
	gs.buy_item("wood")
	gs.sell_fish(_adult("red", 4, "delta").id)
	gs.sell_fish_wholesale(_adult().id)
	gs.buy_upgrade("premium")
	gs.inventory.add("food", 5)
	var fry := gs.inventory.add_fish(F.fish(Fish.MALE, "red", 0, 2))
	fry.parent_stars = 3.0
	gs.end_day()
	assert_eq(gs.records.size(), 3)
	var loaded := _reload(gs)
	assert_eq(JSON.stringify(SaveFile.normalize(loaded.records)), JSON.stringify(SaveFile.normalize(gs.records)))
	for key in gs.records:
		assert_eq(loaded.records[key]["amount"], gs.records[key]["amount"])
		assert_true(loaded.records[key]["amount"] is int, "whole numbers stay ints after JSON")
		assert_eq(loaded.records[key]["what"], gs.records[key]["what"])
		assert_eq(loaded.records[key]["day"], gs.records[key]["day"])
	assert_eq(loaded.stats, gs.stats)
	# And records still only improve after loading.
	var best: int = loaded.records["best_sale"]["amount"]
	loaded.inventory.add_fish(F.fish(Fish.FEMALE, "grey", 1, 3))
	loaded.sell_fish(loaded.inventory.fish_list().filter(func(f): return f.stars == 1)[0].id)
	assert_eq(loaded.records["best_sale"]["amount"], best)


func test_an_old_save_without_records_loads() -> void:
	gs.sell_fish(_adult().id)
	var data: Dictionary = SaveFile.parse(JSON.stringify(gs.to_dict()))
	data.erase("records")
	data.erase("start_id")
	data.erase("challenge_id")
	var loaded := GameState.from_dict(F.db(), F.rng(99), data)
	assert_true(loaded != null)
	assert_eq(loaded.records, {})
	assert_eq(loaded.start_id, "")
	assert_eq(loaded.challenge_id, "")
	assert_eq(loaded.challenge_rules(), {})
	loaded.sell_fish(loaded.inventory.add_fish(F.fish(Fish.FEMALE, "grey", 5)).id)
	assert_true(loaded.records.has("best_sale"), "records start filling in")
