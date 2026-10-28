class_name Fish
extends RefCounted
## A single fish. Plain data plus small helpers; no scene dependencies.

const HOLDING := "holding"
## The first breeding tank. Further ones are "breeding2", "breeding3", ...
## (see breeding_location()).
const BREEDING := "breeding"
const DISPLAY := "display"


## Location name of breeding tank `index` (0-based): "breeding", "breeding2", ...
static func breeding_location(index: int) -> String:
	return BREEDING if index == 0 else "%s%d" % [BREEDING, index + 1]


## Which breeding tank a location is (0-based), or -1 if it isn't one.
static func breeding_index(location: String) -> int:
	if location == BREEDING:
		return 0
	var suffix := location.trim_prefix(BREEDING)
	if suffix != location and suffix.is_valid_int() and int(suffix) >= 2:
		return int(suffix) - 1
	return -1


static func is_breeding(location: String) -> bool:
	return breeding_index(location) >= 0

const MALE := "male"
const FEMALE := "female"

var id: int = 0
var species_id: String = ""
## Named strain this fish was bought as ("" for home-bred fish).
var strain_id: String = ""
## What you paid for this fish (0 for fish you bred, or were given).
var paid: int = 0
var sex: String = FEMALE
var traits: Dictionary = {}
## 1–5 once adult. 0 while still a fry: quality is revealed when it grows up.
var stars: int = 0
## Average star rating of the parents, used to roll stars at adulthood.
var parent_stars: float = 0.0
var age_days: int = 0
## Becomes false after a night without food. Fry fed every night roll better stars.
var fed_every_night: bool = true
var location: String = HOLDING


func is_adult(species: Dictionary) -> bool:
	return age_days >= int(species["days_to_adult"])


## Trait value by name. "sex" is treated as a trait so requests can ask for it.
func get_trait(trait_name: String) -> String:
	if trait_name == "sex":
		return sex
	return traits.get(trait_name, "")


func rare_trait_count(species: Dictionary) -> int:
	var count := 0
	for trait_name in traits:
		if Genetics.is_rare(species, trait_name, traits[trait_name]):
			count += 1
	return count


func to_dict() -> Dictionary:
	return {
		"id": id,
		"species_id": species_id,
		"strain_id": strain_id,
		"paid": paid,
		"sex": sex,
		"traits": traits.duplicate(),
		"stars": stars,
		"parent_stars": parent_stars,
		"age_days": age_days,
		"fed_every_night": fed_every_night,
		"location": location,
	}


static func from_dict(d: Dictionary) -> Fish:
	var f := Fish.new()
	f.id = int(d.get("id", 0))
	f.species_id = d.get("species_id", "")
	f.strain_id = d.get("strain_id", "")
	f.paid = int(d.get("paid", 0))
	f.sex = d.get("sex", FEMALE)
	f.traits = d.get("traits", {}).duplicate()
	f.stars = int(d.get("stars", 0))
	f.parent_stars = float(d.get("parent_stars", 0.0))
	f.age_days = int(d.get("age_days", 0))
	f.fed_every_night = bool(d.get("fed_every_night", true))
	f.location = d.get("location", HOLDING)
	return f
