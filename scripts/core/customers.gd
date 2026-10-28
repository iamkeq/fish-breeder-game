class_name Customers
extends RefCounted
## Walk-in customer rules: how appealing the shop is, how often customers
## arrive, and what they ask for. Rules come from economy["customers"].


## How much each fish adds to shop appeal: its stars plus a bonus per rare trait.
static func fish_appeal(fish: Fish, species: Dictionary, rules: Dictionary) -> float:
	if not fish.is_adult(species):
		return 0.0
	return fish.stars + fish.rare_trait_count(species) * float(rules["appeal"]["rare_trait_bonus"])


## Overall shop appeal. Fish for sale on display count fully, fish in holding
## partly, breeding stock a little; a good-looking display tank adds more.
static func shop_appeal(display: Array, holding: Array, breeding: Array, display_looks: int,
		species_db: Dictionary, rules: Dictionary) -> float:
	var weights: Dictionary = rules["appeal"]
	var total := 0.0
	for group in [[display, "display_weight"], [holding, "holding_weight"], [breeding, "breeding_weight"]]:
		for f in group[0]:
			total += fish_appeal(f, species_db[f.species_id], rules) * float(weights[group[1]])
	total += display_looks / 100.0 * float(weights["looks_weight"])
	return total


## Customers come this many times faster than the base rate (1 = base).
static func speedup(appeal: float, rules: Dictionary) -> float:
	var weights: Dictionary = rules["appeal"]
	return minf(1.0 + appeal * float(weights["speedup_per_point"]), float(weights["max_speedup"]))


## In-game minutes until the next customer arrives.
static func next_arrival_minutes(appeal: float, rules: Dictionary, rng: RandomNumberGenerator) -> float:
	var range_: Array = rules["spawn_interval_minutes"]
	var base := rng.randf_range(float(range_[0]), float(range_[1]))
	return maxf(base / speedup(appeal, rules), float(rules["min_interval_minutes"]))


## Picks what a walk-in wants. `ctx` describes the shop right now:
##   fish_for_sale: Array[Fish]     adults they could buy
##   species_db: Dictionary
##   items_in_stock: Array          item ids with stock > 0
##   all_items: Array               every item id in the catalogue
##   strains: Dictionary            Market strains (id -> data), for fish wishes
##   tank_for_sale: bool            display tank is decorated
##   can_take_request: bool         room for another order
## Kinds: fish / item / tank (in stock), wish_item / wish_fish (out of stock:
## the player can back-order it), request, browse.
static func make_walk_in(ctx: Dictionary, rules: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var names: Array = rules.get("names", ["A customer"])
	var customer := {
		"name": names[rng.randi_range(0, names.size() - 1)],
		"waited": 0.0,
		"patience": float(rules["patience_minutes"]),
	}
	var can_request: bool = ctx.get("can_take_request", false)
	if can_request and rng.randf() < float(rules["request_chance"]):
		customer["kind"] = "request"
		return customer

	var fish_for_sale: Array = ctx.get("fish_for_sale", [])
	var in_stock: Array = ctx.get("items_in_stock", [])
	var missing: Array = ctx.get("all_items", []).filter(func(id): return not id in in_stock)
	var strains: Dictionary = ctx.get("strains", {})
	var wants: Dictionary = rules["wants"]
	var options := {}
	if not fish_for_sale.is_empty():
		options["fish"] = float(wants["fish"])
	if not in_stock.is_empty():
		options["item"] = float(wants["item"])
	if ctx.get("tank_for_sale", false):
		options["tank"] = float(wants["tank"])
	if not missing.is_empty():
		options["wish_item"] = float(wants.get("wish", 0.0)) * 0.5
	if not strains.is_empty():
		options["wish_fish"] = float(wants.get("wish", 0.0)) * 0.5
	options = _positive(options)
	if options.is_empty():
		customer["kind"] = "request" if can_request else "browse"
		return customer

	customer["kind"] = _weighted_key(options, rng)
	match customer["kind"]:
		"fish":
			# Better and rarer fish catch the eye more often.
			var species_db: Dictionary = ctx["species_db"]
			var weights := {}
			for f in fish_for_sale:
				weights[f.id] = 1.0 + fish_appeal(f, species_db[f.species_id], rules)
			customer["fish_id"] = _weighted_key(weights, rng)
		"item":
			customer["item_id"] = in_stock[rng.randi_range(0, in_stock.size() - 1)]
		"tank":
			customer["with_fish"] = true
		"wish_item":
			customer["item_id"] = missing[rng.randi_range(0, missing.size() - 1)]
		"wish_fish":
			# Cheaper tiers are wished for more often.
			var weights := {}
			for id in strains:
				weights[id] = 1.0 / maxf(float(strains[id]["tier"]), 1.0)
			customer["strain_id"] = _weighted_key(weights, rng)
			customer["sex"] = Fish.MALE if rng.randf() < 0.5 else Fish.FEMALE
	return customer


static func _positive(weights: Dictionary) -> Dictionary:
	var result := {}
	for k in weights:
		if weights[k] > 0.0:
			result[k] = weights[k]
	return result


## Matches a fish against a strain wish: same species and sex, at least the
## strain's stars, and every trait the strain fixes. Home-bred fish count too.
static func matches_strain(f: Fish, strain: Dictionary, sex: String, species: Dictionary) -> bool:
	if f.species_id != strain["species"] or f.sex != sex or not f.is_adult(species):
		return false
	if f.stars < int(strain["stars"]):
		return false
	for trait_name in strain["traits"]:
		if f.get_trait(trait_name) != strain["traits"][trait_name]:
			return false
	return true


## The discounted price for something the customer has to wait for.
static func backorder_price(full_price: int, rules: Dictionary) -> int:
	return maxi(1, roundi(full_price * (1.0 - float(rules["discount"]))))

static func _weighted_key(weights: Dictionary, rng: RandomNumberGenerator):
	var keys := weights.keys()
	keys.sort()
	var total := 0.0
	for k in keys:
		total += weights[k]
	var roll := rng.randf() * total
	for k in keys:
		roll -= weights[k]
		if roll < 0.0:
			return k
	return keys[-1]
