extends Control
## Debug scene: every guppy variety (as drawn in the tanks), the fry stages, and
## a fish frozen at stages of turning around. Run this scene directly (F6).

const FishSprite := preload("res://scenes/fish_sprite.gd")
const SPECIES_ID := "guppy"
const COLUMNS := 6


func _ready() -> void:
	var species: Dictionary = Game.db.species[SPECIES_ID]
	var trait_name: String = species["sprites"]["trait"] if species.has("sprites") else species["traits"].keys()[0]
	var t: Dictionary = species["traits"][trait_name]
	var values: Array = t["common"] + t.get("rare", [])
	var next_id := 1

	# Every variety, males on even cells and females on odd ones.
	var cell := Vector2(205, 82)
	for i in values.size():
		var at := Vector2(80 + (i % COLUMNS) * cell.x, 50 + (i / COLUMNS) * cell.y)
		var f := _fish(next_id, Fish.MALE if i % 2 == 0 else Fish.FEMALE, {trait_name: values[i]}, species)
		next_id += 1
		_add(f, species, at)
		var rarity := "common" if values[i] in t["common"] else ("mutation" if values[i] in t.get("mutations", []) else "recipe")
		_label("%s  (%s)" % [values[i].replace("_", " ").capitalize(), rarity], at + Vector2(-60, 30))

	# Fry growing up, day 0 to adult.
	var fry_y := 50 + ceili(values.size() / float(COLUMNS)) * cell.y + 10
	_label("fry: day 0, 1, 2, adult", Vector2(10, fry_y - 34))
	for day in int(species["days_to_adult"]) + 1:
		var f := _fish(next_id, Fish.FEMALE, {trait_name: values[0]}, species)
		next_id += 1
		f.age_days = day
		_add(f, species, Vector2(60 + day * 110, fry_y))

	# Turning around: yaw 0 -> 180 degrees.
	_label("turning around", Vector2(560, fry_y - 34))
	for i in 6:
		var f := _fish(next_id, Fish.MALE, {trait_name: "koi" if "koi" in values else values[0]}, species)
		next_id += 1
		var sprite := _add(f, species, Vector2(600 + i * 110, fry_y))
		sprite._phi = PI * i / 5.0


func _fish(id: int, sex: String, traits: Dictionary, species: Dictionary) -> Fish:
	var f := Fish.new()
	f.id = id
	f.species_id = species["id"]
	f.sex = sex
	f.stars = 3
	f.age_days = int(species["days_to_adult"])
	f.traits = traits
	return f


func _add(f: Fish, species: Dictionary, at: Vector2) -> Node2D:
	var sprite := FishSprite.new()
	sprite.swims = false
	add_child(sprite)
	sprite.position = at
	sprite.setup(f, species, Rect2(at, Vector2.ONE))
	return sprite


func _label(text: String, at: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", 12)
	add_child(l)
