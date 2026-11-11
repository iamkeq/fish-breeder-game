extends Control
## Top bar (day, clock, money), switching between rooms, the overlays
## (Market, tank editor, end-of-day summary) and the shop-door bell.

const DaySummary := preload("res://scenes/ui/day_summary.gd")
const TankEditor := preload("res://scenes/ui/tank_editor.gd")
const ShopBell := preload("res://scenes/ui/shop_bell.gd")
const BreedingBook := preload("res://scenes/ui/breeding_book.gd")
const OrdersRoom := preload("res://scenes/orders_room.gd")
const Goals := preload("res://scenes/ui/goals.gd")

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
var _book: ColorRect
var _orders_room: Control
var _goals: ColorRect
var _goals_button: Button
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
	_goals_button = Button.new()
	_goals_button.pressed.connect(func(): _goals.open())
	_market_button.add_sibling(_goals_button)
	_build_toast()
	_day_summary = DaySummary.new()
	add_child(_day_summary)
	_bell = AudioStreamPlayer.new()
	_bell.stream = ShopBell.make_stream()
	add_child(_bell)

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
	Game.customer_changed.connect(_update_bell_badge)
	Game.goals_reached.connect(_on_goals_reached)
	if Game.loaded_from_save:
		_show_toast("Welcome back! Your shop is just as you left it.")

	_hint.visible = OS.is_debug_build()
	_update_top_bar()


func _show_room(room: Control) -> void:
	_shop_floor.visible = room == _shop_floor
	_back_room.visible = room == _back_room
	_orders_room.visible = room == _orders_room
	_update_bell_badge()


func _update_top_bar() -> void:
	var state := Game.state
	_day_label.text = "Day %d" % state.day
	_clock_label.text = state.clock.time_string() if state.clock.is_open else "Closed"
	if state.restocking:
		_clock_label.text += "  ×%d" % int(state.restock_speed())
	_restock_button.set_pressed_no_signal(state.restocking)
	_restock_button.text = "Reopen" if state.restocking else "Restock"
	_money_label.text = "$%d" % state.money
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
	_day_summary.show_summary(summary)
	_update_top_bar()
