extends Control
## Orders room: one column per accepted customer request, each with its own
## order tank built separately from the display tank. Set it up (uses an empty
## tank from stock), decorate it and add fish in the editor, then deliver it.

const UI := preload("res://scenes/ui/ui_kit.gd")
const TankViewScene := preload("res://scenes/tank_view.tscn")

## Ask the main scene to open the tank editor on an order tank.
signal edit_requested(location: String)

var _columns: HBoxContainer
var _news: Label
## Tank views kept per order id, so fish don't jump around on every refresh.
var _views: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := Label.new()
	title.text = "Special orders"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Build each order in its own tank here, or deliver your display tank from the counter instead."
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)
	_columns = HBoxContainer.new()
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_theme_constant_override("separation", 14)
	box.add_child(_columns)
	_news = Label.new()
	_news.add_theme_font_size_override("font_size", 14)
	_news.modulate = Color(0.25, 0.5, 0.35)
	box.add_child(_news)
	Game.changed.connect(refresh)
	refresh()


func refresh() -> void:
	var state := Game.state
	var live_ids := []
	for order in state.orders:
		live_ids.append(order["id"])
	for id in _views.keys():
		if not id in live_ids or state.order_tank(state.order_index_by_id(id)) == null:
			_views[id].queue_free()
			_views.erase(id)
	for child in _columns.get_children():
		for view in _views.values():
			if view.get_parent() != null and view.get_parent().get_parent() == child:
				view.get_parent().remove_child(view)
		child.queue_free()
	var max_orders := int(Game.db.economy["requests"]["max_orders"])
	for i in max_orders:
		_columns.add_child(_order_column(i) if i < state.orders.size() else _empty_column())


func _order_column(i: int) -> Control:
	var state := Game.state
	var order: Dictionary = state.orders[i]
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(_text("Order for %s" % order.get("customer", "a customer"), 18))
	var wants := _text(RequestGenerator.describe(order, Game.db.species[order["species_id"]]), 14)
	wants.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(wants)
	var reward := _text("Pays the tank's value plus up to $%d bonus." % order["base_reward"], 12)
	reward.modulate = Color(1, 1, 1, 0.7)
	box.add_child(reward)

	var tank := state.order_tank(i)
	if tank == null:
		var empty := _text("No tank set up yet.", 14)
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(empty)
		var blocker := state.order_tank_blocker(i)
		var spare := state.spare_tank_item()
		var label := "Set up order tank" + (" (uses a %s)" % Game.db.items[spare]["name"] if spare != "" else "")
		var start := Button.new()
		start.text = label
		start.disabled = blocker != ""
		start.tooltip_text = blocker
		start.pressed.connect(func():
			if Game.start_order_tank(i):
				edit_requested.emit(Fish.order_location(order["id"])))
		box.add_child(start)
		if blocker != "":
			var why := _text(blocker, 12)
			why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			why.modulate = Color(0.75, 0.4, 0.2)
			box.add_child(why)
	else:
		var view: Control = _views.get(order["id"])
		if view == null:
			view = TankViewScene.instantiate()
			view.location = Fish.order_location(order["id"])
			_views[order["id"]] = view
		view.custom_minimum_size = Vector2(0, 220)
		box.add_child(view)
		var p := state.preview_delivery(i, true)
		var score := _text("Looks %d/100 · %d/%d fish · match %d%%" % [state.tank_aesthetics(tank),
			tank.fish_ids.size(), order["fish_count"], roundi(p["match"] * 100)], 13)
		box.add_child(score)
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 6)
		var edit := Button.new()
		edit.text = "Edit tank"
		edit.pressed.connect(func(): edit_requested.emit(Fish.order_location(order["id"])))
		buttons.add_child(edit)
		var deliver := Button.new()
		deliver.text = "Deliver → $%d" % p["payout"]
		deliver.tooltip_text = "Tank $%d + bonus $%d" % [p["tank_value"], p["bonus"]]
		deliver.pressed.connect(_on_deliver.bind(i, order.get("customer", "the customer")))
		buttons.add_child(deliver)
		box.add_child(buttons)

	var cancel := UI.small_button("Cancel order", "No penalty. A started tank, its decorations and fish go back to your stock.")
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cancel.pressed.connect(func():
		_news.text = "Cancelled %s's order. Everything went back to your stock." % order.get("customer", "the")
		Game.cancel_order(i))
	box.add_child(cancel)
	return panel


func _empty_column() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.modulate = Color(1, 1, 1, 0.55)
	var l := _text("Free order slot.\nRequest customers drop by the counter now and then.", 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(l)
	return panel


func _on_deliver(i: int, who: String) -> void:
	var r := Game.deliver_order(i, true)
	if r.is_empty():
		return
	_news.text = "Delivered to %s! Match %d%% · Fish %d%% · Looks %d%% → tank $%d + bonus $%d = $%d" % [
		who, roundi(r["match"] * 100), roundi(r["quality"] * 100), roundi(r["looks"] * 100),
		r["tank_value"], r["bonus"], r["payout"]]


func _text(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l
