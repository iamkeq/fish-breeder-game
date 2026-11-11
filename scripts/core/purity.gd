class_name Purity
extends RefCounted
## Line purity (0-100): how true-breeding a fish's variety is. Hidden until the
## fish is scanned in the Lab. Numbers come from economy["purity"] and ["lab"].


## True when two fish share every trait (the game's notion of "same variety").
static func same_variety(a: Fish, b: Fish) -> bool:
	return a.traits == b.traits


## A fry's purity from its parents and its own looks. Both parents match it:
## the line gains purity. One matches: an outcross, the line loses some. Neither
## (a recipe or a mutation): a brand new line.
static func offspring_purity(mother: Fish, father: Fish, fry: Fish, rules: Dictionary) -> int:
	var from_mother := same_variety(fry, mother)
	var from_father := same_variety(fry, father)
	var average := (mother.purity + father.purity) / 2.0
	if from_mother and from_father:
		return mini(100, roundi(average) + int(rules["true_gain"]))
	if from_mother or from_father:
		return maxi(int(rules["floor"]), roundi(average) - int(rules["outcross_loss"]))
	return int(rules["new_line"])


## The tier name for a purity score ("Mixed", "Pure Line", ...).
static func tier_name(purity: int, rules: Dictionary) -> String:
	var result := ""
	var best := -1
	for tier in rules["tiers"]:
		if purity >= int(tier["min"]) and int(tier["min"]) > best:
			best = int(tier["min"])
			result = tier["name"]
	return result


## How much star-roll probability a purity score moves from the low end to the
## high end (0 for none). Takes the best tier reached.
static func star_shift(purity: int, rules: Dictionary) -> float:
	var shift := 0.0
	var best := -1
	for tier in rules.get("star_nudge", []):
		if purity >= int(tier["min"]) and int(tier["min"]) > best:
			best = int(tier["min"])
			shift = float(tier["shift"])
	return shift


## Moves `shift` of probability to the "+1 star" slot, taking from "-1" first
## and then from "same". `weights` is [p-1, p0, p+1]; returns a new array.
static func shift_weights(weights: Array, shift: float) -> Array:
	var down := float(weights[0])
	var same := float(weights[1])
	var up := float(weights[2])
	var from_down := minf(down, shift)
	var from_same := minf(same, shift - from_down)
	return [down - from_down, same - from_same, up + from_down + from_same]


## Price bonus (0.1 = +10%) for a scanned, shop-bred fish of this purity.
static func certified_bonus(purity: int, lab: Dictionary) -> float:
	var bonus := 0.0
	var best := -1
	for tier in lab.get("certified_bonus", []):
		if purity >= int(tier["min"]) and int(tier["min"]) > best:
			best = int(tier["min"])
			bonus = float(tier["bonus"])
	return bonus
