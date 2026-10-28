class_name Aesthetics
extends RefCounted
## "How good does this tank look?" as a 0–100 score from its contents.
## Weights come from economy["aesthetics"] so they can be tuned in data.

const HEIGHT_RANK := {"short": 0, "medium": 1, "tall": 2}
const ROW_IDEAL := {"back": 2, "mid": 1, "front": 0}


static func score(tank: Tank, items: Dictionary, weights: Dictionary) -> int:
	var total := 0.0
	var parts := breakdown(tank, items, weights)
	for key in parts:
		total += parts[key]
	return clampi(roundi(total), 0, 100)


## Points per component, so the UI can explain the score.
static func breakdown(tank: Tank, items: Dictionary, weights: Dictionary) -> Dictionary:
	var result := {
		"substrate": 0.0, "coverage": 0.0, "hardscape_and_plants": 0.0,
		"variety": 0.0, "layering": 0.0, "theme": 0.0,
	}
	var filled := tank.filled_slot_count()
	var coverage := float(filled) / tank.slot_count()

	if tank.substrate != "":
		result["substrate"] = float(weights["substrate"])
	result["coverage"] = coverage * float(weights["coverage"])

	var has_hardscape := false
	var has_plant := false
	var layer_fit := 0.0
	for i in tank.slot_count():
		var id: String = tank.slots[i]
		if id == "":
			continue
		var item: Dictionary = items[id]
		if item["category"] in ["rock", "driftwood"]:
			has_hardscape = true
		elif item["category"] == "plant":
			has_plant = true
		# Tall things belong at the back, short things at the front.
		var diff := absi(HEIGHT_RANK[item["height"]] - ROW_IDEAL[tank.row_of(i)])
		layer_fit += 1.0 - 0.5 * diff
	if has_hardscape and has_plant:
		result["hardscape_and_plants"] = float(weights["hardscape_and_plants"])

	var distinct := {}
	for id in tank.placed_item_ids():
		distinct[id] = true
	var cap := float(weights["variety_cap"])
	result["variety"] = minf(distinct.size(), cap) / cap * float(weights["variety"])

	# Layering and theme are scaled by coverage so one well-placed pebble isn't a masterpiece.
	if filled > 0:
		result["layering"] = layer_fit / filled * float(weights["layering"]) * coverage
	var theme := main_theme(tank, items)
	if theme != "":
		result["theme"] = tag_share(tank, items, theme) * float(weights["theme"]) * coverage
	return result


## The tag carried by the most placed items (ties broken alphabetically). "" if none.
static func main_theme(tank: Tank, items: Dictionary) -> String:
	var counts := {}
	for id in tank.placed_item_ids():
		for tag in items[id]["tags"]:
			counts[tag] = counts.get(tag, 0) + 1
	var best := ""
	var tags := counts.keys()
	tags.sort()
	for tag in tags:
		if best == "" or counts[tag] > counts[best]:
			best = tag
	return best


## Fraction (0–1) of placed items, substrate included, that carry `tag`.
static func tag_share(tank: Tank, items: Dictionary, tag: String) -> float:
	var placed := tank.placed_item_ids()
	if placed.is_empty():
		return 0.0
	var with_tag := 0
	for id in placed:
		if tag in items[id]["tags"]:
			with_tag += 1
	return float(with_tag) / placed.size()


## Up to `limit` friendly suggestions for raising the looks score, biggest win first.
static func tips(tank: Tank, items: Dictionary, weights: Dictionary, limit: int = 3) -> Array[String]:
	var parts := breakdown(tank, items, weights)
	var result: Array[String] = []
	if tank.substrate == "":
		result.append("Add substrate (+%d)." % int(weights["substrate"]))
	var filled := tank.filled_slot_count()
	if filled < tank.slot_count():
		result.append("Fill more spots: %d of %d used." % [filled, tank.slot_count()])
	if parts["hardscape_and_plants"] == 0.0:
		result.append("Mix hardscape (rocks or driftwood) with plants (+%d)." % int(weights["hardscape_and_plants"]))
	var misplaced := 0
	for i in tank.slot_count():
		var id: String = tank.slots[i]
		if id != "" and HEIGHT_RANK[items[id]["height"]] != ROW_IDEAL[tank.row_of(i)]:
			misplaced += 1
	if misplaced > 0:
		result.append("Tall items look best at the back, short ones at the front (%d out of place)." % misplaced)
	var distinct := {}
	for id in tank.placed_item_ids():
		distinct[id] = true
	if not tank.placed_item_ids().is_empty() and distinct.size() < int(weights["variety_cap"]):
		result.append("Try more different items for variety (%d of %d)." % [distinct.size(), int(weights["variety_cap"])])
	var theme := main_theme(tank, items)
	if theme != "" and tag_share(tank, items, theme) < 1.0:
		result.append("Your tank leans \"%s\"; more %s items will tie it together." % [theme, theme])
	return result.slice(0, limit)
