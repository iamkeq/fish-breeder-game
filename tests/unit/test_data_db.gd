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


func test_real_guppies_have_art_for_every_variety() -> void:
	var db := DataDB.load_from_dir("res://data")
	var guppy: Dictionary = db.species["guppy"]
	var t: Dictionary = guppy["traits"]["variety"]
	assert_eq(t["common"].size() + t["rare"].size(), 28, "24 from the sheet + 4 new mutations")
	for v in t["common"] + t["rare"]:
		assert_true(guppy["sprites"]["varieties"].has(v) or guppy["sprites"].get("placeholders", {}).has(v), v)


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
	assert_has(db.errors, "species/guppy/sprites: no frame [x, y, w, h] or placeholder for body_color 'orange'")


func test_market_never_sells_mutation_only_varieties() -> void:
	var db := DataDB.load_from_dir("res://data")
	for id in db.strains:
		var strain: Dictionary = db.strains[id]
		var species: Dictionary = db.species[strain["species"]]
		for trait_name in strain["traits"]:
			assert_false(Genetics.is_mutation(species, trait_name, strain["traits"][trait_name]),
				"%s sells a mutation-only %s" % [id, trait_name])


func test_placeholders_stand_in_for_missing_art() -> void:
	var s := F.species()
	s["sprites"] = {"sheet": "res://assets/fish/guppy_sheet.png", "trait": "body_color",
		"varieties": {"grey": [0, 0, 10, 10], "orange": [10, 0, 10, 10], "red": [20, 0, 10, 10]},
		"placeholders": {"delta_fake": {}}}
	var db := DataDB.from_dicts([s], F.items(), [F.template()], F.economy())
	assert_eq(db.errors, [] as Array[String], "every body_color has a frame")
	s["sprites"]["varieties"].erase("red")
	s["sprites"]["placeholders"] = {"red": {"base": "grey", "tint": "#ff0000"}}
	db = DataDB.from_dicts([s], F.items(), [F.template()], F.economy())
	assert_eq(db.errors, [] as Array[String], "a placeholder counts")
	s["sprites"]["placeholders"] = {"red": {"base": "nope", "tint": "#ff0000"}}
	db = DataDB.from_dicts([s], F.items(), [F.template()], F.economy())
	assert_has(db.errors, "species/guppy/sprites: no frame [x, y, w, h] or placeholder for body_color 'red'")


func test_bad_mutation_weights_are_reported() -> void:
	var s := F.species()
	s["traits"]["body_color"]["mutations"] = ["red"]
	s["traits"]["body_color"]["mutation_weights"] = {"orange": 2, "red": 0}
	var db := DataDB.from_dicts([s], F.items(), [F.template()], F.economy())
	assert_has(db.errors, "species/guppy: mutation_weights lists 'orange', which is not in mutations")
	assert_has(db.errors, "species/guppy: mutation weight for 'red' must be above 0")


func test_real_mutation_odds() -> void:
	var db := DataDB.load_from_dir("res://data")
	var t: Dictionary = db.species["guppy"]["traits"]["variety"]
	assert_eq(t["mutations"].size(), 6)
	assert_true(t["mutation_weights"]["galaxy"] < t["mutation_weights"]["albino"], "the new jackpots are rarer")
