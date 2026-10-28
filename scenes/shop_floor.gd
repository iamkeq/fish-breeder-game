extends Control
## Shop floor: retail shelf, the display tank (with its fish and controls),
## and the counter where customers arrive and orders are delivered.

## The player wants to open the aquascaping editor for the display tank.
signal edit_tank_requested

const UI := preload("res://scenes/ui/ui_kit.gd")
const TEXT_WIDTH := 262.0

@onready var _items: VBoxContainer = %Items
@onready var _tank_info: Label = %TankInfo
@onready var _tank_actions: HBoxContainer = %TankActions
@onready var _display_fish: HBoxContainer = %DisplayFish
@onready var _counter: VBoxContainer = %Counter

## Last thing that happened at the counter ("Sold ... for $8").
var _counter_news := ""


func _ready() -> void:
	Game.changed.connect(refresh)
	Game.customer_changed.connect(_refresh_counter)
	refresh()


func refresh() -> void:
	_refresh_shelf()
	_refresh_tank()
	_refresh_counter()


# --- Shelf -------------------------------------------------------------------

func _refresh_shelf() -> void:
	_clear(_items)
	var stock := Game.state.inventory.stock()
	var ids := stock.keys()
	ids.sort_custom(func(a, b): return Game.db.items[a]["name"] < Game.db.items[b]["name"])
	if ids.is_empty():
		_items.add_child(_label("The shelf is empty."))
	for id in ids:
		var item: Dictionary = Game.db.items[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var swatch := UI.item_icon(item, Vector2(34, 28))
		var name := _label("%s ×%d" % [item["name"], stock[id]])
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var price := _label("$%d" % Pricing.item_price(item))
		price.modulate = Color(1, 1, 1, 0.7)
		row.add_child(swatch)
		row.add_child(name)
		row.add_child(price)
		_items.add_child(row)


# --- Display tank ------------------------------------------------------------

func _refresh_tank() -> void:
	var state := Game.state
	var tank := state.display_tank
	_clear(_tank_actions)
	_clear(_display_fish)
	if tank == null:
		_tank_info.text = "The display stand is empty."
		var tanks := Game.db.items_in_category("tank").filter(func(id): return state.inventory.count(id) > 0)
		if tanks.is_empty():
			_tank_info.text += " Buy a tank in the Market to set up a new one."
		for id in tanks:
			var b := UI.small_button("Set up a new %s (have %d)" % [Game.db.items[id]["name"], state.inventory.count(id)])
			b.pressed.connect(func(): Game.install_display_tank(id))
			_tank_actions.add_child(b)
		return
	_tank_info.text = "Looks %d/100   ·   %d/%d fish   ·   Worth $%d" % [
		state.tank_aesthetics(tank), tank.fish_ids.size(), tank.capacity, state.tank_price(tank, true)]
	var edit := UI.small_button("Edit tank", "Place substrate, rocks, wood, plants and decor from your stock.")
	edit.pressed.connect(func(): edit_tank_requested.emit())
	_tank_actions.add_child(edit)
	if tank.fish_ids.is_empty():
		var hint := _label("No fish on display. Move some here from the Back room. Fish on display bring customers in!")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(560, 0)
		hint.modulate = Color(1, 1, 1, 0.7)
		_display_fish.add_child(hint)
	for f in state.tank_fish(tank):
		_display_fish.add_child(_display_card(f))


func _display_card(f: Fish) -> Control:
	var state := Game.state
	var card := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	top.add_child(UI.fish_preview(f, state.species_of(f), Vector2(64, 34), 0.45))
	var name := _label("%s %s\n%s  $%d" % [UI.sex_symbol(f), state.fish_display_name(f), UI.stars_text(f.stars), state.fish_price(f)])
	name.add_theme_font_size_override("font_size", 12)
	top.add_child(name)
	box.add_child(top)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	var back := UI.small_button("To back room", state.move_blocker(f.id, Fish.HOLDING))
	back.pressed.connect(func(): Game.move_fish(f.id, Fish.HOLDING))
	buttons.add_child(back)
	# Breeding tanks and anywhere else, as a menu (there can be up to 4 tanks).
	buttons.add_child(UI.move_menu(state, f, func(to: String): Game.move_fish(f.id, to)))
	box.add_child(buttons)
	card.add_child(box)
	return card


# --- Counter -----------------------------------------------------------------

func _refresh_counter() -> void:
	var state := Game.state
	_clear(_counter)
	_counter.add_child(_title("Counter"))
	if not state.clock.is_open:
		_counter.add_child(_wrapped("The shop is closed."))
	elif state.customer.is_empty():
		_counter.add_child(_wrapped("Nobody at the counter right now. Someone will be along soon."))
	else:
		_add_customer_card()
	if _counter_news != "":
		var news := _wrapped(_counter_news)
		news.add_theme_font_size_override("font_size", 13)
		news.modulate = Color(0.25, 0.5, 0.35)
		_counter.add_child(news)

	_counter.add_child(HSeparator.new())
	_add_orders()
	_add_backorders()

	_counter.add_child(HSeparator.new())
	var appeal := _wrapped("Shop appeal: %d. Better and rarer fish on display bring customers more often." % roundi(state.shop_appeal()))
	appeal.add_theme_font_size_override("font_size", 13)
	appeal.modulate = Color(1, 1, 1, 0.7)
	_counter.add_child(appeal)


func _add_customer_card() -> void:
	var state := Game.state
	var c := state.customer
	var who: String = c["name"]
	var text := ""
	match c["kind"]:
		"fish":
			var f := state.inventory.get_fish(c["fish_id"])
			if f != null:
				text = "%s would love your %s %s (%s)." % [who, UI.sex_symbol(f), state.fish_display_name(f), UI.stars_text(f.stars)]
				var card := HBoxContainer.new()
				card.add_child(UI.fish_preview(f, state.species_of(f), Vector2(90, 46)))
				_counter.add_child(card)
		"item":
			text = "%s would like to buy some %s." % [who, Game.db.items[c["item_id"]]["name"]]
		"tank":
			text = "%s wants to buy your whole display tank, fish and all!" % who
		"request":
			var request: Dictionary = c["request"]
			text = "%s has a special request:\n\"%s\"\nPays the tank's value plus up to $%d bonus." % [
				who, RequestGenerator.describe(request, Game.db.species[request["species_id"]]), request["base_reward"]]
		"browse":
			text = "%s is just browsing, and says your shop is lovely." % who
		"wish_item":
			text = "%s is looking for %s, but you're out." % [who, Game.db.items[c["item_id"]]["name"]]
		"wish_fish":
			var strain: Dictionary = Game.db.strains[c["strain_id"]]
			text = "%s is looking for a %s %s (%s or better). You don't have one right now." % [
				who, "♂" if c["sex"] == Fish.MALE else "♀", strain["name"], UI.stars_text(int(strain["stars"]))]
	if state.customer_can_backorder():
		text += "\nOrder it in for them? They'll wait and pay $%d (10%% off)." % \
			Customers.backorder_price(state.wish_full_price(c), Game.db.economy["backorders"])
	_counter.add_child(_wrapped(text))

	var leaves_at: float = state.clock.minutes + c["patience"] - c["waited"]
	var wait := _wrapped("Happy to wait until about %s." % GameClock.format_minutes(leaves_at))
	wait.add_theme_font_size_override("font_size", 13)
	wait.modulate = Color(1, 1, 1, 0.7)
	_counter.add_child(wait)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var blocker := state.customer_blocker()
	match c["kind"]:
		"request":
			var accept := Button.new()
			accept.text = "Accept"
			accept.disabled = blocker != ""
			accept.tooltip_text = blocker
			accept.pressed.connect(_on_accept_request)
			buttons.add_child(accept)
			buttons.add_child(_decline_button("No thanks"))
		"browse":
			buttons.add_child(_decline_button("Wave goodbye"))
		"wish_item", "wish_fish":
			buttons.add_child(_backorder_button(blocker))
			buttons.add_child(_decline_button("Not today"))
		_:
			if state.customer_can_backorder():  # sold out while they waited
				buttons.add_child(_backorder_button(""))
			else:
				var sell := Button.new()
				sell.text = "Sell $%d" % state.customer_price()
				sell.disabled = blocker != ""
				sell.tooltip_text = blocker
				sell.pressed.connect(_on_serve)
				buttons.add_child(sell)
			buttons.add_child(_decline_button("Not today"))
	_counter.add_child(buttons)


func _backorder_button(blocker: String) -> Button:
	var b := Button.new()
	b.text = "Order it in"
	b.disabled = blocker != ""
	b.tooltip_text = blocker if blocker != "" else "Goes on your back-order list. Hand it over once you have it."
	b.pressed.connect(func():
		var who: String = Game.state.customer["name"]
		if Game.backorder_customer():
			_counter_news = "Ordered it in for %s. Hand it over from Back-orders once you have it." % who)
	return b


func _add_backorders() -> void:
	var state := Game.state
	if state.backorders.is_empty():
		return
	_counter.add_child(HSeparator.new())
	_counter.add_child(_label("Back-orders  %d/%d" % [state.backorders.size(), int(Game.db.economy["backorders"]["max"])]))
	for i in state.backorders.size():
		var order: Dictionary = state.backorders[i]
		var what := ""
		if order.has("item_id"):
			what = Game.db.items[order["item_id"]]["name"]
		else:
			var strain: Dictionary = Game.db.strains[order["strain_id"]]
			what = "%s %s (%s+)" % ["♂" if order["sex"] == Fish.MALE else "♀", strain["name"], UI.stars_text(int(strain["stars"]))]
		var line := _wrapped("• %s for %s" % [what, order["name"]])
		line.add_theme_font_size_override("font_size", 13)
		_counter.add_child(line)
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 4)
		var blocker := state.backorder_blocker(i)
		var hand := UI.small_button("Hand over $%d" % order["price"], blocker)
		hand.disabled = blocker != ""
		hand.pressed.connect(func():
			var earned := Game.fulfil_backorder(i)
			if earned > 0:
				_counter_news = "%s picked up their order: $%d." % [order["name"], earned]
				_refresh_counter())
		buttons.add_child(hand)
		var cancel := UI.small_button("Cancel", "No penalty.")
		cancel.pressed.connect(func(): Game.cancel_backorder(i))
		buttons.add_child(cancel)
		_counter.add_child(buttons)


func _decline_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		_counter_news = ""
		Game.decline_customer())
	return b


func _add_orders() -> void:
	var state := Game.state
	var max_orders := int(Game.db.economy["requests"]["max_orders"])
	_counter.add_child(_label("Orders  %d/%d" % [state.orders.size(), max_orders]))
	if state.orders.is_empty():
		var none := _wrapped("No orders. Request customers drop by now and then.")
		none.add_theme_font_size_override("font_size", 13)
		none.modulate = Color(1, 1, 1, 0.7)
		_counter.add_child(none)
	for i in state.orders.size():
		var order: Dictionary = state.orders[i]
		var text := _wrapped("• " + RequestGenerator.describe(order, Game.db.species[order["species_id"]]))
		text.add_theme_font_size_override("font_size", 13)
		_counter.add_child(text)
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 4)
		var preview := state.preview_delivery(i)
		var deliver := UI.small_button("Deliver tank → $%d" % preview["payout"] if not preview.is_empty() else "Deliver tank",
			"Build the tank on display, then deliver it. Better match, fish and looks = bigger bonus.")
		deliver.disabled = preview.is_empty()
		deliver.pressed.connect(_on_deliver.bind(i))
		buttons.add_child(deliver)
		var cancel := UI.small_button("Cancel", "No penalty.")
		cancel.pressed.connect(func(): Game.cancel_order(i))
		buttons.add_child(cancel)
		_counter.add_child(buttons)


func _on_serve() -> void:
	var c := Game.state.customer.duplicate()
	var earned := Game.serve_customer()
	if earned > 0:
		_counter_news = "Sold to %s for $%d." % [c["name"], earned]
		_refresh_counter()


func _on_accept_request() -> void:
	var who: String = Game.state.customer["name"]
	if Game.accept_customer_request():
		_counter_news = "Took %s's order. Build it in the display tank, then deliver it." % who


func _on_deliver(index: int) -> void:
	var r := Game.deliver_order(index)
	if r.is_empty():
		return
	_counter_news = "Delivered! Match %d%% · Fish %d%% · Looks %d%%\nTank $%d + bonus $%d = $%d" % [
		roundi(r["match"] * 100), roundi(r["quality"] * 100), roundi(r["looks"] * 100),
		r["tank_value"], r["bonus"], r["payout"]]
	_refresh_counter()


# --- Helpers -----------------------------------------------------------------

func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _wrapped(text: String) -> Label:
	var l := _label(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	return l


func _title(text: String) -> Label:
	var l := _label(text)
	l.add_theme_font_size_override("font_size", 20)
	return l
