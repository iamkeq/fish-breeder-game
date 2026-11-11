extends "res://tests/test_case.gd"
## Starting pairs and challenge modes (data/new_game.json).

const F := preload("res://tests/fixtures.gd")


func _starts() -> Array:
	return [
		{"id": "orange_grey", "name": "Orange & Grey", "description": "",
			"fish": [
				{"species_id": "guppy", "sex": "male", "stars": 3, "location": "breeding",
					"traits": {"body_color": "orange", "tail_shape": "fan", "pattern": "plain"}},
				{"species_id": "guppy", "sex": "female", "stars": 3, "location": "breeding",
					"traits": {"body_color": "grey", "tail_shape": "fan", "pattern": "plain"}}]},
		{"id": "grey_grey", "name": "Grey pair", "description": "",
			"fish": [
				{"species_id": "guppy", "sex": "male", "stars": 2, "traits": {"body_color": "grey"}},
				{"species_id": "guppy", "sex": "female", "stars": 2, "traits": {"body_color": "grey"}}]},
		{"id": "surprise", "name": "Surprise me", "description": "", "random_pair": true, "trait": "body_color"},
	]


func _challenges() -> Array:
	return [
		{"id": "standard", "name": "Standard", "description": "", "rules": {}},
		{"id": "homegrown", "name": "Homegrown", "description": "", "rules": {"market_fish_until_day": 3}},
		{"id": "shoestring", "name": "Shoestring", "description": "", "rules": {"starting_money": 40}},
		{"id": "oddity_shop", "name": "Oddity", "description": "",
			"rules": {"mutation_chance_multiplier": 5, "customers_buy_only_mutations": true}},
	]


## The fixture data with extra colours (so a random pair has real choice) and the starts/challenges above.
func _db(economy: Dictionary = {}) -> DataDB:
	var species := F.species()
	species["traits"]["body_color"]["common"] = ["grey", "orange", "blue", "green", "pink"]
	return DataDB.from_dicts([species], F.items(), [F.template()],
		economy if not economy.is_empty() else F.economy(), F.strains(), F.goals(), F.upgrades(),
		_starts(), _challenges())


func _game(options: Dictionary = {}, seed_value: int = 1234, economy: Dictionary = {}) -> GameState:
	return GameState.new_game(_db(economy), F.rng(seed_value), options)


func _fish_of(gs: GameState, sex: String) -> Array:
	return gs.inventory.fish_list().filter(func(f): return f.sex == sex)


# --- Starts

func test_the_default_game_is_unchanged() -> void:
	var plain := F.new_game()
	assert_eq(plain.money, 100)
	assert_eq(plain.start_id, "standard", "no starts listed: one implicit standard start")
	assert_eq(plain.challenge_id, "")
	assert_eq(plain.challenge_rules(), {})
	assert_eq(plain.inventory.fish_list().size(), 2)
	assert_eq(plain.inventory.fish_list()[0].id, 1)
	assert_eq(plain.inventory.fish_list()[1].id, 2)
	assert_eq(plain.inventory.fish_list()[0].stars, 2)
	assert_eq(plain.inventory.fish_list()[1].stars, 4)
	assert_eq(DataDB.from_dicts([F.species()], F.items(), [F.template()], F.economy()).challenges, [])


func test_each_start_gives_its_fish() -> void:
	var gs := _game({"start_id": "orange_grey"})
	assert_eq(gs.start_id, "orange_grey")
	var male: Fish = _fish_of(gs, Fish.MALE)[0]
	var female: Fish = _fish_of(gs, Fish.FEMALE)[0]
	assert_eq(male.traits["body_color"], "orange")
	assert_eq(female.traits["body_color"], "grey")
	assert_eq(male.stars, 3)
	assert_true(gs.is_adult(male) and gs.is_adult(female))
	assert_eq(male.location, Fish.BREEDING)
	assert_eq(gs.breeding_tank.fish_ids.size(), 2)
	var other := _game({"start_id": "grey_grey"})
	assert_eq(other.start_id, "grey_grey")
	assert_eq(other.inventory.fish_list(Fish.HOLDING).size(), 2, "no location means holding")
	assert_eq(other.inventory.fish_list()[0].stars, 2)
	assert_eq(other.money, 100, "a start only replaces the fish")
	assert_eq(other.inventory.count("stone"), 2)


func test_surprise_is_a_male_and_a_female_of_two_common_varieties() -> void:
	var seen := {}
	for seed_value in range(1, 40):
		var gs := _game({"start_id": "surprise"}, seed_value)
		assert_eq(gs.inventory.fish_list().size(), 2)
		assert_eq(_fish_of(gs, Fish.MALE).size(), 1)
		assert_eq(_fish_of(gs, Fish.FEMALE).size(), 1)
		var m: Fish = _fish_of(gs, Fish.MALE)[0]
		var f: Fish = _fish_of(gs, Fish.FEMALE)[0]
		var common: Array = gs.db.species["guppy"]["traits"]["body_color"]["common"]
		assert_has(common, m.traits["body_color"])
		assert_has(common, f.traits["body_color"])
		assert_ne(m.traits["body_color"], f.traits["body_color"], "two different varieties")
		assert_eq(m.stars, 2)
		assert_eq(f.stars, 2)
		assert_eq(m.location, Fish.BREEDING)
		assert_eq(f.location, Fish.BREEDING)
		assert_true(gs.is_adult(m) and gs.is_adult(f))
		assert_eq(m.traits["tail_shape"], "round", "other traits take the first common value")
		seen["%s+%s" % [m.traits["body_color"], f.traits["body_color"]]] = true
	assert_true(seen.size() > 5, "different seeds give different pairs")


func test_surprise_is_reproducible_with_a_seed() -> void:
	var a := _game({"start_id": "surprise"}, 77)
	var b := _game({"start_id": "surprise"}, 77)
	assert_eq(_fish_of(a, Fish.MALE)[0].traits, _fish_of(b, Fish.MALE)[0].traits)
	assert_eq(_fish_of(a, Fish.FEMALE)[0].traits, _fish_of(b, Fish.FEMALE)[0].traits)


func test_unknown_ids_fall_back_to_the_first_start_and_no_challenge() -> void:
	var gs := _game({"start_id": "nope", "challenge_id": "nope"})
	assert_eq(gs.start_id, "orange_grey")
	assert_eq(gs.challenge_id, "")
	assert_eq(gs.challenge_rules(), {})
	assert_eq(_fish_of(gs, Fish.MALE)[0].traits["body_color"], "orange")
	var none := _game()
	assert_eq(none.start_id, "orange_grey")
	assert_eq(none.challenge_id, "")
	assert_eq(_game({"challenge_id": "standard"}).challenge_id, "standard")


# --- Challenges

func test_shoestring_changes_the_starting_money() -> void:
	assert_eq(_game({"challenge_id": "shoestring"}).money, 40)
	assert_eq(_game({"challenge_id": "standard"}).money, 100)
	assert_eq(_game().money, 100)


func test_homegrown_closes_the_market_fish_after_day_three() -> void:
	var gs := _game({"challenge_id": "homegrown"})
	gs.money = 1000
	assert_eq(gs.market_last_day(), 3)
	assert_true(gs.market_fish_open())
	gs.day = 3
	assert_true(gs.market_fish_open())
	var bought := gs.buy_strain("orange", Fish.MALE)
	assert_true(bought != null, "Day 3 is the last day to buy")
	gs.day = 4
	assert_false(gs.market_fish_open())
	var money := gs.money
	assert_eq(gs.buy_strain("orange", Fish.FEMALE), null, "refused on Day 4")
	assert_eq(gs.money, money, "nothing taken")
	assert_true(gs.buy_item("wood"), "supplies are still sold")
	var standard := _game()
	standard.money = 1000
	standard.day = 50
	assert_eq(standard.market_last_day(), -1)
	assert_true(standard.buy_strain("orange", Fish.MALE) != null)


func test_market_varieties_are_not_wished_for_once_the_market_closes() -> void:
	var gs := _game({"challenge_id": "homegrown"})
	for f in gs.inventory.fish_list():
		gs.inventory.remove_fish(f.id)
	var wanted := func() -> Array: return gs.wishable_fish().filter(func(w): return w["source"] == "market")
	assert_true(wanted.call().size() > 0, "wished for while the market is open")
	gs.day = 4
	assert_eq(wanted.call().size(), 0, "not any more")


func test_a_market_back_order_can_still_be_cancelled_or_filled_after_the_market_closes() -> void:
	var gs := _game({"challenge_id": "homegrown"})
	gs.backorders.append({"name": "Jun", "species_id": "guppy", "sex": Fish.FEMALE,
		"traits": {"body_color": "orange"}, "price": 14, "due_day": 5, "source": "market"})
	gs.day = 5
	assert_eq(gs.backorder_blocker(0), "The Market no longer sells fish. Breed one, or cancel this order (no penalty).")
	assert_true(gs.cancel_backorder(0))
	assert_eq(gs.backorders.size(), 0)
	gs.backorders.append({"name": "Jun", "species_id": "guppy", "sex": Fish.FEMALE,
		"traits": {"body_color": "orange"}, "price": 14, "due_day": 5, "source": "market"})
	gs.inventory.add_fish(F.fish(Fish.FEMALE, "orange"))
	assert_eq(gs.backorder_blocker(0), "", "a bred orange female fills it")
	assert_eq(gs.fulfil_backorder(0), 14)


func test_the_mutation_multiplier_raises_the_chance_and_is_capped() -> void:
	var gs := _game({"challenge_id": "oddity_shop"})
	var species: Dictionary = gs.db.species["guppy"]
	assert_almost(gs.breeding_species(species)["mutation_chance"], 0.25)
	assert_eq(species["mutation_chance"], 0.05, "the data itself is untouched")
	species["mutation_chance"] = 0.2
	assert_almost(gs.breeding_species(species)["mutation_chance"], 0.5, 0.0001, "capped at 50%")
	species["mutation_chance"] = 0.05
	var plain := _game()
	assert_true(is_same(plain.breeding_species(species), species), "no challenge: the very same data")


func test_the_multiplier_makes_mutations_more_common_when_breeding() -> void:
	var rates := []
	for challenge in ["standard", "oddity_shop"]:
		var gs := _game({"start_id": "grey_grey", "challenge_id": challenge}, 5)
		var species: Dictionary = gs.db.species["guppy"]
		species["brood_size"] = [4, 4]
		species["days_between_broods"] = 1
		gs.breeding_tank.capacity = 400
		gs.db.economy["breeding_tanks"]["max_mothers"] = 1
		for f in gs.inventory.fish_list():
			gs.move_fish(f.id, Fish.BREEDING)
		gs.inventory.add("food", 500)
		for i in 14:
			gs.end_day()
			gs.open_day()
		var fry := gs.inventory.fish_list().filter(func(f): return f.id > 2)
		var odd := fry.filter(func(f): return gs.is_mutation_fish(f))
		assert_true(fry.size() >= 40, "enough fry to compare")
		rates.append(float(odd.size()) / float(fry.size()))
	assert_true(rates[1] > rates[0] * 2.0, "Oddity Shop %s vs standard %s" % [rates[1], rates[0]])


# --- Oddity Shop customers

func _oddity_shop(challenge: String) -> GameState:
	var economy := F.economy()
	economy["customers"]["wants"] = {"fish": 3, "item": 2, "tank": 1, "wish": 4.0, "collector": 3.0}
	var gs := _game({"challenge_id": challenge}, 31, economy)
	for f in gs.inventory.fish_list():
		gs.inventory.remove_fish(f.id)
	gs.inventory.add_fish(F.fish(Fish.FEMALE, "grey", 4))
	gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 2))
	gs.inventory.add_fish(F.fish(Fish.MALE, "red", 5))    # a mutation in the test species
	gs.inventory.add_fish(F.fish(Fish.FEMALE, "grey", 5, 3, "delta"))
	gs.inventory.add_fish(F.fish(Fish.FEMALE, "grey", 3, 3, "round", "mosaic"))
	return gs


func test_oddity_shop_only_sells_mutations_to_fish_customers_and_collectors() -> void:
	var gs := _oddity_shop("oddity_shop")
	var kinds := {}
	for i in 500:
		var c := gs._new_customer()
		kinds[c["kind"]] = true
		match c["kind"]:
			"fish":
				assert_true(gs.is_mutation_fish(gs.inventory.get_fish(c["fish_id"])), "a mutation fish")
			"collector":
				var f := gs.inventory.get_fish(c["fish_id"])
				assert_true(gs.is_mutation_fish(f), "collectors want mutations too")
				assert_true(gs.is_collector_fish(f))
		assert_ne(c["kind"], "wish_fish")
		assert_true(c.has("kind") and c["kind"] != "", "no broken card")
	assert_true(kinds.has("fish"), "fish customers still come")
	assert_true(kinds.has("collector"))
	assert_true(kinds.has("item"), "items sell as normal")
	assert_true(kinds.has("wish_item"), "item back-orders work as normal")


func test_the_standard_game_sells_everything_to_everyone() -> void:
	var gs := _oddity_shop("standard")
	var plain_sold := false
	var wishes := false
	for i in 500:
		var c := gs._new_customer()
		if c["kind"] == "fish" and not gs.is_mutation_fish(gs.inventory.get_fish(c["fish_id"])):
			plain_sold = true
		if c["kind"] == "wish_fish":
			wishes = true
	assert_true(plain_sold)
	assert_true(wishes)


func test_oddity_shop_with_no_mutation_fish_has_no_fish_customers() -> void:
	var gs := _oddity_shop("oddity_shop")
	for f in gs.inventory.fish_list().filter(func(f): return gs.is_mutation_fish(f)):
		gs.inventory.remove_fish(f.id)
	for i in 300:
		var c := gs._new_customer()
		assert_false(c["kind"] in ["fish", "collector", "wish_fish"])
		assert_true(c["kind"] != "")


func test_oddity_shop_still_sells_fish_to_the_wholesaler() -> void:
	var gs := _oddity_shop("oddity_shop")
	var plain: Fish = gs.inventory.fish_list()[0]
	assert_true(gs.sell_fish_wholesale(plain.id) > 0)


# --- Saving

func test_start_and_challenge_survive_save_and_load() -> void:
	var gs := _game({"start_id": "grey_grey", "challenge_id": "homegrown"})
	var loaded := GameState.from_dict(_db(), F.rng(9), SaveFile.parse(JSON.stringify(gs.to_dict())))
	assert_eq(loaded.start_id, "grey_grey")
	assert_eq(loaded.challenge_id, "homegrown")
	assert_eq(loaded.market_last_day(), 3)
	assert_eq(loaded.challenge_rules(), {"market_fish_until_day": 3})


func test_an_old_save_loads_as_the_standard_game() -> void:
	var gs := _game({"challenge_id": "homegrown"})
	var data: Dictionary = SaveFile.parse(JSON.stringify(gs.to_dict()))
	data.erase("start_id")
	data.erase("challenge_id")
	var loaded := GameState.from_dict(_db(), F.rng(9), data)
	assert_eq(loaded.challenge_rules(), {})
	assert_eq(loaded.market_last_day(), -1)
	assert_true(loaded.market_fish_open())
	loaded.day = 30
	loaded.money = 500
	assert_true(loaded.buy_strain("orange", Fish.MALE) != null)


# --- Data

func test_real_new_game_data_loads_clean() -> void:
	var db := DataDB.load_from_dir("res://data")
	assert_eq(db.errors, [] as Array[String])
	assert_eq(db.starts.size(), 4)
	assert_eq(db.starts.map(func(s): return s["id"]), ["red_yellow", "blue_grass", "black_white", "surprise"])
	assert_eq(db.challenges.map(func(c): return c["id"]), ["standard", "homegrown", "shoestring", "oddity_shop"])
	assert_eq(JSON.stringify(db.starts[0]["fish"]), JSON.stringify(db.economy["starting_state"]["fish"]),
		"the first start is today's starting pair")
	var standard := GameState.new_game(db, F.rng())
	assert_eq(standard.start_id, "red_yellow")
	assert_eq(standard.money, 150)
	assert_eq(standard.inventory.fish_list().size(), 2)
	assert_eq(standard.breeding_tank.fish_ids.size(), 2)
	for st in db.starts:
		var gs := GameState.new_game(db, F.rng(3), {"start_id": st["id"], "challenge_id": "standard"})
		assert_eq(gs.breeding_tank.fish_ids.size(), 2, st["id"])
		assert_eq(_fish_of(gs, Fish.MALE).size(), 1)
		assert_eq(_fish_of(gs, Fish.FEMALE).size(), 1)
	var pairs := {"blue_grass": ["blue", "grass"], "black_white": ["black", "white"]}
	for id in pairs:
		var gs := GameState.new_game(db, F.rng(), {"start_id": id})
		assert_eq(_fish_of(gs, Fish.MALE)[0].traits["variety"], pairs[id][0])
		assert_eq(_fish_of(gs, Fish.FEMALE)[0].traits["variety"], pairs[id][1])
	assert_eq(GameState.new_game(db, F.rng(), {"challenge_id": "shoestring"}).money, 40)


func test_bad_start_and_challenge_data_is_reported() -> void:
	var bad_starts := [{"id": "x", "name": "X", "description": "", "fish": [{"species_id": "dragon", "sex": "male"}]},
		{"id": "y", "name": "Y", "description": ""}]
	var bad_challenges := [{"id": "z", "name": "Z", "description": "", "rules": {"flying_fish": true}}]
	var db := DataDB.from_dicts([F.species()], F.items(), [F.template()], F.economy(), F.strains(), F.goals(),
		F.upgrades(), bad_starts, bad_challenges)
	assert_has(db.errors, "start/x: fish has unknown species 'dragon'")
	assert_has(db.errors, "start/y: needs a 'fish' list (or 'random_pair')")
	assert_has(db.errors, "challenge/z: unknown rule 'flying_fish'")
