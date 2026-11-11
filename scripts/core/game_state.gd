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
## Each accepted order gets an id (its order tank lives at Fish.order_location(id)).
var _next_order_id: int = 1
## The customer at the counter ({} when nobody is there). See Customers.make_walk_in.
var customer: Dictionary = {}
## In-game minutes until the next customer walks in.
var minutes_to_customer: float = 0.0
## Things customers asked for that were out of stock. They pay a discounted
## price when you hand them over. No deadlines. See backorder_customer().
var backorders: Array = []
## What happened today, for the end-of-day summary. Reset when the shop opens.
var day_log: Dictionary = {}
## "Closed for restock": no customers, and the clock runs faster (see
## restock_speed()) so breeding builds up stock. Stays on across days.
var restocking: bool = false
## Breeding book: recipes ("variety:red+yellow") and mutations ("variety:albino")
## you've bred at least once, with the day they were first bred.
var discovered_recipes: Dictionary = {}
var discovered_mutations: Dictionary = {}
## Breeding-book generation bonuses paid: generation (as a string) -> the day it
## was completed (0 = already complete in a save from before bonuses existed).
var book_bonuses: Dictionary = {}
## Lifetime counters ("fish_sold", "best_day", ...), used by goals.
var stats: Dictionary = {}
## Personal bests that need words: key -> {"amount": int, "what": String, "day": int,
## "tie": int}. Keys: "best_sale", "rarest_sold", "best_bred", "purest_fish". `tie` breaks a tie
## on `amount`. See _record().
var records: Dictionary = {}
## Shop reputation points. Only ever goes up. See data/reputation.json.
var reputation: int = 0
## Reputation when today began, and the level the player has already been told about.
var _rep_day_start: int = 0
var _level_announced: int = 0
## Goals reached: goal id -> the day it was reached.
var completed_goals: Dictionary = {}
## Shop upgrades bought: upgrade id -> the day it was bought.
var upgrades: Dictionary = {}
## The fish entered in the next fish show (fish id, 0 = none).
var show_entry: int = 0
## How many show days have passed (whether or not you entered).
var shows_held: int = 0
## Placings (1st to 3rd) won, newest last: {day, show_number, show_name, place, grand,
## fish: {species_id, traits, sex, stars, nickname, purity, scanned}}. The fish is a
## snapshot, so it stays even if the fish is sold.
var show_history: Array = []
## Gallery entry keys ("fav:<fish id>" or "hof:<show_history index>") pinned on the shop wall.
var gallery_pins: Array = []

## Which starting pair and challenge mode this game began with ("" = the
## standard ones). See data/new_game.json.
var start_id: String = ""
var challenge_id: String = ""

const SAVE_VERSION := 1
## A challenge can raise a species' mutation chance, but never above this.
const MAX_MUTATION_CHANCE := 0.5
## Longest name a fish can be given.
const MAX_NAME_LENGTH := 16


## Starts a game. `options` may hold "start_id" (a starting pair from
## data/new_game.json) and "challenge_id" (a mode). Unknown or missing ids fall
## back to the first start and no challenge.
static func new_game(p_db: DataDB, p_rng: RandomNumberGenerator, options: Dictionary = {}) -> GameState:
	var s := GameState.new()
	s.db = p_db
	s.rng = p_rng
	var chosen_start: Dictionary = p_db.start_by_id(str(options.get("start_id", "")))
	s.start_id = chosen_start.get("id", "")
	s.challenge_id = p_db.challenge_by_id(str(options.get("challenge_id", ""))).get("id", "")
	var start: Dictionary = p_db.economy["starting_state"]
	s.money = int(s.challenge_rule("starting_money", start["money"]))
	for item_id in start["items"]:
		s.inventory.add(item_id, int(start["items"][item_id]))
	s.display_tank = s._make_tank(start["display_tank"])
	s._add_breeding_tank()
	s._apply_starter_layout(s.display_tank, start.get("display_tank_layout", {}))
	for fish_data in s._starting_fish(chosen_start):
		var f := Fish.from_dict(fish_data, int(p_db.economy["purity"]["market"]))
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


## The starting fish (as data) for a start: its listed fish, or for a
## "random_pair" start a male and a female of two different common values of
## one trait (default guppy "variety"), both 2 stars, in the breeding tank.
func _starting_fish(chosen_start: Dictionary) -> Array:
	if not chosen_start.get("random_pair", false):
		return chosen_start.get("fish", db.economy["starting_state"]["fish"])
	var species_id: String = chosen_start.get("species_id", "guppy")
	var trait_name: String = chosen_start.get("trait", "variety")
	var species_traits: Dictionary = db.species[species_id]["traits"]
	var common: Array = species_traits[trait_name]["common"]
	var a := rng.randi_range(0, common.size() - 1)
	var b := rng.randi_range(0, common.size() - 2)
	if b >= a:
		b += 1
	var result := []
	for pick in [[Fish.MALE, common[a]], [Fish.FEMALE, common[b]]]:
		var traits := {}
		for other in species_traits:
			traits[other] = pick[1] if other == trait_name else species_traits[other]["common"][0]
		result.append({"species_id": species_id, "sex": pick[0], "stars": 2,
			"location": Fish.BREEDING, "traits": traits})
	return result


# --- Challenge modes -----------------------------------------------------------

## The active challenge's rules (data/new_game.json), or {} for the standard game.
func challenge_rules() -> Dictionary:
	for c in db.challenges:
		if c["id"] == challenge_id:
			return c.get("rules", {})
	return {}


## One rule of the active challenge, or `default` when it isn't set.
func challenge_rule(rule_name: String, default = null):
	return challenge_rules().get(rule_name, default)


## The species with its mutation chance changed by the challenge (the same
## dictionary when nothing changes, so standard games are untouched).
func breeding_species(species: Dictionary) -> Dictionary:
	var multiplier := float(challenge_rule("mutation_chance_multiplier", 1.0))
	if is_equal_approx(multiplier, 1.0):
		return species
	var adjusted := species.duplicate()
	var base := float(species["mutation_chance"])
	adjusted["mutation_chance"] = maxf(base, minf(base * multiplier, MAX_MUTATION_CHANCE))
	return adjusted


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
			if not f.favorite:  # favourites never go with a tank
				fish_total += fish_price(f)
	return Pricing.tank_price(tank, db.items, tank_aesthetics(tank), fish_total, db.economy)


func tank_at(location: String) -> Tank:
	if location == Fish.DISPLAY:
		return display_tank
	var index := Fish.breeding_index(location)
	if index >= 0 and index < breeding_tanks.size():
		return breeding_tanks[index]
	var order_index := order_index_by_id(Fish.order_id(location))
	if order_index >= 0:
		return orders[order_index].get("tank")
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
	breeding_tanks.append(Tank.new("", breeding_capacity()))
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


## False once a challenge has closed the Market's fish (see market_last_day()).
func market_fish_open() -> bool:
	var last := market_last_day()
	return last < 0 or day <= last


## The last day the Market sells fish in this game, or -1 if it always does.
func market_last_day() -> int:
	return int(challenge_rule("market_fish_until_day", -1))


## Buys an adult of a named strain into holding. Traits the strain doesn't fix
## are random common values. Returns the fish, or null if it couldn't.
func buy_strain(strain_id: String, sex: String) -> Fish:
	if not db.strains.has(strain_id) or not sex in [Fish.MALE, Fish.FEMALE] or not market_fish_open():
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
	f.purity = int(db.economy["purity"]["market"])
	f.paid = cost
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


## The fish's name for lists and messages: "Bubbles (Gold Guppy)" if it has a
## nickname, otherwise just the variety name.
func fish_title(f: Fish) -> String:
	if f.nickname == "":
		return fish_display_name(f)
	return "%s (%s)" % [f.nickname, fish_display_name(f)]


# --- Names and favourites ------------------------------------------------------

## Gives a fish a name: trimmed, control characters removed, at most
## MAX_NAME_LENGTH characters. An empty name clears it. Any fish (fry too).
func rename_fish(fish_id: int, nickname: String) -> bool:
	var f := inventory.get_fish(fish_id)
	if f == null:
		return false
	var clean := ""
	for i in nickname.length():
		var code := nickname.unicode_at(i)
		if code >= 32 and code != 127 and not (code >= 128 and code < 160):
			clean += nickname[i]
	clean = clean.strip_edges().left(MAX_NAME_LENGTH).strip_edges()
	if f.nickname == "" and clean != "":
		_count("fish_named")
	f.nickname = clean
	return true


func favorite_max() -> int:
	return int(db.economy.get("favorites", {}).get("max", 24))


func favorite_count() -> int:
	var n := 0
	for f in inventory.fish_list():
		if f.favorite:
			n += 1
	return n


## Why a fish can't be marked as a favourite, or "" if it can.
func favorite_blocker(fish_id: int) -> String:
	var f := inventory.get_fish(fish_id)
	if f == null:
		return "That fish isn't yours."
	if f.favorite:
		return "Already a favourite."
	if Fish.is_order(f.location):
		return "Take it out of the order tank first"
	if favorite_count() >= favorite_max():
		return "You can keep up to %d favourites." % favorite_max()
	return ""


## Marks or unmarks a favourite. Unmarking always works.
func set_favorite(fish_id: int, value: bool) -> bool:
	var f := inventory.get_fish(fish_id)
	if f == null:
		return false
	if value and not f.favorite and favorite_blocker(fish_id) != "":
		return false
	f.favorite = value
	return true


# --- The Gallery -------------------------------------------------------------------

## A throwaway Fish drawn from a gallery entry's looks, so the UI can reuse the
## normal fish sprite. It is full-grown and is never added to the inventory.
func entry_fish(entry: Dictionary) -> Fish:
	var f := Fish.new()
	f.id = int(entry.get("fish_id", 0))
	f.species_id = entry.get("species_id", "")
	f.traits = entry.get("traits", {}).duplicate()
	f.sex = entry.get("sex", Fish.FEMALE)
	f.stars = int(entry.get("stars", 0))
	f.nickname = entry.get("nickname", "")
	f.purity = int(entry.get("purity", 50))
	f.scanned = bool(entry.get("scanned", false))
	var species: Dictionary = db.species.get(f.species_id, {})
	f.age_days = int(species.get("days_to_adult", 1))
	return f


## A gallery entry (see gallery_favorites / gallery_hall) from a Fish.
func _gallery_entry(key: String, f: Fish, ribbons: Array) -> Dictionary:
	return {
		"key": key, "fish_id": f.id, "title": fish_title(f), "species_id": f.species_id,
		"traits": f.traits.duplicate(), "sex": f.sex, "stars": f.stars, "purity": f.purity,
		"scanned": f.scanned, "ribbons": ribbons.duplicate(true), "age_days": f.age_days,
		"nickname": f.nickname,
	}


## Every favourite fish as a portrait entry, best stars first (then by id).
func gallery_favorites() -> Array:
	var list := []
	for f in inventory.fish_list():
		if f.favorite:
			list.append(_gallery_entry("fav:%d" % f.id, f, f.ribbons))
	list.sort_custom(func(a: Dictionary, b: Dictionary):
		return a["stars"] > b["stars"] or (a["stars"] == b["stars"] and a["fish_id"] < b["fish_id"]))
	return list


## One entry per show win in show_history, newest first. They come from the
## saved snapshots, so they stay after the fish is sold. The key's number is
## the index in show_history.
func gallery_hall() -> Array:
	var list := []
	for i in show_history.size():
		var record: Dictionary = show_history[i]
		var snapshot: Dictionary = record.get("fish", {})
		var entry := _gallery_entry("hof:%d" % i, entry_fish(snapshot), [
			{"place": int(record.get("place", 3)), "show": str(record.get("show_name", "")),
				"day": int(record.get("day", 0))}])
		entry["day"] = int(record.get("day", 0))
		entry["show_number"] = int(record.get("show_number", 0))
		entry["show_name"] = str(record.get("show_name", ""))
		entry["place"] = int(record.get("place", 3))
		entry["grand"] = bool(record.get("grand", false))
		entry["fish"] = snapshot.duplicate(true)
		list.append(entry)
	list.reverse()
	return list


## How many portraits can hang on the shop wall (0 until the wall is unlocked).
func pin_slots() -> int:
	if not has_unlock("gallery_wall"):
		return 0
	return int(db.economy.get("gallery", {}).get("pin_slots", 6))


## The entry for a key, or an empty dictionary if it isn't in the gallery now.
func _gallery_lookup(key: String) -> Dictionary:
	var entries := gallery_favorites() if key.begins_with("fav:") else gallery_hall()
	for entry in entries:
		if entry["key"] == key:
			return entry
	return {}


## Why a portrait can't be pinned, or "" if it can.
func pin_blocker(key: String) -> String:
	if not has_unlock("gallery_wall"):
		return "Reach '%s' to pin portraits" % unlock_level_name("gallery_wall")
	if _gallery_lookup(key).is_empty():
		return "That portrait isn't in your gallery"
	if key in gallery_pins:
		return "Already pinned"
	if pinned_entries().size() >= pin_slots():
		return "The wall is full"
	return ""


func pin_portrait(key: String) -> bool:
	if pin_blocker(key) != "":
		return false
	gallery_pins = _live_pins()  # tidy up pins that no longer resolve
	gallery_pins.append(key)
	return true


func unpin_portrait(key: String) -> bool:
	if not key in gallery_pins:
		return false
	gallery_pins.erase(key)
	return true


## The pinned keys that still resolve to a portrait.
func _live_pins() -> Array:
	var keys := []
	for entry in pinned_entries():
		keys.append(entry["key"])
	return keys


## The pinned portraits in pin order. A pin whose favourite has been un-marked
## is quietly skipped (and dropped from the saved list when it next changes).
func pinned_entries() -> Array:
	var favourites := gallery_favorites()
	var hall := gallery_hall()
	var list := []
	for key in gallery_pins:
		for entry in (favourites if str(key).begins_with("fav:") else hall):
			if entry["key"] == key:
				list.append(entry)
				break
	return list


# --- The Lab ---------------------------------------------------------------------

## True once the shop's reputation has opened the Lab.
func lab_unlocked() -> bool:
	return has_unlock("lab")


func scan_cost() -> int:
	return int(db.economy["lab"]["scan_cost"])


## Why a fish can't be scanned right now ("" if it can).
func scan_blocker(fish_id: int) -> String:
	if not lab_unlocked():
		return "The Lab isn't open yet."
	var f := inventory.get_fish(fish_id)
	if f == null:
		return "No such fish."
	if not is_adult(f):
		return "Only grown-up fish can be scanned."
	if f.scanned:
		return "Already scanned."
	if not can_afford(scan_cost()):
		return "You need $%d more." % (scan_cost() - money)
	return ""


## Pays the fee and reveals a fish's purity. Returns {"purity", "tier"}, or {}
## if it couldn't be scanned.
func scan_fish(fish_id: int) -> Dictionary:
	if scan_blocker(fish_id) != "":
		return {}
	var f := inventory.get_fish(fish_id)
	_spend(scan_cost())
	f.scanned = true
	_count("fish_scanned")
	_record("purest_fish", f.purity, _fish_label(f))
	return {"purity": f.purity, "tier": purity_tier(f.purity)}


func purity_tier(purity: int) -> String:
	return Purity.tier_name(purity, db.economy["purity"])


## Whether this fish's price includes the certified bonus (scanned, shop-bred, pure enough).
func is_certified(f: Fish) -> bool:
	return f.scanned and f.paid == 0 and f.strain_id == "" 		and Purity.certified_bonus(f.purity, db.economy["lab"]) > 0.0


# --- Fish shows ----------------------------------------------------------------

## True once the shop's reputation has opened fish shows.
func shows_unlocked() -> bool:
	return has_unlock("fish_show") and not db.shows.is_empty()


## The show held at the end of the next show day (today, if it is one):
## {number, day, days_left, id, name, description, grand, rule}. {} if no shows.
func next_show() -> Dictionary:
	if db.shows.is_empty():
		return {}
	var number := Shows.number_for_day(day, db.shows)
	var show := Shows.describe(number, db.shows)
	show["day"] = Shows.day_of(number, db.shows)
	show["days_left"] = int(show["day"]) - day
	return show


## What a fish's looks add to its show score: the variety's price multiplier,
## rounded (1 for plain looks, 4 for a Dragon).
func show_value_step(f: Fish) -> int:
	return maxi(1, roundi(Pricing.trait_multiplier(f, species_of(f))))


## Why a fish can't be entered in the next show ("" if it can).
func show_blocker(fish_id: int) -> String:
	if not shows_unlocked():
		return "Fish shows aren't open yet."
	var f := inventory.get_fish(fish_id)
	if f == null:
		return "No such fish."
	if not is_adult(f):
		return "Only grown-up fish can enter."
	if Fish.is_order(f.location):
		return "Promised to a customer in an order tank."
	return Shows.rule_blocker(next_show()["rule"], f.stars, f.rare_trait_count(species_of(f)) > 0,
		is_mutation_fish(f), f.scanned, f.purity)


func show_eligible(fish_id: int) -> bool:
	return show_blocker(fish_id) == ""


## Enters a fish in the next show (replacing any earlier entry).
func enter_show(fish_id: int) -> bool:
	if show_blocker(fish_id) != "":
		return false
	show_entry = fish_id
	return true


func withdraw_show() -> void:
	show_entry = 0


## The fish entered, or null if none (or it was sold or no longer qualifies).
func show_entry_fish() -> Fish:
	if show_entry == 0 or show_blocker(show_entry) != "":
		return null
	return inventory.get_fish(show_entry)


## True if any fish you own could enter the next show.
func has_show_candidate() -> bool:
	return inventory.fish_list().any(func(f: Fish): return show_eligible(f.id))


## "Looks promising" / "Good chance" / "Long shot", from what the player can see.
func show_hint(f: Fish) -> String:
	var show := next_show()
	if show.is_empty():
		return ""
	return Shows.hint(int(show["number"]), bool(show["grand"]), f.stars, show_value_step(f), db.shows)


## Cash prize for a place in a show (grand shows pay more).
func show_prize(place: int, grand: bool) -> int:
	return Shows.prize(place, grand, db.shows)


## Judges tonight's show if today is a show day. The entry (if still valid)
## is scored against the rivals; places 1-3 earn a ribbon, cash and reputation.
## The result goes into summary["show"] (only when you had entered).
func _hold_show(summary: Dictionary) -> void:
	if db.shows.is_empty() or not Shows.is_show_day(day, db.shows):
		return
	var show := next_show()
	var f := show_entry_fish()
	shows_held += 1
	show_entry = 0
	if f == null:
		return  # no entry, or it was sold: nothing happens, nothing is lost
	var base := Shows.base_score(f.stars, show_value_step(f), f.purity, db.shows)
	var result := Shows.judge(base, int(show["number"]), bool(show["grand"]), db.shows, rng)
	var place: int = result["place"]
	var rep_before := reputation
	_count("shows_entered")
	_rep("show_entered")
	var prize := show_prize(place, bool(show["grand"]))
	if place <= 3:
		var key: String = ["", "show_first", "show_second", "show_third"][place]
		_rep(key)
		_count(["", "ribbons_first", "ribbons_second", "ribbons_third"][place])
		if place == 1 and bool(show["grand"]):
			_count("grand_wins")
		if prize > 0:
			money += prize
			_count("show_prizes", prize)
		f.ribbons.append({"place": place, "show": show["name"], "day": day})
		show_history.append({
			"day": day, "show_number": show["number"], "show_name": show["name"],
			"place": place, "grand": show["grand"],
			"fish": {"fish_id": f.id, "species_id": f.species_id, "traits": f.traits.duplicate(), "sex": f.sex,
				"stars": f.stars, "nickname": f.nickname, "purity": f.purity, "scanned": f.scanned},
		})
	var top := []
	for r in result["rivals"].slice(0, 3):
		top.append({"name": r["name"], "score": roundi(r["score"])})
	summary["show"] = {
		"entered": true, "show_name": show["name"], "grand": show["grand"], "place": place,
		"prize": prize, "rep": reputation - rep_before,
		"fish_label": f.nickname if f.nickname != "" else fish_display_name(f),
		"top_rivals": top, "your_score": roundi(result["your_score"]),
	}


# --- Selling -----------------------------------------------------------------

func _earn(amount: int, category: String) -> void:
	money += amount
	earned_today += amount
	_count("total_earned", amount)
	if day_log.is_empty():
		_reset_day_log()
	var sale: Array = day_log["sales"].get(category, [0, 0])
	day_log["sales"][category] = [sale[0] + 1, sale[1] + amount]


func _spend(amount: int) -> void:
	money -= amount
	_count("total_spent", amount)
	if day_log.is_empty():
		_reset_day_log()
	day_log["spent"] += amount


func _reset_day_log() -> void:
	day_log = {"money_start": money, "sales": {}, "spent": 0, "served": 0, "walked_out": 0, "goals": []}


## Sells one item from stock. Returns the money earned (0 if it couldn't).
func sell_item(item_id: String) -> int:
	if not db.items.has(item_id) or not inventory.remove(item_id):
		return 0
	var price := Pricing.item_price(db.items[item_id])
	_earn(price, "item")
	_count("items_sold")
	return price


## Sells an adult fish from wherever it is. Returns the money earned (0 if it couldn't).
func sell_fish(fish_id: int) -> int:
	var f := inventory.get_fish(fish_id)
	if f == null or not is_adult(f) or f.favorite:
		return 0
	var price := fish_price(f)
	_release_fish(f)
	_earn(price, "fish")
	_count_fish_sold(f, price, "")
	return price


func wholesale_price(f: Fish) -> int:
	var bonus := upgrade_effect("wholesale_fraction")
	if bonus > 0.0 and is_adult(f):
		return maxi(1, roundi(fish_price(f) * (float(db.economy["wholesale"]["fraction"]) + bonus)))
	return Pricing.wholesale_price(f, species_of(f), db.economy)


## Sells any fish (fry too) to the wholesaler: instant, no customer needed,
## but for less than a customer would pay. Returns the money earned.
func sell_fish_wholesale(fish_id: int) -> int:
	var f := inventory.get_fish(fish_id)
	if f == null or f.favorite:
		return 0
	var price := wholesale_price(f)
	_release_fish(f)
	_earn(price, "wholesale")
	_count("wholesale_sold")
	return price


## Sells the finished display tank. Without fish, its fish go back to holding.
func sell_display_tank(include_fish: bool) -> int:
	if display_tank == null:
		return 0
	var price := tank_price(display_tank, include_fish)
	_remove_display_tank(include_fish)
	_earn(price, "tank")
	_count("tanks_sold")
	_record("best_sale", price, "Display tank")
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
	if Fish.is_order(to) and f.favorite:
		return "Favourites stay with you. Un-favourite it first."
	if (to == Fish.DISPLAY or Fish.is_order(to)) and not is_adult(f):
		return "Fry stay in the back room until they grow up."
	var target := tank_at(to)
	if to != Fish.HOLDING:
		if target == null:
			if to == Fish.DISPLAY:
				return "There's no tank on display."
			if Fish.is_order(to):
				return "Set up this order's tank first."
			return "You don't have that breeding tank yet."
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


## How many special orders you can hold at once.
func max_orders() -> int:
	return int(db.economy["requests"]["max_orders"]) + int(upgrade_effect("max_orders")) \
		+ reputation_effect("extra_orders")


func can_accept_request() -> bool:
	return orders.size() < max_orders()


func accept_request(request: Dictionary) -> bool:
	if not can_accept_request():
		return false
	request["id"] = _next_order_id
	_next_order_id += 1
	request["tank"] = null
	orders.append(request)
	return true


func order_index_by_id(order_id: int) -> int:
	for i in orders.size():
		if int(orders[i].get("id", -1)) == order_id:
			return i
	return -1


## The order's own tank (built separately from the display tank), or null.
func order_tank(order_index: int) -> Tank:
	if order_index < 0 or order_index >= orders.size():
		return null
	return orders[order_index].get("tank")


## An empty tank item you have in stock, or "".
func spare_tank_item() -> String:
	for item_id in db.items_in_category("tank"):
		if inventory.count(item_id) > 0:
			return item_id
	return ""


## Why an order tank can't be set up, or "" if it can.
func order_tank_blocker(order_index: int) -> String:
	if order_index < 0 or order_index >= orders.size():
		return "No such order."
	if order_tank(order_index) != null:
		return "This order already has a tank."
	if spare_tank_item() == "":
		return "You need an empty tank. Buy one in the Market (Supplies)."
	return ""


## Sets up a separate tank for this order, using an empty tank from stock.
func start_order_tank(order_index: int) -> bool:
	if order_tank_blocker(order_index) != "":
		return false
	var item_id := spare_tank_item()
	inventory.remove(item_id)
	orders[order_index]["tank"] = _make_tank(item_id)
	return true


## What delivering would pay, without doing it: the order's own tank if
## `from_order_tank`, otherwise the display tank.
func preview_delivery(order_index: int, from_order_tank: bool = false) -> Dictionary:
	if order_index < 0 or order_index >= orders.size():
		return {}
	var tank := order_tank(order_index) if from_order_tank else display_tank
	if tank == null:
		return {}
	return RequestScoring.score(orders[order_index], tank, tank_fish(tank).filter(func(f): return not f.favorite),
		db.items, tank_aesthetics(tank), tank_price(tank, true), db.economy)


## Hands a tank (with its fish) to the customer: the order's own tank, or the
## display tank. Returns the score breakdown ({} if it couldn't).
func deliver_order(order_index: int, from_order_tank: bool = false) -> Dictionary:
	var result := preview_delivery(order_index, from_order_tank)
	if result.is_empty():
		return {}
	var order: Dictionary = orders[order_index]
	var customer_name: String = order.get("customer", "")
	var what := "%s for %s" % ["Order tank" if from_order_tank else "Display tank", customer_name] \
		if customer_name != "" else "Special order"
	if from_order_tank:
		for f in tank_fish(order["tank"]):
			inventory.remove_fish(f.id)
		order["tank"] = null
	else:
		_remove_display_tank(true)
		_dismantle_order_tank(order)  # a half-built order tank goes back to stock
	orders.remove_at(order_index)
	_earn(result["payout"], "order")
	_count("orders_delivered")
	_rep("order_delivered")
	_record("best_sale", int(result["payout"]), what)
	return result


## No penalty. A started order tank goes back to stock: the tank, its
## decorations, and its fish (to holding).
func cancel_order(order_index: int) -> bool:
	if order_index < 0 or order_index >= orders.size():
		return false
	_dismantle_order_tank(orders[order_index])
	orders.remove_at(order_index)
	return true


func _dismantle_order_tank(order: Dictionary) -> void:
	var tank: Tank = order.get("tank")
	if tank == null:
		return
	for item_id in tank.placed_item_ids():
		inventory.add(item_id)
	if tank.tank_item_id != "":
		inventory.add(tank.tank_item_id)
	for f in tank_fish(tank):
		f.location = Fish.HOLDING
	order["tank"] = null


# --- Closed for restock ------------------------------------------------------

## How much faster the clock runs while closed for restock (0 = feature off).
func restock_speed() -> float:
	return float(db.economy["clock"].get("restock_speed", 0))


## Turns "Closed for restock" on or off. Turning it on sends any waiting
## customer home (no penalty). Returns false if the feature is switched off in data.
func set_restocking(on: bool) -> bool:
	if on and restock_speed() <= 0.0:
		return false
	restocking = on
	if on and not customer.is_empty():
		_customer_leaves()
	return true


## How fast the clock should run right now (1 normally).
func time_scale() -> float:
	return restock_speed() if restocking else 1.0


# --- Customers ---------------------------------------------------------------

func shop_appeal() -> float:
	var looks := tank_aesthetics(display_tank) if display_tank != null else 0
	return Customers.shop_appeal(inventory.fish_list(Fish.DISPLAY), inventory.fish_list(Fish.HOLDING),
		breeding_fish(), looks, db.species, db.economy["customers"])


## Moves customer timers on by `minutes` of in-game time while the shop is open.
## Returns true if someone arrived at or left the counter.
func tick_customers(minutes: float) -> bool:
	if minutes <= 0.0 or not clock.is_open or restocking:
		return false
	if not customer.is_empty():
		customer["waited"] += minutes
		if customer["waited"] >= customer["patience"]:
			day_log["walked_out"] = day_log.get("walked_out", 0) + 1
			_count("walked_out")
			_customer_leaves()  # no penalty, they just wander off
			return true
		return false
	minutes_to_customer -= minutes
	if minutes_to_customer > 0.0:
		return false
	customer = _new_customer()
	return true


## Fish customers can see and buy: adults on display or in holding, except
## favourites (those are kept back).
func fish_for_sale() -> Array:
	var result := []
	for f in inventory.fish_list(Fish.DISPLAY) + inventory.fish_list(Fish.HOLDING):
		if is_adult(f) and not f.favorite:
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
		"wish_item":
			return Customers.backorder_price(wish_full_price(customer), db.economy["backorders"])
		"wish_fish":
			return fish_wish_terms(customer["wish"])["price"]
		"collector":
			var cf := inventory.get_fish(customer["fish_id"])
			return collector_price(cf) if cf != null else 0
	return 0


## Why the customer's wish can't be met right now, or "" if it can.
func customer_blocker() -> String:
	match customer.get("kind", ""):
		"fish":
			var f := inventory.get_fish(customer["fish_id"])
			if f == null or not is_adult(f) or f.favorite:
				return "That fish isn't available any more."
		"collector":
			var cf := inventory.get_fish(customer["fish_id"])
			if cf == null or not is_collector_fish(cf):
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
	var fish_sold: Fish = null
	if customer["kind"] in ["fish", "collector"]:
		fish_sold = inventory.get_fish(customer["fish_id"])
	match customer["kind"]:
		"fish":
			earned = sell_fish(customer["fish_id"])
		"item":
			earned = sell_item(customer["item_id"])
		"tank":
			earned = sell_display_tank(customer.get("with_fish", true))
		"collector":
			earned = _sell_to_collector(customer["fish_id"])
	if earned > 0:
		# Reputation comes only from selling to customers, never from buying.
		_rep("sale", _star_bonus(fish_sold.stars) if fish_sold != null else 0)
	day_log["served"] = day_log.get("served", 0) + 1
	_count("customers_served")
	_customer_leaves()
	return earned


# --- Collectors ----------------------------------------------------------------

## Collector rules from data (min_stars, price_multipliers); {} if switched off.
func collector_rules() -> Dictionary:
	return db.economy["customers"].get("collector", {})


## True when a collector would buy this fish: an adult for sale (same pool as
## fish_for_sale), at least min_stars, and bred by you. Fish bought at the Market
## (they have a price paid or a strain) never qualify: collectors pay more than
## the Market charges, so that would be a buy-and-resell money loop.
func is_collector_fish(f: Fish) -> bool:
	var rules := collector_rules()
	if rules.is_empty() or f.favorite or f.paid != 0 or f.strain_id != "" or f.stars < int(rules["min_stars"]):
		return false
	if bool(challenge_rule("customers_buy_only_mutations", false)) and not is_mutation_fish(f):
		return false
	return is_adult(f) and f.location in [Fish.DISPLAY, Fish.HOLDING]


## Fish a collector could ask for right now.
func collector_fish() -> Array:
	return fish_for_sale().filter(func(f): return is_collector_fish(f))


## True when any of the fish's looks is a mutation (Genetics.is_mutation).
func is_mutation_fish(f: Fish) -> bool:
	var species := species_of(f)
	for trait_name in f.traits:
		if Genetics.is_mutation(species, trait_name, f.traits[trait_name]):
			return true
	return false


## Fish a walk-in "fish" customer might ask for. Under a challenge that only
## sells mutations, just those.
func fish_for_customers() -> Array:
	if not bool(challenge_rule("customers_buy_only_mutations", false)):
		return fish_for_sale()
	return fish_for_sale().filter(func(f): return is_mutation_fish(f))


## What a collector pays: the usual price times a multiplier for the stars.
func collector_price(f: Fish) -> int:
	var multipliers: Dictionary = collector_rules().get("price_multipliers", {})
	return roundi(fish_price(f) * float(multipliers.get(str(f.stars), 1.0)))


func _sell_to_collector(fish_id: int) -> int:
	var f := inventory.get_fish(fish_id)
	if f == null or not is_collector_fish(f):
		return 0
	var price := collector_price(f)
	_release_fish(f)
	_earn(price, "collector")
	_count_fish_sold(f, price, " to a collector")
	_count("collector_sales")
	_rep("collector_sale")
	return price


func accept_customer_request() -> bool:
	if customer.get("kind") != "request":
		return false
	customer["request"]["customer"] = customer["name"]
	if not accept_request(customer["request"]):
		return false
	_customer_leaves()
	return true


# --- Back-orders ---------------------------------------------------------------

## How many back-orders you can hold at once.
func max_backorders() -> int:
	return int(db.economy["backorders"]["max"]) + int(upgrade_effect("max_backorders"))


func can_backorder() -> bool:
	return backorders.size() < max_backorders()


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
		"collector":
			return false  # they want one of your own bred fish or nothing
	return false


## Full (undiscounted) price of an item a customer wishes for.
func wish_full_price(wish: Dictionary) -> int:
	return Pricing.item_price(db.items[wish["item_id"]])


## Fish a customer could ask you to get for them, when you don't have one for sale:
##   - Market varieties: you order one in. 10% under Market price (the
##     usual back-order discount, since you didn't have it), back tomorrow.
##   - Bred-only varieties you've unlocked in the breeding book: you breed one.
##     Double price, back in a week.
## Never mutations (those are random), and never a variety you already have for
## sale (they'd just buy that one).
## [{species_id, trait, value, source: "market" | "bred", strain_id}]
func wishable_fish() -> Array:
	var result := []
	var seen := {}
	for f in fish_for_sale():
		for trait_name in f.traits:
			seen["%s:%s:%s" % [f.species_id, trait_name, f.traits[trait_name]]] = true
	var strain_ids := db.strains.keys()
	strain_ids.sort()
	for id in strain_ids:
		var strain: Dictionary = db.strains[id]
		if strain["traits"].size() != 1 or not market_fish_open():
			continue
		var trait_name: String = strain["traits"].keys()[0]
		_add_wish(result, seen, strain["species"], trait_name, strain["traits"][trait_name], "market", id)
	var species_ids := db.species.keys()
	species_ids.sort()
	for species_id in species_ids:
		for r in book_recipes(species_id):
			if r["discovered"]:
				_add_wish(result, seen, species_id, r["trait"], r["child"], "bred", "")
	return result


func _add_wish(result: Array, seen: Dictionary, species_id: String, trait_name: String, value: String,
		source: String, strain_id: String) -> void:
	var key := "%s:%s:%s" % [species_id, trait_name, value]
	if seen.has(key) or Genetics.is_mutation(db.species[species_id], trait_name, value):
		return
	seen[key] = true
	result.append({"species_id": species_id, "trait": trait_name, "value": value,
		"source": source, "strain_id": strain_id})


## Price and wait for a fish wish: {price, wait_days}.
func fish_wish_terms(wish: Dictionary) -> Dictionary:
	var rules: Dictionary = db.economy["backorders"]
	if wish["source"] == "market":
		return {"price": Customers.backorder_price(strain_cost(wish["strain_id"]), rules),
			"wait_days": int(rules["market_wait_days"])}
	var spec := Fish.new()
	spec.species_id = wish["species_id"]
	spec.stars = int(rules["bred_reference_stars"])
	spec.traits = {wish["trait"]: wish["value"]}
	spec.age_days = int(db.species[wish["species_id"]]["days_to_adult"])
	return {"price": roundi(fish_price(spec) * float(rules["bred_price_multiplier"])),
		"wait_days": int(rules["bred_wait_days"])}


## Takes the customer's order for something you don't have. Items: they pay the
## discounted price when you hand it over. Fish: the wish's price, and they come
## back after its wait (tomorrow for Market fish, a week for bred ones).
func backorder_customer() -> bool:
	if not customer_can_backorder():
		return false
	var order := {"name": customer["name"]}
	if customer.has("item_id"):
		order["item_id"] = customer["item_id"]
		order["price"] = Customers.backorder_price(wish_full_price(order), db.economy["backorders"])
	else:
		var wish: Dictionary = customer["wish"]
		var terms := fish_wish_terms(wish)
		order["species_id"] = wish["species_id"]
		order["sex"] = customer["sex"]
		order["traits"] = {wish["trait"]: wish["value"]}
		order["source"] = wish["source"]
		order["price"] = terms["price"]
		order["due_day"] = day + terms["wait_days"]
	backorders.append(order)
	_customer_leaves()
	return true


## The fish you'd hand over for a fish back-order: a matching adult (same look
## and sex) from holding, the display tank or a breeding tank, but never one of
## a tank's current breeding group (the sire and its mothers), nor a fish you
## chose to keep (or marked as a favourite).
func backorder_fish(order: Dictionary) -> Fish:
	var candidates: Array = inventory.fish_list(Fish.HOLDING) + inventory.fish_list(Fish.DISPLAY)
	for i in breeding_tanks.size():
		var group := breeding_group_fish(i)
		for f in tank_fish(breeding_tanks[i]):
			if not f in group:
				candidates.append(f)
	for f in candidates:
		if f.favorite or f.id == int(order.get("keep_id", -1)):
			continue
		if _matches_breed_order(f, order):
			return f
	return null


func _matches_breed_order(f: Fish, order: Dictionary) -> bool:
	if f.species_id != order["species_id"] or f.sex != order["sex"] or not is_adult(f):
		return false
	for trait_name in order["traits"]:
		if f.get_trait(trait_name) != order["traits"][trait_name]:
			return false
	return true


## Why a back-order can't be handed over yet, or "" if it can.
func backorder_blocker(index: int) -> String:
	if index < 0 or index >= backorders.size():
		return "No such back-order."
	var order: Dictionary = backorders[index]
	if order.has("item_id"):
		return "" if inventory.count(order["item_id"]) > 0 else "Not in stock yet. Buy it in the Market."
	if day < int(order.get("due_day", 0)):
		return "They'll come back for it on Day %d." % order["due_day"]
	if backorder_fish(order) == null:
		if order.get("source") == "market":
			if not market_fish_open():
				return "The Market no longer sells fish. Breed one, or cancel this order (no penalty)."
			return "No matching adult yet. Buy one in the Market."
		return "No matching adult yet. Breed one (the breeding group itself is never handed over)."
	return ""


# --- Breed-to-order: keep your stock, breed one for the customer ----------------

## What you paid for a fish, if anything (bred fish are free).
func fish_paid(f: Fish) -> int:
	return f.paid


## True when the customer wants one of your fish and selling it now would be
## below what you paid, so you can offer to breed them one instead.
func customer_can_breed_order() -> bool:
	# Only "fish" customers: a collector can't be breed-ordered (see customer_can_backorder).
	if customer.get("kind") != "fish" or not can_backorder():
		return false
	var f := inventory.get_fish(customer["fish_id"])
	return f != null and is_adult(f) and not f.favorite and customer_price() < f.paid


## Promise the customer a fish like the one they asked for (same look and sex),
## bred by you. They pay the price they were quoted when they collect it in
## 2–3 days. You keep the original fish.
func breed_order_for_customer() -> bool:
	if not customer_can_breed_order():
		return false
	var f := inventory.get_fish(customer["fish_id"])
	var wait: Array = db.economy["backorders"]["breed_wait_days"]
	backorders.append({
		"name": customer["name"], "species_id": f.species_id, "sex": f.sex,
		"keep_id": f.id,  # the fish you chose to keep is never handed over
		"traits": f.traits.duplicate(), "price": customer_price(),
		"due_day": day + rng.randi_range(int(wait[0]), int(wait[1])),
	})
	_customer_leaves()
	return true


func fulfil_backorder(index: int) -> int:
	if backorder_blocker(index) != "":
		return 0
	var order: Dictionary = backorders[index]
	if order.has("item_id"):
		inventory.remove(order["item_id"])
	else:
		var f := backorder_fish(order)
		_release_fish(f)
		_count_fish_sold(f, int(order["price"]), " for %s" % order["name"])
	if order.has("item_id"):
		_record("best_sale", int(order["price"]), "%s for %s" % [db.items[order["item_id"]]["name"], order["name"]])
	backorders.remove_at(index)
	_earn(order["price"], "backorder")
	_count("backorders_filled")
	_rep("backorder_filled")
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
		"fish_for_sale": fish_for_customers(), "species_db": db.species,
		"items_in_stock": inventory.stock().keys(), "all_items": db.items.keys(),
		"wishable": wishable_fish() if can_backorder() and not bool(challenge_rule("customers_buy_only_mutations", false)) else [],
		"tank_for_sale": tank_for_sale, "can_take_request": can_accept_request(),
		"collector_fish": collector_fish(),
	}
	if not can_backorder():
		ctx["all_items"] = []
	var c := Customers.make_walk_in(ctx, db.economy["customers"], rng)
	c["patience"] *= 1.0 + upgrade_effect("patience")
	if c["kind"] == "request":
		c["request"] = make_request()
	return c


func _customer_leaves() -> void:
	customer = {}
	minutes_to_customer = Customers.next_arrival_minutes(shop_appeal(), db.economy["customers"], rng) \
		/ customer_speed()


# --- Day cycle ---------------------------------------------------------------

func open_day() -> void:
	_rep_day_start = reputation
	_level_announced = reputation_level()
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
		"born_ids": [], "grown_ids": [], "mutations": [], "discoveries": [], "book_bonuses": [],
	}
	# Each breeding tank is separate: its own food, growth and pair.
	for i in breeding_tanks.size():
		_night_feed_and_grow(summary, tank_fish(breeding_tanks[i]))
		_night_breed(summary, i)
	# Fry moved out to holding (to make room) keep growing there too.
	_night_feed_and_grow(summary, inventory.fish_list(Fish.HOLDING))
	_count("fish_bred", summary["fry_born"])
	_record_best("best_day", earned_today)
	_hold_show(summary)
	check_goals()
	summary["goals"] = day_log["goals"].duplicate(true)
	summary["reputation"] = {
		"before_level": reputation_level_at(_rep_day_start), "after_level": reputation_level(),
		"gained": reputation - _rep_day_start, "points": reputation, "level_name": reputation_level_name(),
	}
	_level_announced = reputation_level()  # the summary tells the player
	summary["money_end"] = money
	day += 1
	# Looking ahead to tomorrow.
	summary["nights_until_brood"] = nights_until_brood()
	summary["brood_outlook"] = []
	for i in breeding_tanks.size():
		summary["brood_outlook"].append(nights_until_brood(i))
	summary["food_left"] = food_count()
	summary["fry_in_tank"] = (breeding_fish() + inventory.fish_list(Fish.HOLDING)) \
		.filter(func(f): return not is_adult(f)).size()
	summary["orders"] = orders.size()
	summary["backorders"] = backorders.size()
	return summary


## Feeds one group of fish (a breeding tank, or holding): if it has fry, it
## uses one portion of food and they all grow a day. No food = no growth
## tonight, but no harm.
func _night_feed_and_grow(summary: Dictionary, group: Array) -> void:
	var fry: Array[Fish] = []
	for f in group:
		if not is_adult(f):
			fry.append(f)
	if fry.is_empty():
		return
	var auto := upgrade_effect("auto_feed") > 0.0  # auto-feeders use no food
	var fed := auto or _use_food()
	if fed and not auto:
		summary["food_used"] += 1
	for f in fry:
		if not fed:
			f.fed_every_night = false
			summary["fry_unfed"] += 1
			continue
		f.age_days += 1
		if is_adult(f):
			f.stars = Quality.roll_offspring_stars(f.parent_stars, f.fed_every_night, _star_nudges(f.purity), rng)
			_count("fish_grown")
			_record_best("best_stars_bred", f.stars)
			_record("best_bred", f.stars, _fish_label(f), _variety_value(f))
			summary["fry_grown_up"] += 1
			summary["grown_ids"].append(f.id)


func _night_breed(summary: Dictionary, tank_index: int) -> void:
	var tank := breeding_tanks[tank_index]
	var group := breeding_group(tank_index)
	if group["mothers"].is_empty():
		brood_nights[tank_index] = 0
		return
	var father: Fish = group["father"]
	var species := species_of(father)
	brood_nights[tank_index] += 1
	if brood_nights[tank_index] < brood_interval(species):
		return
	brood_nights[tank_index] = 0
	var breeding_rules := breeding_species(species)
	# Every mother has her own brood; fry fill the tank until it is full.
	for mother in group["mothers"]:
		for fry in Genetics.breed(mother, father, breeding_rules, rng):
			if not tank.has_room_for_fish():
				return
			fry.purity = Purity.offspring_purity(mother, father, fry, db.economy["purity"])
			fry.location = Fish.breeding_location(tank_index)
			inventory.add_fish(fry)
			tank.add_fish(fry.id)
			summary["fry_born"] += 1
			summary["born_ids"].append(fry.id)
			for trait_name in fry.traits:
				var value: String = fry.traits[trait_name]
				# A look neither parent has, from a recipe (pair mix) or a mutation. Worth celebrating.
				var mum: String = mother.get_trait(trait_name)
				var dad: String = father.get_trait(trait_name)
				if value != mum and value != dad:
					var source := "recipe" if Genetics.recipe_child(species, trait_name, mum, dad) == value else "mutation"
					summary["mutations"].append({"fish_id": fry.id, "trait": trait_name, "value": value,
						"source": source, "parents": [mum, dad]})
					_discover(summary, source, species, trait_name, value, [mum, dad])


## Records a first-time recipe or mutation in the breeding book.
## Pays the book reward (straight into money, not a sale, like goal rewards) and,
## when this completes a generation of recipes, that generation's bonus.
func _discover(summary: Dictionary, source: String, species: Dictionary, trait_name: String, value: String,
		parents: Array) -> void:
	var book := discovered_recipes if source == "recipe" else discovered_mutations
	var key := book_key(trait_name, parents[0], parents[1]) if source == "recipe" else "%s:%s" % [trait_name, value]
	if book.has(key):
		return
	book[key] = day
	_rep("recipe_discovered" if source == "recipe" else "mutation_discovered")
	var generation := 0
	var reward := mutation_reward()
	if source == "recipe":
		generation = Genetics.pair_generation(species, trait_name, parents[0], parents[1])
		reward = recipe_reward(generation)
	_pay_book(reward)
	summary["discoveries"].append({"source": source, "trait": trait_name, "value": value, "parents": parents,
		"generation": generation, "reward": reward})
	if source == "recipe" and not book_bonuses.has(str(generation)) and is_generation_complete(generation):
		var bonus := generation_bonus(generation)
		book_bonuses[str(generation)] = day
		_pay_book(bonus)
		summary["book_bonuses"].append({"generation": generation, "reward": bonus})


func _pay_book(amount: int) -> void:
	money += amount
	_count("book_rewards", amount)


# --- Breeding book -------------------------------------------------------------

## Book key for a recipe: the trait and both parent values, in either order.
static func book_key(trait_name: String, a: String, b: String) -> String:
	var pair := [a, b]
	pair.sort()
	return "%s:%s+%s" % [trait_name, pair[0], pair[1]]


## What the book pays the first time a recipe of this generation is bred
## (deeper generations than the list use its last entry). 0 if not set in data.
func recipe_reward(generation: int) -> int:
	var list: Array = db.economy.get("breeding_book", {}).get("recipe_rewards", [])
	if list.is_empty() or generation < 1:
		return 0
	return int(list[mini(generation - 1, list.size() - 1)])


## What the book pays for each newly bred mutation.
func mutation_reward() -> int:
	return int(db.economy.get("breeding_book", {}).get("mutation_reward", 0))


## What the book pays once every recipe of this generation has been found.
func generation_bonus(generation: int) -> int:
	var list: Array = db.economy.get("breeding_book", {}).get("generation_bonus", [])
	if list.is_empty() or generation < 1:
		return 0
	return int(list[mini(generation - 1, list.size() - 1)])


## True when the generation has recipes and you've found them all (any species).
func is_generation_complete(generation: int) -> bool:
	var total := 0
	for species_id in db.species:
		for r in book_recipes(species_id):
			if r["generation"] == generation:
				total += 1
				if not r["discovered"]:
					return false
	return total > 0


## How many discovered recipes are of this generation (any species).
func discovered_recipe_count(generation: int) -> int:
	var count := 0
	for species_id in db.species:
		for r in book_recipes(species_id):
			if r["generation"] == generation and r["discovered"]:
				count += 1
	return count


## Every recipe of a species, discovered or not:
## [{trait, parents, child, generation, discovered (bool), day (first bred, or 0)}]
func book_recipes(species_id: String) -> Array:
	var result := []
	var recipes: Dictionary = db.species[species_id].get("recipes", {})
	for trait_name in recipes:
		for recipe in recipes[trait_name]:
			var key := book_key(trait_name, recipe["parents"][0], recipe["parents"][1])
			result.append({"trait": trait_name, "parents": recipe["parents"], "child": recipe["child"],
				"generation": Genetics.pair_generation(db.species[species_id], trait_name,
					recipe["parents"][0], recipe["parents"][1]),
				"discovered": discovered_recipes.has(key), "day": discovered_recipes.get(key, 0)})
	return result


## Every mutation of a species, discovered or not:
## [{trait, value, weight, discovered (bool), day}]
func book_mutations(species_id: String) -> Array:
	var result := []
	var species: Dictionary = db.species[species_id]
	for trait_name in species["traits"]:
		var t: Dictionary = species["traits"][trait_name]
		for value in Genetics.mutation_pool(species, trait_name):
			var key := "%s:%s" % [trait_name, value]
			result.append({"trait": trait_name, "value": value,
				"weight": float(t.get("mutation_weights", {}).get(value, 1.0)),
				"discovered": discovered_mutations.has(key), "day": discovered_mutations.get(key, 0)})
	return result


## The breeding group of tank `tank_index`: the sire is the first adult male who
## has at least one adult female of his species in the tank, and every such
## female (in tank order, up to economy.breeding_tanks.max_mothers) is a
## mother. {"father": Fish or null, "mothers": Array[Fish]}; no group = null
## father and no mothers. Fish never pair across tanks.
func breeding_group(tank_index: int = 0) -> Dictionary:
	var adults := tank_fish(breeding_tanks[tank_index]).filter(func(f): return is_adult(f))
	for father in adults:
		if father.sex != Fish.MALE:
			continue
		var mothers: Array[Fish] = []
		for f in adults:
			if f.sex == Fish.FEMALE and f.species_id == father.species_id and mothers.size() < max_mothers():
				mothers.append(f)
		if not mothers.is_empty():
			return {"father": father, "mothers": mothers}
	return {"father": null, "mothers": [] as Array[Fish]}


## Every fish in tank `tank_index`'s breeding group: the sire, then the mothers.
func breeding_group_fish(tank_index: int = 0) -> Array[Fish]:
	var group := breeding_group(tank_index)
	var result: Array[Fish] = []
	if group["father"] != null:
		result.append(group["father"])
		result.append_array(group["mothers"])
	return result


## How many mothers one sire serves in a tank (data; 1 if not set).
func max_mothers() -> int:
	return maxi(1, int(db.economy["breeding_tanks"].get("max_mothers", 1)))


## [first mother, father] in breeding tank `tank_index`, or [] if there is no
## group. See breeding_group() for the rest of the mothers.
func breeding_pair(tank_index: int = 0) -> Array:
	var group := breeding_group(tank_index)
	if group["mothers"].is_empty():
		return []
	return [group["mothers"][0], group["father"]]


## Nights until breeding tank `tank_index` has its next brood, or -1 if it has no pair.
func nights_until_brood(tank_index: int = 0) -> int:
	var group := breeding_group(tank_index)
	if group["mothers"].is_empty():
		return -1
	return brood_interval(species_of(group["father"])) - brood_nights[tank_index]


## Nights between a pair's broods (tank heaters shorten it; never below 1).
func brood_interval(species: Dictionary) -> int:
	return maxi(1, int(species["days_between_broods"]) - int(upgrade_effect("brood_nights")))


## The star-nudge odds for fry growing up. Conditioning food swaps the
## "fed every night" odds for the better "premium" ones.
## A high-purity line shifts both sets of odds towards better stars (Purity.star_shift).
func _star_nudges(purity: int = -1) -> Dictionary:
	var nudges: Dictionary = db.economy["offspring_quality_nudge"]
	var result: Dictionary = nudges
	if upgrade_effect("premium_food") > 0.0 and nudges.has("premium"):
		result = {"normal": nudges["normal"], "fed": nudges["premium"]}
	var shift := Purity.star_shift(purity, db.economy["purity"]) if purity >= 0 else 0.0
	if shift > 0.0:
		result = {"normal": Purity.shift_weights(result["normal"], shift),
			"fed": Purity.shift_weights(result["fed"], shift)}
	return result


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


# --- Stats and goals -----------------------------------------------------------

func stat(stat_name: String) -> int:
	return int(stats.get(stat_name, 0))


func _count(stat_name: String, amount: int = 1) -> void:
	stats[stat_name] = stat(stat_name) + amount


func _record_best(stat_name: String, value: int) -> void:
	if value > stat(stat_name):
		stats[stat_name] = value


## Counts a fish sold to a customer (not the wholesaler) and updates the
## best-sale and rarest-sold records. `suffix` says who bought it ("" for a
## walk-in, " to a collector", " for Rosa").
func _count_fish_sold(f: Fish, price: int, suffix: String) -> void:
	_count("fish_sold")
	_record_best("best_stars_sold", f.stars)
	var what := _fish_label(f) + suffix
	_record("best_sale", price, what)
	_record("rarest_sold", _variety_value(f), what, f.stars)


## "★★★★★ Koi Guppy": stars, then the fish's name. For the records.
func _fish_label(f: Fish) -> String:
	return ("%s %s" % ["★".repeat(f.stars), fish_title(f)]).strip_edges()


## How much a fish's looks multiply its price, times 100 (a whole number so it
## saves cleanly): Pricing.trait_multiplier(). 100 for plain looks.
func _variety_value(f: Fish) -> int:
	return roundi(Pricing.trait_multiplier(f, species_of(f)) * 100.0)


## Keeps a personal best in `records` if it beats the old one: a higher
## `amount`, or the same amount with a higher `tie`. Stamped with today.
func _record(key: String, amount: int, what: String, tie: int = 0) -> void:
	var old: Dictionary = records.get(key, {})
	if not old.is_empty():
		var old_amount := int(old["amount"])
		if amount < old_amount or (amount == old_amount and tie <= int(old.get("tie", 0))):
			return
	records[key] = {"amount": amount, "what": what, "day": day, "tie": tie}


## The current number behind a goal metric (see DataDB.GOAL_METRICS).
func goal_value(metric: String) -> int:
	match metric:
		"recipes":
			return discovered_recipes.size()
		"mutations":
			return discovered_mutations.size()
		"third_gen_recipes":
			return discovered_recipe_count(3)
		"breeding_tanks":
			return breeding_tanks.size()
		"upgrades":
			return upgrades.size()
		"display_looks":
			return tank_aesthetics(display_tank) if display_tank != null else 0
		"best_day":
			return maxi(stat("best_day"), earned_today)
		"favorites":
			return favorite_count()
		"reputation_level":
			return reputation_level() + 1
		"best_purity_scanned":
			return int(records.get("purest_fish", {}).get("amount", 0))
		"ribbons":
			return stat("ribbons_first") + stat("ribbons_second") + stat("ribbons_third")
		"hall_of_fame":
			return show_history.size()
		"pinned":
			return pinned_entries().size()
	return stat(metric)


func is_goal_done(goal_id: String) -> bool:
	return completed_goals.has(goal_id)


## How far along a goal is, capped at its target.
func goal_progress(goal: Dictionary) -> int:
	if is_goal_done(goal["id"]):
		return int(goal["target"])
	return mini(goal_value(goal["metric"]), int(goal["target"]))


## Marks every goal that has just been reached as done and pays its reward
## (once). Returns the goals reached this time.
func check_goals() -> Array:
	var reached := []
	# A goal pays reputation, which can finish a reputation goal, so go round
	# again until nothing new is reached. Each goal completes once, so it ends.
	var found := true
	while found:
		found = false
		for goal in db.goals:
			if is_goal_done(goal["id"]) or goal_value(goal["metric"]) < int(goal["target"]):
				continue
			completed_goals[goal["id"]] = day
			var reward := int(goal["reward"])
			money += reward
			_count("goal_rewards", reward)
			_rep("goal_reached")
			if day_log.is_empty():
				_reset_day_log()
			day_log["goals"].append({"name": goal["name"], "reward": reward})
			reached.append(goal)
			found = true
	return reached


# --- Shop reputation -----------------------------------------------------------

## Adds the points for one source (see data/reputation.json), plus `extra`.
func _rep(key: String, extra: int = 0) -> void:
	reputation += maxi(0, int(db.reputation.get("points", {}).get(key, 0)) + extra)


## Public form: awards a source's points `amount_multiplier` times.
func award_reputation(source: String, amount_multiplier: int = 1) -> void:
	for i in maxi(0, amount_multiplier):
		_rep(source)


## The extra reputation for selling a fish of this many stars.
func _star_bonus(stars: int) -> int:
	var list: Array = db.reputation.get("points", {}).get("star_bonus", [])
	return int(list[stars]) if stars >= 0 and stars < list.size() else 0


func reputation_levels() -> Array:
	return db.reputation.get("levels", [])


## The 0-based level these points reach.
func reputation_level_at(points: int) -> int:
	var level := 0
	var levels := reputation_levels()
	for i in levels.size():
		if points >= int(levels[i]["points"]):
			level = i
	return level


func reputation_level() -> int:
	return reputation_level_at(reputation)


func reputation_level_name() -> String:
	var levels := reputation_levels()
	return str(levels[reputation_level()]["name"]) if not levels.is_empty() else ""


## The next level as {name, points}, or {} at the top.
func reputation_next() -> Dictionary:
	var levels := reputation_levels()
	var next := reputation_level() + 1
	if next >= levels.size():
		return {}
	return {"name": levels[next]["name"], "points": int(levels[next]["points"])}


## How far through the current level you are, 0..1 (1 at the top level).
func reputation_progress() -> float:
	var next := reputation_next()
	if next.is_empty():
		return 1.0
	var start := int(reputation_levels()[reputation_level()]["points"])
	return clampf(float(reputation - start) / float(int(next["points"]) - start), 0.0, 1.0)


## The total of one effect across every level reached (like upgrade_effect).
func reputation_effect(effect: String) -> int:
	var total := 0
	var levels := reputation_levels()
	for i in mini(reputation_level() + 1, levels.size()):
		total += int(levels[i]["effects"].get(effect, 0))
	return total


## True when this level or any lower one lists the unlock id ("lab", ...).
func has_unlock(unlock_id: String) -> bool:
	var levels := reputation_levels()
	for i in mini(reputation_level() + 1, levels.size()):
		if unlock_id in levels[i]["unlocks"]:
			return true
	return false


## The name of the lowest reputation level that lists this unlock ("" if none).
func unlock_level_name(unlock_id: String) -> String:
	for level in reputation_levels():
		if unlock_id in level["unlocks"]:
			return level["name"]
	return ""


## How much faster customers come than the base rate (1 = base): upgrades
## and reputation. The arrival floor (min_interval_minutes) still applies.
func customer_speed() -> float:
	return 1.0 + upgrade_effect("customer_speed") \
		+ reputation_effect("extra_customers") * float(db.reputation.get("customer_speed_per_extra", 0.0))


## The new level (0-based) if the shop has reached one the player hasn't been
## told about yet, else -1. Asking marks it told. For the level-up toast.
func take_level_up() -> int:
	var level := reputation_level()
	if level <= _level_announced:
		return -1
	_level_announced = level
	return level


# --- Shop upgrades -------------------------------------------------------------

func has_upgrade(upgrade_id: String) -> bool:
	return upgrades.has(upgrade_id)


## The total of one effect across every upgrade you own (0 if none).
func upgrade_effect(effect: String) -> float:
	var total := 0.0
	for id in upgrades:
		if db.upgrades.has(id):
			total += float(db.upgrades[id]["effects"].get(effect, 0.0))
	return total


## Why you can't buy an upgrade, or "" if you can.
func upgrade_blocker(upgrade_id: String) -> String:
	if not db.upgrades.has(upgrade_id):
		return "No such upgrade."
	if has_upgrade(upgrade_id):
		return "Already bought."
	var upgrade: Dictionary = db.upgrades[upgrade_id]
	var needs: String = upgrade.get("requires", "")
	if needs != "" and not has_upgrade(needs):
		return "Buy the %s first." % db.upgrades[needs]["name"]
	if not can_afford(int(upgrade["cost"])):
		return "You need $%d more." % (int(upgrade["cost"]) - money)
	return ""


func buy_upgrade(upgrade_id: String) -> bool:
	if upgrade_blocker(upgrade_id) != "":
		return false
	_spend(int(db.upgrades[upgrade_id]["cost"]))
	upgrades[upgrade_id] = day
	for tank in breeding_tanks:
		tank.capacity = breeding_capacity()
	return true


## How many fish each breeding tank holds.
func breeding_capacity() -> int:
	return int(db.economy["breeding_tank_capacity"]) + int(upgrade_effect("breeding_capacity"))


# --- Saving --------------------------------------------------------------------

## Everything needed to carry on later, as plain data. Meant to be taken
## between days: the customer at the counter and today's log aren't kept.
func to_dict() -> Dictionary:
	var saved_orders := []
	for order in orders:
		var o := {}
		for key in order:
			o[key] = order[key]
		var tank: Tank = order.get("tank")
		o["tank"] = tank.to_dict() if tank != null else null
		saved_orders.append(o)
	return {
		"version": SAVE_VERSION,
		"money": money,
		"day": day,
		"stock": inventory.stock(),
		"fish": inventory.fish_list().map(func(f): return f.to_dict()),
		"next_fish_id": inventory.next_fish_id(),
		"display_tank": display_tank.to_dict() if display_tank != null else null,
		"breeding_tanks": breeding_tanks.map(func(t): return t.to_dict()),
		"brood_nights": Array(brood_nights),
		"orders": saved_orders,
		"next_order_id": _next_order_id,
		"backorders": backorders.duplicate(true),
		"restocking": restocking,
		"discovered_recipes": discovered_recipes.duplicate(),
		"discovered_mutations": discovered_mutations.duplicate(),
		"book_bonuses": book_bonuses.duplicate(),
		"stats": stats.duplicate(),
		"reputation": reputation,
		"records": records.duplicate(true),
		"start_id": start_id,
		"challenge_id": challenge_id,
		"completed_goals": completed_goals.duplicate(),
		"upgrades": upgrades.duplicate(),
		"show_entry": show_entry,
		"shows_held": shows_held,
		"show_history": show_history.duplicate(true),
		"gallery_pins": gallery_pins.duplicate(),
	}


## Rebuilds a game from to_dict() data and opens its day. Returns null if the
## data is from another save version or is missing its basics.
static func from_dict(p_db: DataDB, p_rng: RandomNumberGenerator, d: Dictionary) -> GameState:
	if int(d.get("version", 0)) != SAVE_VERSION or not d.has("money") or d.get("breeding_tanks", []).is_empty():
		return null
	var s := GameState.new()
	s.db = p_db
	s.rng = p_rng
	s.money = int(d["money"])
	s.day = int(d.get("day", 1))
	s.restocking = bool(d.get("restocking", false))
	s.discovered_recipes = d.get("discovered_recipes", {}).duplicate()
	s.discovered_mutations = d.get("discovered_mutations", {}).duplicate()
	if d.has("book_bonuses"):
		s.book_bonuses = d["book_bonuses"].duplicate()
	else:
		# Older save: generations already complete get no retroactive bonus.
		for g in range(1, 10):
			if s.is_generation_complete(g):
				s.book_bonuses[str(g)] = 0
	s.stats = d.get("stats", {}).duplicate()
	if d.has("reputation"):
		s.reputation = int(d["reputation"])
	else:
		# Older save: credit the sales and orders already made.
		var points: Dictionary = p_db.reputation.get("points", {})
		s.reputation = s.stat("fish_sold") * int(points.get("sale", 0)) \
			+ s.stat("orders_delivered") * int(points.get("order_delivered", 0)) \
			+ s.stat("backorders_filled") * int(points.get("backorder_filled", 0))
	s.records = d.get("records", {}).duplicate(true)
	s.start_id = str(d.get("start_id", ""))
	s.challenge_id = str(d.get("challenge_id", ""))
	s.completed_goals = d.get("completed_goals", {}).duplicate()
	s.show_entry = int(d.get("show_entry", 0))
	s.shows_held = int(d.get("shows_held", 0))
	s.show_history = d.get("show_history", []).duplicate(true)
	s.gallery_pins = d.get("gallery_pins", []).duplicate()
	for id in d.get("upgrades", {}):
		if p_db.upgrades.has(id):
			s.upgrades[id] = int(d["upgrades"][id])
	var stock: Dictionary = d.get("stock", {})
	for item_id in stock:
		if p_db.items.has(item_id) and int(stock[item_id]) > 0:
			s.inventory.add(item_id, int(stock[item_id]))
	for fish_data in d.get("fish", []):
		if p_db.species.has(fish_data.get("species_id", "")):
			s.inventory.add_fish(Fish.from_dict(fish_data, int(p_db.economy["purity"]["baseline"])))
	s.inventory.set_next_fish_id(int(d.get("next_fish_id", 1)))
	if d.get("display_tank") != null:
		s.display_tank = Tank.from_dict(d["display_tank"])
	for tank_data in d["breeding_tanks"]:
		s.breeding_tanks.append(Tank.from_dict(tank_data))
		s.brood_nights.append(0)
	var nights: Array = d.get("brood_nights", [])
	for i in mini(nights.size(), s.brood_nights.size()):
		s.brood_nights[i] = int(nights[i])
	for order_data in d.get("orders", []):
		var order: Dictionary = order_data.duplicate(true)
		order["tank"] = Tank.from_dict(order_data["tank"]) if order_data.get("tank") != null else null
		s.orders.append(order)
	s._next_order_id = int(d.get("next_order_id", 1))
	s.backorders = d.get("backorders", []).duplicate(true)
	s._match_fish_to_tanks()
	s.clock = GameClock.new(p_db.economy["clock"])
	s.open_day()
	return s


## After loading: every tank lists exactly the fish that say they live in it
## (saved order kept), and fish whose tank is gone wait in holding.
func _match_fish_to_tanks() -> void:
	var tanks: Array = [display_tank]
	tanks.append_array(breeding_tanks)
	for order in orders:
		tanks.append(order.get("tank"))
	for tank in tanks:
		if tank != null:
			tank.fish_ids = tank.fish_ids.filter(func(id): return inventory.has_fish(id) \
				and tank_at(inventory.get_fish(id).location) == tank)
	for f in inventory.fish_list():
		if f.location == Fish.HOLDING:
			continue
		var home := tank_at(f.location)
		if home == null:
			f.location = Fish.HOLDING
		elif not f.id in home.fish_ids:
			home.fish_ids.append(f.id)


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
		if fish_leave_with_tank and not f.favorite:  # favourites always stay with you
			inventory.remove_fish(f.id)
		else:
			f.location = Fish.HOLDING
	display_tank = null
