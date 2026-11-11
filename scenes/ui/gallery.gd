extends ColorRect
## The Gallery: framed portraits of your favourite fish and a Hall of Fame of
## every fish that won a show ribbon (kept even after the fish is sold). Once
## the shop is well known you can pin portraits on the shop-floor wall. It is
## all for show: nothing here changes money or stars. Pauses the shop clock.

const UI := preload("res://scenes/ui/ui_kit.gd")
const PLATE := Color(0.8, 0.65, 0.36)
const PLATE_TEXT := Color(0.24, 0.15, 0.06)
const COLUMNS := 3

var _tab := "favourites"
var _fav_tab: Button
var _hall_tab: Button
var _count: Label
var _grid: GridContainer
var _footer: Label


func _ready() -> void:
	visible = false
	color = Color(0.15, 0.1, 0.08, 0.45)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 620)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Gallery"
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)
	var group := ButtonGroup.new()
	_fav_tab = _tab_button("Favourites", "favourites", group)
	_hall_tab = _tab_button("Hall of Fame", "hall", group)
	header.add_child(_fav_tab)
	header.add_child(_hall_tab)
	_count = Label.new()
	_count.modulate = Color(1, 1, 1, 0.75)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_count)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	box.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(_grid)
	box.add_child(scroll)

	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", 13)
	_footer.modulate = Color(1, 1, 1, 0.75)
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_footer)
	Game.changed.connect(func():
		if visible:
			_refresh())


func _tab_button(text: String, tab: String, group: ButtonGroup) -> Button:
	var b := UI.small_button(text)
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = tab == _tab
	b.pressed.connect(func():
		_tab = tab
		_refresh())
	return b


func open() -> void:
	if visible:
		return
	visible = true
	Game.push_pause()
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	Game.pop_pause()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var state := Game.state
	_fav_tab.set_pressed_no_signal(_tab == "favourites")
	_hall_tab.set_pressed_no_signal(_tab == "hall")
	var entries: Array = state.gallery_favorites() if _tab == "favourites" else state.gallery_hall()
	if _tab == "favourites":
		_count.text = "%d / %d" % [entries.size(), state.favorite_max()]
	else:
		_count.text = "%d portrait%s" % [entries.size(), "" if entries.size() == 1 else "s"]
	for entry in entries:
		_grid.add_child(_card(state, entry))
	if entries.is_empty():
		# One message spread over the first cell, so the grid stays simple.
		var empty := Label.new()
		empty.text = "Mark a fish with ♥ Favourite and it will hang here." if _tab == "favourites" \
			else "Win a ribbon at a fish show and the portrait will hang here."
		empty.modulate = Color(1, 1, 1, 0.65)
		_grid.add_child(empty)
	if state.pin_slots() > 0:
		_footer.text = "On the shop wall: %d / %d. Pin a portrait to hang it near the display tank." % [
			state.pinned_entries().size(), state.pin_slots()]
	else:
		_footer.text = "Reach '%s' to pin portraits on the shop wall." % state.unlock_level_name("gallery_wall")


func _card(state: GameState, entry: Dictionary) -> Control:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 3)
	card.custom_minimum_size = Vector2(262, 0)
	card.add_child(UI.portrait(state, entry, Vector2(236, 120), 1.5))

	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PLATE
	style.set_corner_radius_all(3)
	style.border_color = Color(0.5, 0.38, 0.17)
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 4
	plate.add_theme_stylebox_override("panel", style)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	lines.add_child(_plate_label(entry["title"], 14))
	lines.add_child(_plate_label(UI.stars_text(int(entry["stars"])), 13))
	if entry["scanned"]:
		lines.add_child(_plate_label("Purity %d%% · %s" % [entry["purity"], state.purity_tier(int(entry["purity"]))], 12))
	if entry.has("show_name"):
		lines.add_child(_plate_label("%s · %s, Day %d" % [Shows.PLACE_WORDS[clampi(int(entry["place"]), 1, 3)],
			entry["show_name"], entry["day"]], 12))
	plate.add_child(lines)
	card.add_child(plate)
	# Favourites carry every ribbon they've won; Hall portraits just this one.
	if _tab == "favourites":
		UI.add_ribbon_chips(card, entry["ribbons"])

	if state.pin_slots() > 0:
		var key: String = entry["key"]
		var pinned: bool = key in state.gallery_pins
		var blocker := "" if pinned else state.pin_blocker(key)
		var button := UI.small_button("Unpin" if pinned else "Pin to wall",
			"Take it down from the shop wall." if pinned else (blocker if blocker != "" else "Hang this portrait on the shop wall."))
		button.disabled = blocker != ""
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.pressed.connect(func():
			if pinned:
				Game.unpin_portrait(key)
			else:
				Game.pin_portrait(key))
		card.add_child(button)
	return card


func _plate_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", PLATE_TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(220, 0)
	return l
