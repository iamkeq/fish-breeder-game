extends SceneTree
## Finds every sprite on a sprite sheet with a transparent background and
## writes their rectangles, grouped into rows (top to bottom) and numbered
## left to right, so data files can refer to frames by [x, y, w, h].
##
##   godot --headless --path . -s res://tools/cut_sheet.gd -- <source> <out.png> <out.json> [min_area] [merge_gap] [alpha] [repack]
##
## Small pieces within `merge_gap` pixels of a sprite join it (pebble
## piles, loose leaves). Leftover specks smaller than `min_area` (label text,
## crumbs, bubbles) are dropped. The PNG is a lossless copy of the source.
## Only pixels at least `alpha` opaque (default 0.5) count, so faint
## compression haze between sprites doesn't chain them together.
## With "repack", each sprite is copied (its own pixels and their soft edge
## only) into its own slot of a new sheet. Use it when sprites sit so close
## that one's rectangle catches bits of its neighbours.
## Examples:
##   ... -- res://assets/fish/guppy_sheet_source.webp res://assets/fish/guppy_sheet.png res://assets/fish/guppy_cells.json 350 0
##   ... -- res://assets/decor/decor_sheet_source.webp res://assets/decor/decor_sheet.png res://assets/decor/decor_cells.json 1000 4 0.5 repack

const ROW_GAP := 30         # a jump in vertical centre bigger than this starts a new row
const SPECK := 30           # blobs this small are noise; dropped before merging so they can't chain sprites together
const PAD := 1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: -- <source> <out.png> <out.json> [min_area] [merge_gap] [alpha] [repack]")
		quit(1)
		return
	var src: String = args[0]
	var min_area := int(args[3]) if args.size() > 3 else 350
	var merge_gap := int(args[4]) if args.size() > 4 else 0
	var alpha := float(args[5]) if args.size() > 5 else 0.5

	var img := Image.load_from_file(src)
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var blobs := []
	for y in h:
		for x in w:
			var start := y * w + x
			if seen[start] == 1 or img.get_pixel(x, y).a < alpha:
				continue
			blobs.append(_flood_blob(img, seen, start, w, h, alpha))

	blobs = blobs.filter(func(b): return b["area"] >= SPECK)
	blobs = _attach_pieces(blobs, min_area, merge_gap)

	# Group into rows by vertical centre, then number left to right.
	blobs.sort_custom(func(a, b): return a["rect"].get_center().y < b["rect"].get_center().y)
	var rows := []
	for b in blobs:
		var cy: int = b["rect"].get_center().y
		if rows.is_empty() or cy - rows[-1]["cy"] > ROW_GAP:
			rows.append({"cy": cy, "items": []})
		rows[-1]["items"].append(b)
	var cells := []
	var ordered := []
	for r in rows.size():
		var items: Array = rows[r]["items"]
		items.sort_custom(func(a, b): return a["rect"].position.x < b["rect"].position.x)
		for c in items.size():
			var rect: Rect2i = items[c]["rect"]
			ordered.append(items[c])
			cells.append({"row": r, "col": c, "area": items[c]["area"],
				"rect": [rect.position.x - PAD, rect.position.y - PAD, rect.size.x + PAD * 2, rect.size.y + PAD * 2]})

	if args.size() > 6 and args[6] == "repack":
		# Copy each sprite's own pixels into its own slot, so tightly packed
		# neighbours can't bleed into its rectangle.
		var packed := _repack(img, ordered, alpha)
		for i in cells.size():
			cells[i]["source_rect"] = cells[i]["rect"]
			var d: Rect2i = ordered[i]["dest"]
			cells[i]["rect"] = [d.position.x, d.position.y, d.size.x, d.size.y]
		img = packed

	img.save_png(args[1])
	var f := FileAccess.open(args[2], FileAccess.WRITE)
	f.store_string(JSON.stringify(cells, "\t"))
	f.close()
	print("found %d sprites in %d rows" % [cells.size(), rows.size()])
	for c in cells:
		print("r%d c%d rect=%s area=%d" % [c["row"], c["col"], str(c["rect"]), c["area"]])
	quit()


## Sprites (blobs of at least `min_area`) are kept as they are; neighbouring
## sprites never merge. Smaller pieces (a loose leaf, a stray pebble) join the
## sprite whose rectangle they touch within `gap` pixels, or are dropped.
static func _attach_pieces(blobs: Array, min_area: int, gap: int) -> Array:
	var sprites := blobs.filter(func(b): return b["area"] >= min_area)
	if gap <= 0:
		return sprites
	for piece in blobs.filter(func(b): return b["area"] < min_area):
		var p: Rect2i = piece["rect"]
		var best := -1
		var best_overlap := -1
		for i in sprites.size():
			var grown: Rect2i = sprites[i]["rect"].grow(gap)
			if grown.intersects(p):
				var overlap := grown.intersection(p).get_area()
				if overlap > best_overlap:
					best = i
					best_overlap = overlap
		if best >= 0:
			sprites[best] = {"rect": sprites[best]["rect"].merge(p), "area": sprites[best]["area"] + piece["area"],
				"pixels": sprites[best]["pixels"] + piece["pixels"]}
	return sprites


static func _flood_blob(img: Image, seen: PackedByteArray, start: int, w: int, h: int, alpha: float) -> Dictionary:
	var stack := PackedInt32Array([start])
	var pixels := PackedInt32Array()
	var min_p := Vector2i(w, h)
	var max_p := Vector2i(-1, -1)
	var area := 0
	while not stack.is_empty():
		var i: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if seen[i] == 1:
			continue
		var x := i % w
		var y := i / w
		if img.get_pixel(x, y).a < alpha:
			continue
		seen[i] = 1
		area += 1
		pixels.append(i)
		min_p = Vector2i(mini(min_p.x, x), mini(min_p.y, y))
		max_p = Vector2i(maxi(max_p.x, x), maxi(max_p.y, y))
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var nx: int = x + dx
				var ny: int = y + dy
				if (dx != 0 or dy != 0) and nx >= 0 and ny >= 0 and nx < w and ny < h:
					stack.append(ny * w + nx)
	return {"rect": Rect2i(min_p, max_p - min_p + Vector2i.ONE), "area": area, "pixels": pixels}


## Lays the sprites out left to right in rows on a new sheet (same width as the
## source) and copies each one's pixels, plus the faint anti-aliased pixels
## right around them, into its slot. Sets item["dest"] to the new rectangle.
static func _repack(img: Image, items: Array, alpha: float) -> Image:
	const GAP := 6
	const EDGE := 2
	var width := img.get_width()
	var iw := img.get_width()
	var ih := img.get_height()
	var x := GAP
	var y := GAP
	var row_h := 0
	for it in items:
		var r: Rect2i = it["rect"].grow(EDGE)
		if x + r.size.x + GAP > width:
			x = GAP
			y += row_h + GAP
			row_h = 0
		it["dest"] = Rect2i(Vector2i(x, y), r.size)
		x += r.size.x + GAP
		row_h = maxi(row_h, r.size.y)
	var out := Image.create(width, y + row_h + GAP, false, Image.FORMAT_RGBA8)
	for it in items:
		var r: Rect2i = it["rect"].grow(EDGE)
		var offset: Vector2i = it["dest"].position - r.position
		for i in it["pixels"]:
			var p := Vector2i(i % iw, i / iw)
			out.set_pixelv(p + offset, img.get_pixelv(p))
			# Soft edge: faint neighbours that aren't solid pixels of another sprite.
			for dy in range(-EDGE, EDGE + 1):
				for dx in range(-EDGE, EDGE + 1):
					var q := p + Vector2i(dx, dy)
					if q.x < 0 or q.y < 0 or q.x >= iw or q.y >= ih:
						continue
					var c := img.get_pixelv(q)
					if c.a > 0.0 and c.a < alpha:
						out.set_pixelv(q + offset, c)
	return out
