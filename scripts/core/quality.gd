class_name Quality
extends RefCounted
## Star ratings (1–5). Offspring start from the parents' average and get a
## small random nudge; fry that were fed every night get a kinder nudge.

const MIN_STARS := 1
const MAX_STARS := 5


## `nudges` is economy["offspring_quality_nudge"]: {"normal": [p-1, p0, p+1], "fed": [...]}.
static func roll_offspring_stars(parent_avg: float, fed_every_night: bool, nudges: Dictionary,
		rng: RandomNumberGenerator) -> int:
	var weights: Array = nudges["fed"] if fed_every_night else nudges["normal"]
	var roll := rng.randf()
	var nudge := 1
	if roll < float(weights[0]):
		nudge = -1
	elif roll < float(weights[0]) + float(weights[1]):
		nudge = 0
	return clampi(roundi(parent_avg) + nudge, MIN_STARS, MAX_STARS)
