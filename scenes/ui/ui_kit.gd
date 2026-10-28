extends RefCounted
## Small UI helpers shared by screens: compact buttons, fish previews, text.

const FishSprite := preload("res://scenes/fish_sprite.gd")
const BUTTON_STATES := ["normal", "hover", "pressed", "hover_pressed", "disabled"]


## A compact version of the theme's button.
static func small_button(text: String, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	for state in BUTTON_STATES:
		var sb = b.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			sb = sb.duplicate()
			sb.content_margin_left = 9
			sb.content_margin_right = 9
			sb.content_margin_top = 3
			sb.content_margin_bottom = 3
			b.add_theme_stylebox_override(state, sb)
	return b


## A small box with a gently animated fish in it (it doesn't swim around).
static func fish_preview(fish: Fish, species: Dictionary, box: Vector2 = Vector2(90, 46),
		fish_scale: float = 0.62) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = box
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sprite := FishSprite.new()
	sprite.swims = false
	sprite.scale = Vector2.ONE * fish_scale
	sprite.position = Vector2(box.x * 0.6, box.y * 0.5)  # leave room for the tail
	holder.add_child(sprite)
	sprite.setup(fish, species, Rect2(sprite.position, Vector2.ONE))
	return holder


static func sex_symbol(f: Fish) -> String:
	return "♂" if f.sex == Fish.MALE else "♀"


static func stars_text(stars: int) -> String:
	return "★".repeat(stars) + "☆".repeat(Quality.MAX_STARS - stars)


static func pretty(value: String) -> String:
	return value.replace("_", " ").capitalize()


## "Koi" for guppies, or e.g. "Orange · Fan tail · Spotted" for multi-trait species.
static func traits_text(f: Fish) -> String:
	var parts := PackedStringArray()
	for trait_name in f.traits:
		var v := pretty(f.traits[trait_name])
		parts.append(v + " tail" if trait_name == "tail_shape" else v)
	return " · ".join(parts)
