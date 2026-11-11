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
## One or more goals were just reached (entries from data/goals.json).
signal goals_reached(goals: Array)
## The shop just reached a new reputation level (0-based index and its name).
signal reputation_level_up(level: int, level_name: String)
## A screen wants the "name your fish" box opened for this fish.
signal name_requested(fish_id: int)

var save_path := "user://save.json"

## Debug builds only: hold F to run the clock this many times faster.
const FAST_FORWARD := 20.0

var db: DataDB
var state: GameState
var _pause_requests: int = 0
## Whether this run loads and writes the save file. Off for headless runs and
## scripted tools (tests, screenshots), so they never touch a real save.
var persist: bool = true
## True if this run carried on from a save (for the "welcome back" note).
var loaded_from_save: bool = false
## True until the player has picked a starting pair and mode (a real run with
## no save). The clock stays paused and the new-game screen shows. Never true
## for headless or scripted runs, which start the standard game as before.
var needs_setup: bool = false


func _ready() -> void:
	_add_symbol_font()
	db = DataDB.load_from_dir("res://data")
	for e in db.errors:
		push_error("Game data: " + e)
	var args := OS.get_cmdline_args()
	persist = DisplayServer.get_name() != "headless" and not ("-s" in args or "--script" in args)
	state = _load_saved()
	loaded_from_save = state != null
	if state == null:
		state = GameState.new_game(db, _new_rng())
		if persist:
			_wait_for_setup()
	changed.connect(_check_goals)


func _new_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng


## The saved game, or null if there isn't a usable one.
func _load_saved() -> GameState:
	if not persist:
		return null
	var data := SaveFile.read(save_path)
	if data.is_empty():
		return null
	var loaded := GameState.from_dict(db, _new_rng(), data)
	if loaded == null:
		push_warning("Save file couldn't be used; starting a new game.")
	return loaded


## Writes the save. Called at the end of every day, once the night has run.
## Never writes a game the player hasn't started yet.
func save_game() -> bool:
	return persist and not needs_setup and SaveFile.write(save_path, state.to_dict())


## Holds the placeholder game still until the player picks how to start.
func _wait_for_setup() -> void:
	needs_setup = true
	_pause_requests = 1
	state.clock.paused = true


## Wipes the save and goes back to the new-game screen (the placeholder game
## underneath is replaced when the player presses Start). Runs without a save
## (headless, scripts) just start the standard game again.
func new_game() -> void:
	if persist and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	state = GameState.new_game(db, _new_rng())
	loaded_from_save = false
	_pause_requests = 0
	needs_setup = false
	if persist:
		_wait_for_setup()
	get_tree().reload_current_scene()


## Starts the game the player chose on the new-game screen (ids from
## data/new_game.json) and reloads the scene.
func start_new_game(start_id: String, challenge_id: String) -> void:
	state = GameState.new_game(db, _new_rng(), {"start_id": start_id, "challenge_id": challenge_id})
	loaded_from_save = false
	needs_setup = false
	_pause_requests = 0
	get_tree().reload_current_scene()


## Runs after anything changes: pays out goals that were just reached.
func _check_goals() -> void:
	var reached := state.check_goals()
	if not reached.is_empty():
		goals_reached.emit(reached)
		changed.emit()  # money went up
	var level := state.take_level_up()
	if level >= 0:
		reputation_level_up.emit(level, state.reputation_levels()[level]["name"])


func _process(delta: float) -> void:
	var clock := state.clock
	if not clock.is_open:
		return
	var speed := state.time_scale()
	if OS.is_debug_build() and Input.is_key_pressed(KEY_F):
		speed *= FAST_FORWARD
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


func rename_fish(fish_id: int, nickname: String) -> bool:
	var ok := state.rename_fish(fish_id, nickname)
	if ok:
		changed.emit()
	return ok


func set_favorite(fish_id: int, value: bool) -> bool:
	var ok := state.set_favorite(fish_id, value)
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
	save_game()
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


## Delivers an order: its own order tank, or (from_order_tank = false) the display tank.
func deliver_order(order_index: int, from_order_tank: bool = false) -> Dictionary:
	var result := state.deliver_order(order_index, from_order_tank)
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


func buy_upgrade(upgrade_id: String) -> bool:
	return _changed_if(state.buy_upgrade(upgrade_id))


func breed_order_for_customer() -> bool:
	var ok := state.breed_order_for_customer()
	if ok:
		changed.emit()
		customer_changed.emit()
	return ok


## "Closed for restock": no customers, clock runs faster (for playtesting breeding).
func set_restocking(on: bool) -> bool:
	var ok := state.set_restocking(on)
	if ok:
		changed.emit()
		customer_changed.emit()
		clock_ticked.emit()
	return ok


func start_order_tank(order_index: int) -> bool:
	return _changed_if(state.start_order_tank(order_index))
