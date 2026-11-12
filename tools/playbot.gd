extends SceneTree
## Headless balance-testing "play bot". It plays N in-game days using only the
## game's public GameState rules (no poking state, no save file) and prints a
## CSV line per day plus a summary of where money came from and went.
##
##   godot --headless --path . -s res://tools/playbot.gd -- \
##       --days=60 --seed=1 --start=red_yellow --challenge=standard --style=casual
##
## Output lines: HEADER/DAY (one per day), WARN (anomalies), SUMMARY (end), RECON.
##
## STYLES (what each simulated player does)
##   casual    A sensible casual player. Keeps the starting pair breeding (one
##             sire, one mother per tank), moves every new adult out so
##             customers can buy it, puts the best adults on display, hangs
##             decorations it owns (buys a few when money is comfortable), keeps
##             food stocked, buys breeding tanks 2 and 3, one cheap upgrade at
##             a time when money is comfortable, accepts orders and wished-for
##             bred fish, fills orders and back-orders when the stock is there,
##             enters the best eligible fish in each show (it is free), hires
##             a feeder when rich. No Lab, no favourites, no recipe chasing.
##             Sells everything it is asked for except the whole display tank.
##   optimizer A strong player. Buys breeding tanks asap, then upgrades in value
##             order, runs 1 sire + 3 mothers per tank, keeps the highest-star
##             fish as breeders, dedicates tanks 2-4 to chasing undiscovered
##             recipes (buying missing parent strains), scans breeders in the
##             Lab, enters the best fish in every show (scanning for the pure
##             line class), favourites its breeders and pins gallery portraits,
##             hires staff when unlocked, always fills orders and back-orders,
##             breed-orders instead of selling bought fish at a loss.
##   lazy      Only feeds fish, moves new adults to holding and sells what
##             customers ask for. Never invests, never decorates, declines
##             orders and back-orders. A floor: does the game still work?
##
## Optional --tanks=sell: any style also sells the display tank to every tank
## customer and rebuilds it at once (the default is to decline them).
##
## All money is attributed to a source by measuring money around each call, so
## the accounting does not depend on the game's own bookkeeping.

const STEP_MINUTES := 5.0
const CUSTOMER_SOURCE := {"fish": "fish_sales", "item": "item_sales", "tank": "tank_sales",
	"collector": "collector_sales"}
const INCOME_SOURCES := ["fish_sales", "item_sales", "collector_sales", "tank_sales", "special_orders",
	"back_orders", "wholesale", "show_prizes", "goal_rewards", "book_rewards"]
const SPEND_CATEGORIES := ["market_fish", "food", "items", "upgrades", "breeding_tanks", "lab_scans",
	"staff_hires", "wages", "staff_purchases", "standing_orders"]
const CHECKPOINT_DAYS := [10, 20, 30, 45, 60, 80, 100]

var db: DataDB
var s: GameState
var brng := RandomNumberGenerator.new()  # the bot's own dice (distraction)
var style := "casual"
var days := 60
var seed_value := 1
var start_id := "red_yellow"
var challenge_id := "standard"
var sell_tanks := false  # --tanks=sell: sell the display tank to tank customers and rebuild it

var start_money := 0
var income := {}
var spend := {}
var order_age := {}      # order id -> day accepted
var backorder_age := {}  # back-order object id -> day taken (see _bo_key)
var rep_level_day := {}
var checkpoints := {}
var goal_day := {}
var zero_streak := 0
var max_zero_streak := 0
var customers_by_kind := {}
var declined_by_kind := {}
var starved_days := 0


func _initialize() -> void:
	_read_args()
	db = DataDB.load_from_dir("res://data")
	for e in db.errors:
		print("ERR,data,%s" % e)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	brng.seed = seed_value * 7919 + 13
	s = GameState.new_game(db, rng, {"start_id": start_id, "challenge_id": challenge_id})
	start_money = s.money
	for k in INCOME_SOURCES:
		income[k] = 0
	for k in SPEND_CATEGORIES:
		spend[k] = 0
	print("CONFIG,style=%s,days=%d,seed=%d,start=%s,challenge=%s" % [style, days, seed_value, start_id, challenge_id])
	print("HEADER,day,money,earned_today,fish_total,adults,avg_adult_stars,breeding_tanks,reputation_points,"
		+ "reputation_level,upgrades_owned,goals_done,customers_served,walked_out,recipes_found")
	_goals()
	for i in days:
		_play_day()
	_summary()
	quit(0)


func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not "=" in arg:
			continue
		var parts := arg.trim_prefix("--").split("=", true, 1)
		match parts[0]:
			"days": days = int(parts[1])
			"seed": seed_value = int(parts[1])
			"start": start_id = parts[1]
			"challenge": challenge_id = parts[1]
			"style": style = parts[1]
			"tanks": sell_tanks = parts[1] == "sell"


# --- The day ------------------------------------------------------------------

func _play_day() -> void:
	var day := s.day
	var stats_before := s.stats.duplicate()
	_morning()
	_run_shop()
	_evening()
	var money_before_night := s.money
	var earned := s.earned_today
	var served := s.stat("customers_served") - int(stats_before.get("customers_served", 0))
	var walked := s.stat("walked_out") - int(stats_before.get("walked_out", 0))
	_night()
	_report_day(day, earned, served, walked, money_before_night)
	if day in CHECKPOINT_DAYS:
		checkpoints[day] = s.money
	s.open_day()


## Ticks the clock in small steps until the shop closes at the hard-close hour
## (the same as Game._process), handling each customer as they arrive.
func _run_shop() -> void:
	var step_seconds := STEP_MINUTES * s.clock.real_seconds_per_hour / 60.0
	var guard := 0
	while s.clock.is_open and guard < 1000:
		guard += 1
		var minutes := s.clock.advance(step_seconds)
		if minutes <= 0.0:
			break
		# Shelf items sell themselves inside the tick (and may set off standing
		# orders), so book both sides the way _act() does.
		var spent_before := s.stat("total_spent")
		var arrived := s.tick_customers(minutes)
		for sale in s.auto_sales:
			_add(income, "item_sales", int(sale["price"]))
		s.auto_sales.clear()
		_add(spend, "standing_orders", s.stat("total_spent") - spent_before)
		if arrived and not s.customer.is_empty():
			_handle_customer()
	if guard >= 1000:
		print("WARN,day=%d,clock loop guard hit" % s.day)


## The night: end_day() and attribution of what it paid and cost.
func _night() -> void:
	var before := s.money
	var pending_before: Array = _deliveries()
	var prizes := s.stat("show_prizes")
	var goals := s.stat("goal_rewards")
	var book := s.stat("book_rewards")
	var wages := s.stat("staff_wages")
	s.end_day()
	prizes = s.stat("show_prizes") - prizes
	goals = s.stat("goal_rewards") - goals
	book = s.stat("book_rewards") - book
	wages = s.stat("staff_wages") - wages
	_add(income, "show_prizes", prizes)
	_add(income, "goal_rewards", goals)
	_add(income, "book_rewards", book)
	_add(spend, "wages", wages)
	var delta := s.money - before
	var standing := 0
	for d in _deliveries():
		if not d in pending_before:
			standing += int(db.items[d["item_id"]]["cost"]) * int(d["quantity"])
	_add(spend, "standing_orders", standing)
	var staff_bought := prizes + goals + book - wages - delta - standing
	if staff_bought > 0:
		_add(spend, "staff_purchases", staff_bought)
	elif staff_bought < 0:
		print("WARN,day=%d,night money does not reconcile by %d" % [s.day - 1, staff_bought])
	_watch_reputation()


## Standing-order deliveries on the way (v0.21+; empty on older builds).
func _deliveries() -> Array:
	var list = s.get("deliveries")
	return list.duplicate(true) if list is Array else []


func _report_day(day: int, earned: int, served: int, walked: int, _money_before_night: int) -> void:
	var adults := s.inventory.fish_list().filter(func(f): return s.is_adult(f))
	var star_total := 0
	for f in adults:
		star_total += f.stars
	var avg_stars := float(star_total) / adults.size() if not adults.is_empty() else 0.0
	print("DAY,%d,%d,%d,%d,%d,%.2f,%d,%d,%d,%d,%d,%d,%d,%d" % [day, s.money, earned,
		s.inventory.fish_list().size(), adults.size(), avg_stars, s.breeding_tanks.size(), s.reputation,
		s.reputation_level() + 1, s.upgrades.size(), s.completed_goals.size(), served, walked,
		s.discovered_recipes.size()])
	if earned == 0:
		zero_streak += 1
		max_zero_streak = maxi(max_zero_streak, zero_streak)
		if zero_streak == 7:
			print("WARN,day=%d,seven days in a row with no income (money=%d, adults=%d, fish=%d, food=%d)" % [
				day, s.money, adults.size(), s.inventory.fish_list().size(), s.food_count()])
	else:
		zero_streak = 0


# --- Customers ---------------------------------------------------------------------

func _distraction() -> float:
	return {"casual": 0.04, "lazy": 0.12, "optimizer": 0.0}.get(style, 0.0)


func _handle_customer() -> void:
	var kind: String = s.customer.get("kind", "")
	customers_by_kind[kind] = int(customers_by_kind.get(kind, 0)) + 1
	if brng.randf() < _distraction():
		return  # looked away: they wander off when their patience runs out
	match kind:
		"fish":
			if style == "optimizer" and s.customer_can_breed_order():
				_act("back_orders", s.breed_order_for_customer)
			else:
				_serve(kind)
		"item":
			if s.customer.get("item_id", "") in db.items_in_category("food") and _needs_food() 					and s.food_count() <= s.breeding_tanks.size() + 1:
				_decline(kind)  # keep the fry's food
			elif s.customer_blocker() == "":
				_serve(kind)
			elif style != "lazy" and s.customer_can_backorder():
				s.backorder_customer()
			else:
				_decline(kind)
		"collector":
			_serve(kind)
		"tank":
			if sell_tanks and s.money >= 100 and s.customer_blocker() == "":
				_serve(kind)
				_rebuild_display()
			else:
				_decline(kind)
		"request":
			if style != "lazy" and s.can_accept_request():
				if s.accept_customer_request():
					order_age[int(s.orders[-1]["id"])] = s.day
			else:
				_decline(kind)
		"wish_item":
			if style != "lazy" and s.customer_can_backorder():
				s.backorder_customer()
			else:
				_decline(kind)
		"wish_fish":
			if style != "lazy" and _wants_fish_wish() and s.customer_can_backorder():
				s.backorder_customer()
			else:
				_decline(kind)
		_:
			_decline(kind)
	_goals()


func _serve(kind: String) -> void:
	if s.customer_blocker() != "":
		_decline(kind)
		return
	_act(CUSTOMER_SOURCE[kind], s.serve_customer)


func _decline(kind: String) -> void:
	declined_by_kind[kind] = int(declined_by_kind.get(kind, 0)) + 1
	s.decline_customer()


## Bred wishes pay double, so everyone takes them. A Market wish pays 10% under
## what the fish costs, so only the optimizer (for reputation) takes cheap ones.
func _wants_fish_wish() -> bool:
	var wish: Dictionary = s.customer["wish"]
	if wish["source"] == "bred":
		return true
	if style != "optimizer":
		return false
	return s.strain_cost(wish["strain_id"]) - int(s.fish_wish_terms(wish)["price"]) <= 3


# --- Morning management ------------------------------------------------------------

func _morning() -> void:
	_goals()
	if style != "lazy":
		_fill_backorders()
		_fill_orders()
	if style != "lazy":
		_standing_orders()
	_buy_food()
	match style:
		"lazy":
			_tidy_breeding()
		"casual":
			_casual_morning()
		"optimizer":
			_optimizer_morning()
	_goals()


func _casual_morning() -> void:
	if s.breeding_tanks.size() < 3 and s.money >= s.next_breeding_tank_cost() + 50:
		_act("breeding_tanks", s.buy_breeding_tank)
	_ensure_pairs(true)
	_tidy_breeding()
	_stock_display()
	if s.money >= 150:
		_decorate(s.display_tank, 30, "")
	_buy_upgrades(["shop_sign", "waiting_bench", "auto_feeder", "bigger_breeding_tanks", "order_desk",
		"wholesale_contract"], 100, 200, 1)
	_dump_surplus(24)
	if s.money > 400 and _has_staff_api() and s.staff_unlocked() and s.staff.is_empty():
		_act("staff_hires", func(): return s.hire_staff("feeder"))
	_goals()


func _optimizer_morning() -> void:
	while s.next_breeding_tank_cost() > 0 and s.money >= s.next_breeding_tank_cost() + 15:
		if not _act("breeding_tanks", s.buy_breeding_tank):
			break
	_optimizer_pairs()
	_tidy_breeding()
	_stock_display()
	if s.money >= 120:
		_decorate(s.display_tank, 60, "")
	_stock_shelf()
	_buy_upgrades(["tank_heaters", "shop_sign", "bigger_breeding_tanks", "auto_feeder", "conditioning_food",
		"window_display", "order_desk", "breeding_room_extension", "wholesale_contract", "waiting_bench"], 30, 99999, 3)
	_buy_expansions()
	_lab_scans(3, 150)
	_hire_staff()
	_favourites_and_pins()
	_dump_surplus(24)
	_goals()


func _has_staff_api() -> bool:
	return s.has_method("hire_staff") and s.has_method("staff_unlocked")


## Switches on standing orders (v0.21+): casual and optimizer keep food coming
## in; the optimizer also keeps the three best-margin shelf items stocked.
## Spending is booked by the money delta of the night/sales that trigger it.
func _standing_orders() -> void:
	if not s.has_method("set_standing_order") or s.standing_orders_active() > 0:
		return
	var foods := db.items_in_category("food")
	if not foods.is_empty():
		s.set_standing_order(foods[0], true, s.breeding_tanks.size() + 2, 10)
	if style != "optimizer" or s.money < 300:
		return
	var ids := db.items.keys()
	ids.sort_custom(func(a, b): return int(db.items[a]["price"]) - int(db.items[a]["cost"]) > int(db.items[b]["price"]) - int(db.items[b]["cost"]))
	for id in ids.slice(0, 3):
		s.set_standing_order(id, true, 1, 4)


# --- Supplies -----------------------------------------------------------------------

func _buy(item_id: String, qty: int, category: String) -> bool:
	return _act(category, func(): return s.buy_item(item_id, qty))


## False when auto-feeders or a hired feeder mean the bot never buys food itself.
func _needs_food() -> bool:
	if s.upgrade_effect("auto_feed") > 0.0:
		return false
	return not (_has_staff_api() and not s.staff_for_task("feeder").is_empty())


func _buy_food() -> void:
	if not _needs_food():
		return
	var foods := db.items_in_category("food")
	if foods.is_empty():
		return
	var have := s.food_count()
	var floor_count := 2 if style == "lazy" else s.breeding_tanks.size() + 3
	if have >= floor_count:
		return
	var target := 6 if style == "lazy" else s.breeding_tanks.size() * 2 + 6
	var qty := mini(target - have, s.money / int(db.items[foods[0]]["cost"]))
	if qty > 0:
		_buy(foods[0], qty, "food")


## Optimizer only: keeps a few cheap, high-margin items on the shelf for the
## customers who ask for an item.
func _stock_shelf() -> void:
	if s.money < 150:
		return
	var best_id := ""
	var best_margin := 0.0
	for id in db.items:
		var item: Dictionary = db.items[id]
		if item["category"] in ["food", "tank", "substrate"]:
			continue
		var margin := float(item["price"]) / float(item["cost"])
		if s.inventory.count(id) < 2 and margin > best_margin:
			best_margin = margin
			best_id = id
	if best_id != "":
		_buy(best_id, 2, "items")


func _dump_surplus(keep: int) -> void:
	var for_sale := s.fish_for_sale()
	if for_sale.size() <= keep:
		return
	for_sale.sort_custom(func(a: Fish, b: Fish): return s.fish_price(a) < s.fish_price(b))
	for i in for_sale.size() - keep:
		var f: Fish = for_sale[i]
		_act("wholesale", func(): return s.sell_fish_wholesale(f.id))


# --- Moving fish ---------------------------------------------------------------------

## Every adult that is not in its tank's breeding group goes out to the shop.
func _tidy_breeding() -> void:
	for i in s.breeding_tanks.size():
		var keep := s.breeding_group_fish(i)
		if keep.is_empty():
			continue
		for f in s.tank_fish(s.breeding_tanks[i]):
			if s.is_adult(f) and not f in keep:
				_move_out(f)


func _move_out(f: Fish) -> void:
	if style != "lazy" and s.move_fish(f.id, Fish.DISPLAY):
		return
	s.move_fish(f.id, Fish.HOLDING)


## Fills the display tank with the best-looking adults from holding.
func _stock_display() -> void:
	if s.display_tank == null:
		return
	var waiting := s.inventory.fish_list(Fish.HOLDING).filter(
		func(f): return s.is_adult(f) and not f.favorite)
	waiting.sort_custom(func(a: Fish, b: Fish): return _appeal(a) > _appeal(b))
	for f in waiting:
		if not s.move_fish(f.id, Fish.DISPLAY) and not s.move_fish(f.id, Fish.DISPLAY2):
			break


func _appeal(f: Fish) -> float:
	return Customers.fish_appeal(f, s.species_of(f), db.economy["customers"])


## Casual/lazy pairing: gives a tank without a breeding group a male and a
## female (from fish waiting in the shop, or a cheap Market pair if `may_buy`).
func _ensure_pairs(may_buy: bool) -> void:
	for i in s.breeding_tanks.size():
		if not s.breeding_group(i)["mothers"].is_empty():
			continue
		var location := Fish.breeding_location(i)
		var members := s.tank_fish(s.breeding_tanks[i]).filter(func(f): return s.is_adult(f))
		var species_id := ""
		var have := {Fish.MALE: false, Fish.FEMALE: false}
		for f in members:
			have[f.sex] = true
			species_id = f.species_id
		for sex in [Fish.MALE, Fish.FEMALE]:
			if have[sex]:
				continue
			var pick := _pool_fish(sex, species_id)
			if pick == null and may_buy and s.market_fish_open():
				pick = _buy_cheapest(sex, species_id)
			if pick != null:
				species_id = pick.species_id
				s.move_fish(pick.id, location)


## The best adult of this sex waiting in holding or on display (species "" = any).
func _pool_fish(sex: String, species_id: String) -> Fish:
	var best: Fish = null
	for f in s.inventory.fish_list(Fish.HOLDING) + s.inventory.fish_list(Fish.DISPLAY):
		if not s.is_adult(f) or f.favorite or f.sex != sex or (species_id != "" and f.species_id != species_id):
			continue
		if best == null or f.stars > best.stars:
			best = f
	return best


func _buy_cheapest(sex: String, species_id: String) -> Fish:
	var best_id := ""
	var best_cost := 1 << 30
	for id in db.strains:
		var strain: Dictionary = db.strains[id]
		if species_id != "" and strain["species"] != species_id:
			continue
		var cost := s.strain_cost(id)
		if cost < best_cost:
			best_cost = cost
			best_id = id
	if best_id == "" or s.money < best_cost + 30:
		return null
	return _act("market_fish", func(): return s.buy_strain(best_id, sex))


## After a tank sale: a new tank from the shelf (bought if needed), decorated again.
func _rebuild_display() -> void:
	if s.display_tank != null:
		return
	var tank_id := "tank_20l"
	if s.spare_tank_item() == "" and not _buy(tank_id, 1, "items"):
		return
	if s.install_display_tank(s.spare_tank_item()):
		_decorate(s.display_tank, 80, "")
		_stock_display()


# --- Decorating ----------------------------------------------------------------------

## Fills empty spots in `tank` (and the substrate) with the best-looking items,
## using stock first and buying more within `budget`. With a `theme`, items with
## that tag score higher (for special orders).
func _decorate(tank: Tank, budget: int, theme: String) -> void:
	if tank == null:
		return
	var weights: Dictionary = db.economy["aesthetics"]
	var left := budget
	if tank.substrate == "":
		var pick := _best_item(tank, -1, left, theme, weights)
		if pick != "":
			left -= _obtain(pick, left)
			s.set_substrate(tank, pick)
	for slot in tank.slot_count():
		if not tank.is_slot_empty(slot):
			continue
		var pick := _best_item(tank, slot, left, theme, weights)
		if pick == "":
			continue
		left -= _obtain(pick, left)
		s.place_item(tank, slot, pick)


## Makes sure one of the item is in stock (buying it if not); returns the cost paid.
func _obtain(item_id: String, budget: int) -> int:
	if s.inventory.count(item_id) > 0:
		return 0
	var cost := int(db.items[item_id]["cost"])
	if cost > budget or not _buy(item_id, 1, "items"):
		return 0
	return cost


func _best_item(tank: Tank, slot: int, budget: int, theme: String, weights: Dictionary) -> String:
	var best := ""
	var best_value := -1e9
	var base := _looks_value(tank, theme, weights)
	for id in db.items:
		var item: Dictionary = db.items[id]
		var is_sub := slot < 0
		if is_sub and not Tank.is_substrate(item):
			continue
		if not is_sub and not Tank.is_placeable(item):
			continue
		var owned := s.inventory.count(id) > 0
		var cost := 0 if owned else int(item["cost"])
		if cost > budget:
			continue
		var trial := Tank.from_dict(tank.to_dict())
		if is_sub:
			trial.set_substrate(item)
		else:
			trial.place(slot, item)
		var value := _looks_value(trial, theme, weights) - base - cost * 0.4
		if value > best_value:
			best_value = value
			best = id
	return best if best_value > -1e8 else ""


func _looks_value(tank: Tank, theme: String, weights: Dictionary) -> float:
	var value := float(Aesthetics.score(tank, db.items, weights))
	if theme != "":
		value += Aesthetics.tag_share(tank, db.items, theme) * 40.0
	return value


# --- Special orders and back-orders ---------------------------------------------------

func _fill_orders() -> void:
	var stale := 12 if style == "casual" else 8
	for i in range(s.orders.size() - 1, -1, -1):
		var id := int(s.orders[i]["id"])
		if s.day - int(order_age.get(id, s.day)) > stale:
			s.cancel_order(i)
			order_age.erase(id)
	for i in range(s.orders.size() - 1, -1, -1):
		_try_deliver(i)


## Builds the order's own tank from stock and shop fish, if the fish are there.
func _try_deliver(i: int) -> void:
	var order: Dictionary = s.orders[i]
	var picks := _pick_order_fish(order)
	if picks.is_empty():
		return
	if s.order_tank(i) == null:
		if s.spare_tank_item() == "":
			var tank_id := "tank_20l"
			if s.money < int(db.items[tank_id]["cost"]) + 40 or not _buy(tank_id, 1, "items"):
				return
		if not s.start_order_tank(i):
			return
	var tank := s.order_tank(i)
	_decorate(tank, 45, str(order["theme"]))
	for f in picks:
		s.move_fish(f.id, Fish.order_location(int(order["id"])))
	var id := int(order["id"])
	if _act("special_orders", func(): return not s.deliver_order(i, true).is_empty()):
		order_age.erase(id)
	_goals()


## Fish that would satisfy the order exactly, or [] if the shop can't.
func _pick_order_fish(order: Dictionary) -> Array:
	var pool: Array = []
	var group_ids := {}
	for t in s.breeding_tanks.size():
		for f in s.breeding_group_fish(t):
			group_ids[f.id] = true
	for f in s.inventory.fish_list():
		if s.is_adult(f) and not f.favorite and not Fish.is_order(f.location) and not group_ids.has(f.id) \
				and f.species_id == order["species_id"] and f.id != s.show_entry:
			pool.append(f)
	pool.sort_custom(func(a: Fish, b: Fish): return a.stars > b.stars)
	var chosen: Array = []
	for c in order["constraints"]:
		var have := 0
		for f in chosen:
			if f.get_trait(c["trait"]) == c["value"]:
				have += 1
		for f in pool:
			if have >= int(c["min_count"]):
				break
			if f in chosen or f.get_trait(c["trait"]) != c["value"]:
				continue
			chosen.append(f)
			have += 1
		if have < int(c["min_count"]):
			return []
	for f in pool:
		if chosen.size() >= int(order["fish_count"]):
			break
		if not f in chosen:
			chosen.append(f)
	if chosen.size() != int(order["fish_count"]):
		return []
	return chosen


func _fill_backorders() -> void:
	for i in range(s.backorders.size() - 1, -1, -1):
		var b: Dictionary = s.backorders[i]
		var key := _bo_key(b)
		if not backorder_age.has(key):
			backorder_age[key] = s.day
		if b.has("item_id"):
			if s.inventory.count(b["item_id"]) <= 0 and s.money > int(db.items[b["item_id"]]["cost"]) + 10:
				_buy(b["item_id"], 1, "items")
		elif s.backorder_blocker(i) != "" and s.day >= int(b.get("due_day", 0)) and b.get("source") == "market" \
				and s.market_fish_open() and style == "optimizer":
			_buy_wish_fish(b)
		if s.backorder_blocker(i) == "":
			_act("back_orders", func(): return s.fulfil_backorder(i))
			backorder_age.erase(key)
		elif s.day > maxi(int(b.get("due_day", 0)), int(backorder_age[key])) + 14:
			s.cancel_backorder(i)  # no penalty; the bot gives up on a stale one
			backorder_age.erase(key)


func _bo_key(b: Dictionary) -> String:
	return "%s|%s|%s|%s" % [b.get("name", ""), b.get("item_id", ""), str(b.get("traits", {})), b.get("sex", "")]


func _buy_wish_fish(b: Dictionary) -> void:
	for id in db.strains:
		var strain: Dictionary = db.strains[id]
		if strain["species"] == b["species_id"] and strain["traits"] == b["traits"]:
			_act("market_fish", func(): return s.buy_strain(id, b["sex"]))
			return


# --- Upgrades, tanks, staff ---------------------------------------------------------

func _buy_upgrades(order: Array, reserve: int, max_cost: int, max_per_day: int) -> void:
	var bought := 0
	for id in order:
		if bought >= max_per_day or not db.upgrades.has(id):
			break
		if s.has_upgrade(id):
			continue
		var cost := int(db.upgrades[id]["cost"])
		var needs: String = db.upgrades[id].get("requires", "")
		if needs != "" and not s.has_upgrade(needs):
			continue
		if cost > max_cost:
			continue
		if s.money - cost >= reserve:
			if _act("upgrades", func(): return s.buy_upgrade(id)):
				bought += 1
		elif style == "optimizer" and cost <= s.money * 3:
			break  # save up for the next one in value order


## Optimizer only: the shop expansions, bought once money is over twice their cost.
func _buy_expansions() -> void:
	for id in db.upgrade_order:
		if db.upgrades[id].get("group", "") != "expansion" or s.has_upgrade(id):
			continue
		if s.upgrade_blocker(id) == "" and s.money > 2 * int(db.upgrades[id]["cost"]):
			_act("upgrades", func(): return s.buy_upgrade(id))


func _hire_staff() -> void:
	if not _has_staff_api() or not s.staff_unlocked():
		return
	var plan := [["feeder", 100], ["decorator", 250], ["stocker", 400]]
	for entry in plan:
		var task: String = entry[0]
		if not s.staff_for_task(task).is_empty() or s.hire_blocker(task) != "":
			continue
		if s.money >= s.hire_cost() + int(entry[1]):
			_act("staff_hires", func(): return s.hire_staff(task))


func _lab_scans(per_day: int, reserve: int) -> void:
	if not s.lab_unlocked() or s.money < reserve:
		return
	var targets: Array = []
	for t in s.breeding_tanks.size():
		targets.append_array(s.breeding_group_fish(t))
	var done := 0
	for f in targets:
		if done >= per_day or s.stat("fish_scanned") >= 14:
			break
		if s.scan_blocker(f.id) == "":
			_act("lab_scans", func(): return not s.scan_fish(f.id).is_empty())
			done += 1


func _favourites_and_pins() -> void:
	var keepers: Array = []
	for t in s.breeding_tanks.size():
		keepers.append_array(s.breeding_group_fish(t))
	keepers.sort_custom(func(a: Fish, b: Fish): return s.fish_price(a) > s.fish_price(b))
	for f in keepers:
		if s.favorite_count() >= 5:
			break
		if not f.favorite:
			s.set_favorite(f.id, true)
	if s.pin_slots() > 0:
		for entry in s.gallery_favorites():
			s.pin_portrait(entry["key"])


# --- Optimizer breeding plans ---------------------------------------------------------

func _optimizer_pairs() -> void:
	var pool: Array = []
	for f in s.inventory.fish_list():
		if s.is_adult(f) and not Fish.is_order(f.location):
			pool.append(f)
	var used := {}
	var plans: Array = []
	var bought_today := 0
	for i in s.breeding_tanks.size():
		var plan := {}
		if i > 0:
			plan = _recipe_plan(pool, used, bought_today)
			bought_today = int(plan.get("bought", 0)) if not plan.is_empty() else bought_today
			if not plan.is_empty() and plan.has("pool_add"):
				pool.append_array(plan["pool_add"])
		if plan.is_empty():
			plan = _production_plan(pool, used)
		plans.append(plan)
		if not plan.is_empty():
			used[plan["father"].id] = true
			for m in plan["mothers"]:
				used[m.id] = true
	for i in plans.size():
		_apply_plan(i, plans[i])


func _sorted_best_first(list: Array) -> Array:
	var sorted := list.duplicate()
	sorted.sort_custom(func(a: Fish, b: Fish):
		return a.stars > b.stars or (a.stars == b.stars and (a.purity > b.purity or (a.purity == b.purity and a.id < b.id))))
	return sorted


## One sire and up to max_mothers mothers of the single most valuable variety.
func _production_plan(pool: Array, used: Dictionary) -> Dictionary:
	var by_variety := {}
	for f in _sorted_best_first(pool):
		if used.has(f.id):
			continue
		var key := "%s|%s" % [f.species_id, str(f.traits)]
		if not by_variety.has(key):
			by_variety[key] = {"males": [], "females": []}
		by_variety[key]["males" if f.sex == Fish.MALE else "females"].append(f)
	var best := {}
	var best_value := -1
	for key in by_variety:
		var group: Dictionary = by_variety[key]
		if group["males"].is_empty() or group["females"].is_empty():
			continue
		var value: int = s.fish_price(group["males"][0]) + s.fish_price(group["females"][0])
		if value > best_value:
			best_value = value
			best = {"father": group["males"][0], "mothers": group["females"].slice(0, s.max_mothers())}
	if not best.is_empty():
		return best
	# No true pair: any sire with any mother of its species.
	for male in _sorted_best_first(pool):
		if used.has(male.id) or male.sex != Fish.MALE:
			continue
		var mothers := _sorted_best_first(pool).filter(
			func(f): return f.sex == Fish.FEMALE and f.species_id == male.species_id and not used.has(f.id))
		if not mothers.is_empty():
			return {"father": male, "mothers": mothers.slice(0, s.max_mothers())}
	return {}


## A pair that could make an undiscovered recipe, buying a missing parent from
## the Market when it is cheap. Lowest generation first.
func _recipe_plan(pool: Array, used: Dictionary, bought_today: int) -> Dictionary:
	var recipes: Array = []
	for species_id in db.species:
		for r in s.book_recipes(species_id):
			if not r["discovered"]:
				r["species_id"] = species_id
				recipes.append(r)
	recipes.sort_custom(func(a, b): return int(a["generation"]) < int(b["generation"]))
	for r in recipes:
		var a: String = r["parents"][0]
		var b: String = r["parents"][1]
		for pair in [[a, b], [b, a]]:  # [sire value, mother value]
			var sire := _find(pool, used, r["species_id"], r["trait"], pair[0], Fish.MALE)
			var mums := _find_all(pool, used, r["species_id"], r["trait"], pair[1], Fish.FEMALE)
			if sire != null and not mums.is_empty():
				return {"father": sire, "mothers": mums.slice(0, s.max_mothers())}
		# One side owned, the other buyable: buy the missing parent.
		if bought_today < 2 and s.market_fish_open():
			for pair in [[a, b], [b, a]]:
				var sire := _find(pool, used, r["species_id"], r["trait"], pair[0], Fish.MALE)
				var mums := _find_all(pool, used, r["species_id"], r["trait"], pair[1], Fish.FEMALE)
				var bought: Fish = null
				if sire == null and not mums.is_empty():
					bought = _buy_variety(r["species_id"], r["trait"], pair[0], Fish.MALE)
				elif sire != null and mums.is_empty():
					bought = _buy_variety(r["species_id"], r["trait"], pair[1], Fish.FEMALE)
				if bought != null:
					var plan := {"bought": bought_today + 1, "pool_add": [bought]}
					if sire == null:
						plan["father"] = bought
						plan["mothers"] = mums.slice(0, s.max_mothers())
					else:
						plan["father"] = sire
						plan["mothers"] = [bought]
					return plan
	return {}


func _find(pool: Array, used: Dictionary, species_id: String, trait_name: String, value: String, sex: String) -> Fish:
	var all := _find_all(pool, used, species_id, trait_name, value, sex)
	return all[0] if not all.is_empty() else null


func _find_all(pool: Array, used: Dictionary, species_id: String, trait_name: String, value: String, sex: String) -> Array:
	return _sorted_best_first(pool).filter(func(f: Fish):
		return not used.has(f.id) and f.species_id == species_id and f.sex == sex and f.get_trait(trait_name) == value)


## Buys one fish of a variety from the Market if it is cheap enough (<= 60 and
## within a quarter of the money on hand). Returns the fish or null.
func _buy_variety(species_id: String, trait_name: String, value: String, sex: String) -> Fish:
	for id in db.strains:
		var strain: Dictionary = db.strains[id]
		if strain["species"] != species_id or strain["traits"].get(trait_name, "") != value or strain["traits"].size() != 1:
			continue
		var cost := s.strain_cost(id)
		if cost > 60 or cost > s.money / 4:
			return null
		return _act("market_fish", func(): return s.buy_strain(id, sex))
	return null


## Moves a tank's group into place: everything else adult goes out, the group
## comes in, and fry make way when the tank is nearly full.
func _apply_plan(i: int, plan: Dictionary) -> void:
	if plan.is_empty():
		return
	var tank := s.breeding_tanks[i]
	var wanted: Array = [plan["father"]] + plan["mothers"]
	var location := Fish.breeding_location(i)
	for f in s.tank_fish(tank):
		if s.is_adult(f) and not f in wanted:
			_move_out(f)
	for f in wanted:
		if f.location == location:
			continue
		if not tank.has_room_for_fish():
			_make_room(tank, i, wanted)
		s.move_fish(f.id, location)
	if tank.capacity - tank.fish_ids.size() < 4:
		_make_room(tank, i, wanted)


## Sends fry to holding (they keep growing there) until the tank has some room.
func _make_room(tank: Tank, i: int, wanted: Array) -> void:
	for f in s.tank_fish(tank):
		if tank.capacity - tank.fish_ids.size() >= 4:
			return
		if not s.is_adult(f) or not f in wanted:
			s.move_fish(f.id, Fish.HOLDING)


# --- Evening: shows ------------------------------------------------------------------

func _evening() -> void:
	if style == "lazy" or not s.shows_unlocked():
		return
	if style == "optimizer":
		_scan_for_show()
	_enter_show()


## What the bot can see of a fish's show chances (unscanned purity is hidden).
func _show_score(f: Fish) -> float:
	var purity := f.purity if f.scanned else int(db.shows["hints"]["typical_purity"])
	return Shows.base_score(f.stars, s.show_value_step(f), purity, db.shows)


func _enter_show() -> void:
	var best: Fish = null
	for f in s.inventory.fish_list():
		if s.show_eligible(f.id) and (best == null or _show_score(f) > _show_score(best)):
			best = f
	if best != null:
		s.enter_show(best.id)


## For the Pure Line class: scan the best-looking unscanned adults.
func _scan_for_show() -> void:
	var show := s.next_show()
	var rule: Dictionary = show.get("rule", {})
	if not rule.has("min_purity_scanned") or not s.lab_unlocked() or int(show.get("days_left", 1)) != 0:
		return
	var cands := s.inventory.fish_list().filter(func(f): return s.is_adult(f) and not f.scanned)
	cands.sort_custom(func(a: Fish, b: Fish): return _show_score(a) > _show_score(b))
	for f in cands.slice(0, 3):
		if s.scan_blocker(f.id) == "":
			_act("lab_scans", func(): return not s.scan_fish(f.id).is_empty())


# --- Accounting ------------------------------------------------------------------------

func _add(dict: Dictionary, key: String, amount: int) -> void:
	dict[key] = int(dict.get(key, 0)) + amount


## Runs a game call and books its money under `source`. Sales can trigger
## standing-order purchases inside the same call, so spending is read from the
## game's total_spent counter and booked apart from what the call earned.
func _act(source: String, f: Callable):
	var before := s.money
	var spent_before := s.stat("total_spent")
	var result = f.call()
	var spent := s.stat("total_spent") - spent_before
	var gross := (s.money - before) + spent
	if source in INCOME_SOURCES:
		_add(income, source, gross)
		_add(spend, "standing_orders", spent)
	elif gross > 0:
		_add(income, source, gross)
		_add(spend, source, spent)
	else:
		_add(spend, source, spent)
	return result


## Pays out goals the way the real game does after every change, and notes
## the day each reputation level and goal is first seen.
func _goals() -> void:
	var before := s.money
	for g in s.check_goals():
		goal_day[g["id"]] = s.day
	_add(income, "goal_rewards", s.money - before)
	_watch_reputation()


func _watch_reputation() -> void:
	for level in s.reputation_level() + 1:
		if not rep_level_day.has(level):
			rep_level_day[level] = s.day


# --- Summary -----------------------------------------------------------------------------

func _summary() -> void:
	var total_in := 0
	var total_out := 0
	for k in income:
		total_in += int(income[k])
	for k in spend:
		total_out += int(spend[k])
	for k in INCOME_SOURCES:
		print("SUMMARY,income,%s,%d,%.1f" % [k, income[k], 100.0 * income[k] / maxf(1.0, total_in)])
	print("SUMMARY,income,TOTAL,%d,100.0" % total_in)
	for k in SPEND_CATEGORIES:
		print("SUMMARY,spend,%s,%d,%.1f" % [k, spend[k], 100.0 * spend[k] / maxf(1.0, total_out)])
	print("SUMMARY,spend,TOTAL,%d,100.0" % total_out)
	var levels := s.reputation_levels()
	for level in levels.size():
		print("SUMMARY,rep_level,%d,%s,%s" % [level + 1, levels[level]["name"],
			str(rep_level_day[level]) if rep_level_day.has(level) else "never"])
	for d in CHECKPOINT_DAYS:
		if checkpoints.has(d):
			print("SUMMARY,money_at,%d,%d" % [d, checkpoints[d]])
	var goal_money := 0
	for g in db.goals:
		if s.completed_goals.has(g["id"]):
			goal_money += int(g["reward"])
		print("SUMMARY,goal,%s,%s,%d" % [g["id"], str(s.completed_goals[g["id"]]) if s.completed_goals.has(g["id"]) else "never",
			int(g["reward"])])
	print("SUMMARY,goals,%d,of,%d,reward_total,%d" % [s.completed_goals.size(), db.goals.size(), goal_money])
	print("SUMMARY,final,money=%d,day=%d,fish=%d,tanks=%d,upgrades=%d,recipes=%d,mutations=%d,rep=%d,staff=%d" % [
		s.money, s.day, s.inventory.fish_list().size(), s.breeding_tanks.size(), s.upgrades.size(),
		s.discovered_recipes.size(), s.discovered_mutations.size(), s.reputation, s.staff.size()])
	print("SUMMARY,counts,fish_sold=%d,collector=%d,orders=%d,backorders=%d,ribbons=%d,scans=%d,bred=%d,walked_out=%d,customers=%d" % [
		s.stat("fish_sold"), s.stat("collector_sales"), s.stat("orders_delivered"), s.stat("backorders_filled"),
		s.stat("ribbons_first") + s.stat("ribbons_second") + s.stat("ribbons_third"), s.stat("fish_scanned"),
		s.stat("fish_bred"), s.stat("walked_out"), s.stat("customers_served")])
	print("SUMMARY,customer_kinds,%s,declined,%s" % [JSON.stringify(customers_by_kind), JSON.stringify(declined_by_kind)])
	print("SUMMARY,max_zero_income_streak,%d" % max_zero_streak)
	var expected := start_money + total_in - total_out
	print("RECON,%s,money=%d,expected=%d,diff=%d" % ["ok" if expected == s.money else "MISMATCH", s.money, expected,
		s.money - expected])
	var stat_goals := s.stat("goal_rewards")
	if stat_goals != int(income["goal_rewards"]):
		print("WARN,goal_rewards stat %d vs booked %d" % [stat_goals, income["goal_rewards"]])
