class_name Shows
extends RefCounted
## Fish show rules that need no game state: the schedule, scoring, rivals and
## the "how likely" hint. Numbers come from data/shows.json (a Dictionary).

const PLACE_WORDS := ["", "1st", "2nd", "3rd"]


## The show number held at the end of `day`'s next show day (today counts if it
## is a show day). Show n is held at the end of day n * every_days.
static func number_for_day(day: int, data: Dictionary) -> int:
	var every := maxi(1, int(data["every_days"]))
	return maxi(1, ceili(float(day) / every))


static func day_of(number: int, data: Dictionary) -> int:
	return number * int(data["every_days"])


static func is_show_day(day: int, data: Dictionary) -> bool:
	return day > 0 and day % int(data["every_days"]) == 0


static func is_grand(number: int, data: Dictionary) -> bool:
	return number % maxi(1, int(data["grand_every"])) == 0


## {number, id, name, description, grand, rule} for show `number`. The class
## list rotates; every grand_every-th show is the Grand Show.
static func describe(number: int, data: Dictionary) -> Dictionary:
	var list: Array = data["shows"]
	var base: Dictionary = list[(number - 1) % list.size()]
	var grand := is_grand(number, data)
	return {
		"number": number, "id": base["id"],
		"name": ("Grand " + base["name"]) if grand else base["name"],
		"description": base["description"], "grand": grand, "rule": base["rule"],
	}


## Cash for a place (0 for 4th and below). Grand shows pay more.
static func prize(place: int, grand: bool, data: Dictionary) -> int:
	if place < 1 or place > 3:
		return 0
	var amount := int(data["prizes"][str(place)])
	return amount * int(data["prizes"]["grand_multiplier"]) if grand else amount


## Why a fish with these looks fails a class rule ("" if it passes).
static func rule_blocker(rule: Dictionary, stars: int, rare: bool, mutation: bool,
		scanned: bool, purity: int) -> String:
	if rule.has("min_stars") and stars < int(rule["min_stars"]):
		return "Needs %d stars or more." % int(rule["min_stars"])
	if rule.get("rare", false) and not rare:
		return "Needs a rare trait."
	if rule.get("mutation", false) and not mutation:
		return "Mutation fish only."
	if rule.has("min_purity_scanned"):
		var need := int(rule["min_purity_scanned"])
		if not scanned:
			return "Needs a Lab scan showing %d%% purity or more." % need
		if purity < need:
			return "Needs %d%% purity or more (this one scanned at %d%%)." % [need, purity]
	return ""


## A fish's judging score before the judge's swing. `value_step` is the
## variety's price multiplier rounded (1 for plain looks, 4 for a Dragon).
static func base_score(stars: int, value_step: int, purity: int, data: Dictionary) -> float:
	var s: Dictionary = data["score"]
	return stars * float(s["per_star"]) + value_step * float(s["per_value_step"]) \
		+ purity * float(s["purity_weight"])


## The usual strength of the rivals at this show.
static func rival_strength(number: int, grand: bool, data: Dictionary) -> float:
	var r: Dictionary = data["rival_strength"]
	var strength := minf(float(r["max"]), float(r["base"]) + float(r["per_show"]) * (number - 1))
	return strength + (float(r["grand_bonus"]) if grand else 0.0)


## Judges one entry against the rivals. Returns {your_score, place, rivals}
## where rivals is [{name, score}] best first. Ties go to the player.
static func judge(base: float, number: int, grand: bool, data: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var swing := float(data["score"]["judge_swing"])
	var mine := base + rng.randf_range(-swing, swing)
	var strength := rival_strength(number, grand, data)
	var spread := float(data["rival_strength"]["spread"])
	var names: Array = data["rival_names"].duplicate()
	var rivals := []
	for i in int(data["rivals"]):
		var name := "Rival %d" % (i + 1)
		if not names.is_empty():
			name = names.pop_at(rng.randi_range(0, names.size() - 1))
		rivals.append({"name": name, "score": rng.randf_range(strength - spread, strength + spread)})
	rivals.sort_custom(func(a, b): return a["score"] > b["score"])
	var place := 1
	for r in rivals:
		if r["score"] > mine:
			place += 1
	return {"your_score": mine, "place": place, "rivals": rivals}


## "Looks promising" / "Good chance" / "Long shot" from what the player can see
## (stars and variety value), assuming a typical purity so it never leaks the
## hidden one. Cut-offs are in data (hints).
static func hint(number: int, grand: bool, stars: int, value_step: int, data: Dictionary) -> String:
	var h: Dictionary = data["hints"]
	var estimate := base_score(stars, value_step, int(h["typical_purity"]), data)
	var margin := estimate - rival_strength(number, grand, data)
	if margin >= float(h["promising"]):
		return "Looks promising"
	if margin >= float(h["good"]):
		return "Good chance"
	return "Long shot"
