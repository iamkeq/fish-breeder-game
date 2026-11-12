extends Control
## A thin strip above the display tank showing the shopfront improvements you
## have bought: painted planters, a striped awning, a glowing neon fish sign and
## a reading corner. Drawn in code; hidden until you buy something.

const HEIGHT := 46.0
const WALL := Color("#bfe0d6")
const WALL_PLAIN := Color("#e6dccb")
const AWNING_RED := Color("#d9695a")
const AWNING_CREAM := Color("#f6eddc")
const POT := Color("#9c6b4a")
const LEAF := Color("#5e9a5a")
const FLOWERS := [Color("#f2a0b4"), Color("#f6d36b"), Color("#f4f0f0"), Color("#c9a0e8")]
const NEON_PINK := Color("#ff6fae")
const NEON_CYAN := Color("#6fe8ff")
const NEON_PANEL := Color("#2a2540")
const CHAIR := Color("#c9784f")
const BOOKS := [Color("#6a8fc4"), Color("#e0b04f"), Color("#8cc48a")]

var _paint := false
var _awning := false
var _neon := false
var _corner := false


func _ready() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	Game.changed.connect(refresh)
	refresh()


func refresh() -> void:
	var state := Game.state
	_paint = state.has_upgrade("fresh_paint")
	_awning = state.has_upgrade("striped_awning")
	_neon = state.has_upgrade("neon_sign")
	_corner = state.has_upgrade("reading_corner")
	visible = _paint or _awning or _neon or _corner
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := HEIGHT
	draw_rect(Rect2(0, 0, w, h), WALL if _paint else WALL_PLAIN)
	if _awning:
		_draw_awning(w)
	if _paint:
		_draw_planter(Vector2(10, h - 12))
		_draw_planter(Vector2(w - 80, h - 12))
	if _neon:
		_draw_neon(w)
	if _corner:
		_draw_corner(Vector2(w - 150, h - 2))
	draw_rect(Rect2(0, 0, w, h), Color("#8a7a6a"), false, 1.0)


func _draw_awning(w: float) -> void:
	var stripe := 22.0
	var count := int(ceil(w / stripe))
	for i in count:
		var color := AWNING_RED if i % 2 == 0 else AWNING_CREAM
		draw_rect(Rect2(i * stripe, 0, stripe, 12), color)
		draw_circle(Vector2(i * stripe + stripe * 0.5, 12), stripe * 0.5, color)


func _draw_planter(origin: Vector2) -> void:
	draw_rect(Rect2(origin.x, origin.y, 68, 10), POT)
	for i in 6:
		var x := origin.x + 6 + i * 11.0
		draw_circle(Vector2(x, origin.y - 2), 5, LEAF)
		draw_circle(Vector2(x, origin.y - 6 - (i % 2) * 2), 3.2, FLOWERS[i % FLOWERS.size()])


func _draw_neon(w: float) -> void:
	var rect := Rect2(w * 0.5 - 70, 15, 140, 27)
	draw_rect(rect, NEON_PANEL)
	draw_rect(rect, NEON_CYAN, false, 1.5)
	var font := ThemeDB.fallback_font
	var text := "FISH  ><>"
	var at := Vector2(rect.position.x + 14, rect.position.y + 20)
	# A soft glow: the same text a few times, offset and faint, then the bright text on top.
	for offset in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
		draw_string(font, at + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(NEON_PINK, 0.35))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, NEON_PINK)


func _draw_corner(origin: Vector2) -> void:
	# An armchair and a little stack of books.
	draw_rect(Rect2(origin.x, origin.y - 24, 6, 24), CHAIR)
	draw_rect(Rect2(origin.x, origin.y - 12, 34, 12), CHAIR)
	draw_rect(Rect2(origin.x + 28, origin.y - 20, 6, 20), CHAIR)
	for i in BOOKS.size():
		draw_rect(Rect2(origin.x + 44, origin.y - 7 - i * 6, 22 - i * 3, 6), BOOKS[i])
