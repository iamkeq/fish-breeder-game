class_name Pricing
extends RefCounted
## Sale prices. All numbers come from data (species, items, economy).


static func quality_multiplier(stars: int, economy: Dictionary) -> float:
	return float(economy["quality_multipliers"][str(stars)])


## Fry can't be sold, so their price is 0.
static func fish_price(fish: Fish, species: Dictionary, economy: Dictionary) -> int:
	if not fish.is_adult(species):
		return 0
	var price := float(species["base_price"]) * quality_multiplier(fish.stars, economy) \
		* trait_multiplier(fish, species)
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


## Tank + marked-up contents + a looks bonus + (optionally) the fish inside.
## Pass `fish_total` = 0 to sell the tank without fish.
static func tank_price(tank: Tank, items: Dictionary, aesthetics_score: int, fish_total: int,
		economy: Dictionary) -> int:
	var rules: Dictionary = economy["tank_pricing"]
	var total := 0.0
	if tank.tank_item_id != "":
		total += float(items[tank.tank_item_id]["price"])
	for id in tank.placed_item_ids():
		total += float(items[id]["price"]) * float(rules["item_markup"])
	total += aesthetics_score * float(rules["aesthetics_bonus_per_point"])
	total += fish_total
	return roundi(total)


## What the Fish Market charges for an adult of a named strain: the customer
## price times fish_market.price_multiplier (below 1, so reselling makes a
## profit). Only the traits the strain fixes count (unlisted ones are random).
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
