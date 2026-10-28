class_name RequestGenerator
extends RefCounted
## Builds a concrete customer request from a template. Fish constraints only
## use values the player can realistically get (common values, or values
## already in their stock), so requests stay achievable.


static func generate(template: Dictionary, species: Dictionary, owned_fish: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	var themes: Array = template["theme_tags"]
	var count_range: Array = template["fish_count"]
	var fish_count := rng.randi_range(int(count_range[0]), int(count_range[1]))

	var pool: Array = template["constraints"].duplicate()
	_shuffle(pool, rng)
	var cc: Array = template["constraint_count"]
	var n := mini(rng.randi_range(int(cc[0]), int(cc[1])), pool.size())

	var constraints := []
	for i in n:
		var trait_name: String = pool[i]
		var values := candidate_values(trait_name, species, owned_fish)
		var min_count := fish_count
		if trait_name == "sex":
			min_count = rng.randi_range(1, fish_count)
		constraints.append({
			"trait": trait_name,
			"value": values[rng.randi_range(0, values.size() - 1)],
			"min_count": min_count,
		})

	return {
		"template_id": template["id"],
		"species_id": species["id"],
		"theme": themes[rng.randi_range(0, themes.size() - 1)],
		"fish_count": fish_count,
		"constraints": constraints,
		"base_reward": int(template["base_reward"]),
	}


static func candidate_values(trait_name: String, species: Dictionary, owned_fish: Array) -> Array:
	if trait_name == "sex":
		return [Fish.MALE, Fish.FEMALE]
	var values: Array = species["traits"][trait_name]["common"].duplicate()
	for f in owned_fish:
		if f.species_id != species["id"]:
			continue
		var v: String = f.get_trait(trait_name)
		if v != "" and not v in values:
			values.append(v)
	return values


## Player-facing text, e.g. "A planted tank with 2 guppies: all orange, at least 1 female."
static func describe(request: Dictionary, species: Dictionary) -> String:
	var count: int = request["fish_count"]
	var noun: String = species["name"].to_lower()
	if count != 1:
		noun = species.get("plural_name", species["name"] + "s").to_lower()
	var text := "A %s tank with %d %s" % [request["theme"], count, noun]
	var parts := []
	for c in request["constraints"]:
		var value: String = c["value"].replace("_", " ")
		if c["min_count"] >= count:
			parts.append(("all " if count > 1 else "") + value)
		else:
			parts.append("at least %d %s" % [c["min_count"], value])
	if not parts.is_empty():
		text += ": " + ", ".join(parts)
	return text + "."


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
