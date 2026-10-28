extends ColorRect
## Market, in three tabs: Fish (named strains grouped by price tier, all always
## visible), Decorations (plants, rocks, driftwood, decor) and Supplies (tanks,
## fish food, substrate).
## Pauses the shop clock while open. Bought fish go to the holding tanks.

const UI := preload("res://scenes/ui/ui_kit.gd")

@onready var _tiers: VBoxContainer = %Tiers
@onready var _money: Label = %MarketMoney
@onready var _status: Label = %MarketStatus

const TABS := ["Fish", "Decorations", "Supplies"]
var _tab := 0
var _tab_buttons: Array[Button] = []


func _ready() -> void:
	visible = false
	%CloseMarket.pressed.connect(close)
	_build_tabs()
	Game.changed.connect(func(): if visible: _refresh())


func open() -> void:
	if visible:
		return
	visible = true
	_status.text = "Bought fish wait in the holding tanks. Move them from the Back room."
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


func _build_tabs() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = i == _tab
		b.pressed.connect(_select_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	# Just under the header row.
	var box: VBoxContainer = %Tiers.get_parent().get_parent()
	box.add_child(tabs)
	box.move_child(tabs, 1)


func _select_tab(index: int) -> void:
	_tab = index
	_refresh()
	%Tiers.get_parent().scroll_vertical = 0


func _refresh() -> void:
	var state := Game.state
	_money.text = "You have $%d" % state.money
	for i in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
	for child in _tiers.get_children():
		child.queue_free()
	match _tab:
		1:
			_add_item_sections(DECOR_SECTIONS)
		2:
			_add_item_sections(SUPPLY_SECTIONS)
		_:
			_add_fish_tiers()


func _add_fish_tiers() -> void:
	var state := Game.state
	for tier in state.market_tiers():
		var ids := state.strains_in_tier(int(tier["tier"]))
		if ids.is_empty():
			continue
		var header := Label.new()
		header.text = "Tier %d · %s" % [int(tier["tier"]), tier["name"]]
		header.add_theme_font_size_override("font_size", 19)
		_tiers.add_child(header)
		for id in ids:
			_tiers.add_child(_strain_row(id))
		_tiers.add_child(HSeparator.new())


func _strain_row(strain_id: String) -> Control:
	var state := Game.state
	var strain: Dictionary = Game.db.strains[strain_id]
	var species: Dictionary = Game.db.species[strain["species"]]
	var cost := state.strain_cost(strain_id)
	var affordable := state.can_afford(cost)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(UI.fish_preview(_preview_fish(strain, species), species, Vector2(120, 56), 0.85))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	var name := Label.new()
	name.text = "%s   %s" % [strain["name"], UI.stars_text(int(strain["stars"]))]
	var looks := Label.new()
	looks.text = _looks_text(strain, species)
	looks.add_theme_font_size_override("font_size", 13)
	var blurb := Label.new()
	blurb.text = strain.get("blurb", "")
	blurb.add_theme_font_size_override("font_size", 13)
	blurb.modulate = Color(1, 1, 1, 0.7)
	info.add_child(name)
	info.add_child(looks)
	info.add_child(blurb)
	row.add_child(info)

	var price := Label.new()
	price.text = "$%d" % cost
	price.add_theme_font_size_override("font_size", 19)
	price.custom_minimum_size = Vector2(56, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.modulate = Color.WHITE if affordable else Color(1, 1, 1, 0.45)
	row.add_child(price)

	var short := "You need $%d more." % (cost - state.money)
	for sex in [Fish.MALE, Fish.FEMALE]:
		var b := UI.small_button("Buy ♂" if sex == Fish.MALE else "Buy ♀", "" if affordable else short)
		b.disabled = not affordable
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(_on_buy.bind(strain_id, sex))
		row.add_child(b)
	return row


func _on_buy(strain_id: String, sex: String) -> void:
	var f := Game.buy_strain(strain_id, sex)
	if f != null:
		_status.text = "Bought a %s %s! It's waiting in the holding tanks (Back room)." % [
			"male" if sex == Fish.MALE else "female", Game.db.strains[strain_id]["name"]]


## A representative fish for the preview: fixed traits, first common value otherwise.
func _preview_fish(strain: Dictionary, species: Dictionary) -> Fish:
	var f := Fish.new()
	f.id = strain["id"].hash()
	f.species_id = species["id"]
	f.sex = Fish.MALE
	f.age_days = int(species["days_to_adult"])
	for trait_name in species["traits"]:
		f.traits[trait_name] = strain["traits"].get(trait_name, species["traits"][trait_name]["common"][0])
	return f


func _looks_text(strain: Dictionary, species: Dictionary) -> String:
	var parts := PackedStringArray()
	for trait_name in species["traits"]:
		if strain["traits"].has(trait_name):
			var v: String = UI.pretty(strain["traits"][trait_name])
			parts.append(v + " tail" if trait_name == "tail_shape" else v)
	if parts.is_empty():
		return "Random common looks"
	if parts.size() < species["traits"].size():
		parts.append("other traits random")
	return " · ".join(parts)


## Item sections per tab: [heading, categories].
const DECOR_SECTIONS := [["Plants", ["plant"]], ["Rocks", ["rock"]], ["Driftwood", ["driftwood"]], ["Decor", ["decor"]]]
const SUPPLY_SECTIONS := [["Tanks", ["tank"]], ["Fish food", ["food"]], ["Substrate", ["substrate"]]]


func _add_item_sections(sections: Array) -> void:
	for section in sections:
		var ids := []
		for category in section[1]:
			ids.append_array(Game.db.items_in_category(category))
		if ids.is_empty():
			continue
		ids.sort_custom(func(a, b): return Game.db.items[a]["name"] < Game.db.items[b]["name"])
		var header := Label.new()
		header.text = "%s  (%d)" % [section[0], ids.size()]
		header.add_theme_font_size_override("font_size", 19)
		_tiers.add_child(header)
		for id in ids:
			_tiers.add_child(_supply_row(id))
		_tiers.add_child(HSeparator.new())


func _supply_row(item_id: String) -> Control:
	var state := Game.state
	var item: Dictionary = Game.db.items[item_id]
	var cost := int(item["cost"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var swatch := UI.item_icon(item, Vector2(48, 40))
	row.add_child(swatch)
	var name := Label.new()
	name.text = "%s   (%s, have %d)" % [item["name"], item["category"], state.inventory.count(item_id)]
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var price := Label.new()
	price.text = "$%d" % cost
	price.custom_minimum_size = Vector2(56, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price)
	for qty in [1, 5]:
		var total: int = cost * qty
		var b := UI.small_button("Buy" if qty == 1 else "Buy 5",
			"" if state.can_afford(total) else "You need $%d more." % (total - state.money))
		b.disabled = not state.can_afford(total)
		b.pressed.connect(func():
			if Game.buy_item(item_id, qty):
				_status.text = "Bought %d× %s." % [qty, item["name"]])
		row.add_child(b)
	return row
