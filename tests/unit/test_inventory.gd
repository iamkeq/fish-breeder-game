extends "res://tests/test_case.gd"

const F := preload("res://tests/fixtures.gd")

var inv: Inventory


func before_each() -> void:
	inv = Inventory.new()


func test_starts_empty() -> void:
	assert_eq(inv.count("sand"), 0)
	assert_eq(inv.stock(), {})


func test_add_and_count() -> void:
	inv.add("sand", 3)
	inv.add("sand")
	assert_eq(inv.count("sand"), 4)


func test_cannot_remove_more_than_in_stock() -> void:
	inv.add("sand", 2)
	assert_false(inv.can_remove("sand", 3))
	assert_false(inv.remove("sand", 3))
	assert_eq(inv.count("sand"), 2, "a failed remove changes nothing")


func test_cannot_remove_unknown_item() -> void:
	assert_false(inv.can_remove("stone"))
	assert_false(inv.remove("stone"))


func test_remove_down_to_zero_drops_the_entry() -> void:
	inv.add("sand", 2)
	assert_true(inv.remove("sand", 2))
	assert_eq(inv.count("sand"), 0)
	assert_false(inv.stock().has("sand"))


func test_zero_or_negative_quantities_are_rejected() -> void:
	inv.add("sand", 2)
	assert_false(inv.can_remove("sand", 0))
	assert_false(inv.remove("sand", -1))
	assert_eq(inv.count("sand"), 2)


func test_fish_get_unique_ids() -> void:
	var a := inv.add_fish(F.fish(Fish.MALE))
	var b := inv.add_fish(F.fish(Fish.FEMALE))
	assert_ne(a.id, 0)
	assert_ne(a.id, b.id)
	assert_eq(inv.get_fish(a.id), a)


func test_existing_fish_ids_are_kept_and_not_reused() -> void:
	var old := F.fish(Fish.MALE)
	old.id = 10
	inv.add_fish(old)
	var fresh := inv.add_fish(F.fish(Fish.FEMALE))
	assert_eq(old.id, 10)
	assert_true(fresh.id > 10)


func test_remove_fish() -> void:
	var a := inv.add_fish(F.fish(Fish.MALE))
	assert_true(inv.remove_fish(a.id))
	assert_false(inv.has_fish(a.id))
	assert_false(inv.remove_fish(a.id), "can't remove twice")


func test_fish_list_filters_by_location() -> void:
	var a := inv.add_fish(F.fish(Fish.MALE))
	var b := inv.add_fish(F.fish(Fish.FEMALE))
	b.location = Fish.BREEDING
	assert_eq(inv.fish_list().size(), 2)
	assert_eq(inv.fish_list(Fish.HOLDING).size(), 1)
	assert_eq(inv.fish_list(Fish.BREEDING)[0], b)
	assert_eq(inv.fish_list(Fish.DISPLAY).size(), 0)
	assert_eq(a.location, Fish.HOLDING)
