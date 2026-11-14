extends "res://tests/test_case.gd"

const F := preload("res://tests/fixtures.gd")

var gs: GameState


func before_each() -> void:
	var items := F.items()
	items.append({"id": "flakes", "name": "Growth Flakes", "category": "food", "cost": 8, "price": 10,
		"tags": [], "growth_days": 2})
	var db := DataDB.from_dicts([F.species()], items, [F.template()], F.economy(), F.strains(), F.goals(),
		F.upgrades(), [], [], F.reputation(), F.shows(), F.staff())
	gs = GameState.new_game(db, F.rng())
	gs.inventory.remove("food", gs.inventory.count("food"))


func _fry(age: int = 0) -> Fish:
	var f := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, age))
	gs.move_fish(f.id, Fish.BREEDING)
	return f


func test_chosen_flakes_used_instead_of_normal_food() -> void:
	gs.inventory.add("food", 3)
	gs.inventory.add("flakes", 1)
	assert_true(gs.set_food_choice(Fish.BREEDING, "flakes"))
	var fry := _fry()
	var s := gs.end_day()
	assert_eq(gs.inventory.count("flakes"), 0)
	assert_eq(gs.inventory.count("food"), 3)
	assert_eq(fry.age_days, 2)
	assert_eq(s["growth_food_used"], 1)


func test_growth_capped_at_adulthood_and_stars_rolled_once() -> void:
	gs.inventory.add("flakes", 1)
	var fry := _fry(2)  # days_to_adult is 3
	var s := gs.end_day()
	assert_eq(fry.age_days, 3, "grows up, doesn't overshoot")
	assert_true(gs.is_adult(fry))
	assert_eq(s["fry_grown_up"], 1)
	assert_eq(s["grown_ids"].count(fry.id), 1)


func test_normal_food_when_flakes_run_out() -> void:
	gs.inventory.add("food", 1)
	var fry := _fry()
	var s := gs.end_day()
	assert_eq(fry.age_days, 1)
	assert_eq(s["growth_food_used"], 0)


func test_auto_feeder_uses_a_flake_when_chosen_and_in_stock() -> void:
	gs.money = 100
	assert_true(gs.buy_upgrade("feeder"))
	assert_true(gs.set_food_choice(Fish.BREEDING, "flakes"))
	var plain := _fry()
	var s := gs.end_day()
	assert_eq(plain.age_days, 1, "free day of growth, no food used")
	assert_eq(s["food_used"], 0)
	gs.inventory.add("flakes", 1)
	s = gs.end_day()
	assert_eq(plain.age_days, 3, "a flake: two more days")
	assert_eq(gs.inventory.count("flakes"), 0)
	assert_eq(s["growth_food_used"], 1)


func test_summary_counts_flakes_used() -> void:
	gs.inventory.add("flakes", 2)
	gs.buy_breeding_tank()
	gs.set_food_choice(Fish.BREEDING, "flakes")
	gs.set_food_choice("breeding2", "flakes")
	var a := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 0))
	var b := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 0))
	gs.move_fish(a.id, Fish.BREEDING)
	gs.move_fish(b.id, "breeding2")
	var s := gs.end_day()
	assert_eq(s["growth_food_used"], 2)
	assert_eq(s["food_used"], 2)


func test_holding_is_fed_before_breeding_tanks() -> void:
	gs.inventory.add("food", 1)
	var in_tank := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 0))
	gs.move_fish(in_tank.id, Fish.BREEDING)
	var in_holding := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 0))
	var s := gs.end_day()
	assert_eq(in_holding.age_days, 1, "holding got the only portion")
	assert_eq(in_tank.age_days, 0)
	assert_eq(s["fry_unfed"], 1)
	assert_eq(s["unfed_places"], ["Tank 1"])


func _holding_fry(age: int = 0) -> Fish:
	var f := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, age))
	gs.move_fish(f.id, Fish.HOLDING)
	return f


func test_holding_fry_grow_a_day_without_food() -> void:
	var fry := _holding_fry()
	var bred := _fry()
	var s := gs.end_day()
	assert_eq(fry.location, Fish.HOLDING)
	assert_eq(fry.age_days, 1, "holding fry grow at the regular rate with no food")
	assert_true(fry.fed_every_night, "not counted as going hungry")
	assert_eq(bred.age_days, 0, "breeding-tank fry still need food")
	assert_false("Holding" in s["unfed_places"])


func test_holding_fry_still_eat_food_when_there_is_some() -> void:
	gs.inventory.add("flakes", 1)
	assert_true(gs.set_food_choice(Fish.HOLDING, "flakes"))
	var fry := _holding_fry()
	gs.end_day()
	assert_eq(fry.age_days, 2, "flakes still speed them up")
	assert_eq(gs.inventory.count("flakes"), 0)
