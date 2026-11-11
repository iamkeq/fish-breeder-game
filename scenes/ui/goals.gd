extends ColorRect
## Goals: things to aim for, each with a progress bar and a one-off cash
## reward. Open goals come first, finished ones below. Also shows a few
## lifetime numbers and the "start a new game" button.
## Pauses the shop clock while open.

const GOOD := Color(0.25, 0.5, 0.35)
const STATS := [["days", "Days open"], ["fish_sold", "Fish sold"], ["fish_bred", "Fry bred"],
	["orders_delivered", "Orders delivered"], ["best_day", "Best day"], ["total_earned", "Earned in total"]]

var _progress: Label
var _body: VBoxContainer
var _stats: Label
var _new_game_button: Button
var _confirming := false


func _ready() -> void:
	visible = false
	color = Color(0.15, 0.1, 0.08, 0.45)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 620)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	var title := Label.new()
	title.text = "Goals"
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)
	_progress = Label.new()
	_progress.add_theme_font_size_override("font_size", 16)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_progress)
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
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)
	box.add_child(scroll)

	box.add_child(HSeparator.new())
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 13)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_stats)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	var saved := Label.new()
	saved.text = "Your shop is saved at the end of every day." if Game.persist \
		else "Saving is off in this run."
	saved.add_theme_font_size_override("font_size", 13)
	saved.modulate = Color(1, 1, 1, 0.7)
	saved.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(saved)
	_new_game_button = Button.new()
	_new_game_button.add_theme_font_size_override("font_size", 13)
	_new_game_button.pressed.connect(_on_new_game_pressed)
	footer.add_child(_new_game_button)
	box.add_child(footer)
	Game.changed.connect(func(): if visible: _refresh())


func open() -> void:
	if visible:
		return
	visible = true
	_confirming = false
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
	var goals: Array = Game.db.goals
	var done := goals.filter(func(g): return state.is_goal_done(g["id"]))
	_progress.text = "%d of %d reached" % [done.size(), goals.size()]
	for g in goals:
		if not state.is_goal_done(g["id"]):
			_body.add_child(_goal_row(g, false))
	if not done.is_empty():
		var heading := Label.new()
		heading.text = "Reached"
		heading.add_theme_font_size_override("font_size", 19)
		_body.add_child(heading)
		for g in done:
			_body.add_child(_goal_row(g, true))

	var parts := PackedStringArray()
	for entry in STATS:
		var value: int = state.day - 1 if entry[0] == "days" else state.goal_value(entry[0])
		parts.append("%s: %s%d" % [entry[1], "$" if entry[0] in ["best_day", "total_earned"] else "", value])
	_stats.text = "   ·   ".join(parts)
	_new_game_button.text = "Really start over? Click again" if _confirming else "Start a new game"


func _goal_row(goal: Dictionary, done: bool) -> Control:
	var state := Game.state
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	var name := Label.new()
	name.text = ("✔ " if done else "") + goal["name"]
	info.add_child(name)
	var what := Label.new()
	what.text = goal["description"]
	what.add_theme_font_size_override("font_size", 13)
	what.modulate = Color(1, 1, 1, 0.7)
	info.add_child(what)
	row.add_child(info)

	if done:
		var when := Label.new()
		when.text = "Day %d" % int(state.completed_goals[goal["id"]])
		when.add_theme_font_size_override("font_size", 13)
		when.modulate = Color(1, 1, 1, 0.7)
		when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(when)
		panel.modulate = Color(1, 1, 1, 0.75)
	else:
		var target := int(goal["target"])
		var bar := ProgressBar.new()
		bar.max_value = target
		bar.value = state.goal_progress(goal)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(150, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var count := Label.new()
		count.text = "%d/%d" % [state.goal_progress(goal), target]
		count.add_theme_font_size_override("font_size", 13)
		count.custom_minimum_size = Vector2(70, 0)
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(count)
	var reward := Label.new()
	reward.text = "+$%d" % int(goal["reward"])
	reward.add_theme_font_size_override("font_size", 18)
	reward.custom_minimum_size = Vector2(64, 0)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reward.modulate = GOOD if done else Color.WHITE
	row.add_child(reward)
	return panel


## Starting over wipes the save, so it takes two clicks.
func _on_new_game_pressed() -> void:
	if not _confirming:
		_confirming = true
		_refresh()
		return
	close()
	Game.new_game()
