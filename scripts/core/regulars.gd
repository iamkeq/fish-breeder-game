class_name Regulars
extends RefCounted
## Regular customers: named people who come back, remember the shop and get
## more generous as they grow loyal. Pure maths on the data in
## data/regulars.json; GameState keeps the saved progress.


## Loyalty level (0 to max) for a number of loyalty points.
static func level(points: int, rules: Dictionary) -> int:
	var levels: Array = rules.get("loyalty_levels", [0])
	var result := 0
	for i in levels.size():
		if points >= int(levels[i]):
			result = i
	return result


## The highest loyalty level (5 hearts).
static func max_level(rules: Dictionary) -> int:
	return maxi(0, rules.get("loyalty_levels", [0]).size() - 1)


## Extra share of the price a regular of this level adds as a tip.
static func tip_rate(lvl: int, rules: Dictionary) -> float:
	return float(rules.get("tip_per_level", 0.0)) * lvl


## The tip on a price, in whole dollars. Rounded down, so a tip never makes a
## fish worth more than its exact percentage (and cheap Market fish stay a loss).
static func tip(price: int, lvl: int, rules: Dictionary) -> int:
	return tip_amount(price, tip_rate(lvl, rules))


## The same from a tip rate.
static func tip_amount(price: int, rate: float) -> int:
	return floori(price * rate + 0.000001)


## True when this fish is the kind the regular loves, at enough stars.
static func likes(fish: Fish, regular: Dictionary) -> bool:
	var fav: Dictionary = regular["favorite"]
	return fish.species_id == regular.get("species", "guppy") \
		and fish.get_trait(fav["trait"]) == fav["value"] \
		and fish.stars >= int(regular.get("min_stars", 1))


## The best fish a regular would buy from these (highest stars, then lowest id), or null.
static func best_match(fish_list: Array, regular: Dictionary) -> Fish:
	var best: Fish = null
	for f in fish_list:
		if not likes(f, regular):
			continue
		if best == null or f.stars > best.stars or (f.stars == best.stars and f.id < best.id):
			best = f
	return best


## Picks who visits: not someone who already came today, and people you've
## met are likelier (weight 2 against 1). Returns "" when nobody fits.
static func pick(regulars: Array, state: Dictionary, visited_today: Array, rng: RandomNumberGenerator) -> String:
	var ids := []
	var weights := []
	var total := 0.0
	for r in regulars:
		if r["id"] in visited_today:
			continue
		ids.append(r["id"])
		var w := 2.0 if bool(state.get(r["id"], {}).get("met", false)) else 1.0
		weights.append(w)
		total += w
	if ids.is_empty():
		return ""
	var roll := rng.randf() * total
	for i in ids.size():
		roll -= weights[i]
		if roll < 0.0:
			return ids[i]
	return ids[-1]


## "Loves Red guppies, 2★+"
static func favorite_text(regular: Dictionary, species_db: Dictionary) -> String:
	var species: Dictionary = species_db.get(regular.get("species", "guppy"), {})
	var plural: String = str(species.get("plural_name", "fish")).to_lower()
	var value: String = str(regular["favorite"]["value"]).replace("_", " ").capitalize()
	return "Loves %s %s, %d★+" % [value, plural, int(regular.get("min_stars", 1))]


## "♥♥♥♡♡" for a loyalty level.
static func hearts(lvl: int, rules: Dictionary) -> String:
	var top := max_level(rules)
	return "♥".repeat(clampi(lvl, 0, top)) + "♡".repeat(top - clampi(lvl, 0, top))
