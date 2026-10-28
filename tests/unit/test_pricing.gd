extends "res://tests/test_case.gd"

const F := preload("res://tests/fixtures.gd")

var species: Dictionary = F.species()
var economy: Dictionary = F.economy()
var items: Dictionary = F.items_by_id()


func test_common_fish_price_follows_quality() -> void:
	assert_eq(Pricing.fish_price(F.fish(Fish.MALE, "grey", 1), species, economy), 6)
	assert_eq(Pricing.fish_price(F.fish(Fish.MALE, "grey", 3), species, economy), 10)
	assert_eq(Pricing.fish_price(F.fish(Fish.MALE, "grey", 4), species, economy), 15)
	assert_eq(Pricing.fish_price(F.fish(Fish.MALE, "grey", 5), species, economy), 23, "22.5 rounds up")


func test_rare_traits_multiply_price() -> void:
	var one_rare := F.fish(Fish.MALE, "red", 3)
	var two_rare := F.fish(Fish.MALE, "red", 3, 3, "delta")
	assert_eq(Pricing.fish_price(one_rare, species, economy), 15)
	assert_eq(Pricing.fish_price(two_rare, species, economy), 23)


func test_fry_have_no_price() -> void:
	assert_eq(Pricing.fish_price(F.fish(Fish.MALE, "grey", 3, 1), species, economy), 0)


func test_item_price() -> void:
	assert_eq(Pricing.item_price(items["castle"]), 15)


func test_tank_price_without_fish() -> void:
	var t := Tank.new("tank")
	t.set_substrate(items["sand"])
	t.place(4, items["stone"])
	# 40 tank + (10 + 5) * 1.2 = 18 + 20 looks * 0.5 = 10  -> 68
	assert_eq(Pricing.tank_price(t, items, 20, 0, economy), 68)


func test_tank_price_with_fish() -> void:
	var t := Tank.new("tank")
	t.set_substrate(items["sand"])
	t.place(4, items["stone"])
	assert_eq(Pricing.tank_price(t, items, 20, 25, economy), 93)


func test_empty_tank_is_worth_its_retail_price() -> void:
	assert_eq(Pricing.tank_price(Tank.new("tank"), items, 0, 0, economy), 40)


func test_strain_cost_counts_only_fixed_traits() -> void:
	var wild := {"stars": 2, "traits": {}}
	var red_delta := {"stars": 4, "traits": {"body_color": "red", "tail_shape": "delta"}}
	assert_eq(Pricing.strain_cost(wild, species, economy), 12)
	assert_eq(Pricing.strain_cost(red_delta, species, economy), 51)


func test_strains_cost_more_than_customers_pay() -> void:
	var strain := {"stars": 3, "traits": {"body_color": "orange"}}
	var same_fish := F.fish(Fish.MALE, "orange", 3)
	assert_true(Pricing.strain_cost(strain, species, economy) > Pricing.fish_price(same_fish, species, economy),
		"profit should come from breeding, not reselling")


func test_wholesale_price() -> void:
	assert_eq(Pricing.wholesale_price(F.fish(Fish.MALE, "grey", 3), species, economy), 4, "40% of 10")
	assert_eq(Pricing.wholesale_price(F.fish(Fish.MALE, "grey", 1), species, economy), 2, "40% of 6 = 2.4")
	assert_eq(Pricing.wholesale_price(F.fish(Fish.MALE, "grey", 3, 0), species, economy), 1, "fry")


func test_value_multipliers_override_the_rare_multiplier() -> void:
	var s := F.species()
	s["value_multipliers"] = {"body_color": {"red": 3.0, "orange": 1.2}}
	assert_eq(Pricing.fish_price(F.fish(Fish.MALE, "red", 3), s, economy), 30, "red is worth x3 here")
	assert_eq(Pricing.fish_price(F.fish(Fish.MALE, "orange", 3), s, economy), 12, "even common values can be priced")
	assert_eq(Pricing.fish_price(F.fish(Fish.MALE, "grey", 3, 3, "delta"), s, economy), 15, "unlisted rare: x1.5")
