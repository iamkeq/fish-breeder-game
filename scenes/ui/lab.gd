extends ColorRect
## The Lab: scan a grown-up fish for a fee to see how pure its line is. Lists
## adults from holding, breeding and display tanks, unscanned first. Pauses the
## shop clock while open.

const UI := preload("res://scenes/ui/ui_kit.gd")

var _money: Label
var _body: VBoxContainer


func _ready() -> void:
	visible = false
	color = Color(0.15, 0.1, 0.08, 0.45)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 560)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	var title := Label.new()
	title.text = "The Lab"
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", 16)
	_money.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_money)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	box.add_child(header)

	var intro := Label.new()
	intro.text = "Scan a fish to see how pure its line is. Pure lines breed better stars."
	intro.modulate = Color(1, 1, 1, 0.8)
	box.add_child(intro)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)
	box.add_child(scroll)
	Game.changed.connect(func():
		if visible:
			_refresh())


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
	for child in _body.get_children():
		child.queue_free()
	var state := Game.state
	_money.text = "Money $%d   ·   Scan $%d" % [state.money, state.scan_cost()]
	var fish: Array = state.inventory.fish_list().filter(
		func(f: Fish): return state.is_adult(f) and not Fish.is_order(f.location))
	# Unscanned first, then by id so rows don't jump around.
	fish.sort_custom(func(a: Fish, b: Fish): return (a.scanned and not b.scanned) \
		or (a.scanned == b.scanned and a.id < b.id))
	if fish.is_empty():
		var empty := Label.new()
		empty.text = "No grown-up fish to scan yet."
		empty.modulate = Color(1, 1, 1, 0.6)
		_body.add_child(empty)
	for f in fish:
		_body.add_child(_row(state, f))


func _row(state: GameState, f: Fish) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UI.fish_preview(f, state.species_of(f)))

	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(250, 0)
	info.add_theme_constant_override("separation", 1)
	var name := Label.new()
	name.text = "%s %s" % [UI.sex_symbol(f), UI.fish_heading(state, f)]
	info.add_child(name)
	var detail := Label.new()
	detail.text = "%s   ·   %s" % [UI.stars_text(f.stars), UI.location_name(f.location, state)]
	detail.add_theme_font_size_override("font_size", 12)
	detail.modulate = Color(1, 1, 1, 0.7)
	info.add_child(detail)
	row.add_child(info)

	var result := HBoxContainer.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_constant_override("separation", 10)
	if f.scanned:
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value = f.purity
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(140, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		result.add_child(bar)
		var text := Label.new()
		text.text = "%d%% · %s" % [f.purity, state.purity_tier(f.purity)]
		result.add_child(text)
		if state.is_certified(f):
			var tag := Label.new()
			tag.text = "✓ Certified"
			tag.modulate = Color(0.75, 0.95, 0.7)
			tag.tooltip_text = "Certified lines sell for more."
			tag.mouse_filter = Control.MOUSE_FILTER_STOP
			result.add_child(tag)
	else:
		var blocker := state.scan_blocker(f.id)
		var scan := UI.small_button("Scan ($%d)" % state.scan_cost(), blocker)
		scan.disabled = blocker != ""
		scan.pressed.connect(func(): Game.scan_fish(f.id))
		result.add_child(scan)
	row.add_child(result)
	return row
