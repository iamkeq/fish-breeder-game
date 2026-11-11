extends ColorRect
## New game: pick a starting pair and a mode, then press Start. There is no
## close button and Escape does nothing, so you always start somewhere. Game
## keeps the clock paused while it is up (Game.needs_setup).

const UI := preload("res://scenes/ui/ui_kit.gd")

const CARD_WIDTH := 236
const START_CARD_HEIGHT := 160
const MODE_CARD_HEIGHT := 172
const PREVIEW_BOX := Vector2(100, 52)

var _start_id := ""
var _challenge_id := ""


func _ready() -> void:
	visible = false
	color = Color(0.15, 0.1, 0.08, 0.7)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "New game"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var starts: Array = Game.db.starts
	if not starts.is_empty():
		_start_id = starts[0]["id"]
		box.add_child(_heading("Starting pair"))
		var row := _card_row()
		var group := ButtonGroup.new()
		for st in starts:
			row.add_child(_card(group, START_CARD_HEIGHT, st["id"] == _start_id,
				func(): _start_id = st["id"], _start_content(st)))
		box.add_child(row)

	var challenges: Array = Game.db.challenges
	if not challenges.is_empty():
		_challenge_id = challenges[0]["id"]
		box.add_child(_heading("Mode"))
		var row := _card_row()
		var group := ButtonGroup.new()
		for c in challenges:
			row.add_child(_card(group, MODE_CARD_HEIGHT, c["id"] == _challenge_id,
				func(): _challenge_id = c["id"], _mode_content(c)))
		box.add_child(row)

	var start_button := Button.new()
	start_button.text = "Start"
	start_button.add_theme_font_size_override("font_size", 22)
	start_button.custom_minimum_size = Vector2(0, 44)
	start_button.pressed.connect(_on_start)
	box.add_child(start_button)


## Shows the screen. (Game holds the clock paused until Start is pressed.)
func open() -> void:
	visible = true


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()  # you must pick a start


func _on_start() -> void:
	Game.start_new_game(_start_id, _challenge_id)


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	return l


func _card_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	return row


## A selectable card: a toggle button with `content` laid over it.
func _card(group: ButtonGroup, height: int, selected: bool, on_pick: Callable, content: Control) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(CARD_WIDTH, height)
	b.button_pressed = selected
	b.pressed.connect(on_pick)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.add_child(content)
	b.add_child(margin)
	_ignore_mouse(margin)
	return b


func _start_content(st: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var pics := HBoxContainer.new()
	pics.custom_minimum_size = Vector2(0, PREVIEW_BOX.y)
	pics.alignment = BoxContainer.ALIGNMENT_CENTER
	if st.get("random_pair", false):
		var q := Label.new()
		q.text = "?"
		q.add_theme_font_size_override("font_size", 40)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pics.add_child(q)
	else:
		for fish_data in st.get("fish", []):
			var f := Fish.from_dict(fish_data)
			f.id = hash(st["id"]) + pics.get_child_count()
			f.age_days = int(Game.db.species[f.species_id]["days_to_adult"])
			pics.add_child(UI.fish_preview(f, Game.db.species[f.species_id], PREVIEW_BOX, 0.7))
	box.add_child(pics)
	box.add_child(_name_label(st["name"]))
	box.add_child(_text_label(st["description"]))
	return box


func _mode_content(c: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_name_label(c["name"]))
	box.add_child(_text_label(c["description"]))
	return box


func _name_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _text_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(1, 1, 1, 0.8)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Clicks go to the card's button, not the labels and pictures drawn on it.
func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)
