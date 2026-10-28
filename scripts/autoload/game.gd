extends Node
## Global access point for the UI (autoloaded as `Game`).
## Owns the GameState and drives the shop clock. Scenes read `Game.state` and
## call methods here; the core logic in scripts/core never touches Nodes.

## Stock, money, tanks or fish changed. Views should refresh.
signal changed
## The in-game time moved forward.
signal clock_ticked
## The shop closed and the night ran. `summary` comes from GameState.end_day().
signal day_ended(summary: Dictionary)
## A new day began and the shop is open.
signal day_started
## Someone arrived at, or left, the counter.
signal customer_changed
## A new customer just walked in (rings the shop bell).
signal customer_arrived

## Debug builds only: hold F to run the clock this many times faster.
const FAST_FORWARD := 20.0

var db: DataDB
var state: GameState
var _pause_requests: int = 0


func _ready() -> void:
	_add_symbol_font()
	db = DataDB.load_from_dir("res://data")
	for e in db.errors:
		push_error("Game data: " + e)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	state = GameState.new_game(db, rng)


func _process(delta: float) -> void:
	var clock := state.clock
	if not clock.is_open:
		return
	var speed := 1.0
	if OS.is_debug_build() and Input.is_key_pressed(KEY_F):
		speed = FAST_FORWARD
	var minutes := clock.advance(delta * speed)
	if minutes > 0.0:
		clock_ticked.emit()
		if state.tick_customers(minutes):
			customer_changed.emit()
			if not state.customer.is_empty():
				customer_arrived.emit()
	if not clock.is_open:
		_finish_day()  # reached the hard-close hour


## The default UI font lacks ★ ☆ ♂ ♀ and friends. Desktop builds borrow them
## from system fonts, but web builds can only use bundled fonts, so add
## DejaVu Sans (free licence, see assets/fonts) as a fallback everywhere.
func _add_symbol_font() -> void:
	var symbols: Font = load("res://assets/fonts/DejaVuSans.ttf")
	var base := ThemeDB.fallback_font
	if symbols == null or base == null:
		return
	var fallbacks := base.fallbacks.duplicate()
	fallbacks.append(symbols)
	base.fallbacks = fallbacks


func can_close_shop() -> bool:
	return state.clock.can_close()


func close_shop() -> bool:
	if not state.clock.close_shop():
		return false
	_finish_day()
	return true


func open_next_day() -> void:
	state.open_day()
	customer_changed.emit()
	day_started.emit()
	changed.emit()
	clock_ticked.emit()


## Menus call push_pause() when they open and pop_pause() when they close.
## The clock stays paused while any menu is open.
func push_pause() -> void:
	_pause_requests += 1
	state.clock.paused = true


func pop_pause() -> void:
	_pause_requests = maxi(_pause_requests - 1, 0)
	state.clock.paused = _pause_requests > 0


func notify_changed() -> void:
	changed.emit()


# --- Player actions (each one emits `changed` when it worked) -----------------

func buy_strain(strain_id: String, sex: String) -> Fish:
	var f := state.buy_strain(strain_id, sex)
	if f != null:
		changed.emit()
	return f


func move_fish(fish_id: int, to: String) -> bool:
	var ok := state.move_fish(fish_id, to)
	if ok:
		changed.emit()
	return ok


func sell_fish_wholesale(fish_id: int) -> int:
	var earned := state.sell_fish_wholesale(fish_id)
	if earned > 0:
		changed.emit()
	return earned


func _finish_day() -> void:
	var summary := state.end_day()
	changed.emit()
	customer_changed.emit()
	day_ended.emit(summary)


func serve_customer() -> int:
	var earned := state.serve_customer()
	if earned > 0:
		changed.emit()
		customer_changed.emit()
	return earned


func accept_customer_request() -> bool:
	var ok := state.accept_customer_request()
	if ok:
		changed.emit()
		customer_changed.emit()
	return ok


func decline_customer() -> void:
	state.decline_customer()
	customer_changed.emit()


func deliver_order(order_index: int) -> Dictionary:
	var result := state.deliver_order(order_index)
	if not result.is_empty():
		changed.emit()
	return result


func cancel_order(order_index: int) -> void:
	if state.cancel_order(order_index):
		changed.emit()


func install_display_tank(tank_item_id: String) -> bool:
	var ok := state.install_display_tank(tank_item_id)
	if ok:
		changed.emit()
	return ok


func buy_item(item_id: String, qty: int = 1) -> bool:
	var ok := state.buy_item(item_id, qty)
	if ok:
		changed.emit()
	return ok


func backorder_customer() -> bool:
	var ok := state.backorder_customer()
	if ok:
		changed.emit()
		customer_changed.emit()
	return ok


func fulfil_backorder(index: int) -> int:
	var earned := state.fulfil_backorder(index)
	if earned > 0:
		changed.emit()
	return earned


func cancel_backorder(index: int) -> void:
	if state.cancel_backorder(index):
		changed.emit()


# --- Aquascaping (tank is a location: Fish.DISPLAY or a breeding tank) -------

func place_item(location: String, slot: int, item_id: String) -> bool:
	return _changed_if(state.place_item(state.tank_at(location), slot, item_id))


func take_item(location: String, slot: int) -> bool:
	return _changed_if(state.tank_at(location) != null and state.take_item(state.tank_at(location), slot))


func set_substrate(location: String, item_id: String) -> bool:
	return _changed_if(state.set_substrate(state.tank_at(location), item_id))


func take_substrate(location: String) -> bool:
	return _changed_if(state.tank_at(location) != null and state.take_substrate(state.tank_at(location)))


func _changed_if(ok: bool) -> bool:
	if ok:
		changed.emit()
	return ok


func buy_breeding_tank() -> bool:
	return _changed_if(state.buy_breeding_tank())


func breed_order_for_customer() -> bool:
	var ok := state.breed_order_for_customer()
	if ok:
		changed.emit()
		customer_changed.emit()
	return ok
