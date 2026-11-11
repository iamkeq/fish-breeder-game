extends "res://tests/test_case.gd"
## Fish shows: schedule, entering, judging, prizes, ribbons, saving and tuning.

const F := preload("res://tests/fixtures.gd")

var gs: GameState


func before_each() -> void:
	gs = F.new_game()
	gs.reputation = 60  # "Liked": shows are open in the fixture data


func _adult(color: String = "grey", stars: int = 3, purity: int = 50, tail: String = "round", pattern: String = "plain") -> Fish:
	var f := F.fish(Fish.FEMALE, color, stars, 3, tail, pattern)
	f.purity = purity
	return gs.inventory.add_fish(f)


# --- Schedule

func test_shows_follow_the_calendar_and_rotate() -> void:
	var data: Dictionary = gs.db.shows
	assert_eq(Shows.number_for_day(1, data), 1)
	assert_eq(Shows.number_for_day(7, data), 1)
	assert_eq(Shows.number_for_day(8, data), 2)
	assert_eq(Shows.day_of(2, data), 14)
	assert_true(Shows.is_show_day(14, data))
	assert_false(Shows.is_show_day(13, data))
	assert_eq(Shows.describe(1, data)["id"], "open")
	assert_eq(Shows.describe(2, data)["id"], "stars3")
	assert_eq(Shows.describe(6, data)["id"], "open", "the list rotates")
	assert_false(Shows.describe(3, data)["grand"])
	var grand := Shows.describe(4, data)
	assert_true(grand["grand"])
	assert_eq(grand["name"], "Grand Oddity Class")


func test_next_show_counts_days() -> void:
	var show := gs.next_show()
	assert_eq(show["number"], 1)
	assert_eq(show["day"], 7)
	assert_eq(show["days_left"], 6)
	gs.day = 7
	assert_eq(gs.next_show()["days_left"], 0, "tonight")
	gs.day = 8
	assert_eq(gs.next_show()["number"], 2)
	assert_eq(gs.next_show()["day"], 14)


func test_prizes_and_grand_multiplier() -> void:
	assert_eq(gs.show_prize(1, false), 75)
	assert_eq(gs.show_prize(3, false), 20)
	assert_eq(gs.show_prize(1, true), 150)
	assert_eq(gs.show_prize(4, false), 0)


# --- Eligibility

func test_shows_need_the_reputation_unlock() -> void:
	var f := _adult()
	assert_true(gs.shows_unlocked())
	gs.reputation = 0
	assert_false(gs.shows_unlocked())
	assert_eq(gs.show_blocker(f.id), "Fish shows aren't open yet.")
	assert_false(gs.enter_show(f.id))


func test_open_show_takes_any_adult_but_not_fry_or_order_tank_fish() -> void:
	var f := _adult()
	assert_eq(gs.show_blocker(f.id), "")
	var fry := gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 0))
	assert_eq(gs.show_blocker(fry.id), "Only grown-up fish can enter.")
	assert_eq(gs.show_blocker(9999), "No such fish.")
	f.location = Fish.order_location(1)
	assert_ne(gs.show_blocker(f.id), "")


func test_class_rules_and_their_blockers() -> void:
	var plain := _adult("grey", 2)
	var good := _adult("grey", 4)
	var red := _adult("red", 2)
	gs.day = 8  # show 2: Quality Class (3 stars or more)
	assert_eq(gs.show_blocker(plain.id), "Needs 3 stars or more.")
	assert_eq(gs.show_blocker(good.id), "")
	gs.day = 15  # show 3: Rare Colours
	assert_eq(gs.show_blocker(plain.id), "Needs a rare trait.")
	assert_eq(gs.show_blocker(red.id), "")
	gs.day = 22  # show 4: Grand Oddity Class (mutations only)
	gs.db.species["guppy"]["traits"]["pattern"]["mutations"] = []  # mosaic is rare but not a mutation
	var mosaic := _adult("grey", 3, 50, "round", "mosaic")
	assert_eq(gs.show_blocker(mosaic.id), "Mutation fish only.")
	assert_eq(gs.show_blocker(red.id), "")
	gs.day = 29  # show 5: Pure Line Class
	assert_true("Lab scan" in gs.show_blocker(red.id))
	red.scanned = true
	red.purity = 60
	assert_true("60%" in gs.show_blocker(red.id), gs.show_blocker(red.id))
	red.purity = 70
	assert_eq(gs.show_blocker(red.id), "")


func test_enter_withdraw_and_replace() -> void:
	var a := _adult()
	var b := _adult("orange")
	assert_true(gs.enter_show(a.id))
	assert_eq(gs.show_entry_fish(), a)
	assert_true(gs.enter_show(b.id), "one entry at a time: the new one replaces it")
	assert_eq(gs.show_entry_fish(), b)
	gs.withdraw_show()
	assert_eq(gs.show_entry_fish(), null)
	assert_false(gs.enter_show(9999))


func test_favourites_may_enter_and_stay_where_they_are() -> void:
	var f := _adult()
	f.favorite = true
	f.location = Fish.DISPLAY
	assert_true(gs.enter_show(f.id))
	assert_eq(f.location, Fish.DISPLAY, "not moved")


func test_selling_the_entry_lapses_it_quietly() -> void:
	gs.day = 7
	var f := _adult()
	gs.enter_show(f.id)
	var money := gs.money
	gs.sell_fish(f.id)
	assert_eq(gs.show_entry_fish(), null)
	gs.check_goals()
	var rep := gs.reputation
	var summary := gs.end_day()
	assert_false(summary.has("show"))
	assert_eq(gs.shows_held, 1, "the show day still passed")
	assert_eq(gs.show_entry, 0)
	assert_eq(gs.stat("shows_entered"), 0)
	assert_eq(gs.reputation, rep, "no show reputation")
	assert_true(gs.money > money)


# --- Judging

func test_no_entry_only_advances_the_calendar() -> void:
	gs.day = 7
	var rep := gs.reputation
	var money := gs.money
	var summary := gs.end_day()
	assert_false(summary.has("show"))
	assert_eq(gs.shows_held, 1)
	assert_eq(gs.reputation, rep)
	assert_eq(gs.money, money)
	assert_eq(gs.stat("shows_entered"), 0)
	gs.day = 3
	gs.end_day()
	assert_eq(gs.shows_held, 1, "day 3 is not a show day")


func test_an_entry_waits_for_show_day() -> void:
	var f := _adult("grey", 5, 100)
	gs.day = 3
	gs.enter_show(f.id)
	var summary := gs.end_day()
	assert_false(summary.has("show"))
	assert_eq(gs.show_entry, f.id, "still entered for day 7")


func test_a_winning_entry_earns_ribbon_prize_reputation_and_a_snapshot() -> void:
	gs.db.shows["rival_strength"]["base"] = 0
	gs.day = 7
	var f := _adult("red", 5, 100)
	f.nickname = "Bubbles"
	f.scanned = true
	gs.enter_show(f.id)
	var money := gs.money
	var rep := gs.reputation
	var summary := gs.end_day()
	var show: Dictionary = summary["show"]
	assert_eq(show["place"], 1)
	assert_eq(show["prize"], 75)
	assert_eq(show["show_name"], "Open Show")
	assert_eq(show["fish_label"], "Bubbles")
	assert_eq(show["rep"], 3 + 25)
	assert_eq(show["top_rivals"].size(), 3)
	assert_true(show["top_rivals"][0]["score"] >= show["top_rivals"][1]["score"])
	assert_eq(gs.money, money + 75, "paid straight into money, not as a sale")
	assert_eq(gs.reputation, rep + 28)
	assert_eq(f.ribbons, [{"place": 1, "show": "Open Show", "day": 7}])
	assert_eq(gs.stat("shows_entered"), 1)
	assert_eq(gs.stat("ribbons_first"), 1)
	assert_eq(gs.stat("show_prizes"), 75)
	assert_eq(gs.shows_held, 1)
	assert_eq(gs.show_entry, 0)
	assert_eq(gs.show_history.size(), 1)
	var entry: Dictionary = gs.show_history[0]
	assert_eq(entry["place"], 1)
	assert_eq(entry["show_name"], "Open Show")
	assert_false(entry["grand"])
	assert_eq(entry["fish"]["nickname"], "Bubbles")
	assert_eq(entry["fish"]["stars"], 5)
	assert_eq(entry["fish"]["traits"]["body_color"], "red")
	assert_true(entry["fish"]["scanned"])
	# The snapshot stays even when the fish is sold.
	gs.sell_fish(f.id)
	assert_eq(gs.show_history[0]["fish"]["nickname"], "Bubbles")


func test_a_poor_placing_costs_nothing() -> void:
	gs.db.shows["rival_strength"]["base"] = 1000
	gs.day = 7
	var f := _adult("grey", 1, 10)
	gs.enter_show(f.id)
	var money := gs.money
	var summary := gs.end_day()
	var show: Dictionary = summary["show"]
	assert_eq(show["place"], 6)
	assert_eq(show["prize"], 0)
	assert_eq(show["rep"], 3, "entering still earns the entry points")
	assert_eq(gs.money, money)
	assert_eq(f.ribbons, [])
	assert_eq(gs.show_history, [])
	assert_eq(gs.stat("shows_entered"), 1)
	assert_true(gs.inventory.has_fish(f.id), "nothing lost")


func test_grand_show_pays_double_and_counts_grand_wins() -> void:
	gs.db.shows["rival_strength"]["base"] = 0
	gs.day = 28  # show 4, Grand Oddity Class
	var f := _adult("red", 5, 100)
	assert_true(gs.enter_show(f.id), gs.show_blocker(f.id))
	var summary := gs.end_day()
	assert_true(summary["show"]["grand"])
	assert_eq(summary["show"]["show_name"], "Grand Oddity Class")
	assert_eq(summary["show"]["prize"], 150)
	assert_eq(gs.stat("grand_wins"), 1)
	assert_eq(f.ribbons[0]["show"], "Grand Oddity Class")


func test_places_two_and_three_are_possible_and_counted() -> void:
	# A middling fish against mid-strength rivals lands everywhere over many seeds.
	var seen := {}
	for seed_value in range(1, 200):
		var g := GameState.new_game(F.db(), F.rng(seed_value))
		g.reputation = 60
		g.day = 7
		var f := g.inventory.add_fish(F.fish(Fish.FEMALE, "grey", 3, 3))
		g.enter_show(f.id)
		var place: int = g.end_day()["show"]["place"]
		seen[place] = int(seen.get(place, 0)) + 1
		if place <= 3:
			assert_eq(f.ribbons[0]["place"], place)
			assert_eq(g.stat(["", "ribbons_first", "ribbons_second", "ribbons_third"][place]), 1)
			assert_eq(g.stat("show_prizes"), Shows.prize(place, false, g.db.shows))
	for place in [1, 2, 3]:
		assert_true(seen.has(place), "place %d never happened: %s" % [place, str(seen)])


func test_judging_is_deterministic_under_a_seed() -> void:
	var results := []
	for i in 2:
		var g := GameState.new_game(F.db(), F.rng(77))
		g.reputation = 60
		g.day = 7
		var f := g.inventory.add_fish(F.fish(Fish.FEMALE, "grey", 3, 3))
		g.enter_show(f.id)
		results.append(g.end_day()["show"])
	assert_eq(results[0], results[1])


# --- Goals

func test_show_goals_and_ribbon_counts() -> void:
	gs.stats["ribbons_first"] = 1
	gs.stats["ribbons_second"] = 2
	gs.stats["ribbons_third"] = 3
	assert_eq(gs.goal_value("ribbons"), 6)
	var db := DataDB.load_from_dir("res://data")
	for id in ["first_show", "first_ribbon", "blue_ribbon", "ribbons_5", "grand_win"]:
		assert_true(db.goals.any(func(g): return g["id"] == id), id)


func test_entering_a_show_completes_its_goal_in_real_data() -> void:
	var db := DataDB.load_from_dir("res://data")
	var g := GameState.new_game(db, F.rng(5))
	g.stats["shows_entered"] = 1
	var ids := g.check_goals().map(func(goal): return goal["id"])
	assert_has(ids, "first_show")


# --- Hints and scoring

func test_hints_use_visible_looks_only() -> void:
	var data: Dictionary = gs.db.shows
	assert_eq(Shows.hint(1, false, 5, 1, data), "Looks promising")
	assert_eq(Shows.hint(1, false, 3, 1, data), "Good chance")
	assert_eq(Shows.hint(1, false, 1, 1, data), "Long shot")
	var f := _adult("grey", 3, 10)
	var g := _adult("grey", 3, 100)
	assert_eq(gs.show_hint(f), gs.show_hint(g), "hidden purity does not change the hint")


func test_value_step_is_the_rounded_variety_multiplier() -> void:
	assert_eq(gs.show_value_step(_adult("grey")), 1)
	assert_eq(gs.show_value_step(_adult("red")), 2, "rare x1.5 rounds to 2")
	gs.db.species["guppy"]["value_multipliers"] = {"body_color": {"red": 4.0}}
	assert_eq(gs.show_value_step(_adult("red")), 4)


func test_rivals_are_stronger_each_show_and_in_grand_shows() -> void:
	var data: Dictionary = gs.db.shows
	assert_eq(Shows.rival_strength(1, false, data), 70.0)
	assert_eq(Shows.rival_strength(3, false, data), 73.0)
	assert_eq(Shows.rival_strength(100, false, data), 95.0, "capped")
	assert_eq(Shows.rival_strength(4, true, data), 70.0 + 4.5 + 12.0)


# --- Tuning (real data)

func _win_rate(data: Dictionary, stars: int, step: int, purity: int, number: int, seeds: int = 400) -> Array:
	var wins := 0
	var podium := 0
	var base := Shows.base_score(stars, step, purity, data)
	for s in range(1, seeds + 1):
		var r := Shows.judge(base, number, Shows.is_grand(number, data), data, F.rng(s))
		if r["place"] == 1:
			wins += 1
		if r["place"] <= 3:
			podium += 1
	return [float(wins) / seeds, float(podium) / seeds]


func test_tuning_better_fish_win_more_and_one_star_rarely_wins() -> void:
	var data: Dictionary = DataDB.load_from_dir("res://data").shows
	for number in [1, 2, 5, 10]:
		var one_star := _win_rate(data, 1, 1, 50, number)
		var three_star := _win_rate(data, 3, 1, 50, number)
		var five_star := _win_rate(data, 5, 4, 90, number)
		assert_true(one_star[0] < 0.05, "1 star wins %f at show %d" % [one_star[0], number])
		assert_true(five_star[0] > three_star[0] and three_star[0] >= one_star[0], "show %d" % number)
		assert_true(five_star[0] > 0.9, "a 5 star pure Dragon usually wins (%f at show %d)" % [five_star[0], number])
	var early := _win_rate(data, 3, 1, 50, 1)
	assert_true(early[1] > 0.5 and early[0] < 0.6, "a decent 3 star fish places but doesn't always win: %s" % str(early))


# --- Saving

func test_save_round_trip_keeps_shows_ribbons_and_history() -> void:
	gs.db.shows["rival_strength"]["base"] = 0
	gs.day = 7
	var f := _adult("grey", 5, 100)
	gs.enter_show(f.id)
	gs.end_day()
	var other := _adult("orange")
	gs.enter_show(other.id)
	var data: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	var loaded := GameState.from_dict(F.db(), F.rng(), data)
	assert_eq(loaded.shows_held, 1)
	assert_eq(loaded.show_entry, other.id)
	assert_eq(loaded.show_history.size(), 1)
	assert_eq(loaded.show_history[0]["place"], 1)
	assert_eq(loaded.show_history[0]["fish"]["stars"], 5)
	assert_eq(loaded.inventory.get_fish(f.id).ribbons.size(), 1)
	assert_eq(loaded.inventory.get_fish(f.id).ribbons[0]["show"], "Open Show")


func test_an_old_save_without_shows_loads_with_defaults() -> void:
	var d := gs.to_dict()
	d.erase("show_entry")
	d.erase("shows_held")
	d.erase("show_history")
	for fish_data in d["fish"]:
		fish_data.erase("ribbons")
	var loaded := GameState.from_dict(F.db(), F.rng(), d)
	assert_eq(loaded.show_entry, 0)
	assert_eq(loaded.shows_held, 0)
	assert_eq(loaded.show_history, [])
	assert_eq(loaded.inventory.fish_list()[0].ribbons, [])


# --- Data validation

func test_bad_show_data_is_reported() -> void:
	var bad := F.shows()
	bad["shows"][0]["rule"] = {"flies": true}
	bad["prizes"]["1"] = 0
	bad["rival_names"] = []
	bad["every_days"] = 0
	var db := DataDB.from_dicts([F.species()], F.items(), [F.template()], F.economy(), F.strains(),
		F.goals(), F.upgrades(), [], [], F.reputation(), bad)
	var text := str(db.errors)
	assert_true("flies" in text, text)
	assert_true("prizes" in text, text)
	assert_true("rival_names" in text, text)
	assert_true("every_days" in text, text)


func test_real_show_data_is_valid() -> void:
	var db := DataDB.load_from_dir("res://data")
	assert_eq(db.errors, [] as Array[String])
	assert_false(db.shows.is_empty())
