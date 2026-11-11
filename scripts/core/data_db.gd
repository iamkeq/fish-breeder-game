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
	"fish_market", "starting_state", "purity", "lab"]

var species: Dictionary = {}
var items: Dictionary = {}
var request_templates: Dictionary = {}
## Named breeding-stock lines sold in the Fish Market, by id.
var strains: Dictionary = {}
var economy: Dictionary = {}
## Goals in the order they're listed (data/goals.json).
var goals: Array = []
## Shop upgrades by id, and their listed order (data/upgrades.json).
var upgrades: Dictionary = {}
var upgrade_order: Array = []
## Shop reputation: points per source, and the levels (data/reputation.json).
## Empty when a test builds a DataDB without it (reputation then does nothing).
var reputation: Dictionary = {}
## Fish show rules (data/shows.json). Empty when a test builds a DataDB without
## it (fish shows are then closed).
var shows: Dictionary = {}
## Shop staff rules (data/staff.json). Empty when a test builds a DataDB without
## it (hiring is then closed).
var staff: Dictionary = {}
## Starting pairs and challenge modes for a new game, in listed order
## (data/new_game.json). With no starts listed there is one implicit "standard"
## start built from economy.starting_state.fish; challenges may be empty.
var starts: Array = []
var challenges: Array = []
## True when `starts` is the implicit standard one (already checked as economy data).
var _implicit_start := false
var errors: Array[String] = []

const GOAL_FIELDS := ["id", "name", "description", "metric", "target", "reward"]
## What a goal can count. See GameState.goal_value().
const GOAL_METRICS := ["fish_sold", "fish_bred", "recipes", "mutations", "display_looks",
	"orders_delivered", "backorders_filled", "breeding_tanks", "upgrades", "best_day",
	"best_stars_sold", "total_earned", "customers_served", "third_gen_recipes", "collector_sales", "fish_named", "favorites",
	"reputation_level", "fish_scanned", "best_purity_scanned", "shows_entered", "ribbons_first", "ribbons",
	"grand_wins", "hall_of_fame", "pinned", "staff_hired", "staff_count", "staff_actions"]
## The jobs a hire can be given, in the order they run each night. See GameState.end_day().
const STAFF_TASKS := ["feeder", "decorator", "stocker"]
## What a reputation level can change. See GameState.reputation_effect().
const REPUTATION_EFFECTS := ["extra_customers", "extra_orders"]
## What earns reputation points. See GameState._rep().
const REPUTATION_POINTS := ["sale", "star_bonus", "order_delivered", "backorder_filled",
	"collector_sale", "goal_reached", "recipe_discovered", "mutation_discovered",
	"show_entered", "show_first", "show_second", "show_third"]
## What a fish show class rule can ask for. See GameState.show_blocker().
const SHOW_RULES := ["min_stars", "rare", "mutation", "min_purity_scanned"]
const REPUTATION_LEVEL_FIELDS := ["name", "points", "effects", "unlocks", "description"]
const START_FIELDS := ["id", "name", "description"]
const CHALLENGE_FIELDS := ["id", "name", "description", "rules"]
## What a challenge rule can change. See GameState.challenge_rule().
const CHALLENGE_RULES := ["starting_money", "market_fish_until_day", "mutation_chance_multiplier",
	"customers_buy_only_mutations"]
const UPGRADE_FIELDS := ["id", "name", "description", "cost", "effects"]
const UPGRADE_EFFECTS := ["customer_speed", "patience", "max_orders", "max_backorders",
	"breeding_capacity", "auto_feed", "premium_food", "wholesale_fraction", "brood_nights"]


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
	var goal_data = _read_file(root.path_join("goals.json"), read_errors)
	var upgrade_data = _read_file(root.path_join("upgrades.json"), read_errors)
	var reputation_data = _read_file(root.path_join("reputation.json"), read_errors)
	var shows_data = _read_file(root.path_join("shows.json"), read_errors)
	var staff_data = _read_file(root.path_join("staff.json"), read_errors)
	# Optional: without it there is one standard start and no challenges.
	var new_game_data = null
	if FileAccess.file_exists(root.path_join("new_game.json")):
		new_game_data = _read_file(root.path_join("new_game.json"), read_errors)
	var db := from_dicts(species_list, item_list, template_list,
		economy_data if economy_data is Dictionary else {}, strain_list,
		goal_data.get("goals", []) if goal_data is Dictionary else [],
		upgrade_data.get("upgrades", []) if upgrade_data is Dictionary else [],
		new_game_data.get("starts", []) if new_game_data is Dictionary else [],
		new_game_data.get("challenges", []) if new_game_data is Dictionary else [],
		reputation_data if reputation_data is Dictionary else {},
		shows_data if shows_data is Dictionary else {},
		staff_data if staff_data is Dictionary else {})
	read_errors.append_array(db.errors)
	db.errors = read_errors
	return db


static func from_dicts(species_list: Array, item_list: Array, template_list: Array,
		economy_data: Dictionary, strain_list: Array = [], goal_list: Array = [],
		upgrade_list: Array = [], start_list: Array = [], challenge_list: Array = [], reputation_data: Dictionary = {}, shows_data: Dictionary = {},
		staff_data: Dictionary = {}) -> DataDB:
	var db := DataDB.new()
	db.reputation = reputation_data
	db.shows = shows_data
	db.staff = staff_data
	for s in species_list:
		db._add_unique(db.species, s, "species")
	for i in item_list:
		db._add_unique(db.items, i, "item")
	for t in template_list:
		db._add_unique(db.request_templates, t, "request")
	for s in strain_list:
		db._add_unique(db.strains, s, "strain")
	var goal_ids := {}
	for g in goal_list:
		db._add_unique(goal_ids, g, "goal")
	db.goals = goal_list.filter(func(g): return g is Dictionary and g.has("id"))
	for u in upgrade_list:
		db._add_unique(db.upgrades, u, "upgrade")
		if u is Dictionary and u.has("id") and not u["id"] in db.upgrade_order:
			db.upgrade_order.append(u["id"])
	db.economy = economy_data
	var start_ids := {}
	for st in start_list:
		db._add_unique(start_ids, st, "start")
	db.starts = start_list.filter(func(st): return st is Dictionary and st.has("id"))
	var challenge_ids := {}
	for c in challenge_list:
		db._add_unique(challenge_ids, c, "challenge")
	db.challenges = challenge_list.filter(func(c): return c is Dictionary and c.has("id"))
	if db.starts.is_empty() and economy_data.get("starting_state") is Dictionary \
			and economy_data["starting_state"].get("fish") is Array:
		db.starts = [{"id": "standard", "name": "Standard", "description": "The usual pair.",
			"fish": economy_data["starting_state"]["fish"]}]
		db._implicit_start = true
	db.validate()
	return db


## The start with this id, or the first one listed (so unknown ids fall back).
func start_by_id(start_id: String) -> Dictionary:
	for st in starts:
		if st["id"] == start_id:
			return st
	return starts[0] if not starts.is_empty() else {}


## The challenge with this id, or {} (no challenge) if there isn't one.
func challenge_by_id(challenge_id: String) -> Dictionary:
	for c in challenges:
		if c["id"] == challenge_id:
			return c
	return {}


func is_valid() -> bool:
	return errors.is_empty()


func items_in_category(category: String) -> Array:
	var result := []
	for id in items:
		if items[id]["category"] == category:
			result.append(id)
	result.sort()
	return result


func _validate_reputation() -> void:
	if reputation.is_empty():
		return
	var points = reputation.get("points")
	if not points is Dictionary:
		errors.append("reputation: missing 'points'")
	else:
		for key in points:
			if not key in REPUTATION_POINTS:
				errors.append("reputation: unknown point source '%s'" % key)
		for key in REPUTATION_POINTS:
			if not points.has(key):
				errors.append("reputation: missing point source '%s'" % key)
		if points.has("star_bonus") and not (points["star_bonus"] is Array and points["star_bonus"].size() >= 6):
			errors.append("reputation: star_bonus needs 6 numbers (index = stars)")
	var levels = reputation.get("levels")
	if not levels is Array or levels.is_empty():
		errors.append("reputation: needs a list of levels")
		return
	var last := -1
	for i in levels.size():
		var lv = levels[i]
		var ctx := "reputation/level %d" % (i + 1)
		if not lv is Dictionary or not _require(lv, REPUTATION_LEVEL_FIELDS, ctx):
			continue
		if i == 0 and int(lv["points"]) != 0:
			errors.append("%s: the first level must start at 0 points" % ctx)
		if int(lv["points"]) <= last:
			errors.append("%s: levels must be in ascending order of points" % ctx)
		last = int(lv["points"])
		for effect in lv["effects"]:
			if not effect in REPUTATION_EFFECTS:
				errors.append("%s: unknown effect '%s'" % [ctx, effect])


func _validate_staff() -> void:
	if staff.is_empty():
		return
	var ctx := "staff"
	if not _require(staff, ["max_staff", "hire_costs", "daily_wage", "restock_to", "restock_budget",
			"keep_money", "names", "colors", "tasks"], ctx):
		return
	for key in ["max_staff", "daily_wage", "restock_budget"]:
		if not _is_whole(staff[key]) or int(staff[key]) < 1:
			errors.append("%s: '%s' must be a positive whole number" % [ctx, key])
	for key in ["keep_money", "decorator_keep"]:
		if staff.has(key) and (not _is_whole(staff[key]) or int(staff[key]) < 0):
			errors.append("%s: '%s' must be a whole number, 0 or more" % [ctx, key])
	var costs = staff["hire_costs"]
	if not costs is Array or (_is_whole(staff["max_staff"]) and costs.size() != int(staff["max_staff"])):
		errors.append("%s: hire_costs needs one price per member of staff (max_staff)" % ctx)
	elif costs.any(func(c): return not _is_whole(c) or int(c) < 1):
		errors.append("%s: hire_costs must be positive whole numbers" % ctx)
	for key in ["names", "colors"]:
		if not staff[key] is Array or staff[key].is_empty():
			errors.append("%s: '%s' needs at least one entry" % [ctx, key])
	if staff["restock_to"] is Dictionary:
		for id in staff["restock_to"]:
			if not _is_whole(staff["restock_to"][id]) or int(staff["restock_to"][id]) < 1:
				errors.append("%s: restock_to/%s must be a positive whole number" % [ctx, id])
			if not items.is_empty() and not items.has(id):
				errors.append("%s: restock_to lists unknown item '%s'" % [ctx, id])
	else:
		errors.append("%s: restock_to must be a list of item ids and targets" % ctx)
	if not staff["tasks"] is Array:
		errors.append("%s: tasks must be a list" % ctx)
		return
	var seen := {}
	for t in staff["tasks"]:
		if not t is Dictionary or not _require(t, ["id", "name", "description"], "%s/task" % ctx):
			continue
		if not t["id"] in STAFF_TASKS:
			errors.append("%s: unknown task '%s'" % [ctx, t["id"]])
		if seen.has(t["id"]):
			errors.append("%s: task '%s' listed twice" % [ctx, t["id"]])
		seen[t["id"]] = true


static func _is_whole(value) -> bool:
	return (value is int) or (value is float and value == floorf(value))


func _validate_shows() -> void:
	if shows.is_empty():
		return
	var ctx := "shows"
	var ok := _require(shows, ["every_days", "grand_every", "rivals", "score", "prizes", "rival_strength",
		"hints", "rival_names", "shows"], ctx)
	if not ok:
		return
	for key in ["every_days", "grand_every", "rivals"]:
		if not (shows[key] is int or shows[key] is float) or int(shows[key]) < 1:
			errors.append("%s: '%s' must be a positive whole number" % [ctx, key])
	var groups := {
		"score": ["per_star", "per_value_step", "purity_weight", "judge_swing"],
		"prizes": ["1", "2", "3", "grand_multiplier"],
		"rival_strength": ["base", "per_show", "max", "spread", "grand_bonus"],
		"hints": ["typical_purity", "promising", "good"],
	}
	for group in groups:
		if not shows[group] is Dictionary:
			errors.append("%s: '%s' must be an object" % [ctx, group])
			continue
		for key in groups[group]:
			if not shows[group].has(key):
				errors.append("%s/%s: missing '%s'" % [ctx, group, key])
			elif not (shows[group][key] is int or shows[group][key] is float):
				errors.append("%s/%s: '%s' must be a number" % [ctx, group, key])
	if shows["prizes"] is Dictionary:
		for key in ["1", "2", "3", "grand_multiplier"]:
			if shows["prizes"].has(key) and (shows["prizes"][key] is int or shows["prizes"][key] is float) \
					and int(shows["prizes"][key]) < 1:
				errors.append("%s/prizes: '%s' must be a positive whole number" % [ctx, key])
	if not (shows["rival_names"] is Array and not shows["rival_names"].is_empty()):
		errors.append("%s: 'rival_names' needs a list of names" % ctx)
	if not (shows["shows"] is Array and not shows["shows"].is_empty()):
		errors.append("%s: 'shows' needs a list of classes" % ctx)
		return
	for st in shows["shows"]:
		var show_ctx := "shows/%s" % (st.get("id", "?") if st is Dictionary else "?")
		if not st is Dictionary or not _require(st, ["id", "name", "description", "rule"], show_ctx):
			continue
		if not st["rule"] is Dictionary:
			errors.append("%s: 'rule' must be an object" % show_ctx)
			continue
		for rule_key in st["rule"]:
			if not rule_key in SHOW_RULES:
				errors.append("%s: unknown rule '%s'" % [show_ctx, rule_key])


func validate() -> void:
	for id in species:
		_validate_species(species[id])
	for id in items:
		_validate_item(items[id])
	for id in request_templates:
		_validate_template(request_templates[id])
	for id in strains:
		_validate_strain(strains[id])
	for g in goals:
		var goal_ctx := "goal/%s" % g["id"]
		if _require(g, GOAL_FIELDS, goal_ctx) and not g["metric"] in GOAL_METRICS:
			errors.append("%s: unknown metric '%s'" % [goal_ctx, g["metric"]])
	for id in upgrades:
		var u: Dictionary = upgrades[id]
		var upgrade_ctx := "upgrade/%s" % id
		if not _require(u, UPGRADE_FIELDS, upgrade_ctx):
			continue
		for effect in u["effects"]:
			if not effect in UPGRADE_EFFECTS:
				errors.append("%s: unknown effect '%s'" % [upgrade_ctx, effect])
		if u.has("requires") and not upgrades.has(u["requires"]):
			errors.append("%s: requires unknown upgrade '%s'" % [upgrade_ctx, u["requires"]])
	_validate_reputation()
	_validate_shows()
	_validate_staff()
	_validate_economy()
	for st in starts:
		if not _implicit_start:
			_validate_start(st)
	for c in challenges:
		_validate_challenge(c)


func _validate_start(st: Dictionary) -> void:
	var ctx := "start/%s" % st["id"]
	if not _require(st, START_FIELDS, ctx):
		return
	if st.get("random_pair", false):
		var species_id: String = st.get("species_id", "guppy")
		var trait_name: String = st.get("trait", "variety")
		if not species.has(species_id) or not species[species_id]["traits"].has(trait_name) \
				or species[species_id]["traits"][trait_name].get("common", []).size() < 2:
			errors.append("%s: random_pair needs a species trait with two or more common values" % ctx)
		return
	if not st.get("fish") is Array or st["fish"].is_empty():
		errors.append("%s: needs a 'fish' list (or 'random_pair')" % ctx)
		return
	for f in st["fish"]:
		var sp: Dictionary = species.get(f.get("species_id", ""), {})
		if sp.is_empty():
			errors.append("%s: fish has unknown species '%s'" % [ctx, f.get("species_id", "")])
			continue
		if not f.get("sex", "") in [Fish.MALE, Fish.FEMALE]:
			errors.append("%s: fish needs a sex" % ctx)
		var where: String = f.get("location", Fish.HOLDING)
		if not (where in [Fish.HOLDING, Fish.DISPLAY] or Fish.is_breeding(where)):
			errors.append("%s: fish has unknown location '%s'" % [ctx, where])
		for trait_name in f.get("traits", {}):
			var t: Dictionary = sp["traits"].get(trait_name, {})
			if t.is_empty() or not f["traits"][trait_name] in t["common"] + t.get("rare", []):
				errors.append("%s: '%s' is not a valid %s" % [ctx, f["traits"][trait_name], trait_name])


func _validate_challenge(c: Dictionary) -> void:
	var ctx := "challenge/%s" % c["id"]
	if not _require(c, CHALLENGE_FIELDS, ctx):
		return
	if not c["rules"] is Dictionary:
		errors.append("%s: 'rules' must be an object" % ctx)
		return
	for rule in c["rules"]:
		if not rule in CHALLENGE_RULES:
			errors.append("%s: unknown rule '%s'" % [ctx, rule])


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
		if item.has("frames"):
			if not item["frames"] is Array or item["frames"].is_empty() or item["frames"].any(func(f): return not f is Array or f.size() != 4):
				errors.append("%s: 'frames' must be a list of [x, y, w, h]" % ctx)
			if float(item.get("body_height", 0)) <= 0:
				errors.append("%s: animated items need 'body_height'" % ctx)
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


## economy.purity (creation numbers, star nudge, tiers) and economy.lab (scan fee, certified bonus).
func _validate_purity() -> void:
	var rules = economy["purity"]
	var lab = economy["lab"]
	if not (rules is Dictionary and lab is Dictionary):
		errors.append("economy: 'purity' and 'lab' must be objects")
		return
	if _require(rules, ["baseline", "market", "true_gain", "outcross_loss", "floor", "new_line", "star_nudge", "tiers"], "economy/purity"):
		for key in ["baseline", "market", "true_gain", "outcross_loss", "floor", "new_line"]:
			var v = rules[key]
			if not ((v is int or v is float) and v >= 0 and v <= 100):
				errors.append("economy/purity: '%s' must be a number from 0 to 100" % key)
		for key in ["star_nudge", "tiers"]:
			if not (rules[key] is Array and not rules[key].is_empty()):
				errors.append("economy/purity: '%s' must be a non-empty list" % key)
				return
		for tier in rules["star_nudge"]:
			if not (tier is Dictionary and tier.has("min") and (tier.get("shift") is float or tier.get("shift") is int)):
				errors.append("economy/purity/star_nudge: each entry needs 'min' and 'shift'")
			elif not (float(tier["shift"]) >= 0.0 and float(tier["shift"]) <= 1.0):
				errors.append("economy/purity/star_nudge: 'shift' must be between 0 and 1")
		var has_zero := false
		for tier in rules["tiers"]:
			if not (tier is Dictionary and tier.has("min") and tier.has("name")):
				errors.append("economy/purity/tiers: each tier needs 'min' and 'name'")
			elif int(tier["min"]) == 0:
				has_zero = true
		if not has_zero:
			errors.append("economy/purity/tiers: needs a tier starting at 0")
	if _require(lab, ["scan_cost", "certified_bonus"], "economy/lab"):
		if not ((lab["scan_cost"] is int or lab["scan_cost"] is float) and int(lab["scan_cost"]) >= 0):
			errors.append("economy/lab: 'scan_cost' must be a number")
		if not lab["certified_bonus"] is Array:
			errors.append("economy/lab: 'certified_bonus' must be a list")
		else:
			for tier in lab["certified_bonus"]:
				if not (tier is Dictionary and tier.has("min") and tier.has("bonus")):
					errors.append("economy/lab/certified_bonus: each entry needs 'min' and 'bonus'")


func _validate_economy() -> void:
	if not _require(economy, ECONOMY_FIELDS, "economy"):
		return
	var tanks: Dictionary = economy["breeding_tanks"]
	if _require(tanks, ["max", "extra_costs"], "economy/breeding_tanks") \
			and tanks["extra_costs"].size() < int(tanks["max"]) - 1:
		errors.append("economy/breeding_tanks: needs a cost for each extra tank (%d)" % (int(tanks["max"]) - 1))
	var mothers = tanks.get("max_mothers", 1)
	if not (mothers is int or mothers is float) or int(mothers) < 1:
		errors.append("economy/breeding_tanks: 'max_mothers' must be a number of 1 or more")
	if tanks.has("substrate") and not items.has(tanks["substrate"]):
		errors.append("economy/breeding_tanks: unknown substrate '%s'" % tanks["substrate"])
	if tanks.has("air_stone") and not ResourceLoader.exists(tanks["air_stone"].get("sheet", "")):
		errors.append("economy/breeding_tanks: air stone sheet '%s' not found" % tanks["air_stone"].get("sheet", ""))
	_validate_breeding_book()
	var favorites = economy.get("favorites")
	if not (favorites is Dictionary and (favorites.get("max") is int or favorites.get("max") is float)
			and int(favorites["max"]) >= 1):
		errors.append("economy/favorites: needs a 'max' number of 1 or more")
	var gallery = economy.get("gallery")
	if not (gallery is Dictionary and (gallery.get("pin_slots") is int or gallery.get("pin_slots") is float)
			and int(gallery["pin_slots"]) >= 1):
		errors.append("economy/gallery: needs a 'pin_slots' number of 1 or more")
	_validate_purity()
	var collector = economy["customers"].get("collector")
	if collector != null and not (collector is Dictionary and collector.has("min_stars")
			and collector.get("price_multipliers") is Dictionary):
		errors.append("economy/customers/collector: needs 'min_stars' and a 'price_multipliers' object")
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


## Optional block: only type-checked when present.
func _validate_breeding_book() -> void:
	var book = economy.get("breeding_book")
	if book == null:
		return
	if not book is Dictionary:
		errors.append("economy/breeding_book: must be an object")
		return
	for key in ["recipe_rewards", "generation_bonus"]:
		if book.has(key) and not book[key] is Array:
			errors.append("economy/breeding_book: '%s' must be a list" % key)
	if book.has("mutation_reward") and not (book["mutation_reward"] is int or book["mutation_reward"] is float):
		errors.append("economy/breeding_book: 'mutation_reward' must be a number")


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
