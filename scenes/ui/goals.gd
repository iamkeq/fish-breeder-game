extends ColorRect
## Goals, Perks and Stats, in three tabs. A reputation bar sits under the title. Goals: things to aim for, each with a progress
## bar and a one-off cash reward (open ones first, finished ones below). Stats:
## lifetime numbers and personal bests. Both tabs have the "start a new game"
## button. Pauses the shop clock while open.

const GOOD := Color(0.25, 0.5, 0.35)
const TABS := ["Goals", "Perks", "Stats"]
const DIM := Color(1, 1, 1, 0.7)

var _progress: Label
var _rep_name: Label
var _rep_bar: ProgressBar
var _rep_points: Label
var _body: VBoxContainer
var _new_game_button: Button
var _confirming := false
var _tab := 0
var _tab_buttons: Array[Button] = []


func _ready() -> void:
	visible = false
	color = Color(0.15, 0.1, 0.08, 0.45)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 620)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	var title := Label.new()
	title.text = "Goals"
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)
	_progress = Label.new()
	_progress.add_theme_font_size_override("font_size", 16)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_progress)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	box.add_child(header)
	box.add_child(_build_reputation_bar())
	box.add_child(_build_tabs())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)
	box.add_child(scroll)

	box.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	var saved := Label.new()
	saved.text = "Your shop is saved at the end of every day." if Game.persist \
		else "Saving is off in this run."
	saved.add_theme_font_size_override("font_size", 13)
	saved.modulate = Color(1, 1, 1, 0.7)
	saved.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(saved)
	_new_game_button = Button.new()
	_new_game_button.add_theme_font_size_override("font_size", 13)
	_new_game_button.pressed.connect(_on_new_game_pressed)
	footer.add_child(_new_game_button)
	box.add_child(footer)
	Game.changed.connect(func(): if visible: _refresh())


## Shop reputation: level name, a bar toward the next level, and the points.
func _build_reputation_bar() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_rep_name = Label.new()
	_rep_name.add_theme_font_size_override("font_size", 17)
	row.add_child(_rep_name)
	_rep_bar = ProgressBar.new()
	_rep_bar.max_value = 1.0
	_rep_bar.show_percentage = false
	_rep_bar.custom_minimum_size = Vector2(260, 14)
	_rep_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_rep_bar)
	_rep_points = Label.new()
	_rep_points.add_theme_font_size_override("font_size", 14)
	_rep_points.modulate = DIM
	row.add_child(_rep_points)
	return row


## Same tab buttons as the Market.
func _build_tabs() -> HBoxContainer:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = i == _tab
		b.pressed.connect(_select_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	return tabs


func _select_tab(index: int) -> void:
	_tab = index
	_refresh()
	_body.get_parent().scroll_vertical = 0


func open() -> void:
	if visible:
		return
	visible = true
	_confirming = false
	Game.push_pause()
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	Game.pop_pause()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	for child in _body.get_children():
		child.queue_free()
	var state := Game.state
	var goals: Array = Game.db.goals
	var done := goals.filter(func(g): return state.is_goal_done(g["id"]))
	_progress.text = "%d of %d reached" % [done.size(), goals.size()]
	for i in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
	_new_game_button.text = "Really start over? Click again" if _confirming else "Start a new game"
	_refresh_reputation(state)
	if _tab == 2:
		_add_stats(state)
		return
	if _tab == 1:
		_add_perks(state)
		return
	for g in goals:
		if not state.is_goal_done(g["id"]):
			_body.add_child(_goal_row(g, false))
	if not done.is_empty():
		var heading := Label.new()
		heading.text = "Reached"
		heading.add_theme_font_size_override("font_size", 19)
		_body.add_child(heading)
		for g in done:
			_body.add_child(_goal_row(g, true))



func _refresh_reputation(state: GameState) -> void:
	_rep_name.text = "★ Lv %d  %s" % [state.reputation_level() + 1, state.reputation_level_name()]
	_rep_bar.value = state.reputation_progress()
	var next := state.reputation_next()
	_rep_points.text = "%d points" % state.reputation if next.is_empty() 		else "%d / %d points to %s" % [state.reputation, int(next["points"]), next["name"]]


## One row per reputation level: what it gave (or gives), greyed until reached.
func _add_perks(state: GameState) -> void:
	var intro := Label.new()
	intro.text = "Your reputation grows with every sale, order, goal and discovery. It never goes down."
	intro.add_theme_font_size_override("font_size", 14)
	intro.modulate = DIM
	_body.add_child(intro)
	var levels := state.reputation_levels()
	for i in levels.size():
		var reached := i <= state.reputation_level()
		var panel := PanelContainer.new()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		panel.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 1)
		var name := Label.new()
		name.text = "%s Lv %d  %s" % ["✔" if reached else "·", i + 1, levels[i]["name"]]
		info.add_child(name)
		var what := Label.new()
		what.text = levels[i]["description"]
		what.add_theme_font_size_override("font_size", 13)
		what.modulate = Color(1, 1, 1, 0.7)
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(what)
		row.add_child(info)
		var need := Label.new()
		need.text = "%d points" % int(levels[i]["points"])
		need.add_theme_font_size_override("font_size", 14)
		need.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		need.modulate = GOOD if reached else Color.WHITE
		row.add_child(need)
		if not reached:
			panel.modulate = Color(1, 1, 1, 0.55)
		_body.add_child(panel)


func _goal_row(goal: Dictionary, done: bool) -> Control:
	var state := Game.state
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	var name := Label.new()
	name.text = ("✔ " if done else "") + goal["name"]
	info.add_child(name)
	var what := Label.new()
	what.text = goal["description"]
	what.add_theme_font_size_override("font_size", 13)
	what.modulate = Color(1, 1, 1, 0.7)
	info.add_child(what)
	row.add_child(info)

	if done:
		var when := Label.new()
		when.text = "Day %d" % int(state.completed_goals[goal["id"]])
		when.add_theme_font_size_override("font_size", 13)
		when.modulate = Color(1, 1, 1, 0.7)
		when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(when)
		panel.modulate = Color(1, 1, 1, 0.75)
	else:
		var target := int(goal["target"])
		var bar := ProgressBar.new()
		bar.max_value = target
		bar.value = state.goal_progress(goal)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(150, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var count := Label.new()
		count.text = "%d/%d" % [state.goal_progress(goal), target]
		count.add_theme_font_size_override("font_size", 13)
		count.custom_minimum_size = Vector2(70, 0)
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(count)
	var reward := Label.new()
	reward.text = "+$%d" % int(goal["reward"])
	reward.add_theme_font_size_override("font_size", 18)
	reward.custom_minimum_size = Vector2(64, 0)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reward.modulate = GOOD if done else Color.WHITE
	row.add_child(reward)
	return panel


## Starting over wipes the save, so it takes two clicks.
func _on_new_game_pressed() -> void:
	if not _confirming:
		_confirming = true
		_refresh()
		return
	close()
	Game.new_game()


# --- Stats tab -----------------------------------------------------------------

## Four sections in two columns, each a plain list of "what ... number".
func _add_stats(state: GameState) -> void:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var left := _stats_column()
	var right := _stats_column()
	columns.add_child(left)
	columns.add_child(right)
	var margin := MarginContainer.new()  # keeps numbers clear of the scrollbar
	margin.add_theme_constant_override("margin_right", 18)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(columns)
	_body.add_child(margin)

	var sold_to_customers := state.stat("fish_sold") - state.stat("collector_sales")
	_section(left, "Shop", [
		["Days open", str(state.day - 1)],
		["Earned in total", _money(state.stat("total_earned"))],
		["Spent in total", _money(state.stat("total_spent"))],
		["Best day", _money(state.goal_value("best_day"))],
		_record_row(state, "Biggest sale", "best_sale", _money_of),
		["Customers served", str(state.stat("customers_served"))],
		["Customers who wandered off", str(state.stat("walked_out"))],
	])
	var best_stars_sold := state.stat("best_stars_sold")
	_section(right, "Fish", [
		["Fry bred", str(state.stat("fish_bred"))],
		["Grown up", str(state.stat("fish_grown"))],
		["Sold to customers", str(sold_to_customers)],
		["Sold to collectors", str(state.stat("collector_sales"))],
		["Sold wholesale", str(state.stat("wholesale_sold"))],
		["Fish named", str(state.stat("fish_named"))],
		["Favourites kept", str(state.favorite_count())],
		_record_row(state, "Best stars bred", "best_bred", _stars_of, true),
		["Best stars sold", "★".repeat(best_stars_sold) if best_stars_sold > 0 else "–"],
		_record_row(state, "Rarest fish sold", "rarest_sold", _variety_of),
		["Fish scanned", str(state.stat("fish_scanned"))],
		_record_row(state, "Purest fish", "purest_fish", func(r): return "%d%%" % int(r["amount"])),
	])
	var progress := [
		["Shop reputation", "%s  (%d pts)" % [state.reputation_level_name(), state.reputation]],
		["Goals reached", "%d/%d" % [state.completed_goals.size(), Game.db.goals.size()]],
		["Recipes found", "%d/%d" % [state.discovered_recipes.size(), _count_book(state, true)]],
		["Mutations found", "%d/%d" % [state.discovered_mutations.size(), _count_book(state, false)]],
		["Upgrades bought", "%d/%d" % [state.upgrades.size(), Game.db.upgrades.size()]],
		["Goal rewards earned", _money(state.stat("goal_rewards"))],
		["Breeding book rewards", _money(state.stat("book_rewards"))],
	]
	if state.challenge_id != "":
		progress.append(["Mode", _name_in(Game.db.challenges, state.challenge_id)])
	if state.start_id != "":
		progress.append(["Starting pair", _name_in(Game.db.starts, state.start_id)])
	_section(left, "Progress", progress)
	_section(left, "Fish shows", [
		["Shows entered", str(state.stat("shows_entered"))],
		["1st place ribbons", str(state.stat("ribbons_first"))],
		["2nd place ribbons", str(state.stat("ribbons_second"))],
		["3rd place ribbons", str(state.stat("ribbons_third"))],
		["Hall of fame portraits", str(state.show_history.size())],
		["Portraits on the wall", str(state.pinned_entries().size())],
	])

	_section(right, "Staff", [
		["Team size", "%d/%d" % [state.staff.size(), state.staff_max()]],
		["Jobs done", str(state.stat("staff_actions"))],
		["Wages paid", _money(state.stat("staff_wages"))],
	])
	_section(right, "Orders and stock", [
		["Special orders delivered", str(state.stat("orders_delivered"))],
		["Back-orders handed over", str(state.stat("backorders_filled"))],
		["Shelf items sold", str(state.stat("items_sold"))],
		["Tanks sold", str(state.stat("tanks_sold"))],
	])


func _stats_column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return column


## A heading and its rows. A row is [label, value] or [label, value, detail]
## (the detail is a small line under it).
func _section(column: VBoxContainer, heading: String, rows: Array) -> void:
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override("font_size", 19)
	column.add_child(h)
	for row in rows:
		var line := HBoxContainer.new()
		var name := Label.new()
		name.text = row[0]
		name.add_theme_font_size_override("font_size", 14)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.modulate = DIM
		line.add_child(name)
		var value := Label.new()
		value.text = row[1]
		value.add_theme_font_size_override("font_size", 14)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)
		column.add_child(line)
		if row.size() > 2 and row[2] != "":
			var detail := Label.new()
			detail.text = row[2]
			detail.add_theme_font_size_override("font_size", 12)
			detail.modulate = Color(1, 1, 1, 0.55)
			detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			detail.custom_minimum_size = Vector2(300, 0)
			column.add_child(detail)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	column.add_child(gap)


## [label, value, detail] for a record, or [label, "–"] if there isn't one yet.
## `format` turns the record into the value text; `strip_stars` drops the
## leading stars from the detail when the value already shows them.
func _record_row(state: GameState, label: String, key: String, format: Callable, strip_stars := false) -> Array:
	var r: Dictionary = state.records.get(key, {})
	if r.is_empty():
		return [label, "–"]
	var what: String = r["what"]
	if strip_stars:
		what = what.lstrip("★ ")
	return [label, format.call(r), "%s · Day %d" % [what, int(r["day"])]]


func _money_of(r: Dictionary) -> String:
	return _money(int(r["amount"]))


func _stars_of(r: Dictionary) -> String:
	return "★".repeat(int(r["amount"]))


## A variety multiplier saved as x100: 320 -> "×3.2".
func _variety_of(r: Dictionary) -> String:
	return "×%s" % ("%.2f" % (float(r["amount"]) / 100.0)).trim_suffix("0").trim_suffix(".0").trim_suffix(".00")


func _money(amount: int) -> String:
	return "$%d" % amount


func _count_book(state: GameState, recipes: bool) -> int:
	var total := 0
	for species_id in Game.db.species:
		total += (state.book_recipes(species_id) if recipes else state.book_mutations(species_id)).size()
	return total


func _name_in(list: Array, id: String) -> String:
	for entry in list:
		if entry["id"] == id:
			return entry["name"]
	return id
