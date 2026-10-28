extends "res://tests/test_case.gd"

const F := preload("res://tests/fixtures.gd")


func _species_with_mutation(chance: float) -> Dictionary:
	var s := F.species()
	s["mutation_chance"] = chance
	return s


func test_traits_come_from_a_parent_when_no_mutation() -> void:
	var species := _species_with_mutation(0.0)
	var rng := F.rng()
	var mom := F.fish(Fish.FEMALE, "grey", 3, 3, "round")
	var dad := F.fish(Fish.MALE, "orange", 3, 3, "fan")
	for i in 200:
		var fry := Genetics.make_offspring(mom, dad, species, rng)
		assert_has(["grey", "orange"], fry.traits["body_color"])
		assert_has(["round", "fan"], fry.traits["tail_shape"])
		assert_eq(fry.traits["pattern"], "plain")


func test_both_parents_contribute() -> void:
	var species := _species_with_mutation(0.0)
	var rng := F.rng()
	var mom := F.fish(Fish.FEMALE, "grey")
	var dad := F.fish(Fish.MALE, "orange")
	var from_mom := 0
	for i in 400:
		if Genetics.make_offspring(mom, dad, species, rng).traits["body_color"] == "grey":
			from_mom += 1
	assert_between(from_mom, 160, 240, "about half should come from mum")


func test_mutation_always_gives_a_rare_value() -> void:
	var species := _species_with_mutation(1.0)
	var rng := F.rng()
	var fry := Genetics.make_offspring(F.fish(Fish.FEMALE), F.fish(Fish.MALE), species, rng)
	assert_eq(fry.traits["body_color"], "red")
	assert_eq(fry.traits["tail_shape"], "delta")
	assert_eq(fry.traits["pattern"], "mosaic")


func test_mutation_rate_roughly_matches_data() -> void:
	var species := _species_with_mutation(0.05)
	var rng := F.rng(99)
	var mom := F.fish(Fish.FEMALE)
	var dad := F.fish(Fish.MALE)
	var rare := 0
	for i in 2000:
		if Genetics.make_offspring(mom, dad, species, rng).traits["body_color"] == "red":
			rare += 1
	assert_between(rare, 60, 140, "expected ~100 mutations in 2000")


func test_sex_is_roughly_even() -> void:
	var rng := F.rng(7)
	var males := 0
	for i in 1000:
		if Genetics.make_offspring(F.fish(Fish.FEMALE), F.fish(Fish.MALE), F.species(), rng).sex == Fish.MALE:
			males += 1
	assert_between(males, 430, 570)


func test_brood_size_stays_in_range() -> void:
	var rng := F.rng()
	var seen := {}
	for i in 200:
		var brood := Genetics.breed(F.fish(Fish.FEMALE), F.fish(Fish.MALE), F.species(), rng)
		assert_between(brood.size(), 2, 4)
		seen[brood.size()] = true
	assert_eq(seen.size(), 3, "every size from 2 to 4 should show up")


func test_offspring_start_as_fry_with_parent_average() -> void:
	var fry := Genetics.make_offspring(F.fish(Fish.FEMALE, "grey", 4), F.fish(Fish.MALE, "grey", 1),
		F.species(), F.rng())
	assert_eq(fry.age_days, 0)
	assert_eq(fry.stars, 0, "quality is unknown until adulthood")
	assert_almost(fry.parent_stars, 2.5)
	assert_false(fry.is_adult(F.species()))


func test_same_seed_gives_same_offspring() -> void:
	var a := Genetics.breed(F.fish(Fish.FEMALE), F.fish(Fish.MALE, "orange"), F.species(), F.rng(42))
	var b := Genetics.breed(F.fish(Fish.FEMALE), F.fish(Fish.MALE, "orange"), F.species(), F.rng(42))
	assert_eq(a.size(), b.size())
	for i in a.size():
		assert_eq(a[i].to_dict(), b[i].to_dict())


func test_is_rare() -> void:
	assert_true(Genetics.is_rare(F.species(), "body_color", "red"))
	assert_false(Genetics.is_rare(F.species(), "body_color", "grey"))
	assert_false(Genetics.is_rare(F.species(), "no_such_trait", "red"))


func test_random_fish_is_an_adult_with_valid_traits() -> void:
	var rng := F.rng()
	for i in 50:
		var f := Genetics.random_fish(F.species(), 2, 0.0, rng)
		assert_true(f.is_adult(F.species()))
		assert_eq(f.stars, 2)
		assert_has(["grey", "orange"], f.traits["body_color"])


# --- Varieties: recipes and mutation pools

func _variety_species(recipe_chance: float, mutation_chance: float = 0.0) -> Dictionary:
	return {
		"id": "guppy", "name": "Guppy", "base_price": 10, "days_to_adult": 3,
		"brood_size": [2, 4], "days_between_broods": 2, "mutation_chance": mutation_chance,
		"rare_value_multiplier": 1.5, "recipe_chance": recipe_chance,
		"traits": {"variety": {"common": ["red", "yellow", "blue"], "rare": ["orange", "albino"],
			"mutations": ["albino"]}},
		"recipes": {"variety": [{"parents": ["red", "yellow"], "child": "orange"}]},
	}


func _variety_fish(sex: String, variety: String) -> Fish:
	var f := Fish.new()
	f.species_id = "guppy"
	f.sex = sex
	f.stars = 3
	f.age_days = 3
	f.traits = {"variety": variety}
	return f


func test_recipe_child_works_in_either_order() -> void:
	var s := _variety_species(0.3)
	assert_eq(Genetics.recipe_child(s, "variety", "red", "yellow"), "orange")
	assert_eq(Genetics.recipe_child(s, "variety", "yellow", "red"), "orange")
	assert_eq(Genetics.recipe_child(s, "variety", "red", "blue"), "")


func test_recipe_pairs_sometimes_make_the_new_variety() -> void:
	var s := _variety_species(0.3)
	var rng := F.rng(8)
	var counts := {}
	for i in 1000:
		var v: String = Genetics.make_offspring(_variety_fish(Fish.FEMALE, "red"), _variety_fish(Fish.MALE, "yellow"), s, rng).traits["variety"]
		counts[v] = counts.get(v, 0) + 1
	assert_between(counts.get("orange", 0), 240, 360, "about 30% orange")
	assert_between(counts.get("red", 0), 290, 410, "the rest split between the parents")
	assert_eq(counts.size(), 3, "no other varieties without mutations")


func test_pairs_without_a_recipe_never_mix() -> void:
	var s := _variety_species(1.0)
	var rng := F.rng()
	for i in 200:
		var v: String = Genetics.make_offspring(_variety_fish(Fish.FEMALE, "red"), _variety_fish(Fish.MALE, "blue"), s, rng).traits["variety"]
		assert_has(["red", "blue"], v)


func test_mutations_come_only_from_the_mutation_pool() -> void:
	var s := _variety_species(0.0, 1.0)
	var rng := F.rng()
	for i in 100:
		var v: String = Genetics.make_offspring(_variety_fish(Fish.FEMALE, "red"), _variety_fish(Fish.MALE, "blue"), s, rng).traits["variety"]
		assert_eq(v, "albino", "orange is recipe-only, so it never mutates in")
	assert_true(Genetics.is_mutation(s, "variety", "albino"))
	assert_false(Genetics.is_mutation(s, "variety", "orange"))


func test_mutation_weights_make_some_mutations_rarer() -> void:
	var s := _variety_species(0.0, 1.0)
	s["traits"]["variety"]["rare"].append("galaxy")
	s["traits"]["variety"]["mutations"] = ["albino", "galaxy"]
	s["traits"]["variety"]["mutation_weights"] = {"albino": 3, "galaxy": 1}
	var rng := F.rng(4)
	var counts := {"albino": 0, "galaxy": 0}
	for i in 4000:
		counts[Genetics.pick_mutation(s, "variety", rng)] += 1
	assert_between(counts["galaxy"], 850, 1150, "about 1 in 4")
	assert_between(counts["albino"], 2850, 3150)


func test_without_weights_mutations_are_equally_likely() -> void:
	var s := _variety_species(0.0, 1.0)
	s["traits"]["variety"]["mutations"] = ["albino", "orange"]
	var rng := F.rng(5)
	var albino := 0
	for i in 2000:
		if Genetics.pick_mutation(s, "variety", rng) == "albino":
			albino += 1
	assert_between(albino, 900, 1100)
