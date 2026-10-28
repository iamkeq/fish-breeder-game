extends Node2D
## A guppy-style fish drawn from its traits: body colour, tail shape, pattern,
## sex and age. Pure vector drawing (no image files), so every trait
## combination works, including ones added later in data.
##
## The fish is modelled as a slim 3D body seen from the side. Turning around
## is a real yaw rotation: mid-turn you see it nose-on (a rounded oval with thin
## edge-on fins) rather than a flat card flipping over.
## Species with a "sprites" block (see data/species/guppy.json) are drawn from
## their sprite sheet instead: animated frames where the sheet has them,
## otherwise the still frame with a tail-wave shader, and fry frames while young.
## Swims around inside `bounds`, which is in the parent's coordinates.

const WaveShader := preload("res://scenes/fish_wave.gdshader")

const ADULT_LENGTH := 58.0          # nose to tail base, in pixels
const SPEED_RANGE := Vector2(16.0, 38.0)
const TURN_TIME := 0.85             # seconds for a full turn-around
const SEGMENTS := 18
const THICKNESS := 0.42             # body half-width as a fraction of body height
const FALLBACK_COLOR := Color("#cccccc")
const EYE_WHITE := Color("#f6f2e9")
const PUPIL := Color("#1c1a1f")
const RED_PUPIL := Color("#c23b3b")

var fish: Fish
var species: Dictionary
var bounds: Rect2
## false = stay in place and just animate (used by previews and the gallery).
var swims: bool = true

var _target := Vector2.ZERO
var _speed := 24.0
var _rest := 0.0
var _wiggle := 0.0
var _tilt := 0.0
## Yaw: 0 = facing right, PI = facing left. Animated during a turn.
var _phi := 0.0
var _facing := 1.0
var _turn_t := 1.0                  # 0..1 progress of the current turn; 1 = not turning
var _turn_from := 0.0
var _turn_dir := 1.0                # +1 turns away from the viewer, -1 towards
## Pick the starting spot on the first frame, once the tank has its final size.
var _needs_spawn := true
## Seconds since this fish started swimming (used to re-place it if the tank
## is resized right after it appeared).
var _alive := 0.0
## Per-fish spot layout, so every spotted fish looks a little different.
var _spots: Array[Vector3] = []
## Visual-only randomness; kept separate from the game RNG.
var _rng := RandomNumberGenerator.new()
## Sprite mode: the sprite, and loaded sheets shared by every fish.
var _sprite: Sprite2D = null
var _anim_time := 0.0
static var _sheets := {}

# Per-frame drawing values (set at the start of _draw).
var _a := 0.0
var _b := 0.0
var _cos := 1.0
var _sin := 0.0
var _curl := 0.0


func setup(p_fish: Fish, p_species: Dictionary, p_bounds: Rect2) -> void:
	fish = p_fish
	species = p_species
	_rng.randomize()
	# Fish created in the same instant would otherwise share a time-based seed
	# and swim in lockstep, so mix in something unique to each one.
	_rng.seed = _rng.seed ^ (get_instance_id() * 2654435761) ^ (fish.id * 7919)
	_wiggle = _rng.randf() * TAU
	_make_spots()
	if species.has("sprites"):
		_setup_sprite()
	set_bounds(p_bounds)


func set_bounds(p_bounds: Rect2) -> void:
	var margin := _length() * 0.9
	bounds = p_bounds.grow(-margin)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		bounds = Rect2(p_bounds.get_center(), Vector2.ONE)
	if swims and not _needs_spawn and _alive < 0.5:
		# Just appeared, then the tank got its real size: pick a fresh spot in it.
		_needs_spawn = true
	elif swims and not _needs_spawn and not bounds.has_point(position):
		position = position.clamp(bounds.position, bounds.end)
		_pick_target()


# --- Movement ----------------------------------------------------------------

func _process(delta: float) -> void:
	if not swims:
		_wiggle += delta * 7.0
		if _sprite != null:
			_update_sprite(delta)
		queue_redraw()
		return
	_alive += delta
	if _needs_spawn:
		if not is_visible_in_tree():
			return  # wait until the tank is on screen and has its real size
		_needs_spawn = false
		_alive = 0.0
		position = _random_point()
		_facing = 1.0 if _rng.randf() < 0.5 else -1.0
		_phi = 0.0 if _facing > 0.0 else PI
		_pick_target()

	_update_turn(delta)
	var vertical := 0.0
	if _rest > 0.0:
		_rest -= delta
		_wiggle += delta * 3.5
		if _rest <= 0.0:
			_pick_target()
	else:
		_wiggle += delta * (6.0 + _speed * 0.18)
		var to := _target - position
		if absf(to.x) < 6.0 and absf(to.y) < 6.0:
			_rest = _rng.randf_range(0.4, 2.2)
			if _rng.randf() < 0.2:
				_start_turn()  # idle turn-around while resting
		else:
			if to.x * _facing < -6.0 and _turn_t >= 1.0:
				_start_turn()
			# Horizontal speed follows the yaw, so the fish slows, stops and
			# reverses smoothly through a turn instead of snapping around.
			var vx := cos(_phi) * _speed
			if absf(to.x) < 6.0:
				vx = 0.0
			var vy := clampf(to.y, -1.0, 1.0) * _speed * 0.45 if absf(to.y) > 2.0 else 0.0
			position += Vector2(vx, vy) * delta
			position = position.clamp(bounds.position, bounds.end)
			vertical = vy / maxf(_speed, 1.0)
	_tilt = lerpf(_tilt, clampf(vertical * 0.9, -0.38, 0.38), minf(delta * 3.0, 1.0))
	if _sprite != null:
		_update_sprite(delta)
	queue_redraw()


func _start_turn() -> void:
	_turn_from = _phi
	_turn_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	_turn_t = 0.0
	_facing = -_facing


func _update_turn(delta: float) -> void:
	if _turn_t >= 1.0:
		return
	_turn_t = minf(_turn_t + delta / TURN_TIME, 1.0)
	_phi = _turn_from + _turn_dir * PI * smoothstep(0.0, 1.0, _turn_t)
	if _turn_t >= 1.0:
		_phi = 0.0 if _facing > 0.0 else PI


func _random_point() -> Vector2:
	return Vector2(_rng.randf_range(bounds.position.x, bounds.end.x),
		_rng.randf_range(bounds.position.y, bounds.end.y))


func _pick_target() -> void:
	# Mostly sideways swimming, with gentle up/down drift.
	var p := _random_point()
	p.y = lerpf(position.y, p.y, 0.4)
	_target = p
	_speed = _rng.randf_range(SPEED_RANGE.x, SPEED_RANGE.y)


# --- Shape helpers -----------------------------------------------------------

func _grown() -> float:
	if fish == null:
		return 1.0
	return clampf(float(fish.age_days) / float(species.get("days_to_adult", 1)), 0.0, 1.0)


func _length() -> float:
	return ADULT_LENGTH * lerpf(0.4, 1.0, _grown())


func _is_male() -> bool:
	return fish.sex == Fish.MALE


func _render_rule(rule: String) -> bool:
	return fish.get_trait("body_color") in species.get("render", {}).get(rule, [])


func _make_spots() -> void:
	_spots.clear()
	var r := RandomNumberGenerator.new()
	r.seed = fish.id * 7919 + 101
	for i in 7:
		# x along the body (-1 tail .. 1 nose), y across it (-1 back .. 1 belly), size
		_spots.append(Vector3(r.randf_range(-0.85, 0.35), r.randf_range(-0.55, 0.3), r.randf_range(0.6, 1.0)))


## Body half-height at t (0 = tail base, 1 = nose), as a fraction of the maximum.
static func _profile(t: float) -> float:
	if t <= 0.6:
		return 0.3 + 0.7 * pow(sin(PI * 0.5 * t / 0.6), 1.2)
	var u := (t - 0.6) / 0.4
	return sqrt(maxf(0.0, 1.0 - u * u))


func _t_of(x: float) -> float:
	return clampf((x / _a + 1.0) * 0.5, 0.0, 1.0)


## Which side of the body faces the viewer (z sign), so markings and the eye
## are drawn on the visible flank.
func _near_side() -> float:
	return -1.0 if _cos >= 0.0 else 1.0


## Maps a point on the fish (x along the body, y up/down, z across the body)
## to the screen: adds the swimming wave and turn curl, then the yaw rotation.
func _pt(p: Vector2, z: float = 0.0) -> Vector2:
	var back := clampf((_a * 0.4 - p.x) / (_a * 1.4), 0.0, 1.3)
	var amp := _length() * (0.025 if _rest > 0.0 else 0.045)
	var wave := sin(_wiggle - p.x / _a * 1.6) * amp * back * back
	p.y += wave
	# Real fish swish sideways; this only shows when seen at an angle.
	z += wave * 1.2
	# Mid-turn, the body bends into a C towards the new direction.
	z += _curl * pow(p.x / _a, 2.0) * _a * 0.45
	return Vector2(p.x * _cos - z * _sin, p.y + sin(_wiggle * 0.25) * 1.2)


static func _ellipse(center: Vector2, rx: float, ry: float, points: int = 16) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in points:
		var t := TAU * i / points
		result.append(center + Vector2(cos(t) * rx, sin(t) * ry))
	return result


# --- Drawing -----------------------------------------------------------------

func _draw() -> void:
	if fish == null or _sprite != null:
		return
	var length := _length()
	_a = length * 0.5
	_b = length * (0.2 if _is_male() else 0.25)
	_cos = cos(_phi)
	_sin = sin(_phi)
	_curl = sin(_turn_t * PI) * _turn_dir if _turn_t < 1.0 else 0.0
	var base := Color(species.get("palette", {}).get(fish.get_trait("body_color"), FALLBACK_COLOR))
	var fin := base.lightened(0.18)
	if _is_male():
		fin = Color.from_hsv(fin.h, minf(fin.s * 1.25, 1.0), fin.v)
	self_modulate.a = lerpf(0.7, 1.0, _grown())  # fry are a little see-through

	draw_set_transform(Vector2.ZERO, _tilt * _cos)
	# Draw the far end first: when the tail swings towards the viewer it goes on top.
	var tail_near := _sin > 0.2  # head turning away from the viewer = tail comes towards them
	if not tail_near:
		_draw_tail(length, base, fin)
	_draw_dorsal(fin)
	_draw_body(base)
	if tail_near:
		_draw_tail(length, base, fin)
	draw_set_transform(Vector2.ZERO)


func _body_rows(t: float) -> Vector2:
	## (top, belly) half-heights at t; females are rounder underneath.
	var h := _profile(t) * _b
	var belly := h
	if not _is_male():
		belly *= 1.0 + 0.2 * sin(PI * clampf((t - 0.2) / 0.6, 0.0, 1.0))
	return Vector2(h, belly)


func _draw_body(base: Color) -> void:
	var tuxedo := fish.get_trait("pattern") == "tuxedo"
	var dark := base.darkened(0.6)
	var side := _near_side()

	# 1. Volume: one cross-section oval per segment. Invisible side-on, they
	#    give the body its rounded nose-on look in the middle of a turn.
	if absf(_sin) > 0.04:
		var order := range(SEGMENTS + 1)
		if _sin > 0.0:  # head is turning away, so draw it first (furthest)
			order.reverse()
		for i in order:
			var t := float(i) / SEGMENTS
			var rows := _body_rows(t)
			var x := lerpf(-_a, _a, t)
			var center := _pt(Vector2(x, (rows.y - rows.x) * 0.5))
			var half_h := (rows.x + rows.y) * 0.5
			var oval := _ellipse(center, maxf(half_h * THICKNESS * 2.0 * absf(_sin), 0.5), half_h)
			var colors := PackedColorArray()
			for p in oval:
				var k := clampf((p.y - center.y) / (half_h * 2.0) + 0.5, 0.0, 1.0)
				var c := base.darkened(0.22).lerp(base.lightened(0.3), k)
				if tuxedo:
					c = c.lerp(dark, smoothstep(0.55, 0.35, t) * 0.85)
				colors.append(c)
			_fill(oval, colors)

	# 2. The flank facing the viewer: shaded bands from back to belly.
	var top := PackedVector2Array()
	var mid := PackedVector2Array()
	var bottom := PackedVector2Array()
	var top_c := PackedColorArray()
	var mid_c := PackedColorArray()
	var bottom_c := PackedColorArray()
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		var x := lerpf(-_a, _a, t)
		var rows := _body_rows(t)
		var bulge := rows.x * THICKNESS * side
		top.append(_pt(Vector2(x, -rows.x)))
		mid.append(_pt(Vector2(x, lerpf(-rows.x, rows.y, 0.45)), bulge))
		bottom.append(_pt(Vector2(x, rows.y)))
		var back_c := base.darkened(0.22)
		var side_c := base
		var under_c := base.lightened(0.35)
		if tuxedo:
			var k := smoothstep(0.55, 0.35, t)
			back_c = back_c.lerp(dark, k)
			side_c = side_c.lerp(dark, k * 0.9)
			under_c = under_c.lerp(dark, k * 0.5)
		top_c.append(back_c)
		mid_c.append(side_c)
		bottom_c.append(under_c)
	for i in SEGMENTS:
		_fill(PackedVector2Array([top[i], top[i + 1], mid[i + 1], mid[i]]),
			PackedColorArray([top_c[i], top_c[i + 1], mid_c[i + 1], mid_c[i]]))
		_fill(PackedVector2Array([mid[i], mid[i + 1], bottom[i + 1], bottom[i]]),
			PackedColorArray([mid_c[i], mid_c[i + 1], bottom_c[i + 1], bottom_c[i]]))

	_draw_body_pattern(base)

	if _render_rule("sheen"):
		var shine := Color(1, 1, 1, 0.3 * absf(_cos))
		for i in range(3, SEGMENTS - 3):
			_fill(PackedVector2Array([top[i].lerp(mid[i], 0.35), top[i + 1].lerp(mid[i + 1], 0.35),
				top[i + 1].lerp(mid[i + 1], 0.75), top[i].lerp(mid[i], 0.75)]), shine)

	var flank := absf(_cos)  # how side-on we are; markings fade when nose-on
	if not _is_male() and _grown() >= 1.0:  # gravid spot
		draw_circle(_pt(Vector2(-_a * 0.05, _b * 0.55), _b * 0.3 * side), _b * 0.2 * lerpf(0.5, 1.0, flank),
			Color(0.15, 0.1, 0.08, 0.3 * flank))

	var gill := PackedVector2Array()
	for i in 7:
		var ang := lerpf(-0.9, 0.9, i / 6.0)
		var p := Vector2(_a * 0.3, 0) + Vector2(cos(ang), sin(ang)) * _b * 0.62
		gill.append(_pt(p, _b * 0.4 * side))
	draw_polyline(gill, Color(base.darkened(0.35), flank), 1.2, true)

	_draw_pectoral(side)

	var outline := PackedVector2Array(top)
	for i in range(SEGMENTS, -1, -1):
		outline.append(bottom[i])
	outline.append(top[0])
	draw_polyline(outline, Color(base.darkened(0.45), pow(flank, 0.6)), 1.4, true)

	_draw_eyes(side)


func _draw_pectoral(side: float) -> void:
	var flap := 0.75 + 0.25 * sin(_wiggle * 1.7)
	var root := Vector2(_a * 0.18, _b * 0.25)
	var reach := _b * 0.75
	var pec := PackedVector2Array([_pt(root, _b * 0.42 * side)])
	for i in 9:
		var ang := lerpf(-0.5, 0.5, i / 8.0)
		var p := root + Vector2(-cos(ang) * flap, sin(ang) * 0.6) * reach
		# The fin sticks out from the flank, so it swings out sideways in a turn.
		pec.append(_pt(p, (_b * 0.42 + reach * 0.5 * flap) * side))
	_fill(pec, Color(1, 1, 1, 0.28))


func _draw_eyes(side: float) -> void:
	var grown := _grown()
	var eye_r := maxf(2.0, _length() * 0.055) * lerpf(1.45, 1.0, grown)  # fry are big-eyed
	var eye_local := Vector2(_a * 0.64, -_b * 0.18)
	var eye_z := _profile(0.82) * _b * THICKNESS * 1.1
	var pupil_color := RED_PUPIL if _render_rule("red_eyes") else PUPIL
	# Head turned away (towards the back of the tank): eyes hidden behind the head.
	if _sin > 0.8:
		return
	var zs := [eye_z * side]
	if _sin < -0.4:  # facing the viewer: both eyes show
		zs.append(-eye_z * side)
	for z in zs:
		var eye := _pt(eye_local, z)
		var squash := lerpf(0.55, 1.0, absf(_cos))
		_fill(_ellipse(eye, eye_r * squash, eye_r, 12), EYE_WHITE)
		var look := Vector2(eye_r * 0.12 * signf(_cos), 0)
		_fill(_ellipse(eye + look, eye_r * 0.66 * squash, eye_r * 0.66, 12), pupil_color)
		draw_circle(eye + Vector2(eye_r * 0.3 * signf(_cos), -eye_r * 0.32), eye_r * 0.24, Color(1, 1, 1, 0.9))


func _draw_body_pattern(base: Color) -> void:
	var ink := base.darkened(0.55)
	var side := _near_side()
	var flank := absf(_cos)
	if flank < 0.15:
		return
	match fish.get_trait("pattern"):
		"spotted":
			for s in _spots:
				var t := (s.x + 1.0) * 0.5
				var rows := _body_rows(t)
				var p := _pt(Vector2(s.x * _a, s.y * rows.x), rows.x * THICKNESS * side * 0.8)
				var r := _b * 0.17 * s.z
				_fill(_ellipse(p, r * 1.45 * flank, r * 1.45, 10), Color(ink, 0.25 * flank))
				_fill(_ellipse(p, r * flank, r, 10), Color(ink, 0.85 * flank))
		"mosaic":
			var r := _b * 0.2
			for col in 7:
				for row in 4:
					var x := -_a * 0.92 + col * _a * 0.19
					var rows := _body_rows(_t_of(x))
					var y := (-0.7 + row * 0.45 + (0.22 if col % 2 == 1 else 0.0)) * rows.x
					var arc := PackedVector2Array()
					for k in 6:
						var ang := lerpf(-PI * 0.5, PI * 0.5, k / 5.0)
						arc.append(_pt(Vector2(x, y) + Vector2(cos(ang), sin(ang)) * r, rows.x * THICKNESS * side * 0.8))
					draw_polyline(arc, Color(ink, 0.7 * flank), 1.3, true)


func _draw_dorsal(fin: Color) -> void:
	var flutter := sin(_wiggle * 1.2) * _b * 0.15
	var start_x := -_a * 0.05
	var end_x := -_a * 0.5
	var p_start := _pt(Vector2(start_x, -_profile(_t_of(start_x)) * _b * 0.9))
	var p_end := _pt(Vector2(end_x, -_profile(_t_of(end_x)) * _b * 0.9))
	var tip_local: Vector2
	if _is_male():  # long, flowing dorsal
		tip_local = Vector2(-_a * 1.0, -_b * 1.25 + flutter)
	else:
		tip_local = Vector2(-_a * 0.45, -_b * 1.35 + flutter * 0.5)
	var tip := _pt(tip_local)
	var bulge := _pt(tip_local.lerp(Vector2(start_x, -_b), 0.45) + Vector2(0, -_b * 0.15))
	var points := PackedVector2Array([p_start, bulge, tip, p_end])
	_fill(points, PackedColorArray([Color(fin, 0.9), Color(fin, 0.75), Color(fin, 0.6), Color(fin, 0.9)]))
	draw_line(p_start, tip, Color(fin.darkened(0.3), 0.4), 1.0, true)


func _draw_tail(length: float, base: Color, fin: Color) -> void:
	var root := Vector2(-_a * 0.97, 0)
	var root_h := _b * 0.32
	var size := length * (0.78 if _is_male() else 0.48)
	var shape := fish.get_trait("tail_shape")
	if shape == "double_sword":
		_draw_tail_lobe(root, root_h, size * 1.25, -0.42, 0.1, fin)
		_draw_tail_lobe(root, root_h, size * 1.25, 0.42, 0.1, fin)
		_draw_tail_lobe(root, root_h, size * 0.45, 0.0, 0.42, fin)
		return
	var spread := 0.55
	var reach := size
	match shape:
		"round":
			spread = 0.95
			reach = size * 0.6
		"delta":
			spread = 0.6
			reach = size * 0.85
	var edge_local := PackedVector2Array()
	var n := 12
	for i in n + 1:
		var ang := lerpf(-spread, spread, float(i) / n)
		var r := reach
		match shape:
			"round":
				r *= pow(cos(ang / spread * PI * 0.5), 0.35) * 0.35 + 0.65
			"delta":
				r /= cos(ang)  # straight back edge
		ang += sin(_wiggle * 1.3 - i * 0.6) * 0.05
		r *= 1.0 + 0.04 * sin(_wiggle * 1.1 + i)
		edge_local.append(root + Vector2(-cos(ang), sin(ang)) * r)
	var edge := PackedVector2Array()
	for p in edge_local:
		edge.append(_pt(p))
	var root_p := _pt(root)
	var points := PackedVector2Array([_pt(root + Vector2(0, -root_h))])
	var colors := PackedColorArray([base])
	for p in edge:
		points.append(p)
		colors.append(Color(fin, 0.82))
	points.append(_pt(root + Vector2(0, root_h)))
	colors.append(base)
	_fill(points, colors)
	for i in range(1, n, 2):  # fin rays
		draw_line(root_p, edge[i], Color(fin.darkened(0.3), 0.35), 1.0, true)
	draw_polyline(edge, Color(fin.darkened(0.25), 0.6), 1.0, true)
	_draw_tail_pattern(root_p, edge, base)


func _draw_tail_lobe(root: Vector2, root_h: float, reach: float, angle: float, width: float, fin: Color) -> void:
	var sway := sin(_wiggle * 1.3) * 0.06
	var tip := root + Vector2(-cos(angle + sway), sin(angle + sway)) * reach
	var side := Vector2(-sin(angle), -cos(angle)) * reach * width
	var points := PackedVector2Array([
		_pt(root + Vector2(0, -root_h * 0.6)), _pt(root.lerp(tip, 0.5) + side), _pt(tip),
		_pt(root.lerp(tip, 0.5) - side), _pt(root + Vector2(0, root_h * 0.6))])
	_fill(points, PackedColorArray([fin, Color(fin, 0.85), Color(fin, 0.7), Color(fin, 0.85), fin]))
	draw_line(_pt(root), _pt(tip), Color(fin.darkened(0.3), 0.4), 1.0, true)


func _draw_tail_pattern(root: Vector2, edge: PackedVector2Array, base: Color) -> void:
	var ink := base.darkened(0.5)
	var alpha := absf(_cos)
	match fish.get_trait("pattern"):
		"spotted":
			for i in [3, 6, 9]:
				draw_circle(root.lerp(edge[i], 0.65), 2.2 * lerpf(0.5, 1.0, alpha), Color(ink, 0.7 * alpha))
		"mosaic":
			for i in range(1, edge.size() - 1, 2):
				for f in [0.45, 0.7, 0.9]:
					draw_circle(root.lerp(edge[i], f), 1.8 * lerpf(0.5, 1.0, alpha), Color(ink, 0.6 * alpha))


## Fills a convex-ish shape as a triangle fan from its first point. Unlike
## draw_polygon this never fails on squashed (nearly flat) shapes mid-turn.
## `colors` is one Color, or a PackedColorArray with one colour per point.
func _fill(points: PackedVector2Array, colors) -> void:
	var uniform := colors is Color
	var none := PackedVector2Array()
	for i in range(1, points.size() - 1):
		var tri := PackedVector2Array([points[0], points[i], points[i + 1]])
		var cols: PackedColorArray
		if uniform:
			cols = PackedColorArray([colors, colors, colors])
		else:
			cols = PackedColorArray([colors[0], colors[i], colors[i + 1]])
		draw_primitive(tri, cols, none)


# --- Sprite mode (species with a sprite sheet) --------------------------------

func _setup_sprite() -> void:
	var path: String = species["sprites"]["sheet"]
	if not _sheets.has(path):
		_sheets[path] = load(path)
	_sprite = Sprite2D.new()
	_sprite.texture = _sheets[path]
	_sprite.region_enabled = true
	var mat := ShaderMaterial.new()
	mat.shader = WaveShader
	mat.set_shader_parameter("phase", _rng.randf() * TAU)
	_sprite.material = mat
	add_child(_sprite)
	_update_sprite(0.0)


## Picks the frame (animation or still) for the fish's own variety, then
## applies facing, size (fry are small copies of their variety), the turn
## squash, tilt and the tail wave.
func _update_sprite(delta: float) -> void:
	var data: Dictionary = species["sprites"]
	_anim_time += delta
	var c := cos(_phi)
	var facing_right := c >= 0.0
	var look := fish.get_trait(data["trait"])
	# Varieties without their own art yet use a tinted copy of another variety.
	var placeholder: Dictionary = data.get("placeholders", {}).get(look, {}) if not data["varieties"].has(look) else {}
	if not placeholder.is_empty():
		look = placeholder["base"]
	var rect: Array = data["varieties"].get(look, data["varieties"].values()[0])
	var tail_right := false
	var animated := false
	var anims: Dictionary = data.get("animations", {}).get(look, {})
	var anim := "idle" if (_rest > 0.0 or not swims) else ("swim_right" if facing_right else "swim_left")
	if anims.has(anim):
		var frames: Array = anims[anim]
		rect = frames[int(_anim_time * float(data.get("fps", 10))) % frames.size()]
		animated = true
		tail_right = anim == "swim_left"
	_sprite.region_rect = Rect2(rect[0], rect[1], rect[2], rect[3])
	# "swim_left" frames already face left; every other frame faces right.
	_sprite.flip_h = not facing_right and not tail_right

	var sheet_size := Vector2(_sprite.texture.get_size())
	var mat: ShaderMaterial = _sprite.material
	mat.set_shader_parameter("region", Vector4(rect[0] / sheet_size.x, rect[1] / sheet_size.y,
		rect[2] / sheet_size.x, rect[3] / sheet_size.y))
	mat.set_shader_parameter("tail_right", tail_right)
	var resting := _rest > 0.0 or not swims
	mat.set_shader_parameter("amount", 0.015 if animated else (0.03 if resting else 0.06))
	mat.set_shader_parameter("speed", 4.5 if resting else 6.0 + _speed * 0.15)

	# Turning: the fish narrows as it swings round, but never to a flat card,
	# and stretches a touch as it bends.
	var squash := maxf(absf(c), 0.45)
	var stretch := 1.0 + (1.0 - absf(c)) * 0.12
	var sex_scale := 1.05 if fish.sex == Fish.FEMALE else 0.92
	# Fry are a small copy of their own variety, growing to full size as they age,
	# so you can see what each tank's parents produced.
	var growth := lerpf(0.4, 1.0, _grown())
	_sprite.scale = Vector2(squash, stretch) * float(data.get("scale", 1.0)) * sex_scale * growth
	_sprite.rotation = _tilt * (1.0 if facing_right else -1.0)
	_sprite.position = Vector2(0, sin(_wiggle * 0.25) * 1.2)
	_sprite.modulate = Color(placeholder.get("tint", "#ffffff")) if not placeholder.is_empty() else Color.WHITE
	_sprite.modulate.a = lerpf(0.8, 1.0, _grown())
