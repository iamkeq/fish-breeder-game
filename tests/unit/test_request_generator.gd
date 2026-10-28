extends "res://tests/test_case.gd"

const F := preload("res://tests/fixtures.gd")


func test_requests_stay_within_template_limits() -> void:
	var rng := F.rng()
	for i in 200:
		var r := RequestGenerator.generate(F.template(), F.species(), [], rng)
		assert_between(r["fish_count"], 1, 3)
		assert_between(r["constraints"].size(), 1, 2)
		assert_has(["planted", "rocky"], r["theme"])
		assert_eq(r["base_reward"], 100)
		var seen := {}
		for c in r["constraints"]:
			assert_false(seen.has(c["trait"]), "no trait asked for twice")
			seen[c["trait"]] = true


func test_constraint_values_are_obtainable() -> void:
	var rng := F.rng()
	for i in 200:
		var r := RequestGenerator.generate(F.template(), F.species(), [], rng)
		for c in r["constraints"]:
			if c["trait"] == "sex":
				assert_has([Fish.MALE, Fish.FEMALE], c["value"])
				assert_between(c["min_count"], 1, r["fish_count"])
			else:
				assert_has(["grey", "orange"], c["value"], "only common colours without rare stock")
				assert_eq(c["min_count"], r["fish_count"])


func test_rare_values_in_stock_can_be_requested() -> void:
	var owned := [F.fish(Fish.MALE, "red")]
	assert_has(RequestGenerator.candidate_values("body_color", F.species(), owned), "red")
	var rng := F.rng()
	var saw_red := false
	for i in 300:
		for c in RequestGenerator.generate(F.template(), F.species(), owned, rng)["constraints"]:
			if c["value"] == "red":
				saw_red = true
	assert_true(saw_red)


func test_same_seed_same_request() -> void:
	var a := RequestGenerator.generate(F.template(), F.species(), [], F.rng(5))
	var b := RequestGenerator.generate(F.template(), F.species(), [], F.rng(5))
	assert_eq(a, b)


func test_describe() -> void:
	var r := {
		"theme": "planted", "fish_count": 2, "base_reward": 60,
		"constraints": [
			{"trait": "body_color", "value": "orange", "min_count": 2},
			{"trait": "sex", "value": "female", "min_count": 1},
		],
	}
	assert_eq(RequestGenerator.describe(r, F.species()),
		"A planted tank with 2 guppies: all orange, at least 1 female.")
