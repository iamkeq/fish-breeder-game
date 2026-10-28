extends Control
## Back room: the breeding tank, plus every fish you own (breeding tank,
## display tank, holding) with buttons to move them or sell them to the wholesaler.

const UI := preload("res://scenes/ui/ui_kit.gd")

const SECTIONS := [
	[Fish.BREEDING, "Breeding tank"],
	[Fish.DISPLAY, "Display tank (shop floor)"],
	[Fish.HOLDING, "Holding tanks"],
]
const MOVE_LABELS := {Fish.DISPLAY: "To display", Fish.BREEDING: "To breeding", Fish.HOLDING: "To holding"}

@onready var _brood_info: Label = %BroodInfo
@onready var _fish_rows: VBoxContainer = %FishRows
@onready var _status: Label = %Status


func _ready() -> void:
	Game.changed.connect(refresh)
	refresh()


func refresh() -> void:
	var state := Game.state
	_brood_info.text = _brood_text(state) + "   ·   Fish food: %d" % state.food_count()
	for child in _fish_rows.get_children():
		child.queue_free()
	for section in SECTIONS:
		_add_section(section[0], section[1])


func _add_section(location: String, title: String) -> void:
	var state := Game.state
	var fish := state.inventory.fish_list(location)
	var header := Label.new()
	header.add_theme_font_size_override("font_size", 17)
	var tank := state.tank_at(location)
	header.text = title + ("   %d/%d" % [fish.size(), tank.capacity] if tank != null else "   %d" % fish.size())
	_fish_rows.add_child(header)
	if fish.is_empty():
		var empty := Label.new()
		empty.text = "    (empty)"
		empty.modulate = Color(1, 1, 1, 0.55)
		_fish_rows.add_child(empty)
	for f in fish:
		_fish_rows.add_child(_fish_entry(f))
	_fish_rows.add_child(HSeparator.new())


func _fish_entry(f: Fish) -> Control:
	var state := Game.state
	var species := state.species_of(f)
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 8)
	entry.add_child(UI.fish_preview(f, species))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	var title := Label.new()
	if state.is_adult(f):
		title.text = "%s %s   %s" % [UI.sex_symbol(f), state.fish_display_name(f), UI.stars_text(f.stars)]
	else:
		title.text = "%s Fry, day %d of %d   ★ ?" % [UI.sex_symbol(f), f.age_days, int(species["days_to_adult"])]
	var traits := Label.new()
	traits.text = UI.traits_text(f)
	# Adults of one-trait species already say it in their name ("Koi Guppy").
	traits.visible = not state.is_adult(f) or species["traits"].size() > 1
	traits.add_theme_font_size_override("font_size", 13)
	traits.modulate = Color(1, 1, 1, 0.8)
	info.add_child(title)
	info.add_child(traits)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	for to in [Fish.DISPLAY, Fish.BREEDING, Fish.HOLDING]:
		if to == f.location:
			continue
		var blocker := state.move_blocker(f.id, to)
		var b := UI.small_button(MOVE_LABELS[to], blocker)
		b.disabled = blocker != ""
		b.pressed.connect(_on_move.bind(f.id, to))
		buttons.add_child(b)
	var price := state.wholesale_price(f)
	var sell := UI.small_button("Sell $%d" % price,
		"Sell to the wholesaler right away. Customers would pay more (%s)." %
		("$%d" % state.fish_price(f) if state.is_adult(f) else "they don't buy fry"))
	sell.pressed.connect(_on_sell_pressed.bind(sell, f.id, price))
	buttons.add_child(sell)
	info.add_child(buttons)
	entry.add_child(info)
	return entry


func _on_move(fish_id: int, to: String) -> void:
	var f: Fish = Game.state.inventory.get_fish(fish_id)
	var name := Game.state.fish_display_name(f) if Game.state.is_adult(f) else "fry"
	if Game.move_fish(fish_id, to):
		_status.text = "Moved the %s to %s." % [name, MOVE_LABELS[to].trim_prefix("To ")]


## Two clicks to sell, so a stray click never loses a fish.
func _on_sell_pressed(button: Button, fish_id: int, price: int) -> void:
	if not button.has_meta("armed"):
		button.set_meta("armed", true)
		button.text = "Sure? +$%d" % price
		return
	var f: Fish = Game.state.inventory.get_fish(fish_id)
	var name := Game.state.fish_display_name(f) if Game.state.is_adult(f) else "fry"
	var earned := Game.sell_fish_wholesale(fish_id)
	if earned > 0:
		_status.text = "Sold the %s to the wholesaler for $%d." % [name, earned]


func _brood_text(state: GameState) -> String:
	var nights := state.nights_until_brood()
	if nights < 0:
		return "Needs an adult male and female to breed."
	return "Next brood in %d night%s." % [nights, "" if nights == 1 else "s"]
