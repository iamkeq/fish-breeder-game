extends "res://tests/test_case.gd"
## Harem breeding: one sire and up to max_mothers mothers per breeding tank.

const F := preload("res://tests/fixtures.gd")

var gs: GameState


func before_each() -> void:
	gs = F.new_game()
	var species: Dictionary = gs.db.species["guppy"]
	species["brood_size"] = [3, 3]
	species["mutation_chance"] = 0.0
	for f in gs.inventory.fish_list():
		gs.inventory.remove_fish(f.id)
	gs.inventory.add("food", 50)
	gs.breeding_tank.capacity = 20  # roomy, so only the tests about space are limited by it


## Adds an adult to a breeding tank (default the first).
func _put(sex: String, color: String = "grey", tank: String = Fish.BREEDING) -> Fish:
	var f := gs.inventory.add_fish(F.fish(sex, color))
	assert_true(gs.move_fish(f.id, tank), "fits in the tank")
	return f


func _fry_count() -> int:
	return gs.inventory.fish_list(Fish.BREEDING).filter(func(f): return not gs.is_adult(f)).size()


# --- The group

func test_group_is_the_first_male_and_every_female() -> void:
	var f1 := _put(Fish.FEMALE)
	var m1 := _put(Fish.MALE, "orange")
	var f2 := _put(Fish.FEMALE)
	_put(Fish.MALE)
	var group := gs.breeding_group()
	assert_eq(group["father"], m1, "the first male in tank order")
	assert_eq(group["mothers"], [f1, f2] as Array[Fish])
	assert_eq(gs.breeding_pair(), [f1, m1], "the pair keeps its old meaning")
	assert_eq(gs.breeding_group_fish(), [m1, f1, f2] as Array[Fish])


func test_no_group_without_both_sexes() -> void:
	var empty := gs.breeding_group()
	assert_eq(empty["father"], null)
	assert_eq(empty["mothers"].size(), 0)
	_put(Fish.MALE)
	assert_eq(gs.breeding_group()["father"], null)
	assert_eq(gs.breeding_pair(), [])
	assert_eq(gs.nights_until_brood(), -1)
	assert_eq(gs.breeding_group_fish(), [] as Array[Fish])


func test_fry_and_other_species_are_not_mothers() -> void:
	var other := F.species()
	other["id"] = "tetra"
	other["name"] = "Tetra"
	gs.db.species["tetra"] = other
	_put(Fish.MALE)
	var tetra := F.fish(Fish.FEMALE)
	tetra.species_id = "tetra"
	gs.inventory.add_fish(tetra)
	gs.move_fish(tetra.id, Fish.BREEDING)
	var fry := gs.inventory.add_fish(F.fish(Fish.FEMALE, "grey", 0, 0))
	gs.move_fish(fry.id, Fish.BREEDING)
	assert_eq(gs.breeding_group()["mothers"].size(), 0, "a tetra and a fry are no match for a guppy sire")
	var mum := _put(Fish.FEMALE)
	assert_eq(gs.breeding_group()["mothers"], [mum] as Array[Fish])


# --- Broods

func test_two_mothers_both_have_a_brood() -> void:
	_put(Fish.MALE)
	_put(Fish.FEMALE)
	_put(Fish.FEMALE, "orange")
	assert_eq(gs.nights_until_brood(), 2)
	assert_eq(gs.end_day()["fry_born"], 0)
	var s := gs.end_day()
	assert_eq(s["fry_born"], 6, "3 fry from each mother")
	assert_eq(_fry_count(), 6)


func test_the_mother_cap_is_respected() -> void:
	_put(Fish.MALE)
	for i in 4:
		_put(Fish.FEMALE)
	assert_eq(gs.breeding_group()["mothers"].size(), 3, "cap is 3")
	gs.end_day()
	assert_eq(gs.end_day()["fry_born"], 9, "3 broods of 3, not 4")


func test_a_second_male_does_not_breed() -> void:
	_put(Fish.FEMALE)
	_put(Fish.MALE)
	_put(Fish.MALE, "orange")
	gs.end_day()
	assert_eq(gs.end_day()["fry_born"], 3, "one brood, from the one sire")


func test_broods_stop_when_the_tank_is_full() -> void:
	gs.breeding_tank.capacity = 8
	_put(Fish.MALE)
	_put(Fish.FEMALE)
	_put(Fish.FEMALE)
	_put(Fish.FEMALE)
	gs.end_day()
	var s := gs.end_day()
	assert_eq(gs.breeding_tank.fish_ids.size(), 8, "the tank holds 8 (4 adults + 4 fry)")
	assert_eq(s["fry_born"], 4, "the rest of the broods had no room")
	assert_eq(_fry_count(), 4)


func test_without_max_mothers_in_data_one_pair_breeds() -> void:
	gs.db.economy["breeding_tanks"].erase("max_mothers")
	var mum := _put(Fish.FEMALE)
	var dad := _put(Fish.MALE)
	_put(Fish.FEMALE)
	assert_eq(gs.max_mothers(), 1)
	assert_eq(gs.breeding_pair(), [mum, dad])
	gs.end_day()
	assert_eq(gs.end_day()["fry_born"], 3, "one brood, as before")


func test_each_tank_keeps_its_own_group() -> void:
	gs.buy_breeding_tank()
	_put(Fish.MALE)
	_put(Fish.FEMALE)
	_put(Fish.FEMALE)
	var spare_mum := _put(Fish.FEMALE, "grey", "breeding2")
	assert_eq(gs.breeding_group(1)["father"], null, "a mother alone in tank 2 has no sire")
	assert_false(spare_mum in gs.breeding_group_fish(0))
	gs.end_day()
	assert_eq(gs.end_day()["fry_born"], 6)


# --- Who gets the credit

func test_a_new_variety_names_the_mother_it_came_from() -> void:
	var species: Dictionary = gs.db.species["guppy"]
	species["recipes"] = {"body_color": [{"parents": ["orange", "grey"], "child": "red"}]}
	species["recipe_chance"] = 1.0
	_put(Fish.FEMALE, "orange")  # orange x orange: no recipe
	var grey_mum := _put(Fish.FEMALE, "grey")
	_put(Fish.MALE, "orange")
	gs.end_day()
	var s := gs.end_day()
	assert_eq(s["fry_born"], 6)
	assert_eq(s["mutations"].size(), 3, "only the grey mother's three fry are a new look")
	for m in s["mutations"]:
		assert_eq(m["source"], "recipe")
		assert_eq(m["value"], "red")
		assert_eq(m["parents"], ["grey", "orange"], "the grey mother's colour, not the first mother's")
	assert_eq(s["discoveries"].size(), 1)
	assert_eq(s["discoveries"][0]["parents"], ["grey", "orange"])
	assert_true(grey_mum != null)
	assert_true(gs.discovered_recipes.has(GameState.book_key("body_color", "grey", "orange")))
	assert_false(gs.discovered_recipes.has(GameState.book_key("body_color", "orange", "orange")))


# --- Back-orders

func _backorder(sex: String, color: String) -> Dictionary:
	return {"name": "Mabel", "species_id": "guppy", "sex": sex, "traits": {"body_color": color},
		"price": 20, "due_day": 1, "source": "bred"}


func test_back_orders_never_take_a_group_member() -> void:
	var sire := _put(Fish.MALE, "red")
	var m1 := _put(Fish.FEMALE, "red")
	var m2 := _put(Fish.FEMALE, "red")
	var m3 := _put(Fish.FEMALE, "red")
	var extra := _put(Fish.FEMALE, "red")
	assert_eq(gs.breeding_group()["mothers"], [m1, m2, m3] as Array[Fish])
	assert_eq(gs.backorder_fish(_backorder(Fish.FEMALE, "red")), extra, "only the one beyond the cap")
	assert_eq(gs.backorder_fish(_backorder(Fish.MALE, "red")), null, "never the sire")
	gs.move_fish(extra.id, Fish.HOLDING)
	gs.sell_fish_wholesale(extra.id)
	assert_eq(gs.backorder_fish(_backorder(Fish.FEMALE, "red")), null, "never a mother")
	assert_true(sire != null)


func test_breed_order_keeps_a_group_member_safe() -> void:
	gs.money = 500
	var f := gs.buy_strain("red_delta", Fish.FEMALE)
	gs.move_fish(f.id, Fish.DISPLAY)
	gs.customer = {"kind": "fish", "fish_id": f.id, "name": "Priya", "waited": 0.0, "patience": 60.0}
	assert_true(gs.breed_order_for_customer())
	gs.move_fish(f.id, Fish.BREEDING)
	_put(Fish.MALE, "red")
	var order: Dictionary = gs.backorders[0]
	assert_eq(order["keep_id"], f.id)
	assert_eq(gs.backorder_fish(order), null, "the kept fish is one of the mothers")
	gs.db.economy["breeding_tanks"]["max_mothers"] = 1
	var daughter := _put(Fish.FEMALE, "red")
	daughter.traits = f.traits.duplicate()
	assert_eq(gs.backorder_fish(order), daughter, "a grown daughter beyond the cap can go; the kept fish never")


# --- Data

func test_real_data_loads_clean_with_the_mother_cap() -> void:
	var db := DataDB.load_from_dir("res://data")
	assert_eq(db.errors, [] as Array[String])
	assert_eq(int(db.economy["breeding_tanks"]["max_mothers"]), 3)
	var state := GameState.new_game(db, F.rng())
	assert_eq(state.max_mothers(), 3)
	assert_eq(state.breeding_group()["mothers"].size(), 1, "the starting pair is a group of one mother")


func test_a_bad_max_mothers_is_reported() -> void:
	var economy := F.economy()
	economy["breeding_tanks"]["max_mothers"] = 0
	var db := DataDB.from_dicts([F.species()], F.items(), [F.template()], economy)
	assert_eq(db.errors.size(), 1)
