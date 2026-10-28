extends SceneTree
## Renders the itch.io cover image (630 x 500) from the game's own art: a lit
## aquarium with plants, rocks and guppies, plus the title.
##   godot --path . -s res://tools/make_thumbnail.gd
## (Needs a window, not --headless, so it can render.) Writes docs/images/itch_cover.png.

const SIZE := Vector2i(630, 500)
const OUT := "res://docs/images/itch_cover.png"
const TITLE := "Fish Breeder"
const SUBTITLE := "Job Simulator"
const SAND := Color("#e3d5b0")

## [item id, x of base centre, height in px, flip]
const DECOR := [
	["giant_sword", 70, 250, false], ["scarlet_alternanthera", 575, 240, false],
	["vallisneria", 150, 215, false], ["jungle_val", 500, 200, true],
	["amazon_sword", 245, 165, false], ["rock_cave", 330, 120, false],
	["red_ludwigia", 430, 175, false], ["mossy_driftwood", 520, 95, true],
	["monte_carlo", 60, 55, false], ["mixed_pebbles", 395, 55, false],
	["java_moss", 250, 45, false], ["anubias_nana", 590, 60, false],
	["dwarf_hairgrass", 165, 55, false], ["seiryu_spire", 470, 70, false],
]
## [variety, x, y, scale, facing right]
const FISH := [
	["koi", 190, 300, 1.25, true], ["neon", 455, 268, 1.1, false], ["normal", 120, 360, 1.0, true],
	["gold", 520, 345, 1.05, false], ["tuxedo", 330, 405, 0.95, true], ["blue", 270, 250, 0.85, false],
	["pink", 580, 270, 0.8, false],
]

var _frames := 0
var _viewport: SubViewport


func _initialize() -> void:
	var db := DataDB.load_from_dir("res://data")
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var canvas := Node2D.new()
	_viewport.add_child(canvas)

	# Water: deep at the bottom, bright near the surface.
	var water := TextureRect.new()
	var gradient := GradientTexture2D.new()
	gradient.gradient = Gradient.new()
	gradient.gradient.set_color(0, Color("#bfe9f2"))
	gradient.gradient.set_color(1, Color("#2f7f9e"))
	gradient.fill_from = Vector2(0.5, 0.0)
	gradient.fill_to = Vector2(0.5, 1.0)
	gradient.width = SIZE.x
	gradient.height = SIZE.y
	water.texture = gradient
	water.size = Vector2(SIZE)
	canvas.add_child(water)

	# Soft light rays from the surface.
	for i in 5:
		var ray := Polygon2D.new()
		var x := 60.0 + i * 130.0
		ray.polygon = PackedVector2Array([Vector2(x, 0), Vector2(x + 46, 0), Vector2(x - 40, SIZE.y), Vector2(x - 130, SIZE.y)])
		ray.color = Color(1, 1, 1, 0.07)
		canvas.add_child(ray)

	# Sand.
	var sand := Polygon2D.new()
	var sand_points := PackedVector2Array([Vector2(0, SIZE.y)])
	for i in 11:
		sand_points.append(Vector2(SIZE.x * i / 10.0, SIZE.y - 46 + sin(i * 1.3) * 5.0))
	sand_points.append(Vector2(SIZE))
	sand.polygon = sand_points
	sand.color = SAND
	canvas.add_child(sand)

	# Plants, rocks and wood, standing on the sand (back to front).
	for d in DECOR:
		var item: Dictionary = db.items[d[0]]
		var sprite := Sprite2D.new()
		sprite.texture = load(item["sheet"])
		sprite.region_enabled = true
		var r: Array = item["sprite"]
		sprite.region_rect = Rect2(r[0], r[1], r[2], r[3])
		var s: float = float(d[2]) / r[3]
		sprite.scale = Vector2(s, s)
		sprite.flip_h = d[3]
		sprite.centered = false
		sprite.position = Vector2(d[1] - r[2] * s * 0.5, SIZE.y - 30 - d[2])
		canvas.add_child(sprite)

	# Guppies.
	var guppy: Dictionary = db.species["guppy"]
	var sheet: Texture2D = load(guppy["sprites"]["sheet"])
	for f in FISH:
		var r: Array = guppy["sprites"]["varieties"][f[0]]
		var sprite := Sprite2D.new()
		sprite.texture = sheet
		sprite.region_enabled = true
		sprite.region_rect = Rect2(r[0], r[1], r[2], r[3])
		sprite.scale = Vector2(f[3], f[3])
		sprite.flip_h = not f[4]
		sprite.position = Vector2(f[1], f[2])
		canvas.add_child(sprite)

	# Bubbles.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		var bubble := Line2D.new()
		var c := Vector2(rng.randf_range(340, 420), rng.randf_range(160, 380))
		var radius := rng.randf_range(3.0, 7.0)
		for k in 17:
			bubble.add_point(c + Vector2.from_angle(TAU * k / 16.0) * radius)
		bubble.width = 1.5
		bubble.default_color = Color(1, 1, 1, 0.6)
		canvas.add_child(bubble)

	# Title on a soft banner.
	var banner := Polygon2D.new()
	banner.polygon = PackedVector2Array([Vector2(0, 26), Vector2(SIZE.x, 26), Vector2(SIZE.x, 164), Vector2(0, 164)])
	banner.color = Color(0.05, 0.2, 0.28, 0.28)
	canvas.add_child(banner)
	_add_label(canvas, TITLE, 70, Vector2(0, 26), Color("#fff8e7"), Color("#1d4f63"), 14)
	_add_label(canvas, SUBTITLE, 34, Vector2(0, 112), Color("#ffd27a"), Color("#1d4f63"), 10)


func _add_label(parent: Node, text: String, font_size: int, pos: Vector2, color: Color, outline: Color, outline_size: int) -> void:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.9
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = Vector2(SIZE.x, font_size + 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", outline)
	label.add_theme_constant_override("outline_size", outline_size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	label.add_theme_constant_override("shadow_offset_y", 4)
	parent.add_child(label)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/images"))
		_viewport.get_texture().get_image().save_png(OUT)
		print("saved ", OUT)
		return true  # quit
	return false
