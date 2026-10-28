extends "res://tests/test_case.gd"

const F := preload("res://tests/fixtures.gd")

var rules: Dictionary = F.economy()["customers"]
var species_db := {"guppy": F.species()}


func test_fish_appeal_is_stars_plus_rarity() -> void:
	assert_eq(Customers.fish_appeal(F.fish(Fish.MALE, "grey", 3), F.species(), rules), 3.0)
	assert_eq(Customers.fish_appeal(F.fish(Fish.MALE, "red", 3, 3, "delta"), F.species(), rules), 6.0, "3 + 2 rare * 1.5")
	assert_eq(Customers.fish_appeal(F.fish(Fish.MALE, "red", 0, 0), F.species(), rules), 0.0, "fry don't count")


func test_display_counts_more_than_holding_and_breeding() -> void:
	var f := [F.fish(Fish.MALE, "grey", 4)]
	var on_display := Customers.shop_appeal(f, [], [], 0, species_db, rules)
	var in_holding := Customers.shop_appeal([], f, [], 0, species_db, rules)
	var breeding := Customers.shop_appeal([], [], f, 0, species_db, rules)
	assert_eq(on_display, 4.0)
	assert_almost(in_holding, 1.6)
	assert_almost(breeding, 1.0)


func test_tank_looks_add_appeal() -> void:
	assert_almost(Customers.shop_appeal([], [], [], 100, species_db, rules), 3.0)


func test_better_fish_bring_customers_sooner() -> void:
	var plain := 0.0
	var fancy := 0.0
	var rng_a := F.rng(3)
	var rng_b := F.rng(3)
	for i in 200:
		plain += Customers.next_arrival_minutes(2.0, rules, rng_a)
		fancy += Customers.next_arrival_minutes(40.0, rules, rng_b)
	assert_true(fancy < plain * 0.6, "high appeal should cut waiting a lot")


func test_arrivals_never_faster_than_minimum() -> void:
	var rng := F.rng()
	for i in 100:
		assert_true(Customers.next_arrival_minutes(10000.0, rules, rng) >= 12.0)


func test_speedup_is_capped() -> void:
	assert_eq(Customers.speedup(0.0, rules), 1.0)
	assert_eq(Customers.speedup(10000.0, rules), 4.0)


func test_walk_in_only_asks_for_what_exists() -> void:
	var rng := F.rng()
	for i in 100:
		var c := Customers.make_walk_in({"species_db": species_db, "items_in_stock": ["sand"]}, rules, rng)
		assert_eq(c["kind"], "item")
		assert_eq(c["item_id"], "sand")


func test_walk_in_prefers_better_fish() -> void:
	var dull := F.fish(Fish.MALE, "grey", 1)
	dull.id = 1
	var star := F.fish(Fish.MALE, "red", 5, 3, "delta")
	star.id = 2
	var rng := F.rng()
	var picks := {1: 0, 2: 0}
	for i in 600:
		var c := Customers.make_walk_in({"fish_for_sale": [dull, star], "species_db": species_db}, rules, rng)
		picks[c["fish_id"]] += 1
	assert_true(picks[2] > picks[1] * 2, "5-star rare fish should be asked for far more often")


func test_nothing_for_sale_means_a_request_or_a_browser() -> void:
	var rng := F.rng()
	assert_eq(Customers.make_walk_in({"can_take_request": true}, rules, rng)["kind"], "request")
	assert_eq(Customers.make_walk_in({}, rules, rng)["kind"], "browse")


func test_request_chance() -> void:
	var r := rules.duplicate(true)
	r["request_chance"] = 1.0
	var c := Customers.make_walk_in({"items_in_stock": ["sand"], "can_take_request": true}, r, F.rng())
	assert_eq(c["kind"], "request")
	assert_eq(c["name"], "Mabel")


func test_wishes_are_for_things_you_dont_have() -> void:
	var r := rules.duplicate(true)
	r["wants"] = {"fish": 0, "item": 0, "tank": 0, "wish": 1.0}
	var strains := {"red_delta": F.strains()[1]}
	var rng := F.rng()
	var kinds := {}
	for i in 200:
		var c := Customers.make_walk_in({"items_in_stock": ["sand"], "all_items": ["sand", "castle"],
			"strains": strains}, r, rng)
		kinds[c["kind"]] = true
		if c["kind"] == "wish_item":
			assert_eq(c["item_id"], "castle", "only out-of-stock items are wished for")
		else:
			assert_eq(c["strain_id"], "red_delta")
			assert_has([Fish.MALE, Fish.FEMALE], c["sex"])
	assert_eq(kinds.size(), 2, "both kinds of wish happen")


func test_matches_strain() -> void:
	var strain: Dictionary = F.strains()[1]  # red delta, 4 stars
	assert_true(Customers.matches_strain(F.fish(Fish.MALE, "red", 4, 3, "delta"), strain, Fish.MALE, F.species()))
	assert_true(Customers.matches_strain(F.fish(Fish.MALE, "red", 5, 3, "delta", "mosaic"), strain, Fish.MALE, F.species()),
		"better stars and unlisted traits are fine")
	assert_false(Customers.matches_strain(F.fish(Fish.FEMALE, "red", 4, 3, "delta"), strain, Fish.MALE, F.species()), "sex")
	assert_false(Customers.matches_strain(F.fish(Fish.MALE, "red", 3, 3, "delta"), strain, Fish.MALE, F.species()), "stars")
	assert_false(Customers.matches_strain(F.fish(Fish.MALE, "grey", 4, 3, "delta"), strain, Fish.MALE, F.species()), "colour")
	assert_false(Customers.matches_strain(F.fish(Fish.MALE, "red", 4, 1, "delta"), strain, Fish.MALE, F.species()), "fry")


func test_backorder_price_is_discounted() -> void:
	var r := {"discount": 0.1}
	assert_eq(Customers.backorder_price(100, r), 90)
	assert_eq(Customers.backorder_price(15, r), 14, "13.5 rounds up")
	assert_eq(Customers.backorder_price(1, r), 1)
