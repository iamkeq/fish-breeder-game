extends "res://tests/test_case.gd"
## The Gallery: favourites, the Hall of Fame, pinning portraits, goals, saving.

const F := preload("res://tests/fixtures.gd")

var gs: GameState


func before_each() -> void:
	gs = F.new_game()
	gs.reputation = 100  # "Famous": shows and the gallery wall are open in the fixture data


func _adult(color: String = "grey", stars: int = 3, purity: int = 50) -> Fish:
	var f := F.fish(Fish.FEMALE, color, stars, 3)
	f.purity = purity
	return gs.inventory.add_fish(f)


func _fav(color: String = "grey", stars: int = 3) -> Fish:
	var f := _adult(color, stars)
	assert_true(gs.set_favorite(f.id, true))
	return f


## Wins a show with this fish (rivals are made hopeless) and returns the summary.
func _win_show(f: Fish, day: int) -> void:
	gs.db.shows["rival_strength"]["base"] = 0
	gs.day = day
	assert_true(gs.enter_show(f.id), gs.show_blocker(f.id))
	gs.end_day()


func _reload(state: GameState) -> GameState:
	return GameState.from_dict(F.db(), F.rng(99), SaveFile.parse(JSON.stringify(state.to_dict())))


# --- Favourites

func test_only_favourites_are_listed_best_stars_first() -> void:
	var low := _fav("grey", 2)
	var high := _fav("red", 5)
	_adult("orange", 4)  # not a favourite
	var list := gs.gallery_favorites()
	assert_eq(list.size(), 2)
	assert_eq(list[0]["fish_id"], high.id)
	assert_eq(list[1]["fish_id"], low.id)
	assert_eq(list[0]["key"], "fav:%d" % high.id)
	assert_eq(list[0]["stars"], 5)
	assert_eq(list[0]["traits"]["body_color"], "red")
	assert_eq(list[0]["species_id"], "guppy")


func test_equal_stars_sort_by_id_and_entries_carry_names_and_ribbons() -> void:
	var a := _fav("grey", 3)
	var b := _fav("red", 3)
	b.nickname = "Bubbles"
	b.scanned = true
	b.purity = 92
	b.ribbons.append({"place": 2, "show": "Open Show", "day": 7})
	var list := gs.gallery_favorites()
	assert_eq(list[0]["fish_id"], a.id)
	assert_eq(list[1]["nickname"], "Bubbles")
	assert_true(list[1]["scanned"])
	assert_eq(list[1]["purity"], 92)
	assert_eq(list[1]["ribbons"], [{"place": 2, "show": "Open Show", "day": 7}])
	assert_true(list[1]["title"].begins_with("Bubbles"))


func test_unfavouriting_removes_the_entry() -> void:
	var f := _fav()
	gs.set_favorite(f.id, false)
	assert_eq(gs.gallery_favorites(), [])


# --- Hall of Fame

func test_a_win_records_the_fish_id_and_appears_in_the_hall() -> void:
	var f := _adult("red", 5, 100)
	f.nickname = "Bubbles"
	_win_show(f, 7)
	assert_eq(gs.show_history[0]["fish"]["fish_id"], f.id)
	var hall := gs.gallery_hall()
	assert_eq(hall.size(), 1)
	assert_eq(hall[0]["key"], "hof:0")
	assert_eq(hall[0]["place"], 1)
	assert_eq(hall[0]["show_name"], "Open Show")
	assert_eq(hall[0]["day"], 7)
	assert_eq(hall[0]["fish_id"], f.id)
	assert_eq(hall[0]["nickname"], "Bubbles")
	assert_eq(hall[0]["ribbons"], [{"place": 1, "show": "Open Show", "day": 7}])


func test_hall_is_newest_first_and_survives_the_fish_being_sold() -> void:
	var f := _adult("red", 5, 100)
	f.nickname = "Bubbles"
	_win_show(f, 7)
	var g := _adult("orange", 5, 100)
	_win_show(g, 14)
	gs.sell_fish(f.id)
	gs.inventory.remove_fish(g.id)
	var hall := gs.gallery_hall()
	assert_eq(hall.size(), 2)
	assert_eq(hall[0]["day"], 14)
	assert_eq(hall[0]["key"], "hof:1")
	assert_eq(hall[1]["nickname"], "Bubbles")
	assert_eq(hall[1]["traits"]["body_color"], "red")


func test_a_favourite_that_won_shows_in_both_lists() -> void:
	var f := _adult("red", 5, 100)
	gs.set_favorite(f.id, true)
	_win_show(f, 7)
	assert_eq(gs.gallery_favorites().size(), 1)
	assert_eq(gs.gallery_favorites()[0]["ribbons"].size(), 1)
	assert_eq(gs.gallery_hall().size(), 1)


func test_old_history_without_a_fish_id_still_lists() -> void:
	gs.show_history.append({"day": 7, "show_number": 1, "show_name": "Open Show", "place": 2, "grand": false,
		"fish": {"species_id": "guppy", "traits": {"body_color": "red", "tail_shape": "round", "pattern": "plain"},
			"sex": "male", "stars": 4, "nickname": "", "purity": 60, "scanned": false}})
	var hall := gs.gallery_hall()
	assert_eq(hall.size(), 1)
	assert_eq(hall[0]["fish_id"], 0)
	assert_eq(hall[0]["stars"], 4)


# --- Pins

func test_pinning_needs_the_unlock() -> void:
	var f := _fav()
	gs.reputation = 0
	assert_eq(gs.pin_slots(), 0)
	assert_eq(gs.pin_blocker("fav:%d" % f.id), "Reach 'Famous' to pin portraits")
	assert_false(gs.pin_portrait("fav:%d" % f.id))
	gs.reputation = 100
	assert_eq(gs.pin_slots(), 2)
	assert_eq(gs.pin_blocker("fav:%d" % f.id), "")
	assert_true(gs.pin_portrait("fav:%d" % f.id))
	assert_eq(gs.pinned_entries().size(), 1)


func test_the_wall_has_a_slot_cap() -> void:
	var a := _fav("grey")
	var b := _fav("red")
	var c := _fav("orange")
	assert_true(gs.pin_portrait("fav:%d" % a.id))
	assert_true(gs.pin_portrait("fav:%d" % b.id))
	assert_eq(gs.pin_blocker("fav:%d" % c.id), "The wall is full")
	assert_false(gs.pin_portrait("fav:%d" % c.id))
	assert_true(gs.unpin_portrait("fav:%d" % a.id))
	assert_true(gs.pin_portrait("fav:%d" % c.id))


func test_duplicate_and_unknown_keys_are_refused() -> void:
	var f := _fav()
	var key := "fav:%d" % f.id
	assert_true(gs.pin_portrait(key))
	assert_eq(gs.pin_blocker(key), "Already pinned")
	assert_false(gs.pin_portrait(key))
	assert_eq(gs.gallery_pins.size(), 1)
	assert_eq(gs.pin_blocker("fav:9999"), "That portrait isn't in your gallery")
	assert_eq(gs.pin_blocker("hof:3"), "That portrait isn't in your gallery")
	assert_eq(gs.pin_blocker("nonsense"), "That portrait isn't in your gallery")
	assert_false(gs.unpin_portrait("fav:9999"))


func test_hall_portraits_can_be_pinned() -> void:
	var f := _adult("red", 5, 100)
	_win_show(f, 7)
	assert_true(gs.pin_portrait("hof:0"))
	var pinned := gs.pinned_entries()
	assert_eq(pinned.size(), 1)
	assert_eq(pinned[0]["key"], "hof:0")


func test_unfavouriting_a_pinned_fish_drops_it_quietly() -> void:
	var a := _fav("grey")
	var b := _fav("red")
	gs.pin_portrait("fav:%d" % a.id)
	gs.pin_portrait("fav:%d" % b.id)
	gs.set_favorite(a.id, false)
	var pinned := gs.pinned_entries()
	assert_eq(pinned.size(), 1)
	assert_eq(pinned[0]["fish_id"], b.id)
	# The dead pin no longer takes a slot, and the saved list is tidied on change.
	var c := _fav("orange")
	assert_true(gs.pin_portrait("fav:%d" % c.id))
	assert_eq(gs.gallery_pins, ["fav:%d" % b.id, "fav:%d" % c.id])


func test_entry_fish_is_a_grown_up_copy() -> void:
	var f := _fav("red", 4)
	var copy := gs.entry_fish(gs.gallery_favorites()[0])
	assert_eq(copy.traits, f.traits)
	assert_eq(copy.stars, 4)
	assert_true(gs.is_adult(copy))
	assert_false(gs.inventory.has_fish(copy.id) and gs.inventory.get_fish(copy.id) == copy)


# --- Goals

func test_the_gallery_metrics_count_history_and_pins() -> void:
	assert_eq(gs.goal_value("hall_of_fame"), 0)
	assert_eq(gs.goal_value("pinned"), 0)
	var f := _fav("red", 5)
	f.purity = 100
	_win_show(f, 7)
	assert_eq(gs.goal_value("hall_of_fame"), 1)
	gs.pin_portrait("fav:%d" % f.id)
	assert_eq(gs.goal_value("pinned"), 1)
	gs.set_favorite(f.id, false)
	assert_eq(gs.goal_value("pinned"), 0, "a pin that no longer resolves doesn't count")


func test_real_data_has_the_gallery_goals_and_setting() -> void:
	var db := DataDB.load_from_dir("res://data")
	assert_eq(db.errors, [] as Array[String])
	var by_id := {}
	for g in db.goals:
		by_id[g["id"]] = g
	assert_eq(by_id["hall_3"]["metric"], "hall_of_fame")
	assert_eq(by_id["hall_3"]["target"], 3)
	assert_eq(by_id["first_pin"]["reward"], 30)
	assert_eq(by_id["full_wall"]["target"], 6)
	assert_eq(int(db.economy["gallery"]["pin_slots"]), 6)


func test_economy_needs_gallery_pin_slots() -> void:
	var economy := F.economy()
	economy.erase("gallery")
	var db := DataDB.from_dicts([F.species()], F.items(), [F.template()], economy, F.strains(), F.goals(), F.upgrades())
	assert_false(db.errors.is_empty())


# --- Saving

func test_pins_survive_save_and_load() -> void:
	var a := _fav("grey")
	var f := _adult("red", 5, 100)
	_win_show(f, 7)
	gs.pin_portrait("fav:%d" % a.id)
	gs.pin_portrait("hof:0")
	var loaded := _reload(gs)
	assert_eq(loaded.gallery_pins, ["fav:%d" % a.id, "hof:0"])
	assert_eq(loaded.pinned_entries().size(), 2)
	assert_eq(loaded.gallery_hall()[0]["fish_id"], f.id)


func test_an_old_save_without_pins_loads() -> void:
	var d := gs.to_dict()
	d.erase("gallery_pins")
	var loaded := GameState.from_dict(F.db(), F.rng(), d)
	assert_eq(loaded.gallery_pins, [])
	assert_eq(loaded.pinned_entries(), [])
