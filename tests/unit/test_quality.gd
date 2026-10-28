extends "res://tests/test_case.gd"

const F := preload("res://tests/fixtures.gd")

var nudges: Dictionary = F.economy()["offspring_quality_nudge"]


func _counts(parent_avg: float, fed: bool, trials: int, seed_value: int) -> Dictionary:
	var rng := F.rng(seed_value)
	var counts := {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	for i in trials:
		counts[Quality.roll_offspring_stars(parent_avg, fed, nudges, rng)] += 1
	return counts


func test_stars_always_between_1_and_5() -> void:
	var rng := F.rng()
	for avg in [0.0, 1.0, 2.5, 5.0, 7.0]:
		for i in 100:
			assert_between(Quality.roll_offspring_stars(avg, true, nudges, rng), 1, 5)


func test_top_and_bottom_are_clamped() -> void:
	var always_up := {"normal": [0.0, 0.0, 1.0], "fed": [0.0, 0.0, 1.0]}
	var always_down := {"normal": [1.0, 0.0, 0.0], "fed": [1.0, 0.0, 0.0]}
	assert_eq(Quality.roll_offspring_stars(5.0, false, always_up, F.rng()), 5)
	assert_eq(Quality.roll_offspring_stars(1.0, false, always_down, F.rng()), 1)


func test_parent_average_is_rounded_half_up() -> void:
	var no_nudge := {"normal": [0.0, 1.0, 0.0], "fed": [0.0, 1.0, 0.0]}
	assert_eq(Quality.roll_offspring_stars(2.5, false, no_nudge, F.rng()), 3)
	assert_eq(Quality.roll_offspring_stars(2.4, false, no_nudge, F.rng()), 2)


func test_unfed_distribution_is_centred_on_parents() -> void:
	var c := _counts(3.0, false, 5000, 11)
	assert_between(c[2], 850, 1150, "~20% one star lower")
	assert_between(c[3], 2800, 3200, "~60% same")
	assert_between(c[4], 850, 1150, "~20% one star higher")
	assert_eq(c[1] + c[5], 0)


func test_fed_fry_do_better_on_average() -> void:
	var fed := _counts(3.0, true, 5000, 12)
	var unfed := _counts(3.0, false, 5000, 12)
	assert_true(fed[4] > unfed[4], "more +1 rolls when fed")
	assert_true(fed[2] < unfed[2], "fewer -1 rolls when fed")
