extends "res://tests/test_case.gd"

const F := preload("res://tests/fixtures.gd")

var items: Dictionary = F.items_by_id()
var weights: Dictionary = F.economy()["aesthetics"]


func _tank(substrate: String, slot_items: Array) -> Tank:
	var t := Tank.new()
	if substrate != "":
		t.set_substrate(items[substrate])
	for i in slot_items.size():
		if slot_items[i] != "":
			t.place(i, items[slot_items[i]])
	return t


func test_empty_tank_scores_zero() -> void:
	assert_eq(Aesthetics.score(Tank.new(), items, weights), 0)


func test_substrate_only() -> void:
	# 15 substrate + variety 1/4 * 15 = 3.75 -> 19
	assert_eq(Aesthetics.score(_tank("sand", []), items, weights), 19)


func test_perfect_tank_scores_100() -> void:
	# Tall at the back, medium in the middle, short at the front, all "natural",
	# hardscape + plants, 4 distinct items (= variety cap).
	var t := _tank("sand", ["wood", "wood", "fern", "fern", "stone", "stone"])
	assert_eq(Aesthetics.score(t, items, weights), 100)


func test_bad_layering_scores_lower() -> void:
	var good := _tank("sand", ["wood", "wood", "fern", "fern", "stone", "stone"])
	var bad := _tank("sand", ["stone", "stone", "fern", "fern", "wood", "wood"])
	var b := Aesthetics.breakdown(bad, items, weights)
	# Back and front rows are fully wrong (fit 0); only the 2 middle slots fit.
	assert_almost(b["layering"], 15.0 * (2.0 / 6.0), 0.001)
	assert_true(Aesthetics.score(bad, items, weights) < Aesthetics.score(good, items, weights))


func test_hardscape_and_plants_bonus_needs_both() -> void:
	var rocks_only := Aesthetics.breakdown(_tank("", ["", "", "", "", "stone", ""]), items, weights)
	var both := Aesthetics.breakdown(_tank("", ["", "", "fern", "", "stone", ""]), items, weights)
	assert_eq(rocks_only["hardscape_and_plants"], 0.0)
	assert_eq(both["hardscape_and_plants"], 15.0)


func test_one_item_is_not_a_masterpiece() -> void:
	var score := Aesthetics.score(_tank("", ["", "", "", "", "stone", ""]), items, weights)
	assert_between(score, 1, 20)


func test_score_is_always_0_to_100() -> void:
	var heavy := weights.duplicate()
	for k in heavy:
		if k != "variety_cap":
			heavy[k] = 100
	var t := _tank("sand", ["wood", "wood", "fern", "fern", "stone", "stone"])
	assert_eq(Aesthetics.score(t, items, heavy), 100)


func test_main_theme_and_tag_share() -> void:
	var t := _tank("sand", ["", "", "fern", "grass", "stone", ""])
	# natural: sand, fern, stone (3); planted: fern, grass (2); rocky: stone (1)
	assert_eq(Aesthetics.main_theme(t, items), "natural")
	assert_almost(Aesthetics.tag_share(t, items, "planted"), 2.0 / 4.0)
	assert_eq(Aesthetics.tag_share(Tank.new(), items, "planted"), 0.0)
	assert_eq(Aesthetics.main_theme(Tank.new(), items), "")


func test_tips_for_an_empty_tank() -> void:
	var tips := Aesthetics.tips(Tank.new(), items, weights)
	assert_eq(tips.size(), 3)
	assert_eq(tips[0], "Add substrate (+15).")
	assert_eq(tips[1], "Fill more spots: 0 of 6 used.")


func test_tips_point_out_bad_layering() -> void:
	var t := _tank("sand", ["stone", "stone", "fern", "fern", "wood", "wood"])
	var tips := Aesthetics.tips(t, items, weights, 10)
	assert_has(tips, "Tall items look best at the back, short ones at the front (4 out of place).")


func test_perfect_tank_has_no_tips() -> void:
	var t := _tank("sand", ["wood", "wood", "fern", "fern", "stone", "stone"])
	assert_eq(Aesthetics.tips(t, items, weights).size(), 0)
