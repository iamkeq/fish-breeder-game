extends Control
## Top bar (day, clock, money), switching between rooms, the overlays
## (Market, tank editor, end-of-day summary) and the shop-door bell.

const DaySummary := preload("res://scenes/ui/day_summary.gd")
const TankEditor := preload("res://scenes/ui/tank_editor.gd")
const ShopBell := preload("res://scenes/ui/shop_bell.gd")
const BreedingBook := preload("res://scenes/ui/breeding_book.gd")
const OrdersRoom := preload("res://scenes/orders_room.gd")
const Goals := preload("res://scenes/ui/goals.gd")
const NewGame := preload("res://scenes/ui/new_game.gd")
const NameFish := preload("res://scenes/ui/name_fish.gd")
const Lab := preload("res://scenes/ui/lab.gd")
const FishShow := preload("res://scenes/ui/fish_show.gd")
const Gallery := preload("res://scenes/ui/gallery.gd")
const StaffScreen := preload("res://scenes/ui/staff.gd")

const SHOP_FLOOR_TEXT := "Shop floor"
const BELL_TEXT := "● Shop floor"

@onready var _day_label: Label = %DayLabel
@onready var _clock_label: Label = %ClockLabel
@onready var _money_label: Label = %MoneyLabel
@onready var _shop_button: Button = %ShopButton
@onready var _back_room_button: Button = %BackRoomButton
@onready var _close_button: Button = %CloseButton
@onready var _shop_floor: Control = %ShopFloor
@onready var _back_room: Control = %BackRoom
@onready var _hint: Label = %Hint
@onready var _market_button: Button = %MarketButton
@onready var _fish_market: ColorRect = %FishMarket
@onready var _restock_button: Button = %RestockButton
@onready var _orders_button: Button = %OrdersButton

var _tank_editor: ColorRect
var _day_summary: ColorRect
var _bell: AudioStreamPlayer
var _ding: AudioStreamPlayer
var _book: ColorRect
var _name_box: ColorRect
var _lab: ColorRect
var _fish_show: ColorRect
var _gallery: ColorRect
var _staff: ColorRect
## The show number the morning reminder was last shown for.
var _show_reminded := 0
var _orders_room: Control
var _goals: ColorRect
var _goals_button: Button
var _pause_button: Button
var _fullscreen_button: Button
var _rep_label: Label
var _toast: PanelContainer
var _toast_label: Label
var _toast_time := 0.0


func _ready() -> void:
	_tank_editor = TankEditor.new()
	add_child(_tank_editor)
	_orders_room = OrdersRoom.new()
	_orders_room.visible = false
	_shop_floor.get_parent().add_child(_orders_room)
	_book = BreedingBook.new()
	add_child(_book)
	_goals = Goals.new()
	add_child(_goals)
	_name_box = NameFish.new()
	add_child(_name_box)
	Game.name_requested.connect(func(fish_id: int): _name_box.open(fish_id))
	_lab = Lab.new()
	add_child(_lab)
	Game.lab_requested.connect(func(): _lab.open())
	_fish_show = FishShow.new()
	add_child(_fish_show)
	Game.fish_show_requested.connect(func(): _fish_show.open())
	_gallery = Gallery.new()
	add_child(_gallery)
	Game.gallery_requested.connect(func(): _gallery.open())
	_staff = StaffScreen.new()
	add_child(_staff)
	Game.staff_requested.connect(func(): _staff.open())
	Game.day_started.connect(_remind_about_show)
	Game.day_started.connect(_announce_deliveries)
	_goals_button = Button.new()
	_goals_button.pressed.connect(func(): _goals.open())
	_market_button.add_sibling(_goals_button)
	_pause_button = Button.new()
	_pause_button.toggle_mode = true
	_pause_button.focus_mode = Control.FOCUS_NONE  # so Space isn't eaten by the button
	_pause_button.pressed.connect(Game.toggle_pause)
	_clock_label.add_sibling(_pause_button)
	_fullscreen_button = Button.new()
	_fullscreen_button.focus_mode = Control.FOCUS_NONE
	_fullscreen_button.pressed.connect(_toggle_fullscreen)
	_close_button.add_sibling(_fullscreen_button)
	_rep_label = Label.new()
	_rep_label.mouse_filter = Control.MOUSE_FILTER_STOP  # so the tooltip shows
	_rep_label.add_theme_font_size_override("font_size", 18)
	_money_label.add_sibling(_rep_label)
	_build_toast()
	_day_summary = DaySummary.new()
	add_child(_day_summary)
	_bell = AudioStreamPlayer.new()
	_bell.stream = ShopBell.make_stream()
	add_child(_bell)
	_ding = AudioStreamPlayer.new()
	_ding.stream = ShopBell.make_ding()
	add_child(_ding)
	if Game.needs_setup:
		var setup := NewGame.new()
		add_child(setup)  # on top of everything: you must pick a start
		setup.open()

	var rooms := ButtonGroup.new()
	_shop_button.button_group = rooms
	_back_room_button.button_group = rooms
	_orders_button.button_group = rooms
	_shop_button.button_pressed = true
	_shop_button.pressed.connect(_show_room.bind(_shop_floor))
	_back_room_button.pressed.connect(_show_room.bind(_back_room))
	_orders_button.pressed.connect(_show_room.bind(_orders_room))
	_orders_room.edit_requested.connect(func(loc: String): _tank_editor.open(loc))
	_shop_floor.orders_room_requested.connect(func():
		_orders_button.button_pressed = true
		_show_room(_orders_room))
	_close_button.pressed.connect(_on_close_pressed)
	_market_button.pressed.connect(func(): _fish_market.open())
	_shop_floor.edit_tank_requested.connect(func(): _tank_editor.open())
	_back_room.book_requested.connect(func(): _book.open())
	_restock_button.toggled.connect(func(on: bool): Game.set_restocking(on))
	_restock_button.visible = Game.state.restock_speed() > 0.0
	_restock_button.tooltip_text = "Closed for restock: no customers, and the clock runs %dx faster so breeding builds up stock. Stays on until you press Reopen." % int(Game.state.restock_speed())

	Game.clock_ticked.connect(_update_top_bar)
	Game.changed.connect(_update_top_bar)
	Game.day_ended.connect(_on_day_ended)
	Game.customer_arrived.connect(_on_customer_arrived)
	Game.auto_sale.connect(_on_auto_sale)
	Game.customer_changed.connect(_update_bell_badge)
	Game.goals_reached.connect(_on_goals_reached)
	Game.reputation_level_up.connect(func(_level: int, level_name: String):
		_show_toast("★ Your shop is now %s!" % level_name))
	if Game.loaded_from_save:
		_show_toast("Welcome back! Your shop is just as you left it.")
		_announce_deliveries()

	_hint.visible = OS.is_debug_build()
	_update_top_bar()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		Game.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()


func _is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Full screen on and off (the button or F11). In the browser this has to come
## from a click or key press, which it always does here.
func _toggle_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if _is_fullscreen()
		else DisplayServer.WINDOW_MODE_FULLSCREEN)
	_update_fullscreen_button.call_deferred()


func _update_fullscreen_button() -> void:
	_fullscreen_button.text = "Exit full screen" if _is_fullscreen() else "Full screen"
	_fullscreen_button.tooltip_text = "Fill the whole screen (F11)."


## The browser can leave full screen on its own (Esc), so keep the label honest.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED and _fullscreen_button != null:
		_update_fullscreen_button()


func _show_room(room: Control) -> void:
	_shop_floor.visible = room == _shop_floor
	_back_room.visible = room == _back_room
	_orders_room.visible = room == _orders_room
	_update_bell_badge()


func _update_top_bar() -> void:
	var state := Game.state
	_day_label.text = "Day %d" % state.day
	_clock_label.text = state.clock.time_string() if state.clock.is_open else "Closed"
	if Game.manual_paused and state.clock.is_open:
		_clock_label.text += "  (paused)"
	_pause_button.set_pressed_no_signal(Game.manual_paused)
	_pause_button.text = "Resume" if Game.manual_paused else "Pause"
	_pause_button.tooltip_text = "Stop the clock so you can think (Space). Everything still works while paused."
	_update_fullscreen_button()
	if state.restocking:
		_clock_label.text += "  ×%d" % int(state.restock_speed())
	_restock_button.set_pressed_no_signal(state.restocking)
	_restock_button.text = "Reopen" if state.restocking else "Restock"
	_money_label.text = "$%d" % state.money
	_rep_label.text = "★ Lv %d" % (state.reputation_level() + 1)
	var next := state.reputation_next()
	_rep_label.tooltip_text = "Shop reputation: %s
%d points%s" % [state.reputation_level_name(), state.reputation,
		"" if next.is_empty() else "
Next: %s at %d" % [next["name"], int(next["points"])]]
	_orders_button.text = "Orders (%d)" % state.orders.size() if not state.orders.is_empty() else "Orders"
	_goals_button.text = "Goals"
	_goals_button.tooltip_text = "%d of %d goals reached" % [state.completed_goals.size(), Game.db.goals.size()]
	var can_close := Game.can_close_shop()
	_close_button.disabled = not can_close
	_close_button.tooltip_text = "" if can_close else \
		"You can close from %s." % GameClock.format_minutes(state.clock.earliest_close_minutes())


## Ring the bell if you can't see the counter (back room, or a menu is open).
func _on_customer_arrived() -> void:
	if not _shop_floor.visible or _fish_market.visible or _tank_editor.visible:
		_bell.play()
	_update_bell_badge()


## A shelf item sold itself: a soft ding and a toast.
func _on_auto_sale(item_name: String, price: int) -> void:
	_ding.play()
	_show_toast("Sold %s from the shelf  +$%d" % [item_name, price])


## "● Shop floor" while someone waits at the counter and you're elsewhere.
func _update_bell_badge() -> void:
	var waiting := not Game.state.customer.is_empty()
	_shop_button.text = BELL_TEXT if waiting and not _shop_floor.visible else SHOP_FLOOR_TEXT


## A small note at the bottom of the screen that fades away by itself.
func _build_toast() -> void:
	var strip := CenterContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -110
	strip.offset_bottom = -24
	add_child(strip)
	_toast = PanelContainer.new()
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)
	strip.add_child(_toast)


func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.modulate.a = 1.0
	_toast.visible = true
	_toast_time = 5.0


func _process(delta: float) -> void:
	if _toast_time <= 0.0:
		return
	_toast_time -= delta
	_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	_toast.visible = _toast_time > 0.0


## "Delivery: 10 fish food, 2 treasure chests" when standing orders arrive.
func _announce_deliveries() -> void:
	var parts := PackedStringArray()
	for d in Game.state.last_deliveries:
		parts.append("%d %s" % [int(d["quantity"]), str(d["name"]).to_lower()])
	if parts.is_empty():
		return
	var text := "Delivery: " + ", ".join(parts)
	if _toast_time > 0.0:
		text = _toast_label.text + "
" + text
	_show_toast(text)


## On show day morning: a nudge, once per show, if you could still enter.
func _remind_about_show() -> void:
	var state := Game.state
	if not state.shows_unlocked() or state.show_entry_fish() != null:
		return
	var show := state.next_show()
	if int(show["days_left"]) != 0 or int(show["number"]) == _show_reminded or not state.has_show_candidate():
		return
	_show_reminded = int(show["number"])
	_show_toast("Fish show tonight! Enter a fish in the %s (back room)." % show["name"])


func _on_goals_reached(goals: Array) -> void:
	var lines := PackedStringArray()
	for g in goals:
		lines.append("★ Goal reached: %s  (+$%d)" % [g["name"], int(g["reward"])])
	_show_toast("\n".join(lines))


func _on_close_pressed() -> void:
	Game.close_shop()


func _on_day_ended(summary: Dictionary) -> void:
	_fish_market.close()
	_tank_editor.close()
	_book.close()
	_goals.close()
	_name_box.close()
	_lab.close()
	_fish_show.close()
	_gallery.close()
	_staff.close()
	_day_summary.show_summary(summary)
	_update_top_bar()
