extends ColorRect
## Breeding book: every recipe and mutation, hidden as "?" until you've bred
## it once. Discovered recipes show both parents and the result as fish.
## Pauses the shop clock while open.

const UI := preload("res://scenes/ui/ui_kit.gd")
const SPECIES_ID := "guppy"
const CARD_FISH := Vector2(74, 40)

var _progress: Label
var _body: VBoxContainer


func _ready() -> void:
	visible = false
	color = Color(0.15, 0.1, 0.08, 0.45)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 620)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	var title := Label.new()
	title.text = "Breeding book"
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
	var recipes := state.book_recipes(SPECIES_ID)
	var mutations := state.book_mutations(SPECIES_ID)
	var found_recipes := recipes.filter(func(r): return r["discovered"]).size()
	var found_mutations := mutations.filter(func(m): return m["discovered"]).size()
	_progress.text = "Recipes %d/%d   ·   Mutations %d/%d" % [found_recipes, recipes.size(), found_mutations, mutations.size()]

	_body.add_child(_heading("Recipes", "Pair two varieties to discover what they make. Only breeding counts."))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for r in recipes:
		grid.add_child(_recipe_card(r))
	_body.add_child(grid)

	_body.add_child(_heading("Mutations", "Any pair, any tank. Rarer ones turn up less often."))
	var mgrid := GridContainer.new()
	mgrid.columns = 3
	mgrid.add_theme_constant_override("h_separation", 10)
	mgrid.add_theme_constant_override("v_separation", 10)
	var max_weight := 0.0
	for m in mutations:
		max_weight = maxf(max_weight, m["weight"])
	for m in mutations:
		mgrid.add_child(_mutation_card(m, max_weight))
	_body.add_child(mgrid)


func _recipe_card(r: Dictionary) -> Control:
	var card := _card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	if not r["discovered"]:
		box.add_child(_big_text("?   ×   ?   →   ?"))
		box.add_child(_small("Not discovered yet"))
		card.add_child(box)
		card.modulate = Color(1, 1, 1, 0.6)
		return card
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.add_child(_fish(r["trait"], r["parents"][0]))
	row.add_child(_symbol("×"))
	row.add_child(_fish(r["trait"], r["parents"][1]))
	row.add_child(_symbol("→"))
	row.add_child(_fish(r["trait"], r["child"]))
	box.add_child(row)
	box.add_child(_big_text("%s × %s → %s" % [UI.pretty(r["parents"][0]), UI.pretty(r["parents"][1]), UI.pretty(r["child"])]))
	box.add_child(_small("First bred on Day %d   ·   worth ×%s" % [r["day"], _value(r["trait"], r["child"])]))
	card.add_child(box)
	return card


func _mutation_card(m: Dictionary, max_weight: float) -> Control:
	var card := _card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var rarity := "Very rare" if m["weight"] < max_weight * 0.5 else ("Rare" if m["weight"] < max_weight else "Uncommon")
	if not m["discovered"]:
		box.add_child(_big_text("?"))
		box.add_child(_small("%s mutation, not found yet" % rarity))
		card.add_child(box)
		card.modulate = Color(1, 1, 1, 0.6)
		return card
	box.add_child(_fish(m["trait"], m["value"]))
	box.add_child(_big_text(UI.pretty(m["value"])))
	box.add_child(_small("%s · first bred on Day %d · worth ×%s" % [rarity, m["day"], _value(m["trait"], m["value"])]))
	card.add_child(box)
	return card


func _fish(trait_name: String, value: String) -> Control:
	var species: Dictionary = Game.db.species[SPECIES_ID]
	var f := Fish.new()
	f.id = value.hash()
	f.species_id = SPECIES_ID
	f.sex = Fish.MALE
	f.age_days = int(species["days_to_adult"])
	f.traits = {trait_name: value}
	return UI.fish_preview(f, species, CARD_FISH, 0.58)


func _value(trait_name: String, value: String) -> String:
	var v := float(Game.db.species[SPECIES_ID].get("value_multipliers", {}).get(trait_name, {}).get(value, 1.0))
	return ("%.1f" % v).trim_suffix(".0")


func _card() -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 96)
	return card


func _heading(text: String, hint: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	box.add_child(l)
	box.add_child(_small(hint))
	return box


func _big_text(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	return l


func _small(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.modulate = Color(1, 1, 1, 0.75)
	return l


func _symbol(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l
