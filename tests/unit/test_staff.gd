extends "res://tests/test_case.gd"
## Shop staff: unlocking, hiring, jobs at night, wages, goals, saving.

const F := preload("res://tests/fixtures.gd")

var gs: GameState


func before_each() -> void:
	gs = F.new_game()
	gs.reputation = 100  # "Famous": staff are unlocked in the fixture data
	# The starting stock includes spare decorations; tests add their own.
	for id in gs.inventory.stock().keys():
		if Tank.is_placeable(gs.db.items[id]):
			gs.inventory.remove(id, gs.inventory.count(id))


func _reload(state: GameState) -> GameState:
	return GameState.from_dict(F.db(), F.rng(99), SaveFile.parse(JSON.stringify(state.to_dict())))


## A fry in holding (it needs one portion of food a night to grow).
func _fry() -> Fish:
	return gs.inventory.add_fish(F.fish(Fish.MALE, "grey", 0, 0))


func _no_food() -> void:
	gs.inventory.remove("food", gs.inventory.count("food"))


# --- Unlocking and hiring

func test_staff_are_locked_until_the_reputation_level() -> void:
	gs.reputation = 0
	assert_false(gs.staff_unlocked())
	assert_eq(gs.hire_blocker("feeder"), "Reach 'Famous' to hire staff")
	assert_false(gs.hire_staff("feeder"))
	gs.reputation = 100
	assert_true(gs.staff_unlocked())
	assert_eq(gs.hire_blocker("feeder"), "")


func test_hiring_pays_the_fee_and_picks_names_and_colours() -> void:
	gs.money = 500
	assert_eq(gs.hire_cost(), 30)
	assert_true(gs.hire_staff("feeder"))
	assert_eq(gs.money, 470)
	assert_eq(gs.hire_cost(), 60, "each hire costs more")
	assert_true(gs.hire_staff("decorator"))
	assert_eq(gs.money, 410)
	assert_eq(gs.hire_cost(), 90)
	assert_eq(gs.staff[0]["name"], "Pip")
	assert_eq(gs.staff[1]["name"], "Marnie")
	assert_ne(gs.staff[0]["color"], gs.staff[1]["color"])
	assert_eq(gs.staff[0]["hired_day"], gs.day)
	assert_eq(gs.stat("staff_hired"), 2)
	assert_eq(gs.stat("total_spent"), 90)


func test_hire_blockers() -> void:
	gs.money = 20
	assert_eq(gs.hire_blocker("feeder"), "You need $10 more.")
	assert_false(gs.hire_staff("feeder"))
	assert_eq(gs.money, 20)
	gs.money = 1000
	assert_eq(gs.hire_blocker("juggler"), "There's no such job.")
	gs.hire_staff("feeder")
	assert_eq(gs.hire_blocker("feeder"), "Someone already does that job")
	assert_false(gs.hire_staff("feeder"))
	gs.hire_staff("decorator")
	gs.hire_staff("stocker")
	assert_eq(gs.hire_cost(), -1)
	assert_eq(gs.hire_blocker("stocker"), "Your team is full")
	assert_eq(gs.staff.size(), 3)


func test_reassigning_keeps_one_hire_per_job() -> void:
	gs.money = 1000
	gs.hire_staff("feeder")
	gs.hire_staff("decorator")
	var pip: int = gs.staff[0]["id"]
	assert_false(gs.set_staff_task(pip, "decorator"), "taken")
	assert_false(gs.set_staff_task(pip, "feeder"), "already theirs")
	assert_false(gs.set_staff_task(pip, "nonsense"))
	assert_true(gs.set_staff_task(pip, "stocker"))
	assert_eq(gs.staff_for_task("stocker")["name"], "Pip")
	assert_true(gs.staff_for_task("feeder").is_empty())


func test_letting_someone_go_is_free_and_lowers_the_next_fee() -> void:
	gs.money = 500
	gs.hire_staff("feeder")
	gs.hire_staff("decorator")
	var money := gs.money
	assert_true(gs.dismiss_staff(gs.staff[0]["id"]))
	assert_eq(gs.money, money, "no refund, no penalty")
	assert_eq(gs.staff.size(), 1)
	assert_eq(gs.hire_cost(), 60)
	assert_false(gs.dismiss_staff(999))
	assert_true(gs.hire_staff("feeder"))
	assert_eq(gs.staff[1]["name"], "Pip", "the first name nobody on the team has")


func test_staff_never_earn_reputation() -> void:
	gs.money = 500
	var before := gs.reputation
	gs.hire_staff("feeder")
	gs.end_day()
	assert_eq(gs.reputation, before)


# --- The Feeder

func test_without_a_feeder_fry_go_hungry() -> void:
	_no_food()
	var fry := _fry()
	var summary := gs.end_day()
	assert_eq(summary["fry_unfed"], 1)
	assert_eq(fry.age_days, 0)
	assert_false(summary.has("staff"))


func test_the_feeder_buys_food_at_the_normal_price_so_fry_grow() -> void:
	gs.money = 500
	gs.hire_staff("feeder")
	_no_food()
	var fry := _fry()
	var money := gs.money
	var summary := gs.end_day()
	assert_eq(summary["fry_unfed"], 0)
	assert_eq(fry.age_days, 1)
	assert_true(fry.fed_every_night, "counts as fed")
	assert_eq(gs.inventory.count("food"), 0, "the food was eaten")
	assert_eq(money - gs.money, 2 + 5, "one portion at the Market price plus the wage")
	assert_eq(summary["staff"]["entries"][0]["text"], "Pip fed 1 fry (bought 1 food, $2)")


func test_the_feeder_uses_your_food_first_and_spends_nothing() -> void:
	gs.money = 500
	gs.hire_staff("feeder")
	_fry()
	var money := gs.money
	var summary := gs.end_day()
	assert_eq(gs.inventory.count("food"), 1)
	assert_eq(money - gs.money, 5, "only the wage")
	assert_eq(summary["staff"]["entries"][0]["text"], "Pip had nothing to do tonight.")


func test_the_feeder_does_what_it_can_when_money_is_short() -> void:
	gs.money = 30
	gs.hire_staff("feeder")
	_no_food()
	var fry := _fry()
	gs.money = 1
	var summary := gs.end_day()
	assert_eq(summary["fry_unfed"], 1, "can't afford food: no harm, just no growth")
	assert_eq(fry.age_days, 0)
	assert_eq(gs.money, 1, "no debt")


func test_the_feeder_does_not_make_the_auto_feeder_pay() -> void:
	gs.money = 500
	gs.hire_staff("feeder")
	gs.buy_upgrade("feeder")
	_no_food()
	var fry := _fry()
	var money := gs.money
	gs.end_day()
	assert_eq(fry.age_days, 1)
	assert_eq(money - gs.money, 5, "auto-feeders need no food, so only the wage")


# --- The Decorator

func _fill_display_except(open_slots: Array) -> void:
	var ids := ["stone", "wood", "fern", "grass", "castle", "stone"]
	for slot in 6:
		if slot in open_slots:
			continue
		gs.inventory.add(ids[slot])
		assert_true(gs.place_item(gs.display_tank, slot, ids[slot]))


func test_the_decorator_fills_empty_spots_without_touching_placed_items() -> void:
	gs.money = 500
	gs.hire_staff("decorator")
	_fill_display_except([4, 5])
	var before: Array = gs.display_tank.slots.duplicate()
	gs.inventory.add("grass", 1)
	gs.inventory.add("castle", 1)
	var money := gs.money
	var summary := gs.end_day()
	for slot in 4:
		assert_eq(gs.display_tank.slots[slot], before[slot], "placed items stay")
	assert_eq(gs.display_tank.filled_slot_count(), 6)
	assert_eq(gs.inventory.count("grass"), 0)
	assert_eq(gs.inventory.count("castle"), 0)
	assert_eq(money - gs.money, 5, "it never buys anything: only the wage")
	assert_eq(summary["staff"]["entries"][0]["text"], "Pip hung 2 decorations")


func test_the_decorator_picks_the_best_looking_item_first() -> void:
	gs.money = 500
	gs.hire_staff("decorator")
	_fill_display_except([5])
	var scores := {}
	for id in ["castle", "grass", "stone", "fern"]:
		gs.display_tank.slots[5] = id
		scores[id] = gs.tank_aesthetics(gs.display_tank)
		gs.display_tank.slots[5] = ""
	var best: String = "castle"
	for id in scores:
		if scores[id] > scores[best]:
			best = id
	for id in scores:
		gs.inventory.add(id)
	gs.end_day()
	assert_eq(gs.display_tank.slots[5], best)
	assert_eq(gs.stat("staff_actions"), 4, "the other three spares go to the breeding tank")


func test_the_decorator_uses_breeding_tanks_only_when_display_is_full() -> void:
	gs.money = 500
	gs.hire_staff("decorator")
	_fill_display_except([5])
	gs.inventory.add("grass", 2)
	gs.end_day()
	assert_eq(gs.display_tank.filled_slot_count(), 6)
	assert_eq(gs.breeding_tanks[0].filled_slot_count(), 1, "the spare goes to the breeding tank")
	# With room on display, nothing goes to the back room.
	var other := F.new_game()
	other.reputation = 100
	other.money = 500
	other.hire_staff("decorator")
	for id in ["stone", "fern"]:
		other.inventory.remove(id, other.inventory.count(id))
	other.inventory.add("grass", 2)
	other.end_day()
	assert_eq(other.display_tank.filled_slot_count(), 2)
	assert_eq(other.breeding_tanks[0].filled_slot_count(), 0)


func test_the_decorator_with_nothing_spare_does_nothing() -> void:
	gs.money = 500
	gs.hire_staff("decorator")
	_fill_display_except([])
	var sand := gs.inventory.count("sand")  # substrate isn't hung
	var summary := gs.end_day()
	assert_eq(summary["staff"]["entries"][0]["text"], "Pip had nothing to do tonight.")
	assert_eq(gs.inventory.count("sand"), sand)


# --- The Stock clerk

func test_the_stock_clerk_tops_up_at_the_normal_price() -> void:
	gs.money = 500
	gs.hire_staff("stocker")
	_no_food()
	var money := gs.money
	var summary := gs.end_day()
	assert_eq(gs.inventory.count("food"), 5)
	assert_eq(money - gs.money, 5 * 2 + 5, "five portions at $2 plus the wage")
	assert_eq(summary["staff"]["entries"][0]["text"], "Pip restocked 5 food ($10)")
	assert_eq(summary["log"]["spent"], 30 + 10, "the hire fee and the restock show in the day's spending")


func test_the_stock_clerk_respects_the_budget() -> void:
	gs.money = 500
	gs.db.staff["restock_budget"] = 4
	gs.hire_staff("stocker")
	_no_food()
	gs.end_day()
	assert_eq(gs.inventory.count("food"), 2)


func test_the_stock_clerk_never_goes_below_the_money_floor() -> void:
	gs.money = 40
	gs.hire_staff("stocker")
	_no_food()
	gs.money = 13  # floor is 10: only one $2 portion fits
	gs.end_day()
	assert_eq(gs.inventory.count("food"), 1)
	assert_true(gs.money >= 0)


func test_the_stock_clerk_leaves_a_full_shelf_alone() -> void:
	gs.money = 500
	gs.hire_staff("stocker")
	gs.inventory.add("food", 10)
	var summary := gs.end_day()
	assert_eq(gs.inventory.count("food"), 12)
	assert_eq(summary["staff"]["entries"][0]["text"], "Pip had nothing to do tonight.")


# --- Wages

func test_wages_are_paid_each_night_and_are_not_earnings() -> void:
	gs.money = 500
	gs.hire_staff("feeder")
	gs.hire_staff("decorator")
	var earned := gs.stat("total_earned")
	var money := gs.money
	var summary := gs.end_day()
	assert_eq(summary["staff"]["wages_paid"], 10)
	assert_eq(summary["staff"]["wages_skipped"], 0)
	assert_eq(gs.money, money - 10)
	assert_eq(gs.stat("staff_wages"), 10)
	assert_eq(gs.stat("total_earned"), earned, "wages are a spend, not negative earnings")
	assert_eq(gs.stat("best_day"), 0)
	assert_eq(summary["earned"], 0)


func test_wages_you_cannot_afford_are_skipped_without_debt() -> void:
	gs.money = 500
	gs.hire_staff("feeder")
	gs.hire_staff("decorator")
	gs.money = 7
	var summary := gs.end_day()
	assert_eq(summary["staff"]["wages_paid"], 5, "one wage fits")
	assert_eq(summary["staff"]["wages_skipped"], 1)
	assert_eq(gs.money, 2)
	gs.money = 0
	gs.end_day()
	assert_eq(gs.money, 0, "never negative")


func test_summary_only_has_a_staff_report_when_staff_exist() -> void:
	assert_false(gs.end_day().has("staff"))


# --- Goals

func test_goals_follow_the_team_and_the_work() -> void:
	gs.money = 1000
	assert_eq(gs.goal_value("staff_hired"), 0)
	gs.hire_staff("feeder")
	assert_eq(gs.goal_value("staff_hired"), 1)
	assert_eq(gs.goal_value("staff_count"), 1)
	gs.dismiss_staff(gs.staff[0]["id"])
	assert_eq(gs.goal_value("staff_count"), 0)
	assert_eq(gs.goal_value("staff_hired"), 1, "hires are lifetime")
	gs._count("staff_actions", 7)
	assert_eq(gs.goal_value("staff_actions"), 7)


func test_real_data_has_staff_and_goals() -> void:
	var db := DataDB.load_from_dir("res://data")
	assert_eq(db.errors, [] as Array[String])
	assert_eq(db.staff["hire_costs"].size(), int(db.staff["max_staff"]))
	var ids := db.goals.map(func(g): return g["id"])
	assert_true("first_hire" in ids and "full_team" in ids and "many_hands" in ids)
	assert_true(db.items.has("fish_food"))


func test_bad_staff_data_is_reported() -> void:
	var bad := F.staff()
	bad["hire_costs"] = [10]
	bad["names"] = []
	bad["daily_wage"] = 0
	bad["tasks"].append({"id": "juggler", "name": "J", "description": "d"})
	bad["restock_to"] = {"ghost": 5}
	var db := DataDB.from_dicts([F.species()], F.items(), [F.template()], F.economy(), [], [], [], [], [], {}, {}, bad)
	assert_has(db.errors, "staff: hire_costs needs one price per member of staff (max_staff)")
	assert_has(db.errors, "staff: 'names' needs at least one entry")
	assert_has(db.errors, "staff: 'daily_wage' must be a positive whole number")
	assert_has(db.errors, "staff: unknown task 'juggler'")
	assert_has(db.errors, "staff: restock_to lists unknown item 'ghost'")


# --- Saving

func test_staff_survive_a_save() -> void:
	gs.money = 1000
	gs.hire_staff("feeder")
	gs.hire_staff("stocker")
	var loaded := _reload(gs)
	assert_eq(loaded.staff.size(), 2)
	assert_eq(loaded.staff[0]["name"], "Pip")
	assert_eq(loaded.staff[1]["task"], "stocker")
	assert_eq(loaded.hire_cost(), 90)
	assert_true(loaded.hire_staff("decorator"))
	assert_eq(loaded.staff[2]["id"], 3, "ids keep counting")


func test_an_old_save_has_no_staff() -> void:
	var d := SaveFile.parse(JSON.stringify(gs.to_dict()))
	d.erase("staff")
	d.erase("next_staff_id")
	var loaded := GameState.from_dict(F.db(), F.rng(99), d)
	assert_true(loaded.staff.is_empty())
	loaded.money = 100
	assert_true(loaded.hire_staff("feeder"))
