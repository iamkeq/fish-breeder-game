extends "res://tests/test_case.gd"

const F := preload("res://tests/fixtures.gd")

var items: Dictionary = F.items_by_id()
var tank: Tank


func before_each() -> void:
	tank = Tank.new("tank", 2)


func test_new_tank_is_empty_with_six_slots_in_rows() -> void:
	assert_eq(tank.slot_count(), 6)
	assert_eq(tank.filled_slot_count(), 0)
	assert_eq(tank.row_of(0), "back")
	assert_eq(tank.row_of(3), "mid")
	assert_eq(tank.row_of(5), "front")
	assert_eq(tank.placed_item_ids(), [])


func test_placeable_items_go_in_slots() -> void:
	for id in ["stone", "wood", "fern", "castle"]:
		var t := Tank.new()
		assert_true(t.place(0, items[id]), id)


func test_substrate_food_and_tanks_cannot_go_in_slots() -> void:
	for id in ["sand", "food", "tank"]:
		assert_false(tank.place(0, items[id]), id)
	assert_eq(tank.filled_slot_count(), 0)


func test_only_substrate_goes_in_the_substrate_slot() -> void:
	assert_false(tank.set_substrate(items["fern"]))
	assert_true(tank.set_substrate(items["sand"]))
	assert_eq(tank.substrate, "sand")
	assert_false(tank.set_substrate(items["sand"]), "already has substrate")


func test_cannot_place_into_an_occupied_or_missing_slot() -> void:
	assert_true(tank.place(2, items["fern"]))
	assert_false(tank.place(2, items["stone"]))
	assert_false(tank.place(6, items["stone"]))
	assert_false(tank.place(-1, items["stone"]))
	assert_eq(tank.slots[2], "fern")


func test_take_returns_the_item_and_empties_the_slot() -> void:
	tank.place(1, items["wood"])
	assert_eq(tank.take(1), "wood")
	assert_true(tank.is_slot_empty(1))
	assert_eq(tank.take(1), "")


func test_placed_item_ids_lists_substrate_then_slots() -> void:
	tank.set_substrate(items["sand"])
	tank.place(4, items["stone"])
	tank.place(0, items["wood"])
	tank.place(5, items["stone"])
	assert_eq(tank.placed_item_ids(), ["sand", "wood", "stone", "stone"])
	assert_eq(tank.filled_slot_count(), 3)


func test_fish_capacity() -> void:
	assert_true(tank.add_fish(1))
	assert_false(tank.add_fish(1), "no duplicates")
	assert_true(tank.add_fish(2))
	assert_false(tank.add_fish(3), "capacity is 2")
	assert_true(tank.remove_fish(1))
	assert_true(tank.add_fish(3))
	assert_false(tank.remove_fish(99))
