extends "res://tests/test_case.gd"
## Third-generation recipes, breeding-book rewards and collectors.

const F := preload("res://tests/fixtures.gd")

const NEW_GEN3 := ["phoenix", "calico", "midnight", "opal", "tiger"]


## The fixture guppy with a small recipe chain on body_color:
##   grey x orange -> red (1), grey x blue -> teal (1), red x blue -> plum (2), plum x red -> ruby (3)
func _chain_species() -> Dictionary:
	var s := F.species()
	s["traits"]["body_color"] = {"common": ["grey", "orange", "blue"], "rare": ["red", "teal", "plum", "ruby"]}
	s["recipes"] = {"body_color": [
		{"parents": ["grey", "orange"], "child": "red"},
		{"parents": ["grey", "blue"], "child": "teal"},
		{"parents": ["red", "blue"], "child": "plum"},
		{"parents": ["plum", "red"], "child": "ruby"},
	]}
	return s


func _db(species: Dictionary = {}, economy: Dictionary = {}) -> DataDB:
	return DataDB.from_dicts([species if not species.is_empty() else _chain_species()], F.items(), [F.template()],
		economy if not economy.is_empty() else F.economy(), F.strains(), F.goals(), F.upgrades())


func _state(species: Dictionary = {}, economy: Dictionary = {}) -> GameState:
	return GameState.new_game(_db(species, economy), F.rng())


func _summary() -> Dictionary:
	return {"discoveries": [], "book_bonuses": []}


func _find(state: GameState, source: String, a: String, b: String, value: String) -> Dictionary:
	var summary := _summary()
	state._discover(summary, source, state.db.species["guppy"], "body_color", value, [a, b])
	return summary


## A state with no starting fish, so tests control exactly who is for sale.
func _empty_shop(wants_collector: float = 1.0) -> GameState:
	var economy := F.economy()
	economy["customers"]["wants"]["collector"] = wants_collector
	var gs := _state({}, economy)
	for f in gs.inventory.fish_list():
		gs.inventory.remove_fish(f.id)
	return gs


func _bred(stars: int, color: String = "grey") -> Fish:
	return F.fish(Fish.MALE, color, stars)


# --- recipe_generation

func test_recipe_generation_counts_steps() -> void:
	var s := _chain_species()
	assert_eq(Genetics.recipe_generation(s, "body_color", "red"), 1)
	assert_eq(Genetics.recipe_generation(s, "body_color", "plum"), 2)
	assert_eq(Genetics.recipe_generation(s, "body_color", "ruby"), 3)
	assert_eq(Genetics.recipe_generation(s, "body_color", "grey"), 0, "a plain value is not made by a recipe")
	assert_eq(Genetics.recipe_generation(s, "body_color", "nonsense"), 0)
	assert_eq(Genetics.recipe_generation(s, "tail_shape", "red"), 0, "other trait")


func test_recipe_generation_survives_a_recipe_loop() -> void:
	var s := _chain_species()
	s["recipes"] = {"body_color": [
		{"parents": ["grey", "red"], "child": "orange"},
		{"parents": ["grey", "orange"], "child": "red"},
	]}
	var g := Genetics.recipe_generation(s, "body_color", "red")
	assert_true(g > 0 and g < 50, "ends, whatever the answer")


func test_book_recipes_carry_their_generation() -> void:
	var gs := _state()
	var by_child := {}
	for r in gs.book_recipes("guppy"):
		by_child[r["child"]] = r["generation"]
	assert_eq(by_child, {"red": 1, "teal": 1, "plum": 2, "ruby": 3})


# --- Real data

func test_real_data_has_twenty_recipes_five_of_them_third_generation() -> void:
	var db := DataDB.load_from_dir("res://data")
	assert_eq(db.errors, [] as Array[String])
	var gs := GameState.new_game(db, F.rng())
	var recipes := gs.book_recipes("guppy")
	assert_eq(recipes.size(), 20)
	var counts := {}
	for r in recipes:
		counts[r["generation"]] = int(counts.get(r["generation"], 0)) + 1
	assert_eq(counts, {1: 9, 2: 6, 3: 5})
	var guppy: Dictionary = db.species["guppy"]
	for r in recipes:
		if r["generation"] == 3:
			assert_has(NEW_GEN3, r["child"])
	for v in NEW_GEN3:
		assert_has(guppy["traits"]["variety"]["rare"], v)
		assert_false(v in guppy["traits"]["variety"]["mutations"], v + " is recipe-only")
		assert_true(guppy["sprites"]["placeholders"].has(v), v + " has a placeholder")
		assert_true(guppy["value_multipliers"]["variety"].has(v), v + " has a value")
	assert_true(db.economy.has("breeding_book"))
	assert_true(db.economy["customers"].has("collector"))
	var all_recipes: Dictionary = db.goals.filter(func(g): return g["id"] == "all_recipes")[0]
	assert_eq(int(all_recipes["target"]), 20)


# --- Book rewards

func test_discovery_pays_its_reward_once() -> void:
	var gs := _state()
	var money := gs.money
	var earned := gs.earned_today
	var summary := _find(gs, "recipe", "grey", "orange", "red")
	assert_eq(gs.money, money + 15)
	assert_eq(summary["discoveries"][0]["reward"], 15)
	assert_eq(summary["discoveries"][0]["generation"], 1)
	assert_eq(gs.stat("book_rewards"), 15)
	assert_eq(gs.earned_today, earned, "a reward is not a sale")
	_find(gs, "recipe", "orange", "grey", "red")  # same recipe, other order
	assert_eq(gs.money, money + 15, "not paid twice")


func test_rewards_grow_with_generation_and_last_entry_covers_deeper() -> void:
	var gs := _state()
	assert_eq(gs.recipe_reward(1), 15)
	assert_eq(gs.recipe_reward(2), 30)
	assert_eq(gs.recipe_reward(3), 60)
	assert_eq(gs.recipe_reward(7), 60)
	assert_eq(gs.generation_bonus(2), 100)
	var money := gs.money
	var summary := _find(gs, "recipe", "red", "blue", "plum")
	assert_eq(summary["discoveries"][0]["reward"], 30, "a second-generation recipe pays 30")
	assert_eq(gs.money, money + 30 + 100, "and it is the only one in its generation here, so the bonus too")


func test_mutation_pays_once() -> void:
	var gs := _state()
	var money := gs.money
	var summary := _summary()
	var species: Dictionary = gs.db.species["guppy"]
	gs._discover(summary, "mutation", species, "body_color", "ruby", ["grey", "grey"])
	gs._discover(summary, "mutation", species, "body_color", "ruby", ["grey", "grey"])
	assert_eq(gs.money, money + 50)
	assert_eq(summary["discoveries"].size(), 1)
	assert_eq(summary["discoveries"][0]["reward"], 50)


func test_generation_bonus_pays_when_the_last_recipe_is_found() -> void:
	var gs := _state()
	var money := gs.money
	var first := _find(gs, "recipe", "grey", "orange", "red")
	assert_eq(first["book_bonuses"], [])
	assert_false(gs.book_bonuses.has("1"))
	var second := _find(gs, "recipe", "grey", "blue", "teal")
	assert_eq(second["book_bonuses"], [{"generation": 1, "reward": 50}])
	assert_eq(gs.money, money + 15 + 15 + 50)
	assert_true(gs.book_bonuses.has("1"))
	assert_eq(gs.stat("book_rewards"), 80)
	assert_eq(gs.earned_today, 0)
	# Nothing more to pay for generation 1.
	var after := gs.money
	_find(gs, "recipe", "grey", "blue", "teal")
	assert_eq(gs.money, after)


func test_book_rewards_land_in_the_end_of_day_summary() -> void:
	var economy := F.economy()
	var species := _chain_species()
	species["recipe_chance"] = 1.0
	species["mutation_chance"] = 0.0
	var gs := _state(species, economy)
	var pair := gs.inventory.fish_list()
	for f in pair:
		gs.move_fish(f.id, Fish.BREEDING)
	var money := gs.money
	gs.end_day()
	gs.open_day()
	var summary := gs.end_day()
	assert_true(summary.has("book_bonuses"))
	var found: Array = summary["discoveries"].filter(func(d): return d["value"] == "red")
	assert_eq(found.size(), 1, "orange x grey always makes red here")
	assert_eq(found[0]["reward"], 15)
	assert_eq(summary["money_end"], gs.money)
	assert_true(summary["money_end"] >= money + 15, "the reward is in the closing money")
	assert_eq(gs.earned_today, 0)


func test_third_generation_metric_and_goal_metric_names() -> void:
	var gs := _state()
	assert_eq(gs.goal_value("third_gen_recipes"), 0)
	_find(gs, "recipe", "plum", "red", "ruby")
	assert_eq(gs.goal_value("third_gen_recipes"), 1)
	var db := DataDB.from_dicts([F.species()], F.items(), [F.template()], F.economy(), F.strains(),
		[{"id": "g", "name": "G", "description": "", "metric": "third_gen_recipes", "target": 1, "reward": 1},
		{"id": "h", "name": "H", "description": "", "metric": "collector_sales", "target": 1, "reward": 1}])
	assert_eq(db.errors, [] as Array[String])


func test_book_bonuses_survive_save_and_load() -> void:
	var gs := _state()
	_find(gs, "recipe", "grey", "orange", "red")
	_find(gs, "recipe", "grey", "blue", "teal")
	var loaded := GameState.from_dict(gs.db, F.rng(99), SaveFile.parse(JSON.stringify(gs.to_dict())))
	assert_eq(loaded.book_bonuses, gs.book_bonuses)
	assert_eq(loaded.money, gs.money)
	var before := loaded.money
	_find(loaded, "recipe", "grey", "blue", "teal")
	assert_eq(loaded.money, before, "no second bonus after loading")


func test_old_save_gets_no_retroactive_bonus() -> void:
	var gs := _state()
	_find(gs, "recipe", "grey", "orange", "red")
	_find(gs, "recipe", "grey", "blue", "teal")
	var data: Dictionary = SaveFile.parse(JSON.stringify(gs.to_dict()))
	data.erase("book_bonuses")
	var loaded := GameState.from_dict(gs.db, F.rng(99), data)
	assert_eq(loaded.money, gs.money, "nothing paid on load")
	assert_true(loaded.book_bonuses.has("1"), "the complete generation is marked as settled")
	assert_false(loaded.book_bonuses.has("2"))
	var before := loaded.money
	_find(loaded, "recipe", "red", "blue", "plum")
	assert_eq(loaded.money, before + 30 + 100, "a later generation still pays when it completes")


func test_economy_without_a_breeding_book_pays_nothing() -> void:
	var economy := F.economy()
	economy.erase("breeding_book")
	var gs := _state({}, economy)
	var money := gs.money
	_find(gs, "recipe", "grey", "orange", "red")
	assert_eq(gs.money, money)


# --- Collectors

func test_collector_only_when_an_eligible_fish_exists() -> void:
	var gs := _empty_shop()
	assert_eq(gs.collector_fish(), [])
	gs.inventory.add_fish(_bred(3))
	assert_eq(gs.collector_fish(), [], "3 stars is not show quality")
	for i in 100:
		assert_ne(gs._new_customer()["kind"], "collector")
	var good := gs.inventory.add_fish(_bred(4))
	assert_eq(gs.collector_fish(), [good])
	var seen := {}
	for i in 100:
		seen[gs._new_customer()["kind"]] = true
	assert_true(seen.has("collector"))


func test_collector_never_wants_market_bought_fish() -> void:
	var gs := _empty_shop(1000.0)
	gs.money = 10000
	var bought := gs.buy_strain("red_delta", Fish.MALE)  # 4 stars from the Market
	assert_true(bought != null and bought.stars >= 4)
	var paid_only := _bred(5)
	paid_only.paid = 30
	gs.inventory.add_fish(paid_only)
	var strain_only := _bred(5)
	strain_only.strain_id = "wild"
	gs.inventory.add_fish(strain_only)
	assert_eq(gs.collector_fish(), [], "Market fish never qualify")
	for i in 200:
		assert_ne(gs._new_customer()["kind"], "collector")
	# And if one is somehow at the counter, it can't be sold.
	gs.customer = {"kind": "collector", "fish_id": bought.id, "name": "Wren", "waited": 0.0, "patience": 60.0}
	assert_ne(gs.customer_blocker(), "")
	assert_eq(gs.serve_customer(), 0)
	assert_true(gs.inventory.has_fish(bought.id))


func test_collector_price_uses_the_star_multiplier() -> void:
	var gs := _empty_shop()
	var four := gs.inventory.add_fish(_bred(4))
	var five := gs.inventory.add_fish(_bred(5))
	assert_eq(gs.collector_price(four), roundi(gs.fish_price(four) * 1.5))
	assert_eq(gs.collector_price(five), roundi(gs.fish_price(five) * 2.0))
	assert_true(gs.collector_price(five) > gs.fish_price(five))


func test_serving_a_collector_pays_and_counts() -> void:
	var gs := _empty_shop()
	var f := gs.inventory.add_fish(_bred(5))
	var money := gs.money
	gs.customer = {"kind": "collector", "fish_id": f.id, "name": "Wren", "waited": 0.0, "patience": 60.0}
	var price := gs.collector_price(f)
	assert_eq(gs.customer_price(), price)
	assert_eq(gs.customer_blocker(), "")
	assert_false(gs.customer_can_backorder())
	assert_false(gs.customer_can_breed_order())
	assert_false(gs.backorder_customer())
	assert_eq(gs.serve_customer(), price)
	assert_eq(gs.money, money + price)
	assert_false(gs.inventory.has_fish(f.id))
	assert_eq(gs.stat("collector_sales"), 1)
	assert_eq(gs.stat("fish_sold"), 1)
	assert_eq(gs.stat("best_stars_sold"), 5)
	assert_eq(gs.day_log["sales"]["collector"], [1, price])
	assert_false(gs.day_log["sales"].has("fish"), "its own sales category")
	assert_eq(gs.customer, {})


func test_collector_blocker_when_the_fish_is_gone_or_no_longer_qualifies() -> void:
	var gs := _empty_shop()
	var f := gs.inventory.add_fish(_bred(4))
	gs.customer = {"kind": "collector", "fish_id": f.id, "name": "Wren", "waited": 0.0, "patience": 60.0}
	assert_eq(gs.customer_blocker(), "")
	gs.move_fish(f.id, Fish.BREEDING)
	assert_eq(gs.customer_blocker(), "That fish isn't available any more.", "moved out of sale")
	gs.move_fish(f.id, Fish.HOLDING)
	gs.inventory.remove_fish(f.id)
	assert_eq(gs.customer_blocker(), "That fish isn't available any more.", "sold or gone")
	assert_eq(gs.customer_price(), 0)
	assert_eq(gs.serve_customer(), 0)


func test_collector_picks_only_from_the_given_fish() -> void:
	var rules: Dictionary = F.economy()["customers"]
	rules["wants"] = {"collector": 1.0}
	var f4 := _bred(4)
	f4.id = 1
	var f5 := _bred(5)
	f5.id = 2
	var rng := F.rng(5)
	var counts := {1: 0, 2: 0}
	for i in 300:
		var c := Customers.make_walk_in({"collector_fish": [f4, f5], "species_db": {"guppy": F.species()}}, rules, rng)
		assert_eq(c["kind"], "collector")
		counts[c["fish_id"]] += 1
	assert_true(counts[2] > counts[1], "5 stars come up more often")


func test_no_collectors_when_the_fixture_wants_none() -> void:
	var gs := F.new_game()  # fixture: wants.collector is 0
	gs.inventory.add_fish(_bred(5))
	for i in 200:
		assert_ne(gs._new_customer()["kind"], "collector")
	assert_eq(gs.collector_fish().size(), 2, "the 4 star starting fish and the new one are eligible, just never asked for")
