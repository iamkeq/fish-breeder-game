extends "res://tests/test_case.gd"

const F := preload("res://tests/fixtures.gd")

var gs: GameState


func before_each() -> void:
	gs = F.new_game()


## Makes the next walk-in want only the given kind, and arrive on the next tick.
func _only(kind: String) -> void:
	var wants := {"fish": 0.0, "item": 0.0, "tank": 0.0, "wish": 0.0, "collector": 0.0}
	if kind == "wish":
		wants["wish"] = 1.0
	else:
		wants[kind] = 1.0
	gs.db.economy["customers"]["wants"] = wants
	gs.minutes_to_customer = 0.0


func test_in_stock_item_sells_itself() -> void:
	_only("item")
	var before_money := gs.money
	var before_stock := gs.inventory.stock().duplicate()
	assert_true(gs.tick_customers(1.0))
	assert_true(gs.customer.is_empty(), "the counter is empty again")
	assert_eq(gs.auto_sales.size(), 1)
	var sale: Dictionary = gs.auto_sales[0]
	assert_eq(gs.money, before_money + int(sale["price"]))
	assert_eq(gs.inventory.count(sale["item_id"]), int(before_stock[sale["item_id"]]) - 1)
	assert_eq(gs.day_log.get("served", 0), 1)


func test_auto_sale_matches_a_manual_sale() -> void:
	_only("item")
	var rep_before := gs.reputation
	gs.tick_customers(1.0)
	var auto_rep := gs.reputation - rep_before
	var manual := F.new_game()
	manual.customer = {"kind": "item", "item_id": "stone", "name": "Mabel", "waited": 0.0, "patience": 60.0}
	var m_before := manual.reputation
	manual.serve_customer()
	assert_eq(auto_rep, manual.reputation - m_before)


func test_out_of_stock_wish_is_not_auto_sold() -> void:
	_only("wish")
	var money := gs.money
	gs.tick_customers(1.0)
	assert_true(gs.auto_sales.is_empty())
	assert_eq(gs.money, money)
	assert_false(gs.customer.is_empty(), "the wish waits at the counter")
	assert_eq(gs.customer["kind"], "wish_item")


func test_fish_customers_are_not_auto_sold() -> void:
	gs.move_fish(gs.inventory.fish_list()[0].id, Fish.DISPLAY)
	_only("fish")
	gs.tick_customers(1.0)
	assert_true(gs.auto_sales.is_empty())
	assert_eq(gs.customer["kind"], "fish")


func test_can_be_switched_off() -> void:
	gs.db.economy["customers"]["auto_sell_shelf_items"] = false
	_only("item")
	var money := gs.money
	gs.tick_customers(1.0)
	assert_true(gs.auto_sales.is_empty())
	assert_eq(gs.money, money)
	assert_eq(gs.customer["kind"], "item", "waits at the counter as before")
