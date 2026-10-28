extends "res://tests/test_case.gd"

const F := preload("res://tests/fixtures.gd")

var clock: GameClock


func before_each() -> void:
	clock = GameClock.new(F.economy()["clock"])
	clock.open_shop()


func test_opens_at_nine() -> void:
	assert_true(clock.is_open)
	assert_eq(clock.time_string(), "09:00")


func test_one_real_minute_is_one_game_hour() -> void:
	assert_almost(clock.advance(60.0), 60.0)
	assert_eq(clock.time_string(), "10:00")
	clock.advance(30.0)
	assert_eq(clock.time_string(), "10:30")


func test_cannot_close_before_four_hours() -> void:
	clock.advance(60.0 * 3.99)
	assert_false(clock.can_close())
	assert_false(clock.close_shop())
	assert_true(clock.is_open)


func test_can_close_after_four_hours() -> void:
	clock.advance(60.0 * 4)
	assert_true(clock.can_close())
	assert_true(clock.close_shop())
	assert_false(clock.is_open)


func test_can_stay_open_longer() -> void:
	clock.advance(60.0 * 7)
	assert_true(clock.is_open)
	assert_eq(clock.time_string(), "16:00")


func test_closes_itself_at_nine_pm() -> void:
	clock.advance(60.0 * 100)
	assert_false(clock.is_open)
	assert_eq(clock.time_string(), "21:00")
	assert_eq(clock.advance(60.0), 0.0, "time stops once closed")


func test_pause_stops_time() -> void:
	clock.paused = true
	assert_eq(clock.advance(600.0), 0.0)
	assert_eq(clock.time_string(), "09:00")
	clock.paused = false
	clock.advance(60.0)
	assert_eq(clock.time_string(), "10:00")


func test_reopening_resets_to_opening_time() -> void:
	clock.advance(60.0 * 5)
	clock.close_shop()
	clock.open_shop()
	assert_eq(clock.time_string(), "09:00")
	assert_true(clock.is_open)
