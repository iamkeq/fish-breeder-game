class_name Tank
extends RefCounted
## Slot-based tank layout: one substrate slot, six placement slots arranged in
## back/mid/front rows, and a list of fish ids up to `capacity`.
## Tank only enforces layout rules; GameState handles taking items from stock.

const ROWS := ["back", "back", "mid", "mid", "front", "front"]

## Item id of the tank itself (its price counts when the tank is sold). Empty for fixtures.
var tank_item_id: String = ""
var capacity: int = 6
var substrate: String = ""
var slots: Array = []
var fish_ids: Array = []


func _init(p_tank_item_id: String = "", p_capacity: int = 6) -> void:
	tank_item_id = p_tank_item_id
	capacity = p_capacity
	slots.resize(ROWS.size())
	slots.fill("")


static func is_placeable(item: Dictionary) -> bool:
	return item.get("category") in DataDB.PLACEABLE_CATEGORIES


static func is_substrate(item: Dictionary) -> bool:
	return item.get("category") == "substrate"


func slot_count() -> int:
	return slots.size()


func row_of(slot: int) -> String:
	return ROWS[slot]


func is_slot_empty(slot: int) -> bool:
	return slots[slot] == ""


func can_place(slot: int, item: Dictionary) -> bool:
	return slot >= 0 and slot < slots.size() and is_slot_empty(slot) and is_placeable(item)


func place(slot: int, item: Dictionary) -> bool:
	if not can_place(slot, item):
		return false
	slots[slot] = item["id"]
	return true


## Empties the slot and returns what was in it ("" if it was empty).
func take(slot: int) -> String:
	var id: String = slots[slot]
	slots[slot] = ""
	return id


func can_set_substrate(item: Dictionary) -> bool:
	return substrate == "" and is_substrate(item)


func set_substrate(item: Dictionary) -> bool:
	if not can_set_substrate(item):
		return false
	substrate = item["id"]
	return true


func take_substrate() -> String:
	var id := substrate
	substrate = ""
	return id


func filled_slot_count() -> int:
	return slots.size() - slots.count("")


## Every placed item id, substrate first, then slots in order (duplicates kept).
func placed_item_ids() -> Array:
	var result := []
	if substrate != "":
		result.append(substrate)
	for id in slots:
		if id != "":
			result.append(id)
	return result


func has_room_for_fish() -> bool:
	return fish_ids.size() < capacity


func add_fish(fish_id: int) -> bool:
	if not has_room_for_fish() or fish_id in fish_ids:
		return false
	fish_ids.append(fish_id)
	return true


func remove_fish(fish_id: int) -> bool:
	if not fish_id in fish_ids:
		return false
	fish_ids.erase(fish_id)
	return true
