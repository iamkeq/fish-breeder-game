extends SceneTree
## Plays a short scripted scene and saves screenshots for the README and itch
## page: the shop floor (with a customer), the back room (with fry), the tank
## editor and the Market.
##   godot --path . -s res://tools/capture_screenshots.gd
## (Needs a window, not --headless.) Writes docs/images/screenshot_*.png.

const OUT_DIR := "res://docs/images"
const LAYOUT := ["giant_sword", "scarlet_alternanthera", "crypt_wendtii", "rock_cave", "monte_carlo", "mixed_pebbles"]

var _frame := 0
var _main: Node
var _wait := 0.0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child.call_deferred(_main)


func _process(delta: float) -> bool:
	# Give the fish real time to swim around between shots.
	_wait += delta
	if _frame > 3 and _wait < 2.0:
		return false
	_wait = 0.0
	_frame += 1
	var game = root.get_node_or_null("Game")
	if game == null:
		return false
	var s = game.state
	match _frame:
		3:
			_main._hint.visible = false
			s.money = 1200
			game.db.species["guppy"]["recipe_chance"] = 1.0  # show off a recipe brood
			s.end_day()
			s.end_day()
			s.open_day()
			s.money = 1200
			game.set_substrate(Fish.DISPLAY, "fine_sand")
			for i in LAYOUT.size():
				game.buy_item(LAYOUT[i])
				game.take_item(Fish.DISPLAY, i)
				game.place_item(Fish.DISPLAY, i, LAYOUT[i])
			for id in ["koi", "neon", "tuxedo", "normal"]:
				game.move_fish(game.buy_strain(id, Fish.MALE if id != "koi" else Fish.FEMALE).id, Fish.DISPLAY)
			for id in ["java_moss", "red_ludwigia", "clay_pot", "seiryu_stone", "hollow_log"]:
				game.buy_item(id)
			var koi = s.inventory.fish_list(Fish.DISPLAY)[0]
			s.customer = {"kind": "fish", "fish_id": koi.id, "name": "Priya", "waited": 0.0, "patience": 90.0}
			s.accept_request(s.make_request())
			game.customer_changed.emit()
			game.notify_changed()
		4:
			pass
		5:
			_save("screenshot_shop_floor")
			_main._show_room(_main._back_room)
		6:
			_save("screenshot_back_room")
			_main._show_room(_main._shop_floor)
			_main._tank_editor.open()
			_main._tank_editor._select(3)
		7:
			_save("screenshot_tank_editor")
			_main._tank_editor.close()
			_main._fish_market.open()
		8:
			_save("screenshot_market")
			return true
	return false


func _save(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := OUT_DIR.path_join(name + ".png")
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
