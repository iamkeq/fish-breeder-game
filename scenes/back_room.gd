extends Control
## Back room: the breeding tanks (one tab each, more can be bought), plus every
## fish you own (breeding tanks, display tank, holding) with a menu to move
## them and a button to sell them to the wholesaler.

const UI := preload("res://scenes/ui/ui_kit.gd")

## The player wants to open the breeding book.
signal book_requested

@onready var _tank_tabs: HBoxContainer = %TankTabs
@onready var _tank_title: Label = %TankTitle
@onready var _tank_view: Control = %TankView
@onready var _brood_info: Label = %BroodInfo
@onready var _fish_rows: VBoxContainer = %FishRows
@onready var _status: Label = %Status

## Width of each tank tab and its little fish list.
const TAB_WIDTH := 150
## Adults listed under a tab before it says "+ N more".
const MAX_LISTED := 4

## Which breeding tank the big view shows (0-based).
var _selected_tank := 0


func _ready() -> void:
	Game.changed.connect(refresh)
	refresh()


func refresh() -> void:
	var state := Game.state
	_selected_tank = mini(_selected_tank, state.breeding_tanks.size() - 1)
	_tank_view.set_location(Fish.breeding_location(_selected_tank))
	var roles := _breeding_roles(state)
	_refresh_tabs(state, roles)
	_tank_title.text = "Breeding tank %d" % (_selected_tank + 1)
	_brood_info.text = _brood_text(state, _selected_tank) + "   ·   Fish food: %d" % state.food_count()
	for child in _fish_rows.get_children():
		child.queue_free()
	for i in state.breeding_tanks.size():
		_add_section(Fish.breeding_location(i), "Breeding tank %d" % (i + 1), roles)
	_add_section(Fish.DISPLAY, "Display tank (shop floor)", roles)
	for order in state.orders:
		if order.get("tank") != null:
			_add_section(Fish.order_location(order["id"]), "Order tank for %s" % order.get("customer", "a customer"), roles)
	_add_section(Fish.HOLDING, "Holding tanks", roles)


func _refresh_tabs(state: GameState, roles: Dictionary) -> void:
	for child in _tank_tabs.get_children():
		child.queue_free()
	for i in state.breeding_tanks.size():
		var tank := state.breeding_tanks[i]
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		column.custom_minimum_size = Vector2(TAB_WIDTH, 0)
		var tab := UI.small_button("Tank %d  (%d)" % [i + 1, tank.fish_ids.size()],
			"Breeding tank %d: %d of %d fish" % [i + 1, tank.fish_ids.size(), tank.capacity])
		tab.toggle_mode = true
		tab.button_pressed = i == _selected_tank
		tab.pressed.connect(_select_tank.bind(i))
		column.add_child(tab)
		column.add_child(_tank_contents(state, tank, roles))
		_tank_tabs.add_child(column)
	var cost := state.next_breeding_tank_cost()
	if cost >= 0:
		var add := UI.small_button("+ Add tank $%d" % cost,
			"Another breeding tank, so you can keep pairs apart and stop cross-breeding."
			if state.can_afford(cost) else "You need $%d more." % (cost - state.money))
		add.disabled = not state.can_afford(cost)
		add.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		add.pressed.connect(_on_add_tank)
		_tank_tabs.add_child(add)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tank_tabs.add_child(spacer)
	var lab := UI.small_button("Lab", "Scan fish to see how pure their line is.")
	lab.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if state.lab_unlocked():
		lab.pressed.connect(func(): Game.lab_requested.emit())
	else:
		lab.disabled = true
		lab.tooltip_text = "Reach '%s' to open the Lab" % state.unlock_level_name("lab")
	_tank_tabs.add_child(lab)
	var show_button := UI.small_button("Fish Show", "Enter a fish in the next show for ribbons and prizes.")
	show_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if state.shows_unlocked():
		show_button.pressed.connect(func(): Game.fish_show_requested.emit())
	else:
		show_button.disabled = true
		show_button.tooltip_text = "Reach '%s' to open fish shows" % state.unlock_level_name("fish_show")
	_tank_tabs.add_child(show_button)
	var book := UI.small_button("Breeding book", "Recipes and mutations you've discovered.")
	book.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	book.pressed.connect(func(): book_requested.emit())
	_tank_tabs.add_child(book)


## A small list under a tank's tab: each adult ("♂ Red ★★ sire"), then the fry
## as a count with their varieties ("+ 6 fry (Red, Orange)"). The tank's sire
## and breeding mothers are tagged.
func _tank_contents(state: GameState, tank: Tank, roles: Dictionary) -> Label:
	var adults := []
	var fry := 0
	var fry_looks := []
	for f in state.tank_fish(tank):
		if state.is_adult(f):
			adults.append(f)
		else:
			fry += 1
			var look := UI.traits_text(f)
			if not look in fry_looks:
				fry_looks.append(look)
	var lines := PackedStringArray()
	for f in adults.slice(0, MAX_LISTED):
		lines.append("%s %s%s %s%s" % [UI.sex_symbol(f), f.nickname if f.nickname != "" else UI.traits_text(f),
			" ♥" if f.favorite else "", "★".repeat(f.stars),
			" · " + roles[f.id] if roles.has(f.id) else ""])
	if adults.size() > MAX_LISTED:
		lines.append("+ %d more" % (adults.size() - MAX_LISTED))
	if fry > 0:
		lines.append("+ %d fry (%s)" % [fry, ", ".join(fry_looks)])
	if lines.is_empty():
		lines.append("(empty)")
	var label := Label.new()
	label.text = "\n".join(lines)
	label.add_theme_font_size_override("font_size", 11)
	label.modulate = Color(1, 1, 1, 0.8)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(TAB_WIDTH, 0)
	return label


func _select_tank(index: int) -> void:
	_selected_tank = index
	refresh()


func _on_add_tank() -> void:
	if Game.buy_breeding_tank():
		_selected_tank = Game.state.breeding_tanks.size() - 1
		_status.text = "New breeding tank set up! Fish only breed with others in the same tank."
		refresh()


func _add_section(location: String, title: String, roles: Dictionary) -> void:
	var state := Game.state
	var fish := state.inventory.fish_list(location)
	var header := Label.new()
	header.add_theme_font_size_override("font_size", 17)
	var tank := state.tank_at(location)
	header.text = title + ("   %d/%d" % [fish.size(), tank.capacity] if tank != null else "   %d" % fish.size())
	_fish_rows.add_child(header)
	if fish.is_empty():
		var empty := Label.new()
		empty.text = "    (empty)"
		empty.modulate = Color(1, 1, 1, 0.55)
		_fish_rows.add_child(empty)
	for f in fish:
		_fish_rows.add_child(_fish_entry(f, roles))
	_fish_rows.add_child(HSeparator.new())


func _fish_entry(f: Fish, roles: Dictionary) -> Control:
	var state := Game.state
	var species := state.species_of(f)
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 8)
	entry.add_child(UI.fish_preview(f, species))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	var title := Label.new()
	if state.is_adult(f):
		title.text = "%s %s   %s" % [UI.sex_symbol(f), UI.fish_heading(state, f), UI.stars_text(f.stars)]
	else:
		title.text = "%s %s, day %d of %d   ★ ?" % [UI.sex_symbol(f), UI.fish_heading(state, f), f.age_days, int(species["days_to_adult"])]
	var traits := Label.new()
	traits.text = UI.traits_text(f)
	# Adults of one-trait species already say it in their name ("Koi Guppy").
	traits.visible = not state.is_adult(f) or species["traits"].size() > 1
	traits.add_theme_font_size_override("font_size", 13)
	traits.modulate = Color(1, 1, 1, 0.8)
	info.add_child(title)
	info.add_child(traits)
	if state.is_adult(f):
		var value := Label.new()
		value.text = "Customers pay $%d   ·   %s" % [state.fish_price(f),
			"you paid $%d" % f.paid if f.paid > 0 else ("bred by you" if f.strain_id == "" else "free")]
		if roles.has(f.id):
			value.text += "   ·   " + roles[f.id]
		value.add_theme_font_size_override("font_size", 12)
		value.modulate = Color(1, 1, 1, 0.7)
		info.add_child(value)
		info.add_child(UI.purity_label(state, f))
		UI.add_ribbons(info, f)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	buttons.add_child(UI.move_menu(state, f, _on_move.bind(f.id)))
	var price := state.wholesale_price(f)
	var sell := UI.small_button("Sell $%d" % price,
		"Sell to the wholesaler right away. Customers would pay more (%s)." %
		("$%d" % state.fish_price(f) if state.is_adult(f) else "they don't buy fry"))
	sell.pressed.connect(_on_sell_pressed.bind(sell, f.id, price))
	if f.favorite:
		sell.disabled = true
		sell.tooltip_text = "A favourite. Un-favourite it to sell it."
	buttons.add_child(sell)
	buttons.add_child(UI.name_button(f))
	buttons.add_child(UI.favorite_button(state, f))
	info.add_child(buttons)
	entry.add_child(info)
	return entry


func _on_move(to: String, fish_id: int) -> void:
	var f: Fish = Game.state.inventory.get_fish(fish_id)
	var name := Game.state.fish_title(f) if Game.state.is_adult(f) else (f.nickname if f.nickname != "" else "fry")
	if Game.move_fish(fish_id, to):
		_status.text = "Moved the %s to the %s." % [name, UI.location_name(to, Game.state).to_lower()]


## Two clicks to sell, so a stray click never loses a fish.
func _on_sell_pressed(button: Button, fish_id: int, price: int) -> void:
	if not button.has_meta("armed"):
		button.set_meta("armed", true)
		button.text = "Sure? +$%d" % price
		return
	var f: Fish = Game.state.inventory.get_fish(fish_id)
	var name := Game.state.fish_title(f) if Game.state.is_adult(f) else (f.nickname if f.nickname != "" else "fry")
	var earned := Game.sell_fish_wholesale(fish_id)
	if earned > 0:
		_status.text = "Sold the %s to the wholesaler for $%d." % [name, earned]


## fish id -> "sire" or "breeding" for the sire and mothers of every breeding tank.
func _breeding_roles(state: GameState) -> Dictionary:
	var roles := {}
	for i in state.breeding_tanks.size():
		var group := state.breeding_group(i)
		if group["father"] == null:
			continue
		roles[group["father"].id] = "sire"
		for mother in group["mothers"]:
			roles[mother.id] = "breeding"
	return roles


func _brood_text(state: GameState, tank_index: int) -> String:
	var nights := state.nights_until_brood(tank_index)
	if nights < 0:
		return "Needs an adult male and female to breed."
	var mothers: int = state.breeding_group(tank_index)["mothers"].size()
	return "Next brood in %d night%s · %d mother%s" % [nights, "" if nights == 1 else "s",
		mothers, "" if mothers == 1 else "s"]
