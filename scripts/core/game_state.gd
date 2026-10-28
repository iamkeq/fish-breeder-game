class_name GameState
extends RefCounted
## All game rules tied together: money, stock, tanks, orders and the day cycle.
## No Nodes here. The Game autoload wraps this for the UI.

var db: DataDB
var rng: RandomNumberGenerator
var money: int = 0
var day: int = 1
var earned_today: int = 0
var inventory := Inventory.new()
## The shop-floor display tank. null when it has been sold and not replaced yet.
var display_tank: Tank = null
## Back-room breeding tanks (1 to start, more can be bought). Each is separate:
## fish only breed with others in the same tank.
var breeding_tanks: Array[Tank] = []
## Nights since each breeding tank's pair last had a brood.
var brood_nights: Array[int] = []
## The first breeding tank.
var breeding_tank: Tank:
	get:
		return breeding_tanks[0]
var clock: GameClock
## Accepted customer requests (Dictionaries from RequestGenerator). No deadlines.
var orders: Array = []
## The customer at the counter ({} when nobody is there). See Customers.make_walk_in.
var customer: Dictionary = {}
## In-game minutes until the next customer walks in.
var minutes_to_customer: float = 0.0
## Things customers asked for that were out of stock. They pay a discounted
## price when you hand them over. No deadlines. See backorder_customer().
var backorders: Array = []
## What happened today, for the end-of-day summary. Reset when the shop opens.
var day_log: Dictionary = {}


static func new_game(p_db: DataDB, p_rng: RandomNumberGenerator) -> GameState:
	var s := GameState.new()
	s.db = p_db
	s.rng = p_rng
	var start: Dictionary = p_db.economy["starting_state"]
	s.money = int(start["money"])
	for item_id in start["items"]:
		s.inventory.add(item_id, int(start["items"][item_id]))
	s.display_tank = s._make_tank(start["display_tank"])
	s._add_breeding_tank()
	s._apply_starter_layout(s.display_tank, start.get("display_tank_layout", {}))
	for fish_data in start["fish"]:
		var f := Fish.from_dict(fish_data)
		f.location = Fish.HOLDING
		if not fish_data.has("age_days"):
			f.age_days = int(p_db.species[f.species_id]["days_to_adult"])
		s.inventory.add_fish(f)
		var where: String = fish_data.get("location", Fish.HOLDING)
		if where != Fish.HOLDING:
			s.move_fish(f.id, where)
	s.clock = GameClock.new(p_db.economy["clock"])
	s.open_day()
	return s


# --- Lookups -----------------------------------------------------------------

func species_of(fish: Fish) -> Dictionary:
	return db.species[fish.species_id]


func is_adult(fish: Fish) -> bool:
	return fish.is_adult(species_of(fish))


func fish_price(fish: Fish) -> int:
	return Pricing.fish_price(fish, species_of(fish), db.economy)


func tank_fish(tank: Tank) -> Array[Fish]:
	var result: Array[Fish] = []
	for fish_id in tank.fish_ids:
		result.append(inventory.get_fish(fish_id))
	return result


func tank_aesthetics(tank: Tank) -> int:
	return Aesthetics.score(tank, db.items, db.economy["aesthetics"])


func tank_price(tank: Tank, include_fish: bool) -> int:
	var fish_total := 0
	if include_fish:
		for f in tank_fish(tank):
			fish_total += fish_price(f)
	return Pricing.tank_price(tank, db.items, tank_aesthetics(tank), fish_total, db.economy)


func tank_at(location: String) -> Tank:
	if location == Fish.DISPLAY:
		return display_tank
	var index := Fish.breeding_index(location)
	if index >= 0 and index < breeding_tanks.size():
		return breeding_tanks[index]
	return null


## Every fish in any breeding tank.
func breeding_fish() -> Array[Fish]:
	var result: Array[Fish] = []
	for tank in breeding_tanks:
		result.append_array(tank_fish(tank))
	return result


# --- Breeding tanks ------------------------------------------------------------

func max_breeding_tanks() -> int:
	return int(db.economy["breeding_tanks"]["max"])


## Price of the next breeding tank, or -1 if you already have the most.
func next_breeding_tank_cost() -> int:
	var index := breeding_tanks.size() - 1  # extra_costs[0] is the 2nd tank
	var costs: Array = db.economy["breeding_tanks"]["extra_costs"]
	if breeding_tanks.size() >= max_breeding_tanks() or index >= costs.size():
		return -1
	return int(costs[index])


func buy_breeding_tank() -> bool:
	var cost := next_breeding_tank_cost()
	if cost < 0 or not can_afford(cost):
		return false
	_spend(cost)
	_add_breeding_tank()
	return true


func _add_breeding_tank() -> void:
	breeding_tanks.append(Tank.new("", int(db.economy["breeding_tank_capacity"])))
	brood_nights.append(0)


# --- Buying ------------------------------------------------------------------

func can_afford(amount: int) -> bool:
	return money >= amount


func buy_item(item_id: String, qty: int = 1) -> bool:
	if not db.items.has(item_id) or qty <= 0:
		return false
	var cost := int(db.items[item_id]["cost"]) * qty
	if not can_afford(cost):
		return false
	_spend(cost)
	inventory.add(item_id, qty)
	return true


## Fish Market tiers from data: [{"tier": 1, "name": "Starter"}, ...]
func market_tiers() -> Array:
	return db.economy["fish_market"]["tiers"]


## Strain ids in a tier, cheapest first.
func strains_in_tier(tier: int) -> Array:
	var ids := db.strains.keys().filter(func(id): return int(db.strains[id]["tier"]) == tier)
	ids.sort_custom(func(a, b):
		var ca := strain_cost(a)
		var cb := strain_cost(b)
		return ca < cb if ca != cb else db.strains[a]["name"] < db.strains[b]["name"])
	return ids


func strain_cost(strain_id: String) -> int:
	var strain: Dictionary = db.strains[strain_id]
	return Pricing.strain_cost(strain, db.species[strain["species"]], db.economy)


## Buys an adult of a named strain into holding. Traits the strain doesn't fix
## are random common values. Returns the fish, or null if it couldn't.
func buy_strain(strain_id: String, sex: String) -> Fish:
	if not db.strains.has(strain_id) or not sex in [Fish.MALE, Fish.FEMALE]:
		return null
	var cost := strain_cost(strain_id)
	if not can_afford(cost):
		return null
	var strain: Dictionary = db.strains[strain_id]
	var f := Genetics.random_fish(db.species[strain["species"]], int(strain["stars"]), 0.0, rng)
	f.sex = sex
	for trait_name in strain["traits"]:
		f.traits[trait_name] = strain["traits"][trait_name]
	f.strain_id = strain_id
	f.location = Fish.HOLDING
	_spend(cost)
	return inventory.add_fish(f)


## "Koi Guppy" for one-trait species (the variety says it all), otherwise the
## strain name for bought fish, or the species name.
func fish_display_name(f: Fish) -> String:
	var species := species_of(f)
	if species["traits"].size() == 1:
		var value: String = f.traits.values()[0] if not f.traits.is_empty() else ""
		return ("%s %s" % [value.replace("_", " ").capitalize(), species["name"]]).strip_edges()
	if f.strain_id != "" and db.strains.has(f.strain_id):
		return db.strains[f.strain_id]["name"]
	return species_of(f)["name"]


# --- Selling -----------------------------------------------------------------

func _earn(amount: int, category: String) -> void:
	money += amount
	earned_today += amount
	if day_log.is_empty():
		_reset_day_log()
	var sale: Array = day_log["sales"].get(category, [0, 0])
	day_log["sales"][category] = [sale[0] + 1, sale[1] + amount]


func _spend(amount: int) -> void:
	money -= amount
	if day_log.is_empty():
		_reset_day_log()
	day_log["spent"] += amount


func _reset_day_log() -> void:
	day_log = {"money_start": money, "sales": {}, "spent": 0, "served": 0, "walked_out": 0}


## Sells one item from stock. Returns the money earned (0 if it couldn't).
func sell_item(item_id: String) -> int:
	if not db.items.has(item_id) or not inventory.remove(item_id):
		return 0
	var price := Pricing.item_price(db.items[item_id])
	_earn(price, "item")
	return price


## Sells an adult fish from wherever it is. Returns the money earned (0 if it couldn't).
func sell_fish(fish_id: int) -> int:
	var f := inventory.get_fish(fish_id)
	if f == null or not is_adult(f):
		return 0
	var price := fish_price(f)
	_release_fish(f)
	_earn(price, "fish")
	return price


func wholesale_price(f: Fish) -> int:
	return Pricing.wholesale_price(f, species_of(f), db.economy)


## Sells any fish (fry too) to the wholesaler: instant, no customer needed,
## but for less than a customer would pay. Returns the money earned.
func sell_fish_wholesale(fish_id: int) -> int:
	var f := inventory.get_fish(fish_id)
	if f == null:
		return 0
	var price := wholesale_price(f)
	_release_fish(f)
	_earn(price, "wholesale")
	return price


## Sells the finished display tank. Without fish, its fish go back to holding.
func sell_display_tank(include_fish: bool) -> int:
	if display_tank == null:
		return 0
	var price := tank_price(display_tank, include_fish)
	_remove_display_tank(include_fish)
	_earn(price, "tank")
	return price


# --- Tanks -------------------------------------------------------------------

## Puts an empty tank from stock on the display stand.
func install_display_tank(tank_item_id: String) -> bool:
	if display_tank != null or db.items.get(tank_item_id, {}).get("category") != "tank":
		return false
	if not inventory.remove(tank_item_id):
		return false
	display_tank = _make_tank(tank_item_id)
	return true


## Places an item from stock into a slot. Anything already there goes back to stock.
func place_item(tank: Tank, slot: int, item_id: String) -> bool:
	var item: Dictionary = db.items.get(item_id, {})
	if tank == null or not Tank.is_placeable(item) or not inventory.can_remove(item_id):
		return false
	if slot < 0 or slot >= tank.slot_count():
		return false
	take_item(tank, slot)
	inventory.remove(item_id)
	tank.place(slot, item)
	return true


func take_item(tank: Tank, slot: int) -> bool:
	var id := tank.take(slot)
	if id == "":
		return false
	inventory.add(id)
	return true


func set_substrate(tank: Tank, item_id: String) -> bool:
	var item: Dictionary = db.items.get(item_id, {})
	if tank == null or not Tank.is_substrate(item) or not inventory.can_remove(item_id):
		return false
	take_substrate(tank)
	inventory.remove(item_id)
	tank.set_substrate(item)
	return true


func take_substrate(tank: Tank) -> bool:
	var id := tank.take_substrate()
	if id == "":
		return false
	inventory.add(id)
	return true


## Why a fish can't move to `to`, or "" if it can. Fry can't go on display.
func move_blocker(fish_id: int, to: String) -> String:
	var f := inventory.get_fish(fish_id)
	if f == null:
		return "That fish isn't yours."
	if f.location == to:
		return "Already there."
	if to == Fish.DISPLAY and not is_adult(f):
		return "Fry stay in the back room until they grow up."
	var target := tank_at(to)
	if to != Fish.HOLDING:
		if target == null:
			return "There's no tank on display." if to == Fish.DISPLAY else "You don't have that breeding tank yet."
		if not target.has_room_for_fish():
			return "That tank is full (%d fish)." % target.capacity
	return ""


func can_move_fish(fish_id: int, to: String) -> bool:
	return move_blocker(fish_id, to) == ""


## Moves a fish between holding, the breeding tank and the display tank.
func move_fish(fish_id: int, to: String) -> bool:
	if not can_move_fish(fish_id, to):
		return false
	var f := inventory.get_fish(fish_id)
	var target := tank_at(to)
	var source := tank_at(f.location)
	if source != null:
		source.remove_fish(fish_id)
	if target != null:
		target.add_fish(fish_id)
	f.location = to
	return true


# --- Requests ----------------------------------------------------------------

func make_request(template_id: String = "") -> Dictionary:
	if template_id == "":
		var ids := db.request_templates.keys()
		ids.sort()
		template_id = ids[rng.randi_range(0, ids.size() - 1)]
	var template: Dictionary = db.request_templates[template_id]
	return RequestGenerator.generate(template, db.species[template["species"]],
		inventory.fish_list(), rng)


func can_accept_request() -> bool:
	return orders.size() < int(db.economy["requests"]["max_orders"])


func accept_request(request: Dictionary) -> bool:
	if not can_accept_request():
		return false
	orders.append(request)
	return true


## What delivering the display tank to an order would pay, without doing it.
func preview_delivery(order_index: int) -> Dictionary:
	if display_tank == null or order_index < 0 or order_index >= orders.size():
		return {}
	return RequestScoring.score(orders[order_index], display_tank, tank_fish(display_tank),
		db.items, tank_aesthetics(display_tank), tank_price(display_tank, true), db.economy)


## Hands the display tank (with its fish) to the customer. Returns the score breakdown.
func deliver_order(order_index: int) -> Dictionary:
	var result := preview_delivery(order_index)
	if result.is_empty():
		return {}
	orders.remove_at(order_index)
	_remove_display_tank(true)
	_earn(result["payout"], "order")
	return result


func cancel_order(order_index: int) -> bool:
	if order_index < 0 or order_index >= orders.size():
		return false
	orders.remove_at(order_index)
	return true


# --- Customers ---------------------------------------------------------------

func shop_appeal() -> float:
	var looks := tank_aesthetics(display_tank) if display_tank != null else 0
	return Customers.shop_appeal(inventory.fish_list(Fish.DISPLAY), inventory.fish_list(Fish.HOLDING),
		breeding_fish(), looks, db.species, db.economy["customers"])


## Moves customer timers on by `minutes` of in-game time while the shop is open.
## Returns true if someone arrived at or left the counter.
func tick_customers(minutes: float) -> bool:
	if minutes <= 0.0 or not clock.is_open:
		return false
	if not customer.is_empty():
		customer["waited"] += minutes
		if customer["waited"] >= customer["patience"]:
			day_log["walked_out"] = day_log.get("walked_out", 0) + 1
			_customer_leaves()  # no penalty, they just wander off
			return true
		return false
	minutes_to_customer -= minutes
	if minutes_to_customer > 0.0:
		return false
	customer = _new_customer()
	return true


## Fish customers can see and buy: adults on display or in holding.
func fish_for_sale() -> Array:
	var result := []
	for f in inventory.fish_list(Fish.DISPLAY) + inventory.fish_list(Fish.HOLDING):
		if is_adult(f):
			result.append(f)
	return result


## What the customer at the counter would pay right now (0 for requests/browsers).
func customer_price() -> int:
	match customer.get("kind", ""):
		"fish":
			var f := inventory.get_fish(customer["fish_id"])
			return fish_price(f) if f != null else 0
		"item":
			return Pricing.item_price(db.items[customer["item_id"]])
		"tank":
			return tank_price(display_tank, true) if display_tank != null else 0
		"wish_item", "wish_fish":
			return Customers.backorder_price(wish_full_price(customer), db.economy["backorders"])
	return 0


## Why the customer's wish can't be met right now, or "" if it can.
func customer_blocker() -> String:
	match customer.get("kind", ""):
		"fish":
			var f := inventory.get_fish(customer["fish_id"])
			if f == null or not is_adult(f):
				return "That fish isn't available any more."
		"item":
			if inventory.count(customer["item_id"]) <= 0:
				return "That's out of stock now."
		"tank":
			if display_tank == null:
				return "There's no display tank any more."
		"request":
			if not can_accept_request():
				return "You already have %d orders on the go." % orders.size()
		"wish_item", "wish_fish":
			if not can_backorder():
				return "Your back-order list is full."
		_:
			return "Nothing to sell."
	return ""


## Sells the customer what they asked for. Returns the money earned (0 if it couldn't).
func serve_customer() -> int:
	if customer_blocker() != "" or customer["kind"] in ["request", "wish_item", "wish_fish"]:
		return 0
	var earned := 0
	match customer["kind"]:
		"fish":
			earned = sell_fish(customer["fish_id"])
		"item":
			earned = sell_item(customer["item_id"])
		"tank":
			earned = sell_display_tank(customer.get("with_fish", true))
	day_log["served"] = day_log.get("served", 0) + 1
	_customer_leaves()
	return earned


func accept_customer_request() -> bool:
	if customer.get("kind") != "request" or not accept_request(customer["request"]):
		return false
	_customer_leaves()
	return true


# --- Back-orders ---------------------------------------------------------------

func can_backorder() -> bool:
	return backorders.size() < int(db.economy["backorders"]["max"])


## True if the customer at the counter wants something you could order in for
## them: an out-of-stock wish, or an item that sold out while they waited.
func customer_can_backorder() -> bool:
	if not can_backorder():
		return false
	match customer.get("kind", ""):
		"wish_item", "wish_fish":
			return true
		"item":
			return inventory.count(customer["item_id"]) <= 0
	return false


## Full (undiscounted) price of what a customer or back-order asks for.
func wish_full_price(wish: Dictionary) -> int:
	if wish.has("item_id"):
		return Pricing.item_price(db.items[wish["item_id"]])
	var strain: Dictionary = db.strains[wish["strain_id"]]
	var spec := Fish.new()
	spec.species_id = strain["species"]
	spec.stars = int(strain["stars"])
	spec.traits = strain["traits"].duplicate()
	spec.age_days = int(db.species[strain["species"]]["days_to_adult"])
	return fish_price(spec)


## Takes the customer's order for something you don't have. They'll pay the
## discounted price when you hand it over later.
func backorder_customer() -> bool:
	if not customer_can_backorder():
		return false
	var order := {"name": customer["name"]}
	if customer.has("item_id"):
		order["item_id"] = customer["item_id"]
	else:
		order["strain_id"] = customer["strain_id"]
		order["sex"] = customer["sex"]
	order["price"] = Customers.backorder_price(wish_full_price(order), db.economy["backorders"])
	backorders.append(order)
	_customer_leaves()
	return true


## The fish you'd hand over for a strain back-order: a matching adult in holding,
## then on display. Never taken from the breeding tank.
func backorder_fish(order: Dictionary) -> Fish:
	var strain: Dictionary = db.strains[order["strain_id"]]
	for location in [Fish.HOLDING, Fish.DISPLAY]:
		for f in inventory.fish_list(location):
			if Customers.matches_strain(f, strain, order["sex"], species_of(f)):
				return f
	return null


## Why a back-order can't be handed over yet, or "" if it can.
func backorder_blocker(index: int) -> String:
	if index < 0 or index >= backorders.size():
		return "No such back-order."
	var order: Dictionary = backorders[index]
	if order.has("item_id"):
		return "" if inventory.count(order["item_id"]) > 0 else "Not in stock yet. Buy it in the Market."
	if backorder_fish(order) == null:
		return "No matching fish yet (holding or display). Buy or breed one."
	return ""


func fulfil_backorder(index: int) -> int:
	if backorder_blocker(index) != "":
		return 0
	var order: Dictionary = backorders[index]
	if order.has("item_id"):
		inventory.remove(order["item_id"])
	else:
		_release_fish(backorder_fish(order))
	backorders.remove_at(index)
	_earn(order["price"], "backorder")
	return order["price"]


func cancel_backorder(index: int) -> bool:
	if index < 0 or index >= backorders.size():
		return false
	backorders.remove_at(index)
	return true


## "Not today": always fine, no penalty.
func decline_customer() -> void:
	if not customer.is_empty():
		_customer_leaves()


func _new_customer() -> Dictionary:
	var tank_for_sale := display_tank != null and not display_tank.placed_item_ids().is_empty()
	var ctx := {
		"fish_for_sale": fish_for_sale(), "species_db": db.species,
		"items_in_stock": inventory.stock().keys(), "all_items": db.items.keys(),
		"strains": db.strains if can_backorder() else {},
		"tank_for_sale": tank_for_sale, "can_take_request": can_accept_request(),
	}
	if not can_backorder():
		ctx["all_items"] = []
	var c := Customers.make_walk_in(ctx, db.economy["customers"], rng)
	if c["kind"] == "request":
		c["request"] = make_request()
	return c


func _customer_leaves() -> void:
	customer = {}
	minutes_to_customer = Customers.next_arrival_minutes(shop_appeal(), db.economy["customers"], rng)


# --- Day cycle ---------------------------------------------------------------

func open_day() -> void:
	earned_today = 0
	_reset_day_log()
	clock.open_shop()
	customer = {}
	minutes_to_customer = float(db.economy["customers"]["first_arrival_minutes"])


## Runs the night: feeding, growth, breeding. Returns a summary for the UI.
func end_day() -> Dictionary:
	clock.is_open = false
	customer = {}
	if day_log.is_empty():
		_reset_day_log()
	var summary := {
		"day": day, "earned": earned_today, "food_used": 0,
		"fry_unfed": 0, "fry_grown_up": 0, "fry_born": 0,
		"log": day_log.duplicate(true), "money_end": money,
		"born_ids": [], "grown_ids": [], "mutations": [],
	}
	# Each breeding tank is separate: its own food, growth and pair.
	for i in breeding_tanks.size():
		_night_feed_and_grow(summary, i)
		_night_breed(summary, i)
	day += 1
	# Looking ahead to tomorrow.
	summary["nights_until_brood"] = nights_until_brood()
	summary["brood_outlook"] = []
	for i in breeding_tanks.size():
		summary["brood_outlook"].append(nights_until_brood(i))
	summary["food_left"] = food_count()
	summary["fry_in_tank"] = breeding_fish().filter(func(f): return not is_adult(f)).size()
	summary["orders"] = orders.size()
	summary["backorders"] = backorders.size()
	return summary


func _night_feed_and_grow(summary: Dictionary, tank_index: int) -> void:
	var fry: Array[Fish] = []
	for f in tank_fish(breeding_tanks[tank_index]):
		if not is_adult(f):
			fry.append(f)
	if fry.is_empty():
		return
	var fed := _use_food()
	if fed:
		summary["food_used"] += 1
	for f in fry:
		if not fed:
			f.fed_every_night = false
			summary["fry_unfed"] += 1
			continue
		f.age_days += 1
		if is_adult(f):
			f.stars = Quality.roll_offspring_stars(f.parent_stars, f.fed_every_night,
				db.economy["offspring_quality_nudge"], rng)
			summary["fry_grown_up"] += 1
			summary["grown_ids"].append(f.id)


func _night_breed(summary: Dictionary, tank_index: int) -> void:
	var tank := breeding_tanks[tank_index]
	var pair := breeding_pair(tank_index)
	if pair.is_empty():
		brood_nights[tank_index] = 0
		return
	var species := species_of(pair[0])
	brood_nights[tank_index] += 1
	if brood_nights[tank_index] < int(species["days_between_broods"]):
		return
	brood_nights[tank_index] = 0
	for fry in Genetics.breed(pair[0], pair[1], species, rng):
		if not tank.has_room_for_fish():
			break
		fry.location = Fish.breeding_location(tank_index)
		inventory.add_fish(fry)
		tank.add_fish(fry.id)
		summary["fry_born"] += 1
		summary["born_ids"].append(fry.id)
		for trait_name in fry.traits:
			var value: String = fry.traits[trait_name]
			# A look neither parent has, from a recipe (pair mix) or a mutation. Worth celebrating.
			var mum: String = pair[0].get_trait(trait_name)
			var dad: String = pair[1].get_trait(trait_name)
			if value != mum and value != dad:
				var source := "recipe" if Genetics.recipe_child(species, trait_name, mum, dad) == value else "mutation"
				summary["mutations"].append({"fish_id": fry.id, "trait": trait_name, "value": value,
					"source": source, "parents": [mum, dad]})


## [mother, father] in breeding tank `tank_index`: the first adult female and an
## adult male of the same species. [] if none. Fish never pair across tanks.
func breeding_pair(tank_index: int = 0) -> Array:
	var adults := tank_fish(breeding_tanks[tank_index]).filter(func(f): return is_adult(f))
	for mother in adults:
		if mother.sex != Fish.FEMALE:
			continue
		for father in adults:
			if father.sex == Fish.MALE and father.species_id == mother.species_id:
				return [mother, father]
	return []


## Nights until breeding tank `tank_index` has its next brood, or -1 if it has no pair.
func nights_until_brood(tank_index: int = 0) -> int:
	var pair := breeding_pair(tank_index)
	if pair.is_empty():
		return -1
	return int(species_of(pair[0])["days_between_broods"]) - brood_nights[tank_index]


func food_count() -> int:
	var total := 0
	for item_id in db.items_in_category("food"):
		total += inventory.count(item_id)
	return total


func _use_food() -> bool:
	for item_id in db.items_in_category("food"):
		if inventory.remove(item_id):
			return true
	return false


# --- Helpers -----------------------------------------------------------------

func _make_tank(tank_item_id: String) -> Tank:
	return Tank.new(tank_item_id, int(db.items[tank_item_id]["capacity"]))


## Decorates a tank for free (not taken from stock). Used for the starting tank.
func _apply_starter_layout(tank: Tank, layout: Dictionary) -> void:
	var substrate: String = layout.get("substrate", "")
	if substrate != "":
		tank.set_substrate(db.items[substrate])
	var slot_items: Array = layout.get("slots", [])
	for i in mini(slot_items.size(), tank.slot_count()):
		if slot_items[i] != "":
			tank.place(i, db.items[slot_items[i]])


func _release_fish(f: Fish) -> void:
	var tank := tank_at(f.location)
	if tank != null:
		tank.remove_fish(f.id)
	inventory.remove_fish(f.id)


## Removes the display tank; its fish leave with it or go back to holding.
func _remove_display_tank(fish_leave_with_tank: bool) -> void:
	for f in tank_fish(display_tank):
		if fish_leave_with_tank:
			inventory.remove_fish(f.id)
		else:
			f.location = Fish.HOLDING
	display_tank = null
