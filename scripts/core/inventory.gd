class_name Inventory
extends RefCounted
## Stock counts by item id, plus every fish the player owns.
## Nothing can be used unless it is in stock right now.

var _stock: Dictionary = {}
var _fish: Dictionary = {}
var _next_fish_id: int = 1


func count(item_id: String) -> int:
	return _stock.get(item_id, 0)


func add(item_id: String, qty: int = 1) -> void:
	if qty <= 0:
		push_error("Inventory.add: qty must be positive (got %d)" % qty)
		return
	_stock[item_id] = count(item_id) + qty


func can_remove(item_id: String, qty: int = 1) -> bool:
	return qty > 0 and count(item_id) >= qty


## Returns false and changes nothing if there isn't enough stock.
func remove(item_id: String, qty: int = 1) -> bool:
	if not can_remove(item_id, qty):
		return false
	var left := count(item_id) - qty
	if left == 0:
		_stock.erase(item_id)
	else:
		_stock[item_id] = left
	return true


## Copy of all stock counts (item_id -> qty), only items with qty > 0.
func stock() -> Dictionary:
	return _stock.duplicate()


## Adds the fish, giving it a fresh id if it doesn't have one.
func add_fish(fish: Fish) -> Fish:
	if fish.id == 0:
		fish.id = _next_fish_id
	_next_fish_id = maxi(_next_fish_id, fish.id + 1)
	_fish[fish.id] = fish
	return fish


func get_fish(fish_id: int) -> Fish:
	return _fish.get(fish_id)


func has_fish(fish_id: int) -> bool:
	return _fish.has(fish_id)


func remove_fish(fish_id: int) -> bool:
	return _fish.erase(fish_id)


## All fish, or only those at `location` (Fish.HOLDING / BREEDING / DISPLAY), sorted by id.
func fish_list(location: String = "") -> Array[Fish]:
	var result: Array[Fish] = []
	var ids := _fish.keys()
	ids.sort()
	for fish_id in ids:
		var f: Fish = _fish[fish_id]
		if location == "" or f.location == location:
			result.append(f)
	return result
