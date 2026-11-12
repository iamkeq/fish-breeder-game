extends ColorRect
## The Fish Show: enter one grown-up fish in the next show. It is judged at the
## end of show day against rival entries. Entering is optional and a poor
## placing costs nothing. Pauses the shop clock while open.

const UI := preload("res://scenes/ui/ui_kit.gd")
const GRAND := Color(0.95, 0.8, 0.35)

var _top: VBoxContainer
var _body: VBoxContainer


func _ready() -> void:
	visible = false
	color = Color(0.15, 0.1, 0.08, 0.45)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 580)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Fish Show"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	box.add_child(header)

	_top = VBoxContainer.new()
	_top.add_theme_constant_override("separation", 3)
	box.add_child(_top)
	box.add_child(HSeparator.new())

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


func _label(text: String, size: int = 14, alpha: float = 1.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.modulate = Color(1, 1, 1, alpha)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _refresh() -> void:
	for child in _top.get_children():
		_top.remove_child(child)
		child.queue_free()
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var state := Game.state
	var show := state.next_show()
	if show.is_empty():
		_top.add_child(_label("No shows are being held."))
		return
	var grand: bool = show["grand"]
	var name := _label(show["name"] + ("  ★ Grand Show ★" if grand else ""), 20)
	if grand:
		name.modulate = GRAND
	_top.add_child(name)
	_top.add_child(_label(show["description"], 14, 0.8))
	var left := int(show["days_left"])
	_top.add_child(_label("Tonight! Judging at the end of today." if left == 0 else
		"Judging at the end of Day %d (%d day%s to go)" % [show["day"], left, "" if left == 1 else "s"]))
	_top.add_child(_label("Prizes:  1st $%d   ·   2nd $%d   ·   3rd $%d   ·   plus a ribbon and shop reputation. Skipping costs nothing." % [
		state.show_prize(1, grand), state.show_prize(2, grand), state.show_prize(3, grand)], 13, 0.8))
	_top.add_child(_entry_line(state))

	var fish: Array = state.inventory.fish_list().filter(func(f: Fish): return state.is_adult(f))
	fish.sort_custom(func(a: Fish, b: Fish):
		var ea := state.show_eligible(a.id)
		var eb := state.show_eligible(b.id)
		if ea != eb:
			return ea
		return a.stars > b.stars or (a.stars == b.stars and a.id < b.id))
	if fish.is_empty():
		_body.add_child(_label("No grown-up fish yet.", 14, 0.6))
	for f in fish:
		_body.add_child(_row(state, f))


func _entry_line(state: GameState) -> Control:
	var box := VBoxContainer.new()
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var entered := state.show_entry_fish()
	if entered == null:
		var none := _label("Not entered yet. Pick a fish below.", 15, 0.7)
		none.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(none)
	else:
		var text := _label("Entered: %s %s" % [UI.stars_text(entered.stars), UI.fish_heading(state, entered)], 15)
		text.modulate = Color(0.75, 0.95, 0.7)
		text.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.add_child(text)
		var withdraw := UI.small_button("Withdraw", "Take it out of the show. No harm done.")
		withdraw.pressed.connect(func(): Game.withdraw_show())
		line.add_child(withdraw)
	box.add_child(line)
	if entered != null and Fish.is_display(entered.location):
		var warn := _label("It's in the display tank, so it may be sold before the show.", 12)
		warn.modulate = Color(0.95, 0.7, 0.4)
		box.add_child(warn)
	return box


func _row(state: GameState, f: Fish) -> Control:
	var blocker := state.show_blocker(f.id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var preview := UI.fish_preview(f, state.species_of(f))
	row.add_child(preview)

	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(300, 0)
	info.add_theme_constant_override("separation", 1)
	var name := Label.new()
	name.text = "%s %s" % [UI.sex_symbol(f), UI.fish_heading(state, f)]
	info.add_child(name)
	var detail := Label.new()
	detail.text = "%s   ·   %s" % [UI.stars_text(f.stars), UI.location_name(f.location, state)]
	detail.add_theme_font_size_override("font_size", 12)
	detail.modulate = Color(1, 1, 1, 0.7)
	info.add_child(detail)
	UI.add_ribbons(info, f)
	row.add_child(info)

	var right := HBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	if blocker == "":
		var hint := _label(state.show_hint(f), 13)
		hint.autowrap_mode = TextServer.AUTOWRAP_OFF
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.modulate = Color(0.75, 0.95, 0.7)
		right.add_child(hint)
		if state.show_entry == f.id:
			var done := UI.small_button("Entered")
			done.disabled = true
			right.add_child(done)
		else:
			var enter := UI.small_button("Enter", "Enter this fish in the show.")
			enter.pressed.connect(func(): Game.enter_show(f.id))
			right.add_child(enter)
	else:
		var why := _label(blocker, 12, 0.7)
		why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.add_child(why)
		var enter := UI.small_button("Enter", blocker)
		enter.disabled = true
		right.add_child(enter)
		row.modulate = Color(1, 1, 1, 0.5)
		row.tooltip_text = blocker
		row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(right)
	return row
