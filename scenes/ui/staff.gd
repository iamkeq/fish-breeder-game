extends ColorRect
## The Staff screen: your helpers (each does one job overnight), and the jobs
## still open to hire for. Pauses the shop clock while open.

const UI := preload("res://scenes/ui/ui_kit.gd")

var _header: Label
var _body: VBoxContainer
## The helper whose "Let go" button was clicked once (it asks again to confirm).
var _confirming_id := -1


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

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	var title := Label.new()
	title.text = "Your staff"
	title.add_theme_font_size_override("font_size", 24)
	top.add_child(title)
	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 16)
	_header.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_header)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	top.add_child(close_button)
	box.add_child(top)

	var intro := Label.new()
	intro.text = "Helpers work overnight, each on one job, for a small wage. They never break anything, and you can let them go any time."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.modulate = Color(1, 1, 1, 0.8)
	box.add_child(intro)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)
	box.add_child(scroll)
	Game.changed.connect(func():
		if visible:
			_refresh())


func open() -> void:
	if visible:
		return
	visible = true
	_confirming_id = -1
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
	_header.text = "Team %d / %d   ·   Wages $%d a day   ·   Money $%d" % [
		state.staff.size(), state.staff_max(), state.staff_wage_bill(), state.money]
	if state.staff.is_empty():
		var empty := Label.new()
		empty.text = "Nobody yet. Hire a helper and your fish are fed and your shelves tidied while you breed."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.modulate = Color(1, 1, 1, 0.7)
		_body.add_child(empty)
	for m in state.staff:
		_body.add_child(_card(state, m))
	var open_jobs: Array = state.staff_task_ids().filter(func(t): return state.staff_for_task(t).is_empty())
	if not open_jobs.is_empty() and state.staff.size() < state.staff_max():
		var heading := Label.new()
		heading.text = "Hire someone"
		heading.add_theme_font_size_override("font_size", 19)
		_body.add_child(heading)
		for task in open_jobs:
			_body.add_child(_hire_row(state, task))


## A coloured circle with the helper's initial. Drawn, no art needed.
static func avatar(m: Dictionary, size: float = 48.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(size, size)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tint := Color.from_string(str(m.get("color", "#999999")), Color(0.6, 0.6, 0.6))
	var letter := str(m.get("name", "?")).left(1).to_upper()
	c.draw.connect(func():
		var mid := Vector2(size, size) / 2.0
		c.draw_circle(mid, size / 2.0, tint.darkened(0.25))
		c.draw_circle(mid, size / 2.0 - 2.0, tint)
		var font := ThemeDB.fallback_font
		var font_size := int(size * 0.5)
		var width := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		c.draw_string(font, Vector2(mid.x - width / 2.0, mid.y + font_size * 0.35), letter,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.15, 0.1, 0.08)))
	c.tooltip_text = str(m.get("name", ""))
	return c


func _card(state: GameState, m: Dictionary) -> Control:
	var card := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	row.add_child(avatar(m))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	var name := Label.new()
	name.text = m["name"]
	name.add_theme_font_size_override("font_size", 18)
	info.add_child(name)
	var task := state.staff_task(m["task"])
	var job := Label.new()
	job.text = task.get("name", m["task"])
	job.add_theme_font_size_override("font_size", 14)
	info.add_child(job)
	var what := Label.new()
	what.text = task.get("description", "")
	what.add_theme_font_size_override("font_size", 12)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.custom_minimum_size = Vector2(300, 0)
	what.modulate = Color(1, 1, 1, 0.7)
	info.add_child(what)
	row.add_child(info)

	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var picker := OptionButton.new()
	picker.tooltip_text = "Give %s a different job" % m["name"]
	var ids := []
	for t in state.staff_task_ids():
		# Only their own job and jobs nobody has: one hire per job.
		if t == m["task"] or state.staff_for_task(t).is_empty():
			ids.append(t)
	for i in ids.size():
		picker.add_item(state.staff_task(ids[i]).get("name", ids[i]), i)
		if ids[i] == m["task"]:
			picker.select(i)
	picker.item_selected.connect(func(index: int): Game.set_staff_task(int(m["id"]), ids[index]))
	picker.disabled = ids.size() < 2
	controls.add_child(picker)
	var sure := _confirming_id == int(m["id"])
	var let_go := UI.small_button("No hard feelings? Click again" if sure else "Let go",
		"No refund, no penalty. You can hire someone new any time.")
	let_go.pressed.connect(func():
		if _confirming_id == int(m["id"]):
			_confirming_id = -1
			Game.dismiss_staff(int(m["id"]))
		else:
			_confirming_id = int(m["id"])
			_refresh())
	controls.add_child(let_go)
	row.add_child(controls)
	return card


func _hire_row(state: GameState, task: String) -> Control:
	var def := state.staff_task(task)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	var name := Label.new()
	name.text = def["name"]
	name.add_theme_font_size_override("font_size", 16)
	info.add_child(name)
	var what := Label.new()
	what.text = def["description"]
	what.add_theme_font_size_override("font_size", 12)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.custom_minimum_size = Vector2(420, 0)
	what.modulate = Color(1, 1, 1, 0.7)
	info.add_child(what)
	row.add_child(info)
	var price := Label.new()
	price.text = "$%d to hire, $%d a day" % [state.hire_cost(), state.staff_wage()]
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(price)
	var blocker := state.hire_blocker(task)
	var hire := UI.small_button("Hire", blocker)
	hire.disabled = blocker != ""
	hire.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hire.pressed.connect(func(): Game.hire_staff(task))
	row.add_child(hire)
	return row
