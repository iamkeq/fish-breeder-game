extends SceneTree
## Finds every sprite on the guppy sheet (transparent background) and writes
## their rectangles, grouped into rows, so data/species/guppy.json can refer to
## frames by row and column.
##   godot --headless --path . -s res://tools/process_guppy_sheet.gd
## Writes:
##   assets/fish/guppy_sheet.png    the atlas as PNG (crisp, no re-compression)
##   assets/fish/guppy_cells.json   [{"row", "col", "rect": [x, y, w, h], "area"}]
## Small blobs (letters of the labels, food crumbs, bubbles) are left out.

const SRC := "res://assets/fish/guppy_sheet_source.webp"
const OUT_PNG := "res://assets/fish/guppy_sheet.png"
const OUT_JSON := "res://assets/fish/guppy_cells.json"
const MIN_AREA := 350       # smaller blobs are text, crumbs, bubbles, hearts
const ROW_GAP := 18         # blobs whose centres are this far apart vertically start a new row
const PAD := 1


func _initialize() -> void:
	var img := Image.load_from_file(SRC)
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var blobs := []
	for y in h:
		for x in w:
			var start := y * w + x
			if seen[start] == 1 or img.get_pixel(x, y).a < 0.5:
				continue
			var blob := _flood_blob(img, seen, start, w, h)
			if blob["area"] >= MIN_AREA:
				blobs.append(blob)

	# Group into rows by vertical centre, then number left to right.
	blobs.sort_custom(func(a, b): return a["rect"].get_center().y < b["rect"].get_center().y)
	var rows := []
	for b in blobs:
		var cy: int = b["rect"].get_center().y
		if rows.is_empty() or cy - rows[-1]["cy"] > ROW_GAP:
			rows.append({"cy": cy, "items": []})
		rows[-1]["items"].append(b)
	var cells := []
	for r in rows.size():
		var items: Array = rows[r]["items"]
		items.sort_custom(func(a, b): return a["rect"].position.x < b["rect"].position.x)
		for c in items.size():
			var rect: Rect2i = items[c]["rect"]
			cells.append({"row": r, "col": c, "area": items[c]["area"],
				"rect": [rect.position.x - PAD, rect.position.y - PAD, rect.size.x + PAD * 2, rect.size.y + PAD * 2]})

	img.save_png(OUT_PNG)
	var f := FileAccess.open(OUT_JSON, FileAccess.WRITE)
	f.store_string(JSON.stringify(cells, "\t"))
	f.close()
	print("found %d sprites in %d rows" % [cells.size(), rows.size()])
	for c in cells:
		print("r%d c%d rect=%s area=%d" % [c["row"], c["col"], str(c["rect"]), c["area"]])
	quit()


static func _flood_blob(img: Image, seen: PackedByteArray, start: int, w: int, h: int) -> Dictionary:
	var stack := PackedInt32Array([start])
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
		if img.get_pixel(x, y).a < 0.5:
			continue
		seen[i] = 1
		area += 1
		min_p = Vector2i(mini(min_p.x, x), mini(min_p.y, y))
		max_p = Vector2i(maxi(max_p.x, x), maxi(max_p.y, y))
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var nx: int = x + dx
				var ny: int = y + dy
				if (dx != 0 or dy != 0) and nx >= 0 and ny >= 0 and nx < w and ny < h:
					stack.append(ny * w + nx)
	return {"rect": Rect2i(min_p, max_p - min_p + Vector2i.ONE), "area": area}
