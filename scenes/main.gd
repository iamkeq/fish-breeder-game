extends Control
## Top bar (day, clock, money), switching between rooms, the overlays
## (Market, tank editor, end-of-day summary) and the shop-door bell.

const DaySummary := preload("res://scenes/ui/day_summary.gd")
const TankEditor := preload("res://scenes/ui/tank_editor.gd")
const ShopBell := preload("res://scenes/ui/shop_bell.gd")

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

var _tank_editor: ColorRect
var _day_summary: ColorRect
var _bell: AudioStreamPlayer


func _ready() -> void:
	_tank_editor = TankEditor.new()
	add_child(_tank_editor)
	_day_summary = DaySummary.new()
	add_child(_day_summary)
	_bell = AudioStreamPlayer.new()
	_bell.stream = ShopBell.make_stream()
	add_child(_bell)

	var rooms := ButtonGroup.new()
	_shop_button.button_group = rooms
	_back_room_button.button_group = rooms
	_shop_button.button_pressed = true
	_shop_button.pressed.connect(_show_room.bind(_shop_floor))
	_back_room_button.pressed.connect(_show_room.bind(_back_room))
	_close_button.pressed.connect(_on_close_pressed)
	_market_button.pressed.connect(func(): _fish_market.open())
	_shop_floor.edit_tank_requested.connect(func(): _tank_editor.open())

	Game.clock_ticked.connect(_update_top_bar)
	Game.changed.connect(_update_top_bar)
	Game.day_ended.connect(_on_day_ended)
	Game.customer_arrived.connect(_on_customer_arrived)
	Game.customer_changed.connect(_update_bell_badge)

	_hint.visible = OS.is_debug_build()
	_update_top_bar()


func _show_room(room: Control) -> void:
	_shop_floor.visible = room == _shop_floor
	_back_room.visible = room == _back_room
	_update_bell_badge()


func _update_top_bar() -> void:
	var state := Game.state
	_day_label.text = "Day %d" % state.day
	_clock_label.text = state.clock.time_string() if state.clock.is_open else "Closed"
	_money_label.text = "$%d" % state.money
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


func _on_close_pressed() -> void:
	Game.close_shop()


func _on_day_ended(summary: Dictionary) -> void:
	_fish_market.close()
	_tank_editor.close()
	_day_summary.show_summary(summary)
	_update_top_bar()
