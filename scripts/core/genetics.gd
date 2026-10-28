class_name Genetics
extends RefCounted
## Simple, readable inheritance: each trait is copied from the mother or the
## father (50/50). Two twists, both from data:
##   - mutations: a small chance of a value from the trait's "mutations" list
##     (or its "rare" list if there is none), whatever the parents are;
##   - recipes: some parent pairs can produce a new value, e.g. red x yellow
##     -> orange, at the species' "recipe_chance".
## All randomness comes from the passed-in RNG so results are reproducible.


static func is_rare(species: Dictionary, trait_name: String, value: String) -> bool:
	var t: Dictionary = species["traits"].get(trait_name, {})
	return value in t.get("rare", [])


static func mutation_pool(species: Dictionary, trait_name: String) -> Array:
	var t: Dictionary = species["traits"].get(trait_name, {})
	return t.get("mutations", t.get("rare", []))


static func is_mutation(species: Dictionary, trait_name: String, value: String) -> bool:
	return value in mutation_pool(species, trait_name)


## The value a recipe makes from these two parent values (either order), or "".
static func recipe_child(species: Dictionary, trait_name: String, a: String, b: String) -> String:
	for recipe in species.get("recipes", {}).get(trait_name, []):
		var p: Array = recipe["parents"]
		if (p[0] == a and p[1] == b) or (p[0] == b and p[1] == a):
			return recipe["child"]
	return ""


static func inherit_trait(species: Dictionary, trait_name: String, mother_value: String,
		father_value: String, rng: RandomNumberGenerator) -> String:
	var pool := mutation_pool(species, trait_name)
	if not pool.is_empty() and rng.randf() < float(species["mutation_chance"]):
		return pool[rng.randi_range(0, pool.size() - 1)]
	var child := recipe_child(species, trait_name, mother_value, father_value)
	if child != "" and rng.randf() < float(species.get("recipe_chance", 0.0)):
		return child
	return mother_value if rng.randf() < 0.5 else father_value


static func make_offspring(mother: Fish, father: Fish, species: Dictionary,
		rng: RandomNumberGenerator) -> Fish:
	var fry := Fish.new()
	fry.species_id = species["id"]
	fry.sex = Fish.MALE if rng.randf() < 0.5 else Fish.FEMALE
	for trait_name in species["traits"]:
		fry.traits[trait_name] = inherit_trait(species, trait_name,
			mother.get_trait(trait_name), father.get_trait(trait_name), rng)
	fry.parent_stars = (mother.stars + father.stars) / 2.0
	fry.age_days = 0
	return fry


static func brood_size(species: Dictionary, rng: RandomNumberGenerator) -> int:
	var range_: Array = species["brood_size"]
	return rng.randi_range(int(range_[0]), int(range_[1]))


static func breed(mother: Fish, father: Fish, species: Dictionary,
		rng: RandomNumberGenerator) -> Array[Fish]:
	var brood: Array[Fish] = []
	for i in brood_size(species, rng):
		brood.append(make_offspring(mother, father, species, rng))
	return brood


## A random adult fish, e.g. for the breeding-stock market.
static func random_fish(species: Dictionary, stars: int, rare_chance: float,
		rng: RandomNumberGenerator) -> Fish:
	var f := Fish.new()
	f.species_id = species["id"]
	f.sex = Fish.MALE if rng.randf() < 0.5 else Fish.FEMALE
	for trait_name in species["traits"]:
		var t: Dictionary = species["traits"][trait_name]
		var rare: Array = t.get("rare", [])
		var pool: Array = rare if (not rare.is_empty() and rng.randf() < rare_chance) else t["common"]
		f.traits[trait_name] = pool[rng.randi_range(0, pool.size() - 1)]
	f.stars = stars
	f.age_days = int(species["days_to_adult"])
	return f
