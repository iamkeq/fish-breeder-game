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
	_compact(b)
	return b


## Gives any button (Button, MenuButton) the theme's button look, compact size.
static func _compact(b: BaseButton) -> void:
	b.add_theme_font_size_override("font_size", 13)
	for state in BUTTON_STATES:
		var sb = b.get_theme_stylebox(state, "Button")
		if sb is StyleBoxFlat:
			sb = sb.duplicate()
			sb.content_margin_left = 9
			sb.content_margin_right = 9
			sb.content_margin_top = 3
			sb.content_margin_bottom = 3
			b.add_theme_stylebox_override(state, sb)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(color_name, Color.WHITE)


static func location_name(location: String, state: GameState = null) -> String:
	if location == Fish.DISPLAY:
		return "Display tank 1" if state != null and state.has_second_display() else "Display tank"
	if location == Fish.DISPLAY2:
		return "Display tank 2"
	if location == Fish.HOLDING:
		return "Holding"
	if Fish.is_order(location):
		var i := state.order_index_by_id(Fish.order_id(location)) if state != null else -1
		return "Order tank for %s" % state.orders[i].get("customer", "a customer") if i >= 0 else "Order tank"
	return "Breeding tank %d" % (Fish.breeding_index(location) + 1)


## A "Move ▾" menu listing everywhere this fish could go: the display tank,
## each breeding tank you own, and holding. Places it can't go are greyed out
## with the reason as a tooltip. Calls `on_move` with the chosen location.
static func move_menu(state: GameState, f: Fish, on_move: Callable, text: String = "Move ▾") -> MenuButton:
	var menu := MenuButton.new()
	menu.text = text
	menu.flat = false
	menu.focus_mode = Control.FOCUS_NONE
	_compact(menu)
	var popup := menu.get_popup()
	var places := [Fish.DISPLAY]
	if state.has_second_display():
		places.append(Fish.DISPLAY2)
	for i in state.breeding_tanks.size():
		places.append(Fish.breeding_location(i))
	for order in state.orders:
		if order.get("tank") != null:
			places.append(Fish.order_location(order["id"]))
	places.append(Fish.HOLDING)
	for place in places:
		if place == f.location:
			continue
		var index := popup.item_count
		popup.add_item(location_name(place, state), index)
		popup.set_item_metadata(index, place)
		var blocker := state.move_blocker(f.id, place)
		popup.set_item_disabled(index, blocker != "")
		popup.set_item_tooltip(index, blocker)
	popup.id_pressed.connect(func(id: int): on_move.call(popup.get_item_metadata(popup.get_item_index(id))))
	return menu


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


## "Bubbles (Gold Guppy) ♥": the fish's name for lists, with a heart if it's a favourite.
## Fry with no name are just "Fry".
static func fish_heading(state: GameState, f: Fish) -> String:
	var text := state.fish_title(f) if state.is_adult(f) else \
		("%s (fry)" % f.nickname if f.nickname != "" else "Fry")
	return text + (" ♥" if f.favorite else "")


## The Name button: opens the naming box for this fish.
static func name_button(f: Fish) -> Button:
	var b := small_button("Rename" if f.nickname != "" else "Name", "Give this fish a name.")
	b.pressed.connect(func(): Game.name_requested.emit(f.id))
	return b


## The ♥ Favourite toggle: favourites are kept, never sold or handed to customers.
static func favorite_button(state: GameState, f: Fish) -> Button:
	var b := small_button("♥ Favourite" if not f.favorite else "♥ Kept",
		"Keep this fish: it's never sold or handed to a customer, but still breeds and can be on display."
		if not f.favorite else "A keeper. Press to let it be sold again.")
	b.toggle_mode = true
	b.set_pressed_no_signal(f.favorite)
	if not f.favorite:
		var blocker := state.favorite_blocker(f.id)
		b.disabled = blocker != ""
		if blocker != "":
			b.tooltip_text = blocker
	b.pressed.connect(func(): Game.set_favorite(f.id, not f.favorite))
	return b


## "Purity: ?" (greyed) until scanned, then "Purity 74% · Pure Line". Fry: nothing, so use for adults.
static func purity_label(state: GameState, f: Fish) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	if f.scanned:
		label.text = "Purity %d%% · %s" % [f.purity, state.purity_tier(f.purity)]
		label.modulate = Color(0.75, 0.95, 0.7, 0.95)
	else:
		label.text = "Purity: ?"
		label.modulate = Color(1, 1, 1, 0.45)
	return label


const RIBBON_COLORS := [Color.WHITE, Color(0.27, 0.45, 0.85), Color(0.82, 0.3, 0.3), Color(0.93, 0.78, 0.28)]
const RIBBON_TEXT := [Color.WHITE, Color.WHITE, Color.WHITE, Color(0.25, 0.18, 0.05)]


## Small coloured chips for a fish's ribbons: 1st blue, 2nd red, 3rd yellow,
## with a count when there are several ("1st ×2"). Adds nothing if it has none.
static func add_ribbons(parent: Control, f: Fish) -> void:
	add_ribbon_chips(parent, f.ribbons)


## Same chips, from a plain list of ribbons [{place, show, day}] (gallery entries).
static func add_ribbon_chips(parent: Control, ribbons: Array) -> void:
	if ribbons.is_empty():
		return
	var counts := [0, 0, 0, 0]
	for r in ribbons:
		counts[clampi(int(r["place"]), 1, 3)] += 1
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for place in [1, 2, 3]:
		if counts[place] == 0:
			continue
		var chip := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = RIBBON_COLORS[place]
		style.set_corner_radius_all(8)
		style.content_margin_left = 7
		style.content_margin_right = 7
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		chip.add_theme_stylebox_override("panel", style)
		var label := Label.new()
		label.text = Shows.PLACE_WORDS[place] + (" ×%d" % counts[place] if counts[place] > 1 else "")
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", RIBBON_TEXT[place])
		chip.add_child(label)
		var names := PackedStringArray()
		for r in ribbons:
			if int(r["place"]) == place:
				names.append("%s, day %d" % [r["show"], int(r["day"])])
		chip.tooltip_text = "\n".join(names)
		row.add_child(chip)
	parent.add_child(row)


const FRAME_COLORS := [Color(0.5, 0.34, 0.2), Color(0.27, 0.45, 0.85), Color(0.82, 0.3, 0.3), Color(0.93, 0.78, 0.28)]
const FRAME_EDGE := Color(0.2, 0.12, 0.07)
const WATER_TOP := Color(0.36, 0.62, 0.7)
const WATER_BOTTOM := Color(0.14, 0.3, 0.42)


## The best (lowest) place among ribbons: 1-3, or 0 when there are none.
static func best_place(ribbons: Array) -> int:
	var best := 0
	for r in ribbons:
		var place := int(r["place"])
		if place >= 1 and place <= 3 and (best == 0 or place < best):
			best = place
	return best


## A framed portrait of a gallery entry: a wooden frame (blue, red or yellow for
## the best ribbon, plain wood for none), an underwater backdrop and the fish.
static func portrait(state: GameState, entry: Dictionary, art: Vector2, fish_scale: float,
		border: int = 7) -> Control:
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = FRAME_COLORS[best_place(entry["ribbons"])]
	style.border_color = FRAME_EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(border)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 3
	style.shadow_offset = Vector2(1, 2)
	frame.add_theme_stylebox_override("panel", style)
	var water := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, WATER_TOP)
	gradient.set_color(1, WATER_BOTTOM)
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0.5, 0)
	tex.fill_to = Vector2(0.5, 1)
	water.texture = tex
	water.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	water.custom_minimum_size = art
	water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	water.clip_contents = true
	frame.add_child(water)
	if state.db.species.has(entry["species_id"]):
		var fish := state.entry_fish(entry)
		var sprite := FishSprite.new()
		sprite.swims = false
		sprite.scale = Vector2.ONE * fish_scale
		sprite.position = art * Vector2(0.55, 0.5)
		water.add_child(sprite)
		sprite.setup(fish, state.db.species[entry["species_id"]], Rect2(sprite.position, Vector2.ONE))
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	return frame


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


static var _sheets := {}


## A sprite sheet texture, loaded once and shared.
static func sheet_texture(path: String) -> Texture2D:
	if not _sheets.has(path):
		_sheets[path] = load(path)
	return _sheets[path]


## The item's sprite cut from its sheet, or null if it has no art.
static func item_texture(item: Dictionary) -> Texture2D:
	if not item.has("sprite"):
		return null
	var r: Array = item["sprite"]
	var tex := AtlasTexture.new()
	tex.atlas = sheet_texture(item["sheet"])
	tex.region = Rect2(r[0], r[1], r[2], r[3])
	return tex


## A small picture of an item for lists: its sprite, or a colour swatch.
static func item_icon(item: Dictionary, box: Vector2 = Vector2(36, 30)) -> Control:
	var tex := item_texture(item)
	if tex == null:
		var swatch := ColorRect.new()
		swatch.color = Color(item.get("color", "#999999"))
		swatch.custom_minimum_size = Vector2(box.y, box.y) * 0.7
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var holder := CenterContainer.new()
		holder.custom_minimum_size = box
		holder.add_child(swatch)
		return holder
	var icon := TextureRect.new()
	icon.texture = tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = box
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon
