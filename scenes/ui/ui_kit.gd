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
		return "Display tank"
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
