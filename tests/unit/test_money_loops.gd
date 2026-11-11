extends "res://tests/test_case.gd"
## v0.22.0: items, display tanks and special orders must not be a repeatable
## markup on Market prices. These run on the real game data on purpose, so a
## future price edit that reopens a loop fails here.

const F := preload("res://tests/fixtures.gd")

var db: DataDB = DataDB.load_from_dir("res://data")


func test_item_retail_margin_over_real_data() -> void:
	var total := 0.0
	var count := 0
	for id in db.items:
		var item: Dictionary = db.items[id]
		var ratio := float(item["price"]) / float(item["cost"])
		total += ratio
		count += 1
		if int(item["cost"]) >= 3:
			assert_between(ratio, 1.15, 1.4, "%s retail/cost" % id)
		else:
			# $2 food can only be $2 (no margin) or $3 (x1.5): whole dollars.
			assert_between(ratio, 1.15, 1.5, "%s retail/cost (whole-dollar rounding)" % id)
	assert_between(total / count, 1.2, 1.3, "mean item margin is about 1.25x")


func test_tank_price_is_build_cost_plus_premium_and_capped_looks() -> void:
	var economy := F.economy()
	var items := F.items_by_id()
	var t := Tank.new("tank")
	t.set_substrate(items["sand"])
	t.place(4, items["castle"])
	var build := Pricing.tank_build_cost(t, items)
	assert_eq(build, 25 + 4 + 8, "tank + substrate + item at Market cost, not retail price")
	# premium 10%, looks bonus up to another 10% at 100 looks.
	assert_eq(Pricing.tank_price(t, items, 0, 0, economy), roundi(build * 1.10))
	assert_eq(Pricing.tank_price(t, items, 100, 0, economy), roundi(build * 1.20))
	assert_eq(Pricing.tank_price(t, items, 500, 0, economy), roundi(build * 1.20), "looks are capped")
	assert_eq(Pricing.tank_price(t, items, 100, 30, economy), roundi(build * 1.20) + 30, "fish keep their own prices")


func test_real_tank_prices_stay_near_build_cost() -> void:
	var rules: Dictionary = db.economy["tank_pricing"]
	var cap := 1.0 + float(rules["premium"]) + float(rules["looks_bonus_max"])
	var rng := F.rng(5)
	var ids := db.items.keys()
	ids.sort()
	for n in 200:
		var t := Tank.new("tank_20l", 6)
		for i in 6:
			var id: String = ids[rng.randi_range(0, ids.size() - 1)]
			if Tank.is_substrate(db.items[id]):
				t.set_substrate(db.items[id])
			elif Tank.is_placeable(db.items[id]):
				t.place(i, db.items[id])
		var build := Pricing.tank_build_cost(t, db.items)
		var price := Pricing.tank_price(t, db.items, Aesthetics.score(t, db.items, db.economy["aesthetics"]), 0, db.economy)
		assert_true(price >= build, "never below build cost")
		assert_true(price <= ceili(build * cap), "never above build cost + premium + looks cap")
	# The advertised range: a well decorated tank pays 15-20% over build cost.
	assert_between(cap, 1.1, 1.3)


func test_selling_and_rebuilding_the_display_tank_never_beats_the_premium() -> void:
	var gs := GameState.new_game(db, F.rng(9))
	gs.money = 100000
	var rules: Dictionary = db.economy["tank_pricing"]
	var layout: Array = []
	for id in gs.display_tank.placed_item_ids():
		layout.append(id)
	var tank_item := gs.display_tank.tank_item_id
	var build := Pricing.tank_build_cost(gs.display_tank, db.items)
	var start := gs.money
	for round_number in 10:
		var before := gs.money
		gs.sell_display_tank(false)
		gs.buy_item(tank_item)
		gs.install_display_tank(tank_item)
		gs.buy_item(layout[0])
		gs.set_substrate(gs.display_tank, layout[0])
		for i in range(1, layout.size()):
			gs.buy_item(layout[i])
			gs.place_item(gs.display_tank, i - 1, layout[i])
		var net := gs.money - before
		var most := ceili(build * (float(rules["premium"]) + float(rules["looks_bonus_max"])))
		assert_true(net <= most, "round %d: net %d is at most premium + looks (%d)" % [round_number, net, most])
	assert_true(gs.money - start <= 10 * ceili(build * (float(rules["premium"]) + float(rules["looks_bonus_max"]))))


func test_special_order_payout_margin_over_real_data() -> void:
	# Perfectly matching fish in the starting tank layout: the best case for the player.
	var gs := GameState.new_game(db, F.rng(3))
	var template: Dictionary = db.request_templates["stocked_tank"]
	var species: Dictionary = db.species["guppy"]
	var build := Pricing.tank_build_cost(gs.display_tank, db.items)
	var looks := gs.tank_aesthetics(gs.display_tank)
	var rng := F.rng(77)
	var total := 0.0
	var orders := 40
	for n in orders:
		var request := RequestGenerator.generate(template, species, [], rng)
		var fish: Array = []
		var fish_total := 0
		for i in int(request["fish_count"]):
			var f := Fish.new()
			f.species_id = "guppy"
			f.stars = 3
			f.sex = Fish.MALE if i % 2 == 0 else Fish.FEMALE
			f.age_days = int(species["days_to_adult"])
			f.traits = {"variety": "red"}
			for c in request["constraints"]:
				if c["trait"] == "sex":
					f.sex = c["value"]
				else:
					f.traits[c["trait"]] = c["value"]
			fish.append(f)
			fish_total += Pricing.fish_price(f, species, db.economy)
		var tank_value := Pricing.tank_price(gs.display_tank, db.items, looks, fish_total, db.economy)
		var result := RequestScoring.score(request, gs.display_tank, fish, db.items, looks, tank_value, db.economy)
		var surplus := int(result["payout"]) - fish_total - build
		total += surplus
		var materials := build + fish_total
		assert_true(surplus >= 0.05 * materials, "an order is always worth more than its parts")
		assert_true(surplus <= 0.8 * materials, "order surplus %d of materials %d stays modest" % [surplus, materials])
	assert_between(total / orders, 20.0, 60.0, "average special-order surplus over fair value + materials")
