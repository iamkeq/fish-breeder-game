extends ColorRect
## Market, in five tabs: Fish (named strains grouped by price tier, all always
## visible), Decorations (plants, rocks, driftwood, decor), Supplies (tanks,
## fish food, substrate), Upgrades (one-off improvements to the shop) and
## Standing orders (the shop reorders supplies by itself).
## Pauses the shop clock while open. Bought fish go to the holding tanks.

const UI := preload("res://scenes/ui/ui_kit.gd")

@onready var _tiers: VBoxContainer = %Tiers
@onready var _money: Label = %MarketMoney
@onready var _status: Label = %MarketStatus

const TABS := ["Fish", "Decorations", "Supplies", "Upgrades", "Standing orders"]
var _tab := 0
var _tab_buttons: Array[Button] = []
## True while a Standing orders field is being edited: the rows are not rebuilt then.
var _editing := false


func _ready() -> void:
	visible = false
	%CloseMarket.pressed.connect(close)
	_build_tabs()
	Game.changed.connect(func(): if visible and not _editing: _refresh())


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
		3:
			_add_upgrades()
		4:
			_add_standing_orders()
		_:
			_add_fish_tiers()


## The Standing orders tab: one row per Market item (not fish).
func _add_standing_orders() -> void:
	var state := Game.state
	var note := Label.new()
	note.text = "Set it and forget it: the shop reorders when stock runs low and it arrives next morning."
	note.add_theme_font_size_override("font_size", 14)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(1, 1, 1, 0.75)
	_tiers.add_child(note)
	var floor_row := HBoxContainer.new()
	floor_row.add_theme_constant_override("separation", 8)
	var floor_label := Label.new()
	floor_label.text = "Keep at least $"
	floor_row.add_child(floor_label)
	var floor_spin := SpinBox.new()
	floor_spin.min_value = 0
	floor_spin.max_value = 9999
	floor_spin.value = state.order_money_floor
	floor_spin.tooltip_text = "The shop won't place an order if it would leave you with less than this."
	floor_spin.value_changed.connect(func(v: float):
		_editing = true
		Game.set_order_money_floor(int(v))
		_editing = false)
	floor_row.add_child(floor_spin)
	var floor_hint := Label.new()
	floor_hint.text = "in the till after an order, so a reorder never empties your purse."
	floor_hint.add_theme_font_size_override("font_size", 13)
	floor_hint.modulate = Color(1, 1, 1, 0.7)
	floor_row.add_child(floor_hint)
	_tiers.add_child(floor_row)
	_tiers.add_child(HSeparator.new())
	var sections: Array = [SUPPLY_SECTIONS[1], SUPPLY_SECTIONS[2], SUPPLY_SECTIONS[0]] + DECOR_SECTIONS  # food first
	for section in sections:
		var ids := []
		for category in section[1]:
			ids.append_array(Game.db.items_in_category(category))
		if ids.is_empty():
			continue
		ids.sort_custom(func(a, b): return Game.db.items[a]["name"] < Game.db.items[b]["name"])
		var header := Label.new()
		header.text = section[0]
		header.add_theme_font_size_override("font_size", 19)
		_tiers.add_child(header)
		for id in ids:
			_tiers.add_child(_standing_order_row(id))
		_tiers.add_child(HSeparator.new())


func _standing_order_row(item_id: String) -> Control:
	var state := Game.state
	var item: Dictionary = Game.db.items[item_id]
	var rule := state.standing_order(item_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UI.item_icon(item, Vector2(48, 40)))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	var name := Label.new()
	name.text = item["name"]
	info.add_child(name)
	var stock := Label.new()
	stock.text = "In stock: %d · On the way: %d" % [state.inventory.count(item_id), state.pending_quantity(item_id)]
	stock.add_theme_font_size_override("font_size", 13)
	stock.modulate = Color(1, 1, 1, 0.7)
	info.add_child(stock)
	if item["category"] == "food":
		var hint := Label.new()
		hint.text = "Your tanks use about %d a night." % state.food_use_per_night()
		hint.add_theme_font_size_override("font_size", 13)
		hint.modulate = Color(0.45, 0.65, 0.5)
		info.add_child(hint)
	row.add_child(info)

	var auto := CheckButton.new()
	auto.text = "Auto"
	auto.button_pressed = rule["enabled"]
	auto.focus_mode = Control.FOCUS_NONE
	auto.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(auto)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var level_label := Label.new()
	level_label.text = "At or below"
	controls.add_child(level_label)
	var level := SpinBox.new()
	level.min_value = 0
	level.max_value = int(Game.db.economy["standing_orders"]["max_level"])
	level.value = rule["reorder_at"]
	level.custom_minimum_size = Vector2(76, 0)
	controls.add_child(level)
	var qty_label := Label.new()
	qty_label.text = "order"
	controls.add_child(qty_label)
	var qty := SpinBox.new()
	qty.min_value = 1
	qty.max_value = int(Game.db.economy["standing_orders"]["max_quantity"])
	qty.value = rule["quantity"]
	qty.custom_minimum_size = Vector2(76, 0)
	controls.add_child(qty)
	var cost := Label.new()
	cost.text = "≈ $%d" % state.standing_order_cost(item_id)
	cost.custom_minimum_size = Vector2(52, 0)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.add_child(cost)
	row.add_child(controls)
	controls.modulate = Color.WHITE if rule["enabled"] else Color(1, 1, 1, 0.45)

	# Changes apply at once. Editing a number never rebuilds the rows (that would
	# steal focus), it just updates the price shown.
	var save := func(_v = 0.0):
		_editing = true
		Game.set_standing_order(item_id, auto.button_pressed, int(level.value), int(qty.value))
		_editing = false
		_money.text = "You have $%d" % state.money
		cost.text = "≈ $%d" % state.standing_order_cost(item_id)
		controls.modulate = Color.WHITE if auto.button_pressed else Color(1, 1, 1, 0.45)
	auto.toggled.connect(save)
	level.value_changed.connect(save)
	qty.value_changed.connect(save)
	return row


func _add_upgrades() -> void:
	var state := Game.state
	var header := Label.new()
	header.text = "Shop upgrades  (%d of %d bought)" % [state.upgrades.size(), Game.db.upgrades.size()]
	header.add_theme_font_size_override("font_size", 19)
	_tiers.add_child(header)
	var hint := Label.new()
	hint.text = "Each one is bought once and lasts for good."
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.7)
	_tiers.add_child(hint)
	for id in Game.db.upgrade_order:
		_tiers.add_child(_upgrade_row(id))
		_tiers.add_child(HSeparator.new())


func _upgrade_row(upgrade_id: String) -> Control:
	var state := Game.state
	var upgrade: Dictionary = Game.db.upgrades[upgrade_id]
	var owned := state.has_upgrade(upgrade_id)
	var blocker := state.upgrade_blocker(upgrade_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	var name := Label.new()
	name.text = ("✔ " if owned else "") + upgrade["name"]
	info.add_child(name)
	var what := Label.new()
	what.text = upgrade["description"]
	what.add_theme_font_size_override("font_size", 13)
	what.modulate = Color(1, 1, 1, 0.7)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(what)
	if not owned and upgrade.has("requires") and not state.has_upgrade(upgrade["requires"]):
		var needs := Label.new()
		needs.text = blocker
		needs.add_theme_font_size_override("font_size", 13)
		needs.modulate = Color(0.75, 0.4, 0.2)
		info.add_child(needs)
	row.add_child(info)
	var price := Label.new()
	price.text = "Bought" if owned else "$%d" % int(upgrade["cost"])
	price.add_theme_font_size_override("font_size", 19)
	price.custom_minimum_size = Vector2(72, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price.modulate = Color.WHITE if blocker == "" else Color(1, 1, 1, 0.45)
	row.add_child(price)
	if not owned:
		var b := UI.small_button("Buy", blocker)
		b.disabled = blocker != ""
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func():
			if Game.buy_upgrade(upgrade_id):
				_status.text = "Bought the %s." % upgrade["name"])
		row.add_child(b)
	else:
		row.modulate = Color(1, 1, 1, 0.75)
	return row


func _add_fish_tiers() -> void:
	var state := Game.state
	var mode: String = Game.db.challenge_by_id(state.challenge_id).get("name", "")
	if state.market_last_day() >= 0:
		var note := Label.new()
		note.add_theme_font_size_override("font_size", 14)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if state.market_fish_open():
			note.text = "%s: the Market sells fish until the end of Day %d." % [mode, state.market_last_day()]
			note.modulate = Color(0.75, 0.4, 0.2)
			_tiers.add_child(note)
		else:
			note.text = "%s: the Market has stopped selling fish (it closed after Day %d). From here on, you breed your own. Supplies, decorations and upgrades are still on sale." % [
				mode, state.market_last_day()]
			note.add_theme_font_size_override("font_size", 16)
			_tiers.add_child(note)
			return
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
	if state.standing_order(item_id)["enabled"]:
		var auto := Label.new()
		auto.text = "Auto-order on"
		auto.add_theme_font_size_override("font_size", 13)
		auto.modulate = Color(0.45, 0.65, 0.5)
		auto.tooltip_text = "Standing order: reorders %d when stock is %d or less." % [
			state.standing_order(item_id)["quantity"], state.standing_order(item_id)["reorder_at"]]
		auto.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(auto)
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
