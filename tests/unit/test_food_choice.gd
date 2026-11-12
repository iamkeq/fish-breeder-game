extends "res://tests/test_case.gd"
## Choosing the food per tank, and Spawning Pellets (bigger broods).

const F := preload("res://tests/fixtures.gd")

var gs: GameState


func _db(brood: Array = [4, 4]) -> DataDB:
	var species := F.species()
	species["brood_size"] = brood
	species["mutation_chance"] = 0.0
	var items := F.items()
	items.append({"id": "flakes", "name": "Growth Flakes", "category": "food", "cost": 8, "price": 10,
		"tags": [], "growth_days": 2, "icon": "arm"})
	items.append({"id": "pellets", "name": "Spawning Pellets", "category": "food", "cost": 8, "price": 10,
		"tags": [], "brood_multiplier": 1.25, "brood_multiplier_full": 1.5, "icon": "heart"})
	return DataDB.from_dicts([species], items, [F.template()], F.economy(), F.strains(), F.goals(),
		F.upgrades(), [], [], F.reputation(), F.shows(), F.staff())


func _setup(seed_value: int = 1234, brood: Array = [4, 4]) -> void:
	gs = GameState.new_game(_db(brood), F.rng(seed_value))
	for f in gs.inventory.fish_list():
		gs.inventory.remove_fish(f.id)
	gs.inventory.remove("food", gs.inventory.count("food"))
	gs.breeding_tank.capacity = 40


func before_each() -> void:
	_setup()


func _fry(age: int = 0, location: String = Fish.BREEDING) -> Fish:
	var f := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, age))
	gs.move_fish(f.id, location)
	return f


func _pair() -> void:
	gs.move_fish(gs.inventory.add_fish(F.fish(Fish.MALE)).id, Fish.BREEDING)
	gs.move_fish(gs.inventory.add_fish(F.fish(Fish.FEMALE)).id, Fish.BREEDING)


func test_default_is_fish_food_even_with_flakes_in_stock() -> void:
	assert_eq(gs.food_choice(Fish.BREEDING), "food")
	gs.inventory.add("food", 2)
	gs.inventory.add("flakes", 2)
	var fry := _fry()
	var s := gs.end_day()
	assert_eq(gs.inventory.count("food"), 1)
	assert_eq(gs.inventory.count("flakes"), 2)
	assert_eq(fry.age_days, 1)
	assert_eq(s["growth_food_used"], 0)


func test_choosing_flakes_uses_flakes() -> void:
	gs.inventory.add("food", 2)
	gs.inventory.add("flakes", 2)
	assert_true(gs.set_food_choice(Fish.BREEDING, "flakes"))
	var fry := _fry()
	var s := gs.end_day()
	assert_eq(gs.inventory.count("flakes"), 1)
	assert_eq(gs.inventory.count("food"), 2)
	assert_eq(fry.age_days, 2)
	assert_eq(s["growth_food_used"], 1)


func test_choice_out_of_stock_falls_back_to_fish_food_then_anything() -> void:
	gs.set_food_choice(Fish.BREEDING, "flakes")
	gs.inventory.add("food", 1)
	var fry := _fry()
	gs.end_day()
	assert_eq(fry.age_days, 1, "fish food when the flakes ran out")
	assert_eq(gs.inventory.count("food"), 0)
	gs.inventory.add("pellets", 1)
	gs.end_day()
	assert_eq(fry.age_days, 2, "any other food rather than going hungry")
	assert_eq(gs.inventory.count("pellets"), 0)


func test_only_food_items_can_be_chosen_and_choices_are_per_tank() -> void:
	assert_false(gs.set_food_choice(Fish.BREEDING, "sand"))
	assert_false(gs.set_food_choice(Fish.BREEDING, "nope"))
	assert_false(gs.set_food_choice("breeding5", "flakes"), "no such tank")
	gs.buy_breeding_tank()
	assert_true(gs.set_food_choice("breeding2", "flakes"))
	assert_true(gs.set_food_choice(Fish.HOLDING, "pellets"))
	assert_eq(gs.food_choice(Fish.BREEDING), "food")
	assert_eq(gs.food_choice("breeding2"), "flakes")
	assert_eq(gs.food_choice(Fish.HOLDING), "pellets")
	assert_true(gs.set_food_choice("breeding2", "food"))
	assert_eq(gs.food_choice("breeding2"), "food")


func test_holding_uses_its_own_choice() -> void:
	gs.inventory.add("flakes", 1)
	gs.set_food_choice(Fish.HOLDING, "flakes")
	var held := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 0))
	gs.end_day()
	assert_eq(held.age_days, 2)


func test_pellets_eaten_nightly_with_a_breeding_group_and_no_fry() -> void:
	_pair()
	gs.inventory.add("pellets", 3)
	gs.set_food_choice(Fish.BREEDING, "pellets")
	assert_eq(gs.food_use_per_night(), 1, "the estimate counts it")
	var s := gs.end_day()
	assert_eq(gs.inventory.count("pellets"), 2)
	assert_eq(s["spawning_food_used"], 1)
	assert_eq(s["food_used"], 1)


func test_no_pellets_eaten_without_a_breeding_group() -> void:
	gs.inventory.add("pellets", 3)
	gs.set_food_choice(Fish.BREEDING, "pellets")
	gs.move_fish(gs.inventory.add_fish(F.fish(Fish.MALE)).id, Fish.BREEDING)
	gs.end_day()
	assert_eq(gs.inventory.count("pellets"), 3)
	assert_eq(gs.food_use_per_night(), 0)


func test_pellets_with_fry_use_one_portion_and_grow_one_day() -> void:
	_pair()
	gs.inventory.add("pellets", 3)
	gs.set_food_choice(Fish.BREEDING, "pellets")
	var fry := _fry()
	var s := gs.end_day()
	assert_eq(gs.inventory.count("pellets"), 2)
	assert_eq(fry.age_days, 1)
	assert_eq(s["spawning_food_used"], 1)


## Runs one brood cycle (2 nights). `pellets` says which nights the tank is set to pellets.
func _brood_with(seed_value: int, pellets: Array, brood: Array) -> Dictionary:
	_setup(seed_value, brood)
	_pair()
	gs.inventory.add("pellets", 5)
	var born := 0
	var bonus := 0
	for night in pellets.size():
		gs.set_food_choice(Fish.BREEDING, "pellets" if pellets[night] else "food")
		var s := gs.end_day()
		born += int(s["fry_born"])
		bonus += int(s["bonus_fry"])
	return {"born": born, "bonus": bonus}


func _average(pellets: Array, brood: Array) -> float:
	var total := 0
	for seed_value in range(1, 121):
		total += _brood_with(seed_value, pellets, brood)["born"]
	return float(total) / 120.0


func test_pellets_on_the_brood_night_only_make_broods_a_quarter_bigger() -> void:
	assert_between(_average([false, true], [6, 6]), 7.2, 7.8, "6 x 1.25 = 7.5 on average")


func test_pellets_every_night_of_the_cycle_make_broods_half_again() -> void:
	assert_between(_average([true, true], [5, 5]), 7.2, 7.8, "5 x 1.5 = 7.5 on average")
	var r := _brood_with(5, [true, true], [6, 6])
	assert_eq(r["born"], 9)
	assert_eq(r["bonus"], 3)


func test_a_missed_night_drops_the_bonus() -> void:
	assert_eq(_brood_with(5, [true, false], [6, 6])["born"], 6, "not eaten on the brood night: no bonus")
	assert_between(_average([true, false], [6, 6]), 5.99, 6.01)
	assert_between(_average([false, true], [6, 6]), 7.2, 7.8, "eaten only on the brood night: 1.25x")


func test_the_cycle_counter_resets_after_a_brood() -> void:
	_setup(3, [6, 6])
	_pair()
	gs.inventory.add("pellets", 10)
	gs.set_food_choice(Fish.BREEDING, "pellets")
	gs.end_day()
	assert_eq(gs.brood_food_nights[0], 1)
	gs.end_day()
	assert_eq(gs.brood_nights[0], 0)
	assert_eq(gs.brood_food_nights[0], 0, "reset with the brood")
	gs.end_day()
	var s := gs.end_day()
	assert_eq(s["fry_born"], 9, "a second full cycle gets the full bonus too")


func test_counter_resets_when_the_group_breaks_up() -> void:
	_pair()
	gs.inventory.add("pellets", 5)
	gs.set_food_choice(Fish.BREEDING, "pellets")
	gs.end_day()
	assert_eq(gs.brood_food_nights[0], 1)
	gs.move_fish(gs.breeding_group()["father"].id, Fish.HOLDING)
	gs.end_day()
	assert_eq(gs.brood_food_nights[0], 0)


func test_pellets_give_exact_whole_numbers_when_they_can() -> void:
	var r := _brood_with(5, [false, true], [4, 4])
	assert_eq(r["born"], 5)
	assert_eq(r["bonus"], 1)


func test_food_buff_lasts_the_day_after_the_feeding() -> void:
	gs.inventory.add("flakes", 5)
	gs.set_food_choice(Fish.BREEDING, "flakes")
	var fry := _fry()
	assert_eq(gs.food_buff(fry), "", "not fed yet")
	var night := gs.day
	fry.age_days = 0  # stays a fry, so it is fed every night
	gs.end_day()
	assert_eq(fry.fed_day, night)
	assert_eq(gs.day, night + 1)
	assert_eq(gs.food_buff(fry), "flakes", "all of the next day")
	assert_eq(gs.food_buff_icon(fry), "arm")
	gs.set_food_choice(Fish.BREEDING, "food")
	gs.inventory.add("food", 1)
	fry.age_days = 0  # stays a fry, so it is fed every night
	gs.end_day()
	assert_eq(gs.food_buff(fry), "", "fed regular food: nothing shown")
	gs.inventory.remove("food", gs.inventory.count("food"))
	gs.set_food_choice(Fish.BREEDING, "flakes")
	fry.age_days = 0  # stays a fry, so it is fed every night
	gs.end_day()
	assert_eq(gs.food_buff(fry), "flakes", "fed flakes again")
	gs.inventory.remove("flakes", gs.inventory.count("flakes"))
	fry.age_days = 0  # stays a fry, so it is fed every night
	gs.end_day()
	assert_eq(gs.food_buff(fry), "", "a night without it, and it is gone")


func test_whole_tank_gets_the_buff_including_adults_with_pellets() -> void:
	_pair()
	gs.inventory.add("pellets", 2)
	gs.set_food_choice(Fish.BREEDING, "pellets")
	gs.end_day()
	for f in gs.tank_fish(gs.breeding_tank):
		assert_eq(gs.food_buff(f), "pellets")
		assert_eq(gs.food_buff_icon(f), "heart")
	assert_true(gs.food_buff_text("pellets").contains("broods +25%"))


func test_buff_and_cycle_counter_survive_save_and_load() -> void:
	_pair()
	gs.inventory.add("pellets", 2)
	gs.set_food_choice(Fish.BREEDING, "pellets")
	gs.end_day()
	var loaded := GameState.from_dict(_db(), F.rng(99), SaveFile.parse(JSON.stringify(gs.to_dict())))
	assert_eq(loaded.brood_food_nights[0], 1)
	for f in loaded.tank_fish(loaded.breeding_tank):
		assert_eq(loaded.food_buff(f), "pellets")
	var d := gs.to_dict()
	d.erase("brood_food_nights")
	for fd in d["fish"]:
		fd.erase("last_food")
		fd.erase("fed_day")
	var old := GameState.from_dict(_db(), F.rng(99), SaveFile.parse(JSON.stringify(d)))
	assert_eq(old.brood_food_nights[0], 0)
	for f in old.tank_fish(old.breeding_tank):
		assert_eq(old.food_buff(f), "")


func test_bonus_fry_are_real_offspring_and_capacity_still_limits() -> void:
	_setup(7, [4, 4])
	_pair()
	gs.inventory.add("pellets", 5)
	gs.set_food_choice(Fish.BREEDING, "pellets")
	gs.breeding_tank.capacity = 4  # two adults + room for two fry
	gs.end_day()
	var s := gs.end_day()
	assert_eq(s["fry_born"], 2)
	assert_eq(gs.tank_fish(gs.breeding_tank).size(), 4)
	for f in gs.tank_fish(gs.breeding_tank):
		if not gs.is_adult(f):
			assert_eq(f.species_id, "guppy")


func test_auto_feeder_with_default_food_uses_none() -> void:
	gs.money = 100
	assert_true(gs.buy_upgrade("feeder"))
	gs.inventory.add("food", 2)
	gs.inventory.add("flakes", 2)
	var fry := _fry()
	assert_eq(gs.food_use_per_night(), 0)
	var s := gs.end_day()
	assert_eq(fry.age_days, 1)
	assert_eq(s["food_used"], 0)
	assert_eq(gs.inventory.count("food"), 2)
	assert_eq(gs.inventory.count("flakes"), 2)


func test_auto_feeder_with_flakes_chosen_uses_a_flake() -> void:
	gs.money = 100
	gs.buy_upgrade("feeder")
	gs.inventory.add("flakes", 2)
	gs.set_food_choice(Fish.BREEDING, "flakes")
	var fry := _fry()
	assert_eq(gs.food_use_per_night(), 1)
	var s := gs.end_day()
	assert_eq(fry.age_days, 2)
	assert_eq(gs.inventory.count("flakes"), 1)
	assert_eq(s["growth_food_used"], 1)


func test_choices_survive_save_and_load() -> void:
	gs.buy_breeding_tank()
	gs.set_food_choice(Fish.BREEDING, "flakes")
	gs.set_food_choice("breeding2", "pellets")
	gs.set_food_choice(Fish.HOLDING, "flakes")
	var loaded := GameState.from_dict(_db(), F.rng(99), SaveFile.parse(JSON.stringify(gs.to_dict())))
	assert_eq(loaded.food_choice(Fish.BREEDING), "flakes")
	assert_eq(loaded.food_choice("breeding2"), "pellets")
	assert_eq(loaded.food_choice(Fish.HOLDING), "flakes")


func test_an_old_save_gets_the_default_food() -> void:
	var d := gs.to_dict()
	d.erase("tank_food")
	var loaded := GameState.from_dict(_db(), F.rng(99), SaveFile.parse(JSON.stringify(d)))
	assert_eq(loaded.food_choice(Fish.BREEDING), "food")
	assert_eq(loaded.food_choice(Fish.HOLDING), "food")
