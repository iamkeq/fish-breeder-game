class_name Pricing
extends RefCounted
## Sale prices. All numbers come from data (species, items, economy).


static func quality_multiplier(stars: int, economy: Dictionary) -> float:
	return float(economy["quality_multipliers"][str(stars)])


## Fry can't be sold, so their price is 0. A fish bred in the shop and scanned
## in the Lab earns a "certified" bonus for high purity (never for bought fish).
static func fish_price(fish: Fish, species: Dictionary, economy: Dictionary) -> int:
	if not fish.is_adult(species):
		return 0
	var price := float(species["base_price"]) * quality_multiplier(fish.stars, economy) \
		* trait_multiplier(fish, species)
	if fish.scanned and fish.paid == 0 and fish.strain_id == "":
		price *= 1.0 + Purity.certified_bonus(fish.purity, economy.get("lab", {}))
	return maxi(1, roundi(price))


## How much a fish's looks add to its price. A trait value listed in the
## species' "value_multipliers" uses that number; any other rare value uses
## "rare_value_multiplier"; common values are x1.
static func trait_multiplier(fish: Fish, species: Dictionary) -> float:
	var result := 1.0
	var values: Dictionary = species.get("value_multipliers", {})
	for trait_name in fish.traits:
		var value: String = fish.traits[trait_name]
		if values.get(trait_name, {}).has(value):
			result *= float(values[trait_name][value])
		elif Genetics.is_rare(species, trait_name, value):
			result *= float(species["rare_value_multiplier"])
	return result


static func item_price(item: Dictionary) -> int:
	return int(item["price"])


## What it cost to build the tank at Market prices: the tank, its substrate
## and everything placed in it.
static func tank_build_cost(tank: Tank, items: Dictionary) -> int:
	var total := 0
	if tank.tank_item_id != "":
		total += int(items[tank.tank_item_id]["cost"])
	for id in tank.placed_item_ids():
		total += int(items[id]["cost"])
	return total


## Build cost + a small premium + a looks bonus (at most `looks_bonus_max` of
## the build cost, at 100 looks) + (optionally) the fish inside at their own
## prices. Pass `fish_total` = 0 to sell the tank without fish. Selling a tank
## and rebuilding it can never earn more than the premium and looks bonus.
static func tank_price(tank: Tank, items: Dictionary, aesthetics_score: int, fish_total: int,
		economy: Dictionary) -> int:
	var rules: Dictionary = economy["tank_pricing"]
	var build := float(tank_build_cost(tank, items))
	var total := build * (1.0 + float(rules["premium"]))
	total += build * float(rules["looks_bonus_max"]) * clampf(aesthetics_score / 100.0, 0.0, 1.0)
	total += fish_total
	return roundi(total)


## What the Fish Market charges for an adult of a named strain. Only the traits
## the strain fixes count (unlisted ones are random common values).
static func strain_cost(strain: Dictionary, species: Dictionary, economy: Dictionary) -> int:
	var f := Fish.new()
	f.species_id = species["id"]
	f.stars = int(strain["stars"])
	f.traits = strain["traits"].duplicate()
	f.age_days = int(species["days_to_adult"])
	var multiplier := float(economy["fish_market"]["price_multiplier"])
	return maxi(1, roundi(fish_price(f, species, economy) * multiplier))


## What the wholesaler pays: a fraction of the customer price, or a token amount for fry.
static func wholesale_price(fish: Fish, species: Dictionary, economy: Dictionary) -> int:
	var rules: Dictionary = economy["wholesale"]
	if not fish.is_adult(species):
		return int(rules["fry_price"])
	return maxi(1, roundi(fish_price(fish, species, economy) * float(rules["fraction"])))
