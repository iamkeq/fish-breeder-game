extends "res://tests/test_case.gd"

const F := preload("res://tests/fixtures.gd")


func test_real_game_data_loads_cleanly() -> void:
	var db := DataDB.load_from_dir("res://data")
	assert_eq(db.errors, [] as Array[String])
	assert_true(db.species.has("guppy"))
	assert_true(db.items.has("fish_food"))
	assert_true(db.request_templates.has("stocked_tank"))
	assert_true(db.economy.has("starting_state"))


func test_fixture_data_is_valid() -> void:
	assert_true(F.db().is_valid(), str(F.db().errors))


func test_missing_field_is_reported() -> void:
	var items := F.items()
	items[0].erase("price")
	var db := DataDB.from_dicts([F.species()], items, [F.template()], F.economy())
	assert_has(db.errors, "item/sand: missing field 'price'")


func test_bad_category_and_missing_height() -> void:
	var items := F.items()
	items.append({"id": "rug", "name": "Rug", "category": "carpet", "cost": 1, "price": 2, "tags": []})
	items.append({"id": "pebble", "name": "Pebble", "category": "rock", "cost": 1, "price": 2, "tags": []})
	var db := DataDB.from_dicts([F.species()], items, [F.template()], F.economy())
	assert_has(db.errors, "item/rug: unknown category 'carpet'")
	assert_has(db.errors, "item/pebble: placeable items need 'height' (short/medium/tall)")


func test_duplicate_ids_are_reported() -> void:
	var items := F.items()
	items.append(F.items()[0])
	var db := DataDB.from_dicts([F.species()], items, [F.template()], F.economy())
	assert_has(db.errors, "item/sand: duplicate id")


func test_bad_references_are_reported() -> void:
	var template := F.template()
	template["species"] = "betta"
	var economy := F.economy()
	economy["starting_state"]["items"]["unobtainium"] = 1
	var db := DataDB.from_dicts([F.species()], F.items(), [template], economy)
	assert_has(db.errors, "request/stocked_tank: unknown species 'betta'")
	assert_has(db.errors, "economy/starting_state: unknown item 'unobtainium'")


func test_unknown_constraint_trait_is_reported() -> void:
	var template := F.template()
	template["constraints"] = ["fin_length"]
	var db := DataDB.from_dicts([F.species()], F.items(), [template], F.economy())
	assert_has(db.errors, "request/stocked_tank: constraint 'fin_length' is not a trait of guppy")


func test_items_in_category() -> void:
	assert_eq(F.db().items_in_category("plant"), ["fern", "grass"])


func test_real_strains_load() -> void:
	var db := DataDB.load_from_dir("res://data")
	assert_true(db.strains.size() >= 4)
	for id in db.strains:
		assert_true(db.species.has(db.strains[id]["species"]), id)


func test_bad_strains_are_reported() -> void:
	var bad := [
		{"id": "a", "name": "A", "species": "betta", "tier": 1, "stars": 2, "traits": {}},
		{"id": "b", "name": "B", "species": "guppy", "tier": 7, "stars": 9, "traits": {}},
		{"id": "c", "name": "C", "species": "guppy", "tier": 1, "stars": 2,
			"traits": {"body_color": "plaid", "fin_length": "long"}},
		{"id": "d", "name": "D", "species": "guppy", "tier": 1},
	]
	var db := DataDB.from_dicts([F.species()], F.items(), [F.template()], F.economy(), bad)
	assert_has(db.errors, "strain/a: unknown species 'betta'")
	assert_has(db.errors, "strain/b: stars must be 1–5 (got 9)")
	assert_has(db.errors, "strain/b: tier 7 is not listed in economy/fish_market/tiers")
	assert_has(db.errors, "strain/c: 'plaid' is not a valid body_color")
	assert_has(db.errors, "strain/c: 'fin_length' is not a trait of guppy")
	assert_has(db.errors, "strain/d: missing field 'stars'")


func test_real_guppies_have_a_sprite_for_every_variety() -> void:
	var db := DataDB.load_from_dir("res://data")
	var guppy: Dictionary = db.species["guppy"]
	var t: Dictionary = guppy["traits"]["variety"]
	assert_eq(t["common"].size() + t["rare"].size(), 24, "one per variety on the sheet")
	for v in t["common"] + t["rare"]:
		assert_true(guppy["sprites"]["varieties"].has(v), v)


func test_bad_recipes_mutations_and_values_are_reported() -> void:
	var s := F.species()
	s["traits"]["body_color"]["mutations"] = ["plaid"]
	s["recipes"] = {"body_color": [{"parents": ["grey", "teal"], "child": "orange"}]}
	s["value_multipliers"] = {"body_color": {"mauve": 2.0}}
	var db := DataDB.from_dicts([s], F.items(), [F.template()], F.economy())
	assert_has(db.errors, "species/guppy: mutation 'plaid' is not a body_color value")
	assert_has(db.errors, "species/guppy: recipe uses 'teal', which is not a body_color value")
	assert_has(db.errors, "species/guppy: value_multipliers lists 'mauve', which is not a body_color value")


func test_missing_sprite_frames_are_reported() -> void:
	var s := F.species()
	s["sprites"] = {"sheet": "res://nope.png", "trait": "body_color", "varieties": {"grey": [0, 0, 10, 10]}}
	var db := DataDB.from_dicts([s], F.items(), [F.template()], F.economy())
	assert_has(db.errors, "species/guppy/sprites: sheet 'res://nope.png' not found")
	assert_has(db.errors, "species/guppy/sprites: no frame [x, y, w, h] for body_color 'orange'")
