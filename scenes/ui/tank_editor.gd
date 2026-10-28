extends ColorRect
## Aquascaping editor for the display tank. Pick a spot (substrate or one of six
## slots, by button or by clicking the tank), then place an item from stock.
## Removing puts the item back in stock. Pauses the shop clock while open.

const UI := preload("res://scenes/ui/ui_kit.gd")
const TankViewScene := preload("res://scenes/tank_view.tscn")

const SLOT_NAMES := ["Back left", "Back right", "Mid left", "Mid right", "Front left", "Front right"]
const IDEAL_HEIGHT := {"back": "tall", "mid": "medium", "front": "short"}
const BREAKDOWN_NAMES := {
	"substrate": "Substrate", "coverage": "Coverage", "hardscape_and_plants": "Rock+plant mix",
	"variety": "Variety", "layering": "Layering", "theme": "Theme",
}

var location: String = Fish.DISPLAY
## -1 = substrate, 0..5 = placement slot.
var _selected: int = 0

var _tank_view: Control
var _looks: Label
var _value: Label
var _breakdown: Label
var _tips: Label
var _spot_buttons: Array[Button] = []
var _spot_group := ButtonGroup.new()
var _selected_label: Label
var _remove_button: Button
var _items: VBoxContainer
var _status: Label


func _ready() -> void:
	visible = false
	color = Color(0.15, 0.1, 0.08, 0.45)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	Game.changed.connect(func(): if visible: _refresh())


func open() -> void:
	if visible or Game.state.tank_at(location) == null:
		return
	visible = true
	_status.text = "Pick a spot, then place something from your stock."
	Game.push_pause()
	_select(_first_empty_spot())


func close() -> void:
	if not visible:
		return
	visible = false
	Game.pop_pause()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# --- Layout ------------------------------------------------------------------

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1200, 640)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	var title := Label.new()
	title.text = "Aquascaping · Display tank"
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_looks = _big_label()
	_value = _big_label()
	header.add_child(_looks)
	header.add_child(_value)
	var close_button := Button.new()
	close_button.text = "Done"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	box.add_child(header)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	box.add_child(body)

	# Left: live preview, score breakdown, tips.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	_tank_view = TankViewScene.instantiate()
	_tank_view.location = location
	_tank_view.show_slot_markers = true
	_tank_view.custom_minimum_size = Vector2(540, 340)
	_tank_view.slot_clicked.connect(_select)
	left.add_child(_tank_view)
	_breakdown = _small_label()
	left.add_child(_breakdown)
	_tips = _small_label()
	_tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tips.custom_minimum_size = Vector2(520, 0)
	_tips.modulate = Color(0.3, 0.45, 0.4)
	left.add_child(_tips)
	body.add_child(left)

	# Middle: the spots.
	var middle := VBoxContainer.new()
	middle.custom_minimum_size = Vector2(250, 0)
	middle.add_theme_constant_override("separation", 6)
	middle.add_child(_section_label("Spots"))
	var substrate_button := _spot_button(-1)
	substrate_button.custom_minimum_size = Vector2(0, 46)
	middle.add_child(substrate_button)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for slot in SLOT_NAMES.size():
		var b := _spot_button(slot)
		b.custom_minimum_size = Vector2(120, 52)
		grid.add_child(b)
	middle.add_child(grid)
	_selected_label = _small_label()
	_selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selected_label.custom_minimum_size = Vector2(240, 0)
	middle.add_child(_selected_label)
	_remove_button = Button.new()
	_remove_button.text = "Remove (back to stock)"
	_remove_button.pressed.connect(_on_remove)
	middle.add_child(_remove_button)
	body.add_child(middle)

	# Right: what you can place.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(340, 0)
	right.add_theme_constant_override("separation", 6)
	right.add_child(_section_label("Your stock"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_items = VBoxContainer.new()
	_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items.add_theme_constant_override("separation", 6)
	scroll.add_child(_items)
	right.add_child(scroll)
	body.add_child(right)

	_status = _small_label()
	box.add_child(_status)


func _spot_button(spot: int) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = _spot_group
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.set_meta("spot", spot)
	b.pressed.connect(_select.bind(spot))
	_spot_buttons.append(b)
	return b


# --- State -------------------------------------------------------------------

func _tank() -> Tank:
	return Game.state.tank_at(location)


func _select(spot: int) -> void:
	_selected = spot
	_refresh()


func _first_empty_spot() -> int:
	var t := _tank()
	if t.substrate == "":
		return -1
	for slot in t.slot_count():
		if t.is_slot_empty(slot):
			return slot
	return 0


func _refresh() -> void:
	var t := _tank()
	if t == null:  # sold while open (shouldn't happen, but be safe)
		close()
		return
	var state := Game.state
	var weights: Dictionary = Game.db.economy["aesthetics"]
	_looks.text = "Looks %d/100" % state.tank_aesthetics(t)
	_value.text = "Worth $%d" % state.tank_price(t, false)
	var parts := Aesthetics.breakdown(t, Game.db.items, weights)
	var bits := PackedStringArray()
	for key in BREAKDOWN_NAMES:
		bits.append("%s %d/%d" % [BREAKDOWN_NAMES[key], roundi(parts[key]), int(weights[key])])
	_breakdown.text = "   ".join(bits)
	var tips := Aesthetics.tips(t, Game.db.items, weights)
	_tips.text = "Looks perfect!" if tips.is_empty() else "Tips: " + "  ".join(tips)

	for b in _spot_buttons:
		var spot: int = b.get_meta("spot")
		var content: String = t.substrate if spot == -1 else t.slots[spot]
		var spot_name: String = "Substrate" if spot == -1 else SLOT_NAMES[spot]
		b.text = "%s\n%s" % [spot_name, Game.db.items[content]["name"] if content != "" else "(empty)"]
		b.button_pressed = spot == _selected
	_tank_view.highlight_slot = _selected
	_tank_view.queue_redraw()

	var current: String = t.substrate if _selected == -1 else t.slots[_selected]
	if _selected == -1:
		_selected_label.text = "Substrate covers the bottom. Every tank looks better with some."
	else:
		var row: String = t.row_of(_selected)
		_selected_label.text = "%s: %s items fit best here." % [SLOT_NAMES[_selected], IDEAL_HEIGHT[row].capitalize()]
	_remove_button.disabled = current == ""
	_refresh_items(t)


func _refresh_items(t: Tank) -> void:
	for child in _items.get_children():
		child.queue_free()
	var state := Game.state
	var categories := ["substrate"] if _selected == -1 else DataDB.PLACEABLE_CATEGORIES
	var ids := []
	for category in categories:
		for id in Game.db.items_in_category(category):
			if state.inventory.count(id) > 0:
				ids.append(id)
	if ids.is_empty():
		var none := _small_label()
		none.text = "Nothing for this spot in stock.\nBuy some in the Market (top bar)."
		_items.add_child(none)
		return
	var ideal := ""
	if _selected >= 0:
		ideal = IDEAL_HEIGHT[t.row_of(_selected)]
	for id in ids:
		_items.add_child(_item_row(id, ideal))


func _item_row(item_id: String, ideal_height: String) -> Control:
	var item: Dictionary = Game.db.items[item_id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var swatch := ColorRect.new()
	swatch.color = Color(item.get("color", "#999999"))
	swatch.custom_minimum_size = Vector2(22, 22)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	var name := Label.new()
	name.text = "%s  ×%d" % [item["name"], Game.state.inventory.count(item_id)]
	info.add_child(name)
	var details := PackedStringArray()
	if item.has("height"):
		var fit := ""
		if ideal_height != "":
			fit = "  ✓ good fit" if item["height"] == ideal_height else ""
		details.append(item["height"] + fit)
	if not item["tags"].is_empty():
		details.append(", ".join(item["tags"]))
	var sub := _small_label()
	sub.text = " · ".join(details)
	sub.modulate = Color(1, 1, 1, 0.75)
	info.add_child(sub)
	row.add_child(info)
	var place := UI.small_button("Place")
	place.pressed.connect(_on_place.bind(item_id))
	row.add_child(place)
	return row


func _on_place(item_id: String) -> void:
	var ok := Game.set_substrate(location, item_id) if _selected == -1 \
		else Game.place_item(location, _selected, item_id)
	if ok:
		_status.text = "Placed %s." % Game.db.items[item_id]["name"]


func _on_remove() -> void:
	var ok := Game.take_substrate(location) if _selected == -1 else Game.take_item(location, _selected)
	if ok:
		_status.text = "Put it back in stock."


# --- Helpers -----------------------------------------------------------------

func _big_label() -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 18)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _small_label() -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 13)
	return l


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	return l
