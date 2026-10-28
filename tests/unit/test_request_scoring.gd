extends "res://tests/test_case.gd"

const F := preload("res://tests/fixtures.gd")

var items: Dictionary = F.items_by_id()
var economy: Dictionary = F.economy()


func _request(fish_count: int = 2) -> Dictionary:
	return {
		"theme": "planted", "fish_count": fish_count, "base_reward": 100,
		"constraints": [
			{"trait": "body_color", "value": "orange", "min_count": fish_count},
			{"trait": "sex", "value": "female", "min_count": 1},
		],
	}


func _planted_tank() -> Tank:
	var t := Tank.new("tank")
	t.place(2, items["fern"])
	t.place(4, items["grass"])
	return t


func test_perfect_delivery_pays_full_bonus() -> void:
	var fish := [F.fish(Fish.FEMALE, "orange", 5), F.fish(Fish.MALE, "orange", 5)]
	var r := RequestScoring.score(_request(), _planted_tank(), fish, items, 100, 80, economy)
	assert_eq(r["match"], 1.0)
	assert_eq(r["quality"], 1.0)
	assert_eq(r["bonus"], 100)
	assert_eq(r["payout"], 180, "tank value + full bonus")


func test_empty_tank_gets_minimum_bonus() -> void:
	var r := RequestScoring.score(_request(), Tank.new("tank"), [], items, 0, 40, economy)
	assert_eq(r["match"], 0.0)
	assert_eq(r["bonus"], 25)
	assert_eq(r["payout"], 65)


func test_payout_never_below_tank_value() -> void:
	var rng := F.rng()
	for i in 50:
		var fish := []
		for j in rng.randi_range(0, 4):
			fish.append(F.fish(Fish.MALE, "grey", rng.randi_range(1, 5)))
		var r := RequestScoring.score(_request(), Tank.new("tank"), fish, items, rng.randi_range(0, 100), 40, economy)
		assert_true(r["payout"] >= 40 + 25)


func test_fish_count_off_by_one_scores_half() -> void:
	var one := [F.fish(Fish.FEMALE, "orange")]
	var four := [F.fish(Fish.FEMALE, "orange"), F.fish(Fish.FEMALE, "orange"),
		F.fish(Fish.FEMALE, "orange"), F.fish(Fish.FEMALE, "orange")]
	assert_eq(RequestScoring.score(_request(2), _planted_tank(), one, items, 50, 0, economy)["count"], 0.5)
	assert_eq(RequestScoring.score(_request(2), _planted_tank(), four, items, 50, 0, economy)["count"], 0.0)


func test_partial_constraint_match() -> void:
	var fish := [F.fish(Fish.MALE, "orange"), F.fish(Fish.MALE, "grey")]
	var r := RequestScoring.score(_request(), _planted_tank(), fish, items, 50, 0, economy)
	assert_eq(r["constraints"], [0.5, 0.0], "1 of 2 orange; no female")
	# theme 1, count 1, colour 0.5, sex 0 -> 0.625
	assert_almost(r["match"], 0.625)


func test_theme_share_counts() -> void:
	var t := _planted_tank()
	t.place(5, items["stone"])
	var r := RequestScoring.score(_request(), t, [], items, 0, 0, economy)
	assert_almost(r["theme"], 2.0 / 3.0)


func test_better_quality_and_looks_pay_more() -> void:
	var low := [F.fish(Fish.FEMALE, "orange", 1), F.fish(Fish.MALE, "orange", 1)]
	var high := [F.fish(Fish.FEMALE, "orange", 5), F.fish(Fish.MALE, "orange", 5)]
	var t := _planted_tank()
	var a := RequestScoring.score(_request(), t, low, items, 30, 0, economy)
	var b := RequestScoring.score(_request(), t, high, items, 30, 0, economy)
	var c := RequestScoring.score(_request(), t, high, items, 90, 0, economy)
	assert_true(b["bonus"] > a["bonus"], "quality")
	assert_true(c["bonus"] > b["bonus"], "looks")
