extends RefCounted
## Small hand-made data, so tests don't break when the real balance numbers change.


static func species() -> Dictionary:
	return {
		"id": "guppy", "name": "Guppy", "plural_name": "Guppies", "base_price": 10, "days_to_adult": 3,
		"brood_size": [2, 4], "days_between_broods": 2, "mutation_chance": 0.05,
		"rare_value_multiplier": 1.5,
		"traits": {
			"body_color": {"common": ["grey", "orange"], "rare": ["red"]},
			"tail_shape": {"common": ["round", "fan"], "rare": ["delta"]},
			"pattern": {"common": ["plain"], "rare": ["mosaic"]},
		},
	}


static func items() -> Array:
	return [
		{"id": "sand", "name": "Sand", "category": "substrate", "cost": 4, "price": 10, "tags": ["natural"]},
		{"id": "stone", "name": "Stone", "category": "rock", "cost": 2, "price": 5, "tags": ["rocky", "natural"], "height": "short"},
		{"id": "wood", "name": "Wood", "category": "driftwood", "cost": 6, "price": 12, "tags": ["natural"], "height": "tall"},
		{"id": "fern", "name": "Fern", "category": "plant", "cost": 3, "price": 6, "tags": ["planted", "natural"], "height": "medium"},
		{"id": "grass", "name": "Grass", "category": "plant", "cost": 2, "price": 4, "tags": ["planted"], "height": "short"},
		{"id": "castle", "name": "Castle", "category": "decor", "cost": 8, "price": 15, "tags": ["colorful"], "height": "tall"},
		{"id": "food", "name": "Food", "category": "food", "cost": 2, "price": 5, "tags": []},
		{"id": "tank", "name": "Tank", "category": "tank", "cost": 25, "price": 40, "tags": [], "capacity": 4},
	]


static func items_by_id() -> Dictionary:
	var result := {}
	for item in items():
		result[item["id"]] = item
	return result


static func template() -> Dictionary:
	return {
		"id": "stocked_tank", "species": "guppy", "theme_tags": ["planted", "rocky"],
		"fish_count": [1, 3], "constraints": ["body_color", "sex"],
		"constraint_count": [1, 2], "base_reward": 100,
	}


static func economy() -> Dictionary:
	return {
		"quality_multipliers": {"1": 0.6, "2": 0.8, "3": 1.0, "4": 1.5, "5": 2.25},
		"offspring_quality_nudge": {"normal": [0.2, 0.6, 0.2], "fed": [0.1, 0.6, 0.3], "premium": [0.0, 0.0, 1.0]},
		"tank_pricing": {"item_markup": 1.2, "aesthetics_bonus_per_point": 0.5},
		"aesthetics": {
			"substrate": 15, "coverage": 25, "hardscape_and_plants": 15,
			"variety": 15, "variety_cap": 4, "layering": 15, "theme": 15,
		},
		"breeding_tank_capacity": 8,
		"breeding_tanks": {"max": 4, "max_mothers": 3, "extra_costs": [20, 30, 40]},
		"clock": {"open_hour": 9, "min_open_hours": 4, "hard_close_hour": 21, "real_seconds_per_hour": 60, "restock_speed": 4},
		"customers": {
			"spawn_interval_minutes": [30, 90], "min_interval_minutes": 12, "first_arrival_minutes": 10,
			"request_chance": 0.0, "patience_minutes": 60, "wants": {"fish": 3, "item": 2, "tank": 1, "wish": 0.0, "collector": 0.0},
			"collector": {"min_stars": 4, "price_multipliers": {"4": 1.5, "5": 2.0}},
			"appeal": {"display_weight": 1.0, "holding_weight": 0.4, "breeding_weight": 0.25,
				"rare_trait_bonus": 1.5, "looks_weight": 3.0, "speedup_per_point": 0.04, "max_speedup": 4.0},
			"names": ["Mabel"],
		},
		"breeding_book": {"recipe_rewards": [15, 30, 60], "mutation_reward": 50, "generation_bonus": [50, 100, 200]},
		"requests": {"max_orders": 2, "min_bonus_fraction": 0.25},
		"backorders": {"discount": 0.1, "max": 2, "breed_wait_days": [2, 3],
			"market_wait_days": 1, "bred_price_multiplier": 2.0,
			"bred_wait_days": 7, "bred_reference_stars": 3},
		"wholesale": {"fraction": 0.4, "fry_price": 1},
		"favorites": {"max": 3},
		"fish_market": {"price_multiplier": 1.5, "tiers": [{"tier": 1, "name": "Starter"}, {"tier": 2, "name": "Fancy"}]},
		"starting_state": {
			"money": 100,
			"display_tank": "tank",
			"items": {"sand": 1, "stone": 2, "fern": 2, "food": 2, "tank": 1},
			"fish": [
				{"species_id": "guppy", "sex": "male", "stars": 2,
					"traits": {"body_color": "orange", "tail_shape": "fan", "pattern": "plain"}},
				{"species_id": "guppy", "sex": "female", "stars": 4,
					"traits": {"body_color": "grey", "tail_shape": "round", "pattern": "plain"}},
			],
		},
	}


static func strains() -> Array:
	return [
		{"id": "wild", "name": "Wild", "species": "guppy", "tier": 1, "stars": 2, "traits": {}},
		{"id": "red_delta", "name": "Red Delta", "species": "guppy", "tier": 2, "stars": 4,
			"traits": {"body_color": "red", "tail_shape": "delta"}},
		{"id": "orange", "name": "Orange", "species": "guppy", "tier": 1, "stars": 3, "traits": {"body_color": "orange"}},
	]


static func goals() -> Array:
	return [
		{"id": "first_sale", "name": "First sale", "description": "Sell a fish.", "metric": "fish_sold", "target": 1, "reward": 10},
		{"id": "two_tanks", "name": "Two tanks", "description": "Own 2 breeding tanks.", "metric": "breeding_tanks", "target": 2, "reward": 30},
		{"id": "good_day", "name": "Good day", "description": "Earn $50 in a day.", "metric": "best_day", "target": 50, "reward": 5},
	]


static func upgrades() -> Array:
	return [
		{"id": "sign", "name": "Sign", "description": "", "cost": 40, "effects": {"customer_speed": 1.0}},
		{"id": "big_sign", "name": "Big Sign", "description": "", "cost": 10, "requires": "sign", "effects": {"customer_speed": 1.0}},
		{"id": "bench", "name": "Bench", "description": "", "cost": 5, "effects": {"patience": 0.5}},
		{"id": "desk", "name": "Desk", "description": "", "cost": 5, "effects": {"max_orders": 2, "max_backorders": 3}},
		{"id": "feeder", "name": "Feeder", "description": "", "cost": 5, "effects": {"auto_feed": 1}},
		{"id": "racks", "name": "Racks", "description": "", "cost": 5, "effects": {"breeding_capacity": 4}},
		{"id": "premium", "name": "Premium", "description": "", "cost": 5, "effects": {"premium_food": 1}},
		{"id": "contract", "name": "Contract", "description": "", "cost": 5, "effects": {"wholesale_fraction": 0.1}},
		{"id": "heaters", "name": "Heaters", "description": "", "cost": 5, "effects": {"brood_nights": 1}},
	]


static func reputation() -> Dictionary:
	return {
		"points": {"sale": 1, "star_bonus": [0, 0, 1, 2, 4, 6], "order_delivered": 10, "backorder_filled": 4,
			"collector_sale": 6, "goal_reached": 5, "recipe_discovered": 3, "mutation_discovered": 8},
		"customer_speed_per_extra": 0.1,
		"levels": [
			{"name": "Start", "points": 0, "effects": {}, "unlocks": [], "description": "Start."},
			{"name": "Known", "points": 20, "effects": {"extra_customers": 1}, "unlocks": ["lab"], "description": "Lab."},
			{"name": "Liked", "points": 60, "effects": {"extra_customers": 2, "extra_orders": 1}, "unlocks": ["fish_show"], "description": "Shows."},
			{"name": "Famous", "points": 100, "effects": {}, "unlocks": [], "description": "Top."},
		],
	}


static func db() -> DataDB:
	return DataDB.from_dicts([species()], items(), [template()], economy(), strains(), goals(), upgrades(),
		[], [], reputation())


static func rng(seed_value: int = 1234) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


static func fish(sex: String, color: String = "grey", stars: int = 3, age_days: int = 3,
		tail: String = "round", pattern: String = "plain") -> Fish:
	var f := Fish.new()
	f.species_id = "guppy"
	f.sex = sex
	f.stars = stars
	f.age_days = age_days
	f.traits = {"body_color": color, "tail_shape": tail, "pattern": pattern}
	return f


static func new_game(seed_value: int = 1234) -> GameState:
	return GameState.new_game(db(), rng(seed_value))
