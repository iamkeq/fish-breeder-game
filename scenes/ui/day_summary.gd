extends ColorRect
## End-of-day summary: money in and out, customers, what happened in the back
## room overnight (new fry, mutations, fish that grew up), and a look ahead.

const UI := preload("res://scenes/ui/ui_kit.gd")

const SALE_NAMES := {
	"fish": "Fish sold", "item": "Shelf items sold", "tank": "Tanks sold",
	"order": "Orders delivered", "backorder": "Back-orders handed over", "wholesale": "Sold to wholesaler",
}
const GOOD := Color(0.25, 0.5, 0.35)
const WARN := Color(0.75, 0.4, 0.2)
const MAX_PREVIEWS := 8

var _title: Label
var _body: VBoxContainer
var _open_button: Button


func _ready() -> void:
	visible = false
	color = Color(0.15, 0.1, 0.08, 0.45)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 5)
	scroll.add_child(_body)
	box.add_child(scroll)
	_open_button = Button.new()
	_open_button.pressed.connect(func(): Game.open_next_day())
	box.add_child(_open_button)
	Game.day_started.connect(func(): visible = false)


func show_summary(s: Dictionary) -> void:
	for child in _body.get_children():
		child.queue_free()
	_title.text = "Day %d is done" % s["day"]
	_add_money(s)
	_add_back_room(s)
	_add_tomorrow(s)
	_open_button.text = ("Start Day %d (still closed for restock)" if Game.state.restocking else "Open shop for Day %d") % Game.state.day
	visible = true


func _add_money(s: Dictionary) -> void:
	var log: Dictionary = s["log"]
	_heading("The shop")
	var start: int = log["money_start"]
	var end: int = s["money_end"]
	var diff := end - start
	var money := _line("$%d  →  $%d   (%s$%d)" % [start, end, "+" if diff >= 0 else "−", absi(diff)])
	money.add_theme_font_size_override("font_size", 18)
	money.modulate = GOOD if diff >= 0 else WARN
	var sales: Dictionary = log["sales"]
	if sales.is_empty():
		_line("No sales today. Fish on display bring customers in!")
	for key in SALE_NAMES:
		if sales.has(key):
			_line("%s: %d  ($%d)" % [SALE_NAMES[key], sales[key][0], sales[key][1]])
	if log["spent"] > 0:
		_line("Spent at the Market: $%d" % log["spent"])
	var people := "Customers served: %d" % log["served"]
	if log["walked_out"] > 0:
		people += "   ·   wandered off: %d" % log["walked_out"]
	_line(people)


func _add_back_room(s: Dictionary) -> void:
	_heading("The back room overnight")
	var state := Game.state
	var born := _existing_fish(s["born_ids"])
	if born.is_empty():
		_line("No new fry tonight.")
	else:
		_line("New fry: %d" % s["fry_born"])
		_fish_row(born, false)
	# New looks, one line per kind: "✿ New variety! Red × Yellow made an Orange fry."
	var seen := {}
	for m in s["mutations"]:
		var key: String = m["source"] + ":" + m["value"]
		if seen.has(key) or seen.size() >= 3:
			continue
		seen[key] = true
		var look := _trait_phrase(m["trait"], m["value"])
		var text := ""
		if m["source"] == "recipe":
			text = "✿ New variety! %s × %s made %s fry." % [
				UI.pretty(m["parents"][0]), UI.pretty(m["parents"][1]), look]
		else:
			text = "✦ Rare mutation! A fry was born %s, which neither parent is." % look
		_line(text).modulate = GOOD
	var grown := _existing_fish(s["grown_ids"])
	if not grown.is_empty():
		_line("Grown up: %d (now ready to sell or breed)" % grown.size())
		_fish_row(grown, true)
	if s["fry_unfed"] > 0:
		_line("%d fry had no food tonight, so they didn't grow. Restock fish food and they'll carry on." % s["fry_unfed"]).modulate = WARN


func _add_tomorrow(s: Dictionary) -> void:
	_heading("Tomorrow")
	var outlook: Array = s.get("brood_outlook", [s["nights_until_brood"]])
	if outlook.size() == 1:
		var nights: int = outlook[0]
		if nights < 0:
			_line("No breeding pair in the back room. Pair an adult male and female to get fry.")
		else:
			_line("Next brood in %d night%s." % [nights, "" if nights == 1 else "s"])
	else:
		var parts := PackedStringArray()
		for i in outlook.size():
			var nights: int = outlook[i]
			parts.append("Tank %d: %s" % [i + 1, "no pair" if nights < 0 else
				"brood in %d night%s" % [nights, "" if nights == 1 else "s"]])
		_line("   ·   ".join(parts))
	var food := _line("Fish food: %d left" % s["food_left"])
	if s["fry_in_tank"] > 0 and s["food_left"] < 2:
		food.text += ". Running low! Fry only grow on nights they're fed."
		food.modulate = WARN
	if s["orders"] > 0 or s["backorders"] > 0:
		_line("Waiting on you: %d order%s, %d back-order%s." % [
			s["orders"], "" if s["orders"] == 1 else "s", s["backorders"], "" if s["backorders"] == 1 else "s"])


func _existing_fish(ids: Array) -> Array:
	var result := []
	for id in ids:
		var f: Fish = Game.state.inventory.get_fish(id)
		if f != null:
			result.append(f)
	return result


func _fish_row(fish: Array, show_stars: bool) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	for f in fish.slice(0, MAX_PREVIEWS):
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 0)
		var scale_ := 0.95 if not Game.state.is_adult(f) else 0.55
		card.add_child(UI.fish_preview(f, Game.state.species_of(f), Vector2(76, 40), scale_))
		var caption := Label.new()
		caption.add_theme_font_size_override("font_size", 11)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.text = UI.sex_symbol(f) + (" " + UI.stars_text(f.stars) if show_stars else "")
		card.add_child(caption)
		row.add_child(card)
	if fish.size() > MAX_PREVIEWS:
		row.add_child(_plain("+%d more" % (fish.size() - MAX_PREVIEWS)))
	_body.add_child(row)


static func _trait_phrase(trait_name: String, value: String) -> String:
	var v := UI.pretty(value)
	match trait_name:
		"variety":
			return _article(v)
		"body_color":
			return v + " colouring"
		"tail_shape":
			return _article(v) + " tail"
	return _article(v) + " " + trait_name.replace("_", " ")


static func _article(word: String) -> String:
	return ("an " if word.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "a ") + word


func _heading(text: String) -> void:
	var l := _plain(text)
	l.add_theme_font_size_override("font_size", 19)
	_body.add_child(l)


func _line(text: String) -> Label:
	var l := _plain(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(580, 0)
	_body.add_child(l)
	return l


func _plain(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l
