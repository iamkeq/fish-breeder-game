extends "res://tests/test_case.gd"
## Line purity, the Lab (scans), the certified price bonus and the Lab goals.

const F := preload("res://tests/fixtures.gd")

var gs: GameState


func before_each() -> void:
	gs = _fresh()


func _fresh() -> GameState:
	var g := F.new_game()
	var species: Dictionary = g.db.species["guppy"]
	species["brood_size"] = [3, 3]
	species["mutation_chance"] = 0.0
	g.inventory.add("food", 50)
	g.breeding_tank.capacity = 30
	return g


func _rules() -> Dictionary:
	return gs.db.economy["purity"]


## An adult (not yet in the inventory) of a given colour and purity.
func _make(color: String, purity: int, stars: int = 3, sex: String = Fish.FEMALE) -> Fish:
	var f := F.fish(sex, color, stars)
	f.purity = purity
	return f


func _adult(color: String, purity: int, stars: int = 3) -> Fish:
	return gs.inventory.add_fish(_make(color, purity, stars))


## Clears the shop's fish, puts a mother and father in the breeding tank and
## runs nights until fry are born. Returns the fry.
func _breed(mother_color: String, mother_purity: int, father_color: String, father_purity: int) -> Array[Fish]:
	for f in gs.inventory.fish_list():
		gs.inventory.remove_fish(f.id)
	var mother := gs.inventory.add_fish(_make(mother_color, mother_purity))
	var father := gs.inventory.add_fish(_make(father_color, father_purity, 3, Fish.MALE))
	assert_true(gs.move_fish(mother.id, Fish.BREEDING))
	assert_true(gs.move_fish(father.id, Fish.BREEDING))
	for i in 6:
		gs.end_day()
		var fry: Array[Fish] = []
		for f in gs.inventory.fish_list(Fish.BREEDING):
			if not gs.is_adult(f):
				fry.append(f)
		if not fry.is_empty():
			return fry
	return []


# --- Creation

func test_new_fish_default_and_market_and_starting_pair_are_baseline() -> void:
	assert_eq(Fish.new().purity, 50)
	for f in gs.inventory.fish_list():
		assert_eq(f.purity, int(_rules()["market"]), "starting pair")
		assert_false(f.scanned)
	gs.money = 500
	var bought := gs.buy_strain("orange", Fish.MALE)
	assert_eq(bought.purity, int(_rules()["market"]))
	assert_false(bought.scanned)


func test_true_breeding_gains_purity_and_caps_at_100() -> void:
	var fry := _breed("grey", 60, "grey", 70)
	assert_eq(fry.size(), 3)
	for f in fry:
		assert_eq(f.purity, 65 + 8, "average 65 plus true_gain")
	gs = _fresh()
	fry = _breed("grey", 96, "grey", 100)
	assert_eq(fry.size(), 3)
	for f in fry:
		assert_eq(f.purity, 100, "never above 100")


func test_outcross_loses_purity_with_a_floor() -> void:
	var fry := _breed("grey", 60, "orange", 70)
	assert_eq(fry.size(), 3)
	for f in fry:
		assert_eq(f.purity, 65 - 12, "fry looks like only one parent")
	gs = _fresh()
	fry = _breed("grey", 12, "orange", 14)
	for f in fry:
		assert_eq(f.purity, int(_rules()["floor"]), "floor of 10")


func test_new_line_from_recipe_or_mutation_is_new_line_purity() -> void:
	var mum := _make("grey", 90)
	var dad := _make("orange", 90, 3, Fish.MALE)
	assert_eq(Purity.offspring_purity(mum, dad, _make("red", 50), _rules()), int(_rules()["new_line"]))
	# End to end: a certain mutation is a new line whatever the parents' purity.
	gs.db.species["guppy"]["mutation_chance"] = 1.0
	gs.db.species["guppy"]["traits"]["body_color"]["mutations"] = ["albino"]
	var fry := _breed("grey", 90, "grey", 90)
	assert_true(fry.size() > 0)
	for f in fry:
		assert_eq(f.purity, 30)


func test_same_variety_compares_every_trait() -> void:
	var a := F.fish(Fish.MALE, "grey", 3, 3, "round")
	var b := F.fish(Fish.FEMALE, "grey", 3, 3, "round")
	var c := F.fish(Fish.FEMALE, "grey", 3, 3, "fan")
	assert_true(Purity.same_variety(a, b))
	assert_false(Purity.same_variety(a, c))


func test_purity_does_not_change_after_birth() -> void:
	var fry := _breed("grey", 60, "grey", 60)
	var before: Array = fry.map(func(f): return f.purity)
	for i in 5:
		gs.end_day()
	for i in fry.size():
		assert_eq(fry[i].purity, before[i])


# --- Stars

func _average_stars(purity: int, parent_stars: float, fed: bool, rolls: int = 600) -> float:
	var r := F.rng(7)
	var total := 0
	for i in rolls:
		total += Quality.roll_offspring_stars(parent_stars, fed, gs._star_nudges(purity), r)
	return float(total) / rolls


func test_purity_raises_average_stars_but_does_not_replace_the_rest() -> void:
	assert_true(_average_stars(100, 3.0, true) > _average_stars(10, 3.0, true) + 0.05)
	assert_true(_average_stars(100, 3.0, false) > _average_stars(10, 3.0, false) + 0.05)
	assert_true(_average_stars(10, 4.0, true) > _average_stars(100, 2.0, true), "parent stars still matter most")
	assert_true(_average_stars(10, 3.0, true) > _average_stars(10, 3.0, false), "food still matters")


func test_five_stars_stay_possible_at_low_purity_and_stars_are_capped() -> void:
	var r := F.rng(11)
	var best := 0
	for i in 400:
		best = maxi(best, Quality.roll_offspring_stars(4.0, true, gs._star_nudges(10), r))
	assert_eq(best, 5, "5 stars reachable at purity 10")
	for i in 200:
		assert_between(Quality.roll_offspring_stars(5.0, true, gs._star_nudges(100), r), 1, 5)
		assert_between(Quality.roll_offspring_stars(1.0, true, gs._star_nudges(100), r), 1, 5)


func test_shift_weights_moves_probability_up_and_keeps_the_total() -> void:
	var w := Purity.shift_weights([0.1, 0.6, 0.3], 0.16)
	assert_almost(w[0], 0.0)
	assert_almost(w[1], 0.54)
	assert_almost(w[2], 0.46)
	assert_almost(w[0] + w[1] + w[2], 1.0)
	assert_eq(Purity.shift_weights([0.2, 0.6, 0.2], 0.0), [0.2, 0.6, 0.2])


func test_star_shift_tiers() -> void:
	assert_eq(gs._star_nudges(), gs.db.economy["offspring_quality_nudge"])
	assert_almost(Purity.star_shift(69, _rules()), 0.0)
	assert_almost(Purity.star_shift(70, _rules()), 0.08)
	assert_almost(Purity.star_shift(95, _rules()), 0.16)


func test_a_grown_fry_uses_its_purity() -> void:
	# Plain fed odds, but pure fish always roll "+1": proves the fry's purity is used.
	gs.db.economy["offspring_quality_nudge"]["fed"] = [0.0, 1.0, 0.0]
	gs.db.economy["purity"]["star_nudge"] = [{"min": 90, "shift": 1.0}]
	var fry := F.fish(Fish.FEMALE, "grey", 0, 2)
	fry.parent_stars = 3.0
	fry.purity = 100
	gs.inventory.add_fish(fry)
	gs.move_fish(fry.id, Fish.BREEDING)
	gs.end_day()
	assert_eq(fry.stars, 4)


# --- Tiers

func test_tiers() -> void:
	assert_eq(gs.purity_tier(0), "Mixed")
	assert_eq(gs.purity_tier(39), "Mixed")
	assert_eq(gs.purity_tier(40), "Developing")
	assert_eq(gs.purity_tier(69), "Developing")
	assert_eq(gs.purity_tier(70), "Pure Line")
	assert_eq(gs.purity_tier(89), "Pure Line")
	assert_eq(gs.purity_tier(90), "Champion Line")
	assert_eq(gs.purity_tier(100), "Champion Line")


# --- Scanning

func _unlock_lab() -> void:
	gs.reputation = 20
	assert_true(gs.lab_unlocked())


func test_scan_blockers() -> void:
	var f := _adult("grey", 80)
	assert_false(gs.lab_unlocked())
	assert_ne(gs.scan_blocker(f.id), "", "locked")
	assert_eq(gs.scan_fish(f.id), {})
	_unlock_lab()
	gs.money = 100
	assert_eq(gs.scan_blocker(f.id), "")
	assert_ne(gs.scan_blocker(9999), "", "unknown fish")
	var fry := gs.inventory.add_fish(F.fish(Fish.FEMALE, "grey", 0, 0))
	assert_ne(gs.scan_blocker(fry.id), "", "fry")
	gs.money = 19
	assert_ne(gs.scan_blocker(f.id), "", "broke")
	assert_eq(gs.scan_fish(f.id), {})
	assert_eq(gs.money, 19)
	gs.money = 100
	assert_eq(gs.scan_blocker(f.id), "")
	assert_eq(gs.scan_fish(f.id)["purity"], 80)
	assert_ne(gs.scan_blocker(f.id), "", "already scanned")
	assert_eq(gs.scan_fish(f.id), {})


func test_scan_pays_the_fee_counts_and_records() -> void:
	_unlock_lab()
	var a := _adult("grey", 80)
	var b := _adult("orange", 95)
	b.favorite = true
	gs.money = 100
	var spent_before := gs.stat("total_spent")
	var earned_before := gs.stat("total_earned")
	var result := gs.scan_fish(a.id)
	assert_eq(result, {"purity": 80, "tier": "Pure Line"})
	assert_eq(gs.money, 80)
	assert_true(a.scanned)
	assert_eq(gs.stat("total_spent") - spent_before, 20, "a spend")
	assert_eq(gs.stat("total_earned"), earned_before, "not an earning")
	assert_eq(gs.scan_fish(b.id)["tier"], "Champion Line", "favourites can be scanned")
	assert_eq(gs.stat("fish_scanned"), 2)
	assert_eq(int(gs.records["purest_fish"]["amount"]), 95)
	gs.scan_fish(_adult("blue", 60).id)
	assert_eq(int(gs.records["purest_fish"]["amount"]), 95, "keeps the best")
	assert_eq(gs.goal_value("best_purity_scanned"), 95)


# --- Certified price

func test_certified_premium_rules() -> void:
	_unlock_lab()
	gs.money = 1000
	var plain := gs.fish_price(_make("grey", 50))
	# Bred fish at 95 purity, scanned: +25%.
	var bred := _adult("grey", 95)
	assert_eq(gs.fish_price(bred), plain, "hidden until scanned")
	gs.scan_fish(bred.id)
	assert_eq(gs.fish_price(bred), roundi(plain * 1.25))
	assert_true(gs.is_certified(bred))
	# Unscanned bred fish at 95: nothing.
	var hidden := _adult("grey", 95)
	assert_eq(gs.fish_price(hidden), plain)
	assert_false(gs.is_certified(hidden))
	# 70-89: +10%. Below 70: nothing.
	var mid := _adult("grey", 75)
	gs.scan_fish(mid.id)
	assert_eq(gs.fish_price(mid), roundi(plain * 1.10))
	var low := _adult("grey", 69)
	gs.scan_fish(low.id)
	assert_eq(gs.fish_price(low), plain)
	# A market fish scanned at purity 100 gets no bonus.
	var market := _make("grey", 100)
	market.strain_id = "wild"
	market.paid = 10
	gs.inventory.add_fish(market)
	gs.scan_fish(market.id)
	assert_eq(gs.fish_price(market), plain)
	assert_false(gs.is_certified(market))
	# Wholesale follows the same price.
	assert_eq(gs.wholesale_price(bred), maxi(1, roundi(gs.fish_price(bred) * 0.4)))


# --- Goals, data and saving

func test_goals_exist_and_pay() -> void:
	var db := DataDB.load_from_dir("res://data")
	assert_eq(db.errors, [] as Array[String])
	var ids := db.goals.map(func(g): return g["id"])
	for id in ["first_scan", "pure_line", "champion_line", "scans_10"]:
		assert_true(id in ids, id)
	assert_eq(db.goals.size(), 49)
	_unlock_lab()
	gs.db.goals.append({"id": "scan1", "name": "Scan", "description": "", "metric": "fish_scanned", "target": 1, "reward": 7})
	gs.scan_fish(_adult("grey", 80).id)
	var before := gs.money
	assert_eq(gs.check_goals().size(), 1)
	assert_eq(gs.money, before + 7)


func test_data_validation_needs_purity_and_lab() -> void:
	var bad := F.economy()
	bad.erase("lab")
	var db := DataDB.from_dicts([F.species()], F.items(), [F.template()], bad, F.strains(), F.goals(), F.upgrades(), [], [], F.reputation())
	assert_false(db.errors.is_empty())
	bad = F.economy()
	bad["purity"]["tiers"] = [{"min": 40, "name": "Only"}]
	db = DataDB.from_dicts([F.species()], F.items(), [F.template()], bad, F.strains(), F.goals(), F.upgrades(), [], [], F.reputation())
	assert_false(db.errors.is_empty())


func test_save_round_trip_keeps_purity_scans_and_records() -> void:
	_unlock_lab()
	gs.money = 200
	var f := _adult("grey", 77)
	gs.scan_fish(f.id)
	var loaded := GameState.from_dict(F.db(), F.rng(5), SaveFile.parse(JSON.stringify(gs.to_dict())))
	var g := loaded.inventory.get_fish(f.id)
	assert_eq(g.purity, 77)
	assert_true(g.scanned)
	assert_eq(loaded.stat("fish_scanned"), 1)
	assert_eq(int(loaded.records["purest_fish"]["amount"]), 77)
	assert_eq(loaded.goal_value("best_purity_scanned"), 77)


func test_old_save_fish_load_with_baseline_purity() -> void:
	var data := gs.to_dict()
	for fd in data["fish"]:
		fd.erase("purity")
		fd.erase("scanned")
	var loaded := GameState.from_dict(F.db(), F.rng(5), SaveFile.parse(JSON.stringify(data)))
	for f in loaded.inventory.fish_list():
		assert_eq(f.purity, 50)
		assert_false(f.scanned)
