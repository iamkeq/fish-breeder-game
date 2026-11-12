extends "res://tests/test_case.gd"
## v0.27.0: regular customers. These run on the real game data on purpose, so a
## future price or loyalty edit that reopens a money loop fails here.

const F := preload("res://tests/fixtures.gd")

var db: DataDB = DataDB.load_from_dir("res://data")


## A game on `day` where only one regular can visit, every time, and nobody has fish.
func _game(day: int = 5, regular_id: String = "mrs_pike") -> GameState:
	var gs := GameState.new_game(db, F.rng(5))
	gs.day = day
	db.regulars["rules"]["visit_chance"] = 1.0
	db.regulars["regulars"] = db.regulars["regulars"].filter(func(r): return r["id"] == regular_id)
	for f in gs.inventory.fish_list():
		gs._release_fish(f)
	return gs


func _adult(gs: GameState, variety: String, stars: int) -> Fish:
	var f := Fish.new()
	f.species_id = "guppy"
	f.sex = Fish.MALE
	f.stars = stars
	f.age_days = 3
	f.traits = {"variety": variety}
	f.location = Fish.HOLDING
	return gs.inventory.add_fish(f)


## Lets the next customer arrive.
func _arrive(gs: GameState) -> Dictionary:
	gs.customer = {}
	gs._regulars_today = []
	gs.minutes_to_customer = 0.0
	gs.tick_customers(1.0)
	return gs.customer


func _make_loyal(gs: GameState, regular_id: String, points: int) -> void:
	var st := gs.regular_state(regular_id)
	st["loyalty"] = points
	st["met"] = true
	gs.regulars_state[regular_id] = st


# --- Data

func test_real_data_has_eight_valid_regulars() -> void:
	assert_eq(db.errors, [] as Array[String])
	assert_eq(db.regulars["regulars"].size(), 8)
	assert_eq(db.goals.size(), 55)
	var ids := db.goals.map(func(g): return g["id"])
	for id in ["familiar_faces", "part_of_family", "everybodys_local"]:
		assert_true(id in ids, id)


func test_bad_regular_data_is_reported() -> void:
	var bad := DataDB.load_from_dir("res://data")
	var copy: Dictionary = bad.regulars["regulars"][0].duplicate(true)
	copy["id"] = "dup"
	copy["favorite"] = {"trait": "variety", "value": "plaid"}
	copy["color"] = "not a colour"
	bad.regulars["regulars"].append(copy)
	bad.errors.clear()
	bad.validate()
	var text := "\n".join(bad.errors)
	assert_true("plaid" in text, "unknown favourite value")
	assert_true("colour" in text, "bad colour")
	var again := DataDB.load_from_dir("res://data")
	again.regulars["regulars"].append(again.regulars["regulars"][0].duplicate(true))
	again.errors.clear()
	again.validate()
	assert_true("duplicate id" in "\n".join(again.errors))


# --- Maths

func test_loyalty_levels_and_tips() -> void:
	var rules: Dictionary = db.regulars["rules"]
	var expected := {0: 0, 1: 0, 2: 1, 4: 1, 5: 2, 9: 3, 13: 3, 14: 4, 20: 5, 500: 5}
	for points in expected:
		assert_eq(Regulars.level(points, rules), expected[points], "points %d" % points)
	assert_eq(Regulars.max_level(rules), 5)
	assert_eq(Regulars.tip(100, 0, rules), 0)
	assert_eq(Regulars.tip(100, 3, rules), 12)
	assert_eq(Regulars.tip(100, 5, rules), 20)
	assert_almost(Regulars.tip_rate(5, rules), 0.2, 0.0001, "the cap is +20%")
	assert_eq(Regulars.hearts(2, rules), "♥♥♡♡♡")


func test_regular_visits_do_not_repeat_in_a_day() -> void:
	var rng := F.rng(3)
	var picked := {}
	var today := []
	for i in 8:
		var id := Regulars.pick(db.regulars["regulars"], {}, today, rng)
		assert_false(picked.has(id), "each regular once")
		picked[id] = true
		today.append(id)
	assert_eq(Regulars.pick(db.regulars["regulars"], {}, today, rng), "", "nobody left")


# --- Visits

func test_regulars_only_appear_from_the_unlock_day() -> void:
	var early := _game(2)
	for i in 30:
		assert_false(_arrive(early).has("regular_id"), "day 2: ordinary walk-ins only")
	var later := _game(3)
	var c := _arrive(later)
	assert_eq(c.get("regular_id"), "mrs_pike")
	assert_eq(c["name"], "Mrs Pike")


func test_first_visit_meets_them_and_counts_visits() -> void:
	var gs := _game()
	var c := _arrive(gs)
	assert_true(c["new_regular"])
	var st := gs.regular_state("mrs_pike")
	assert_true(st["met"])
	assert_eq(st["visits"], 1)
	assert_eq(st["last_day"], 5)
	assert_eq(gs.goal_value("regulars_met"), 1)
	assert_eq(gs.day_log["regulars_met"], ["Mrs Pike"])
	c = _arrive(gs)
	assert_false(c["new_regular"], "only new on the first visit")
	assert_eq(gs.regular_state("mrs_pike")["visits"], 2)


func test_regular_wants_a_matching_fish_if_there_is_one() -> void:
	var gs := _game()
	_adult(gs, "blue", 5)
	var two := _adult(gs, "red", 2)
	var four := _adult(gs, "red", 4)
	_adult(gs, "red", 1)  # too few stars for Mrs Pike
	var c := _arrive(gs)
	assert_eq(c["kind"], "fish")
	assert_eq(c["fish_id"], four.id, "the best match")
	gs.sell_fish(four.id)
	c = _arrive(gs)
	assert_eq(c["fish_id"], two.id)


func test_regular_without_a_match_asks_you_to_order_it() -> void:
	var gs := _game()
	_adult(gs, "blue", 5)
	var c := _arrive(gs)
	assert_eq(c["kind"], "wish_fish")
	assert_eq(c["wish"]["value"], "red")
	assert_eq(c["regular_id"], "mrs_pike")
	assert_true(gs.backorder_customer())
	assert_eq(gs.backorders[0]["regular_id"], "mrs_pike")


func test_regular_without_room_for_back_orders_just_browses() -> void:
	var gs := _game()
	while gs.can_backorder():
		gs.backorders.append({"name": "X", "item_id": "fish_food", "price": 1})
	var c := _arrive(gs)
	assert_eq(c["regular_id"], "mrs_pike", "still themselves")
	assert_ne(c["kind"], "wish_fish")


func test_special_orders_only_come_from_loyal_regulars() -> void:
	db.regulars["rules"]["order_chance"] = 1.0
	var gs := _game()
	_make_loyal(gs, "mrs_pike", 8)  # level 2
	for i in 20:
		assert_ne(_arrive(gs).get("kind"), "request", "not loyal enough yet")
	_make_loyal(gs, "mrs_pike", 9)  # level 3
	var c := _arrive(gs)
	assert_eq(c["kind"], "request")
	var request: Dictionary = c["request"]
	assert_eq(request["regular_id"], "mrs_pike")
	assert_eq(request["base_reward"], roundi(45 * 1.25), "pays 25% more")
	var varieties: Array = request["constraints"].filter(func(k): return k["trait"] == "variety")
	assert_eq(varieties[0]["value"], "red", "built around their favourite")
	assert_true(gs.accept_customer_request())
	assert_eq(gs.orders[0]["customer"], "Mrs Pike")
	assert_eq(gs.orders[0]["regular_id"], "mrs_pike")


func test_special_orders_need_room() -> void:
	db.regulars["rules"]["order_chance"] = 1.0
	var gs := _game()
	_make_loyal(gs, "mrs_pike", 9)
	while gs.can_accept_request():
		gs.accept_request(gs.make_request())
	assert_ne(_arrive(gs).get("kind"), "request")


func test_delivering_a_regulars_order_tips_the_bonus_and_builds_loyalty() -> void:
	var gs := _game()
	_make_loyal(gs, "mrs_pike", 20)
	var request := gs.make_request()
	request["regular_id"] = "mrs_pike"
	gs.accept_request(request)
	var preview := gs.preview_delivery(0)
	assert_eq(preview["tip"], Regulars.tip_amount(preview["bonus"], 0.2))
	var before := gs.money
	var result := gs.deliver_order(0)
	assert_eq(gs.money - before, result["payout"])
	assert_eq(gs.stat("regular_tips"), result["tip"])
	assert_eq(gs.regular_state("mrs_pike")["purchases"], 1)


# --- Selling

func test_selling_to_a_regular_builds_loyalty_and_tips() -> void:
	var gs := _game()
	var f := _adult(gs, "red", 3)
	var base := gs.fish_price(f)
	_make_loyal(gs, "mrs_pike", 14)  # level 4: +16%
	_arrive(gs)
	var expected := base + Regulars.tip_amount(base, 0.16)
	assert_eq(gs.customer_price(), expected, "the counter shows the tipped price")
	var before := gs.money
	assert_eq(gs.serve_customer(), expected)
	assert_eq(gs.money - before, expected)
	assert_eq(gs.stat("regular_tips"), expected - base)
	assert_eq(gs.day_log["tips"], expected - base)
	var st := gs.regular_state("mrs_pike")
	assert_eq(st["purchases"], 1)
	assert_eq(st["loyalty"], 15)
	assert_eq(gs.day_log["regulars_served"], ["Mrs Pike"])
	var summary := gs.end_day()
	assert_eq(summary["log"]["tips"], expected - base)


func test_a_stranger_pays_no_tip() -> void:
	var gs := _game()
	var f := _adult(gs, "red", 3)
	gs.customer = {"name": "Mabel", "kind": "fish", "fish_id": f.id, "waited": 0.0, "patience": 60.0}
	assert_eq(gs.customer_price(), gs.fish_price(f))
	assert_eq(gs.serve_customer(), gs.fish_price(f))
	assert_eq(gs.stat("regular_tips"), 0)


func test_loyalty_goal_reaches_max() -> void:
	var gs := _game()
	_make_loyal(gs, "mrs_pike", 19)
	assert_eq(gs.goal_value("regulars_max_loyal"), 0)
	_adult(gs, "red", 3)
	_arrive(gs)
	gs.serve_customer()
	assert_eq(gs.goal_value("regulars_max_loyal"), 1)
	gs.check_goals()
	assert_true(gs.is_goal_done("part_of_family"))


func test_a_back_order_for_a_regular_adds_loyalty_without_a_market_tip() -> void:
	var gs := _game()
	_make_loyal(gs, "mrs_pike", 20)
	gs.money = 1000
	var f := gs.buy_strain("red", Fish.MALE)
	gs.backorders.append({"name": "Mrs Pike", "regular_id": "mrs_pike", "species_id": "guppy", "sex": Fish.MALE,
		"traits": {"variety": "red"}, "source": "market", "price": 20, "due_day": 1})
	assert_eq(gs.backorder_payout(0), 20, "Market back-orders are priced near cost: no tip")
	assert_eq(gs.fulfil_backorder(0), 20)
	assert_eq(gs.regular_state("mrs_pike")["purchases"], 1)
	assert_false(gs.inventory.has_fish(f.id))
	gs.backorders.append({"name": "Mrs Pike", "regular_id": "mrs_pike", "species_id": "guppy", "sex": Fish.MALE,
		"traits": {"variety": "orange"}, "source": "bred", "price": 100, "due_day": 1})
	assert_eq(gs.backorder_payout(0), 120, "bred orders carry the +20%")


# --- Money

func test_market_fish_sold_to_a_max_loyalty_regular_still_loses_money() -> void:
	var gs := _game()
	gs.money = 100000
	_make_loyal(gs, "mrs_pike", 20)
	var strain_ids := db.strains.keys()
	strain_ids.sort()
	var checked := 0
	for id in strain_ids:
		var strain: Dictionary = db.strains[id]
		if strain["traits"].size() != 1:
			continue
		var f := gs.buy_strain(id, Fish.MALE)
		assert_true(f != null, id)
		var rate := Regulars.tip_rate(5, gs.regular_rules())
		var best := gs.fish_price(f) + Regulars.tip_amount(gs.fish_price(f), rate)
		assert_true(best < f.paid, "%s: sells for at most %d but cost %d" % [id, best, f.paid])
		checked += 1
	assert_true(checked > 5)
	# And for real, through the counter.
	var f2 := gs.buy_strain("red", Fish.MALE)
	for other in gs.inventory.fish_list():
		if other.id != f2.id:
			gs._release_fish(other)
	_arrive(gs)
	var before := gs.money
	var earned := gs.serve_customer()
	assert_eq(gs.money - before, earned)
	assert_true(earned < f2.paid, "earned %d for a fish that cost %d" % [earned, f2.paid])


# --- Saving

func test_regulars_survive_save_and_load() -> void:
	var gs := _game()
	_adult(gs, "red", 3)
	_arrive(gs)
	gs.serve_customer()
	var saved := SaveFile.parse(JSON.stringify(gs.to_dict()))
	var loaded := GameState.from_dict(db, F.rng(1), saved)
	assert_true(loaded != null)
	assert_eq(loaded.regulars_state, gs.regulars_state)
	assert_eq(loaded.regular_state("mrs_pike")["purchases"], 1)
	assert_true(loaded.regular_state("mrs_pike")["met"])
	assert_eq(JSON.stringify(SaveFile.normalize(loaded.to_dict())), JSON.stringify(SaveFile.normalize(gs.to_dict())))


func test_an_old_save_without_regulars_loads_with_none_met() -> void:
	var gs := _game()
	var data := SaveFile.parse(JSON.stringify(gs.to_dict()))
	data.erase("regulars_state")
	var loaded := GameState.from_dict(db, F.rng(1), data)
	assert_true(loaded != null)
	assert_eq(loaded.regulars_state, {})
	assert_eq(loaded.goal_value("regulars_met"), 0)
	assert_eq(loaded.regular_state("mrs_pike")["loyalty"], 0)
