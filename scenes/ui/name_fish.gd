extends ColorRect
## A small box for naming a fish: a text field (up to 16 characters), Save and
## Cancel. An empty name takes the name away. Pauses the shop clock while open.

const UI := preload("res://scenes/ui/ui_kit.gd")

var _fish_id: int = -1
var _heading: Label
var _edit: LineEdit
var _note: Label


func _ready() -> void:
	visible = false
	color = Color(0.15, 0.1, 0.08, 0.45)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Name your fish"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	_heading = Label.new()
	_heading.modulate = Color(1, 1, 1, 0.8)
	box.add_child(_heading)
	_edit = LineEdit.new()
	_edit.max_length = GameState.MAX_NAME_LENGTH
	_edit.placeholder_text = "A name (up to %d letters)" % GameState.MAX_NAME_LENGTH
	_edit.text_submitted.connect(func(_t: String): _save())
	box.add_child(_edit)
	_note = Label.new()
	_note.text = "Leave it empty to take the name away."
	_note.add_theme_font_size_override("font_size", 12)
	_note.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_note)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(close)
	buttons.add_child(cancel)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(_save)
	buttons.add_child(save)
	box.add_child(buttons)


## Opens the box for one fish, with its current name filled in.
func open(fish_id: int) -> void:
	var f := Game.state.inventory.get_fish(fish_id)
	if visible or f == null:
		return
	_fish_id = fish_id
	_heading.text = Game.state.fish_display_name(f) if Game.state.is_adult(f) else "A fry"
	_edit.text = f.nickname
	visible = true
	Game.push_pause()
	_edit.grab_focus()
	_edit.select_all()


func close() -> void:
	if not visible:
		return
	visible = false
	Game.pop_pause()


func _save() -> void:
	Game.rename_fish(_fish_id, _edit.text)
	close()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
