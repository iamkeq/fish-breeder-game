class_name DataDB
extends RefCounted
## Loads and validates all game data (JSON). Core logic receives the plain
## dictionaries held here, so tests can build a DataDB from hand-written data.

const ITEM_CATEGORIES := ["substrate", "rock", "driftwood", "plant", "decor", "food", "tank"]
const PLACEABLE_CATEGORIES := ["rock", "driftwood", "plant", "decor"]
const HEIGHTS := ["short", "medium", "tall"]

const SPECIES_FIELDS := ["id", "name", "base_price", "days_to_adult", "brood_size",
	"days_between_broods", "mutation_chance", "rare_value_multiplier", "traits"]
const ITEM_FIELDS := ["id", "name", "category", "cost", "price", "tags"]
const TEMPLATE_FIELDS := ["id", "species", "theme_tags", "fish_count", "constraints",
	"constraint_count", "base_reward"]
const STRAIN_FIELDS := ["id", "name", "species", "tier", "stars", "traits"]
const ECONOMY_FIELDS := ["quality_multipliers", "offspring_quality_nudge", "tank_pricing",
	"aesthetics", "breeding_tank_capacity", "breeding_tanks", "clock", "customers", "requests", "backorders", "wholesale",
	"fish_market", "starting_state"]

var species: Dictionary = {}
var items: Dictionary = {}
var request_templates: Dictionary = {}
## Named breeding-stock lines sold in the Fish Market, by id.
var strains: Dictionary = {}
var economy: Dictionary = {}
var errors: Array[String] = []


static func load_from_dir(root: String = "res://data") -> DataDB:
	var read_errors: Array[String] = []
	var species_list := _read_dir(root.path_join("species"), read_errors)
	var item_list: Array = []
	for file_data in _read_dir(root.path_join("items"), read_errors):
		item_list.append_array(file_data.get("items", []))
	var template_list := _read_dir(root.path_join("requests"), read_errors)
	var strain_list: Array = []
	for file_data in _read_dir(root.path_join("strains"), read_errors):
		strain_list.append_array(file_data.get("strains", []))
	var economy_data = _read_file(root.path_join("economy.json"), read_errors)
	var db := from_dicts(species_list, item_list, template_list,
		economy_data if economy_data is Dictionary else {}, strain_list)
	read_errors.append_array(db.errors)
	db.errors = read_errors
	return db


static func from_dicts(species_list: Array, item_list: Array, template_list: Array,
		economy_data: Dictionary, strain_list: Array = []) -> DataDB:
	var db := DataDB.new()
	for s in species_list:
		db._add_unique(db.species, s, "species")
	for i in item_list:
		db._add_unique(db.items, i, "item")
	for t in template_list:
		db._add_unique(db.request_templates, t, "request")
	for s in strain_list:
		db._add_unique(db.strains, s, "strain")
	db.economy = economy_data
	db.validate()
	return db


func is_valid() -> bool:
	return errors.is_empty()


func items_in_category(category: String) -> Array:
	var result := []
	for id in items:
		if items[id]["category"] == category:
			result.append(id)
	result.sort()
	return result


func validate() -> void:
	for id in species:
		_validate_species(species[id])
	for id in items:
		_validate_item(items[id])
	for id in request_templates:
		_validate_template(request_templates[id])
	for id in strains:
		_validate_strain(strains[id])
	_validate_economy()


func _add_unique(target: Dictionary, entry, kind: String) -> void:
	if not entry is Dictionary or not entry.has("id"):
		errors.append("%s: entry without an 'id': %s" % [kind, str(entry)])
		return
	if target.has(entry["id"]):
		errors.append("%s/%s: duplicate id" % [kind, entry["id"]])
		return
	target[entry["id"]] = entry


func _require(d: Dictionary, fields: Array, ctx: String) -> bool:
	var ok := true
	for f in fields:
		if not d.has(f):
			errors.append("%s: missing field '%s'" % [ctx, f])
			ok = false
	return ok


func _validate_species(s: Dictionary) -> void:
	var ctx := "species/%s" % s["id"]
	if not _require(s, SPECIES_FIELDS, ctx):
		return
	if not (s["brood_size"] is Array and s["brood_size"].size() == 2):
		errors.append("%s: 'brood_size' must be [min, max]" % ctx)
	if not s["traits"] is Dictionary or s["traits"].is_empty():
		errors.append("%s: 'traits' must be a non-empty object" % ctx)
		return
	for trait_name in s["traits"]:
		var t = s["traits"][trait_name]
		if not t is Dictionary or not t.get("common") is Array or t["common"].is_empty():
			errors.append("%s: trait '%s' needs a non-empty 'common' list" % [ctx, trait_name])
			continue
		var all_values: Array = t["common"] + t.get("rare", [])
		for v in t.get("mutations", []):
			if not v in all_values:
				errors.append("%s: mutation '%s' is not a %s value" % [ctx, v, trait_name])
		var mutation_weights: Dictionary = t.get("mutation_weights", {})
		for v in mutation_weights:
			if not v in t.get("mutations", []):
				errors.append("%s: mutation_weights lists '%s', which is not in mutations" % [ctx, v])
			elif float(mutation_weights[v]) <= 0.0:
				errors.append("%s: mutation weight for '%s' must be above 0" % [ctx, v])
		for recipe in s.get("recipes", {}).get(trait_name, []):
			for v in recipe.get("parents", []) + [recipe.get("child", "")]:
				if not v in all_values:
					errors.append("%s: recipe uses '%s', which is not a %s value" % [ctx, v, trait_name])
		for v in s.get("value_multipliers", {}).get(trait_name, {}):
			if not v in all_values:
				errors.append("%s: value_multipliers lists '%s', which is not a %s value" % [ctx, v, trait_name])
	if s.has("sprites"):
		_validate_sprites(s, ctx)


func _validate_item(item: Dictionary) -> void:
	var ctx := "item/%s" % item["id"]
	if not _require(item, ITEM_FIELDS, ctx):
		return
	var category: String = item["category"]
	if not category in ITEM_CATEGORIES:
		errors.append("%s: unknown category '%s'" % [ctx, category])
	if category in PLACEABLE_CATEGORIES and not item.get("height") in HEIGHTS:
		errors.append("%s: placeable items need 'height' (short/medium/tall)" % ctx)
	if category == "tank" and not item.has("capacity"):
		errors.append("%s: tanks need 'capacity'" % ctx)
	if item.has("sprite"):
		var rect = item["sprite"]
		if not rect is Array or rect.size() != 4:
			errors.append("%s: 'sprite' must be [x, y, w, h]" % ctx)
		if not ResourceLoader.exists(item.get("sheet", "")):
			errors.append("%s: sprite sheet '%s' not found" % [ctx, item.get("sheet", "")])


func _validate_template(t: Dictionary) -> void:
	var ctx := "request/%s" % t["id"]
	if not _require(t, TEMPLATE_FIELDS, ctx):
		return
	if not species.has(t["species"]):
		errors.append("%s: unknown species '%s'" % [ctx, t["species"]])
		return
	var traits: Dictionary = species[t["species"]].get("traits", {})
	for c in t["constraints"]:
		if c != "sex" and not traits.has(c):
			errors.append("%s: constraint '%s' is not a trait of %s" % [ctx, c, t["species"]])


func _validate_economy() -> void:
	if not _require(economy, ECONOMY_FIELDS, "economy"):
		return
	var tanks: Dictionary = economy["breeding_tanks"]
	if _require(tanks, ["max", "extra_costs"], "economy/breeding_tanks") \
			and tanks["extra_costs"].size() < int(tanks["max"]) - 1:
		errors.append("economy/breeding_tanks: needs a cost for each extra tank (%d)" % (int(tanks["max"]) - 1))
	var start: Dictionary = economy["starting_state"]
	if not _require(start, ["money", "display_tank", "items", "fish"], "economy/starting_state"):
		return
	for item_id in start["items"]:
		if not items.has(item_id):
			errors.append("economy/starting_state: unknown item '%s'" % item_id)
	var tank_id: String = start["display_tank"]
	if not items.has(tank_id) or items[tank_id].get("category") != "tank":
		errors.append("economy/starting_state: display_tank '%s' is not a tank item" % tank_id)
	for f in start["fish"]:
		if not species.has(f.get("species_id", "")):
			errors.append("economy/starting_state: fish has unknown species '%s'" % f.get("species_id", ""))
		var where: String = f.get("location", Fish.HOLDING)
		if not (where in [Fish.HOLDING, Fish.DISPLAY] or Fish.is_breeding(where)):
			errors.append("economy/starting_state: fish has unknown location '%s'" % f["location"])
	var layout: Dictionary = start.get("display_tank_layout", {})
	var substrate: String = layout.get("substrate", "")
	if substrate != "" and items.get(substrate, {}).get("category") != "substrate":
		errors.append("economy/starting_state: layout substrate '%s' is not a substrate" % substrate)
	var slot_items: Array = layout.get("slots", [])
	if slot_items.size() > Tank.ROWS.size():
		errors.append("economy/starting_state: layout has more than %d slots" % Tank.ROWS.size())
	for id in slot_items:
		if id != "" and not items.get(id, {}).get("category") in PLACEABLE_CATEGORIES:
			errors.append("economy/starting_state: layout item '%s' can't go in a slot" % id)


static func _read_dir(path: String, errs: Array[String]) -> Array:
	var result := []
	if not DirAccess.dir_exists_absolute(path):
		errs.append("%s: folder not found" % path)
		return result
	var files := DirAccess.get_files_at(path)
	files.sort()
	for file in files:
		if not file.ends_with(".json"):
			continue
		var data = _read_file(path.path_join(file), errs)
		if data is Dictionary:
			result.append(data)
		elif data != null:
			errs.append("%s: expected a JSON object at the top level" % path.path_join(file))
	return result


static func _read_file(path: String, errs: Array[String]):
	if not FileAccess.file_exists(path):
		errs.append("%s: file not found" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errs.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _validate_strain(s: Dictionary) -> void:
	var ctx := "strain/%s" % s["id"]
	if not _require(s, STRAIN_FIELDS, ctx):
		return
	if not species.has(s["species"]):
		errors.append("%s: unknown species '%s'" % [ctx, s["species"]])
		return
	var stars := int(s["stars"])
	if stars < 1 or stars > 5:
		errors.append("%s: stars must be 1–5 (got %d)" % [ctx, stars])
	var tiers := []
	for t in economy.get("fish_market", {}).get("tiers", []):
		tiers.append(int(t["tier"]))
	if not int(s["tier"]) in tiers:
		errors.append("%s: tier %d is not listed in economy/fish_market/tiers" % [ctx, int(s["tier"])])
	var traits: Dictionary = species[s["species"]]["traits"]
	for trait_name in s["traits"]:
		if not traits.has(trait_name):
			errors.append("%s: '%s' is not a trait of %s" % [ctx, trait_name, s["species"]])
			continue
		var allowed: Array = traits[trait_name]["common"] + traits[trait_name].get("rare", [])
		if not s["traits"][trait_name] in allowed:
			errors.append("%s: '%s' is not a valid %s" % [ctx, s["traits"][trait_name], trait_name])


## Every value of the sprite trait needs a frame, and the sheet must exist.
func _validate_sprites(s: Dictionary, ctx: String) -> void:
	var sprites: Dictionary = s["sprites"]
	if not _require(sprites, ["sheet", "trait", "varieties"], ctx + "/sprites"):
		return
	if not ResourceLoader.exists(sprites["sheet"]):
		errors.append("%s/sprites: sheet '%s' not found" % [ctx, sprites["sheet"]])
	var t: Dictionary = s["traits"].get(sprites["trait"], {})
	var placeholders: Dictionary = sprites.get("placeholders", {})
	for v in t.get("common", []) + t.get("rare", []):
		var rect = sprites["varieties"].get(v)
		if rect is Array and rect.size() == 4:
			continue
		# No art yet: a placeholder (a tinted copy of another variety) is fine.
		var ph = placeholders.get(v)
		if ph is Dictionary and sprites["varieties"].has(ph.get("base", "")) and ph.has("tint"):
			continue
		errors.append("%s/sprites: no frame [x, y, w, h] or placeholder for %s '%s'" % [ctx, sprites["trait"], v])
