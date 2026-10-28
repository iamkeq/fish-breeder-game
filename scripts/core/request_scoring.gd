class_name RequestScoring
extends RefCounted
## Scores a delivered tank against a request.
## payout = tank value + bonus, where the bonus scales with how well the tank
## matches, the fish quality and the looks. The bonus never drops below a
## minimum, so taking a request is never worse than selling the tank normally.


static func score(request: Dictionary, tank: Tank, fish: Array, items: Dictionary,
		aesthetics_score: int, tank_value: int, economy: Dictionary) -> Dictionary:
	var theme_score := Aesthetics.tag_share(tank, items, request["theme"])

	var wanted: int = request["fish_count"]
	var diff := absi(fish.size() - wanted)
	var count_score := 1.0 if diff == 0 else (0.5 if diff == 1 else 0.0)

	var parts := [theme_score, count_score]
	var constraint_scores := []
	for c in request["constraints"]:
		var matching := 0
		for f in fish:
			if f.get_trait(c["trait"]) == c["value"]:
				matching += 1
		var s := minf(float(matching) / float(c["min_count"]), 1.0)
		constraint_scores.append(s)
		parts.append(s)

	var match_score := 0.0
	for p in parts:
		match_score += p
	match_score /= parts.size()

	var quality_score := 0.0
	if not fish.is_empty():
		var star_total := 0
		for f in fish:
			star_total += f.stars
		quality_score = float(star_total) / fish.size() / Quality.MAX_STARS

	var looks_score := aesthetics_score / 100.0

	var factor := (0.4 + 0.6 * match_score) * (0.75 + 0.25 * quality_score) \
		* (0.75 + 0.25 * looks_score)
	var reward: int = request["base_reward"]
	var min_bonus := roundi(reward * float(economy["requests"]["min_bonus_fraction"]))
	var bonus := maxi(roundi(reward * factor), min_bonus)

	return {
		"theme": theme_score,
		"count": count_score,
		"constraints": constraint_scores,
		"match": match_score,
		"quality": quality_score,
		"looks": looks_score,
		"tank_value": tank_value,
		"bonus": bonus,
		"payout": tank_value + bonus,
	}
