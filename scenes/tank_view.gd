extends Control
## Draws one tank (glass, water, substrate and decor in its slots) and keeps a
## swimming fish sprite for every fish inside it. Placeholder art only.

const FishSprite := preload("res://scenes/fish_sprite.gd")
const UI := preload("res://scenes/ui/ui_kit.gd")

## Back row first so the front row is drawn on top. x is a fraction of the water width.
const SLOT_X := [0.24, 0.74, 0.1, 0.52, 0.34, 0.88]
const ROW_LIFT := {"back": 14.0, "mid": 6.0, "front": -2.0}
const ROW_SCALE := {"back": 0.85, "mid": 0.95, "front": 1.0}
const HEIGHT_FRACTION := {"short": 0.16, "medium": 0.36, "tall": 0.62}
## Sprite items: how tall each height class is drawn, as a share of the water.
const SPRITE_HEIGHT := {"short": 0.2, "medium": 0.34, "tall": 0.6}

const GLASS := Color("#d7eef5")
const FRAME := Color("#5b6b73")
const WATER_TOP := Color("#a6d8e8")
const WATER_BOTTOM := Color("#5fa9c4")
const EMPTY_TEXT := Color("#7a6e64")
const SUBSTRATE_HEIGHT := 22.0

@export_enum("display", "breeding") var location: String = "display"
## Editor preview: faint markers on empty slots, and a pulsing ring on
## `highlight_slot` (-1 = the substrate, -2 = nothing).
## Emitted in editor mode when a slot marker (or the substrate, -1) is clicked.
signal slot_clicked(slot: int)

var show_slot_markers: bool = false
var highlight_slot: int = -2

const HIGHLIGHT := Color("#e07a4f")
const SLOT_SHORT := ["B1", "B2", "M1", "M2", "F1", "F2"]

var _sprites: Dictionary = {}  # fish id -> sprite
var _pulse := 0.0


func _ready() -> void:
	clip_contents = true
	Game.changed.connect(refresh)
	resized.connect(_on_resized)
	refresh()


func tank() -> Tank:
	return Game.state.tank_at(location)


func water_rect() -> Rect2:
	return Rect2(Vector2(10, 26), size - Vector2(20, 36))


func swim_rect() -> Rect2:
	var w := water_rect()
	return Rect2(w.position + Vector2(0, 14), w.size - Vector2(0, 14 + SUBSTRATE_HEIGHT + 6))


func refresh() -> void:
	var t := tank()
	var ids: Array = t.fish_ids if t != null else []
	for fish_id in _sprites.keys():
		if not fish_id in ids:
			_sprites[fish_id].queue_free()
			_sprites.erase(fish_id)
	for fish_id in ids:
		if not _sprites.has(fish_id):
			var f: Fish = Game.state.inventory.get_fish(fish_id)
			var sprite := FishSprite.new()
			add_child(sprite)
			sprite.setup(f, Game.state.species_of(f), swim_rect())
			_sprites[fish_id] = sprite
		else:
			_sprites[fish_id].set_bounds(swim_rect())  # fry may have grown
	queue_redraw()


func _on_resized() -> void:
	for sprite in _sprites.values():
		sprite.set_bounds(swim_rect())
	queue_redraw()


func _draw() -> void:
	var t := tank()
	var font := get_theme_default_font()
	if t == null:
		var r := Rect2(Vector2(10, 26), size - Vector2(20, 36))
		draw_rect(r, EMPTY_TEXT, false, 2.0)
		draw_string(font, Vector2(r.position.x, r.get_center().y), "No tank on display",
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, EMPTY_TEXT)
		return

	var w := water_rect()
	# Water: a vertical gradient with a bright surface line.
	draw_polygon(PackedVector2Array([w.position, Vector2(w.end.x, w.position.y), w.end, Vector2(w.position.x, w.end.y)]),
		PackedColorArray([WATER_TOP, WATER_TOP, WATER_BOTTOM, WATER_BOTTOM]))
	draw_rect(Rect2(w.position, Vector2(w.size.x, 4)), Color(1, 1, 1, 0.5))

	_draw_substrate(t, w)
	for slot in t.slot_count():
		if not t.is_slot_empty(slot):
			_draw_item(Game.db.items[t.slots[slot]], _slot_base(t, slot, w), w.size.y, ROW_SCALE[t.row_of(slot)])

	if show_slot_markers:
		_draw_slot_markers(t, w, font)

	# Glass frame and lid.
	draw_rect(w, GLASS.lerp(Color.WHITE, 0.3), false, 3.0)
	draw_rect(Rect2(w.position.x - 6, w.position.y - 14, w.size.x + 12, 12), FRAME)
	draw_rect(Rect2(w.position.x - 6, w.end.y, w.size.x + 12, 8), FRAME)


func _slot_base(t: Tank, slot: int, w: Rect2) -> Vector2:
	var row: String = t.row_of(slot)
	return Vector2(w.position.x + w.size.x * SLOT_X[slot], w.end.y - SUBSTRATE_HEIGHT * 0.5 - ROW_LIFT[row])


func _draw_substrate(t: Tank, w: Rect2) -> void:
	if t.substrate == "":
		return
	var color := Color(Game.db.items[t.substrate].get("color", "#d9c9a0"))
	var top := w.end.y - SUBSTRATE_HEIGHT
	var points := PackedVector2Array([Vector2(w.position.x, w.end.y)])
	for i in 9:
		var x := w.position.x + w.size.x * i / 8.0
		points.append(Vector2(x, top + sin(i * 1.7) * 3.0))
	points.append(w.end)
	draw_colored_polygon(points, color)


func _draw_item(item: Dictionary, base: Vector2, water_height: float, scale_: float) -> void:
	if item.has("sprite"):
		_draw_item_sprite(item, base, water_height, scale_)
		return
	var color := Color(item.get("color", "#999999"))
	var h: float = water_height * HEIGHT_FRACTION.get(item.get("height", "short"), 0.2) * scale_
	match item["category"]:
		"rock":
			var rx := h * 0.9 + 8.0
			var dome := PackedVector2Array()
			for i in 11:
				var t := PI * i / 10.0
				var bump := 1.0 + 0.08 * sin(i * 2.3)
				dome.append(base + Vector2(cos(t) * rx * bump, -sin(t) * h * bump))
			draw_colored_polygon(dome, color)
			draw_line(base + Vector2(-rx * 0.4, -h * 0.6), base + Vector2(rx * 0.1, -h * 0.85), color.lightened(0.25), 2.0)
		"driftwood":
			draw_line(base, base + Vector2(-h * 0.15, -h), color, 7.0 * scale_)
			draw_line(base + Vector2(-h * 0.08, -h * 0.5), base + Vector2(-h * 0.5, -h * 0.85), color, 4.0 * scale_)
			draw_line(base + Vector2(-h * 0.12, -h * 0.75), base + Vector2(h * 0.35, -h * 1.05), color, 4.0 * scale_)
			draw_line(base + Vector2(-h * 0.3, 0), base + Vector2(h * 0.3, 0), color, 6.0 * scale_)
		"plant":
			var blades := 4 if item.get("height") == "short" else 6
			for i in blades:
				var spread := (i - (blades - 1) * 0.5) * 6.0 * scale_
				var tip := base + Vector2(spread * 1.8, -h * (0.75 + 0.25 * sin(i * 1.3)))
				var mid := base + Vector2(spread * 0.6 + 4.0 * sin(i), -h * 0.5)
				draw_polyline(PackedVector2Array([base + Vector2(spread * 0.3, 0), mid, tip]),
					color.lightened(0.08 * (i % 3)), 4.0 * scale_)
		_:  # decor: a box with a little roof, so it reads as "an ornament"
			var bw := h * 0.7 + 10.0
			var body := Rect2(base + Vector2(-bw * 0.5, -h * 0.75), Vector2(bw, h * 0.75))
			draw_rect(body, color)
			draw_colored_polygon(PackedVector2Array([
				body.position, body.position + Vector2(bw, 0), base + Vector2(0, -h)]), color.darkened(0.2))
			draw_rect(Rect2(base + Vector2(-bw * 0.12, -h * 0.35), Vector2(bw * 0.24, h * 0.35)), color.darkened(0.4))


func _process(delta: float) -> void:
	if show_slot_markers:
		_pulse += delta
		queue_redraw()


## Where the editor marker for a slot sits (above the item's base).
func slot_marker_position(slot: int) -> Vector2:
	var t := tank()
	var w := water_rect()
	return _slot_base(t, slot, w) + Vector2(0, -16)


func _draw_slot_markers(t: Tank, w: Rect2, font: Font) -> void:
	for slot in t.slot_count():
		var p := slot_marker_position(slot)
		if t.is_slot_empty(slot):
			draw_circle(p, 13.0, Color(1, 1, 1, 0.35))
			draw_arc(p, 13.0, 0.0, TAU, 24, Color(1, 1, 1, 0.8), 1.5, true)
			draw_string(font, p + Vector2(-13, 5), SLOT_SHORT[slot], HORIZONTAL_ALIGNMENT_CENTER, 26, 12, Color(0.2, 0.3, 0.35))
		if slot == highlight_slot:
			var r := 18.0 + sin(_pulse * 5.0) * 2.5
			draw_arc(p, r, 0.0, TAU, 32, HIGHLIGHT, 3.0, true)
	if highlight_slot == -1:
		var band := Rect2(w.position.x + 2, w.end.y - SUBSTRATE_HEIGHT - 4, w.size.x - 4, SUBSTRATE_HEIGHT + 2)
		var a := 0.6 + 0.4 * sin(_pulse * 5.0)
		draw_rect(band, Color(HIGHLIGHT, a), false, 3.0)


func _gui_input(event: InputEvent) -> void:
	if not show_slot_markers or tank() == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var t := tank()
		var best := -2
		var best_dist := 26.0
		for slot in t.slot_count():
			var d: float = slot_marker_position(slot).distance_to(event.position)
			if d < best_dist:
				best = slot
				best_dist = d
		if best == -2 and event.position.y > water_rect().end.y - SUBSTRATE_HEIGHT - 6:
			best = -1
		if best != -2:
			slot_clicked.emit(best)
			accept_event()


## Draws an item's sprite standing on `base`, sized by its height class
## (aspect ratio kept, never wider than 40% of the tank).
func _draw_item_sprite(item: Dictionary, base: Vector2, water_height: float, scale_: float) -> void:
	var r: Array = item["sprite"]
	var src := Rect2(r[0], r[1], r[2], r[3])
	var h: float = water_height * SPRITE_HEIGHT.get(item.get("height", "short"), 0.2) * scale_
	var w := h * src.size.x / src.size.y
	var max_w := size.x * 0.4
	if w > max_w:
		h *= max_w / w
		w = max_w
	# Sink the bottom slightly into the substrate so it looks planted.
	var dest := Rect2(base.x - w * 0.5, base.y - h * 0.94, w, h)
	# Keep it inside the glass, even for wide plants in the edge slots.
	var water := water_rect()
	dest.position.x = clampf(dest.position.x, water.position.x, maxf(water.position.x, water.end.x - w))
	draw_texture_rect_region(UI.sheet_texture(item["sheet"]), dest, src)
