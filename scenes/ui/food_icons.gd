extends RefCounted
## Tiny pixel-art icons for food buffs (made in code, so no art files and no
## emoji font needed). Draw them with nearest-neighbour filtering and scale
## them up by whole numbers to keep them crisp.

const PALETTE := {
	"o": Color("#5a2e2e"),  # outline
	"R": Color("#e4506b"),  # heart
	"W": Color("#ffc2cf"),  # heart shine
	"S": Color("#f2b988"),  # skin
	"H": Color("#fbd9b8"),  # skin highlight
	"d": Color("#c98b5e"),  # skin shade
}

const MAPS := {
	"heart": [
		"..ooo.ooo..",
		".oRRRoRRRo.",
		"oRWRRRRRRRo",
		"oRWRRRRRRRo",
		"oRRRRRRRRRo",
		".oRRRRRRRo.",
		"..oRRRRRo..",
		"...oRRRo...",
		"....oRo....",
		".....o.....",
	],
	"arm": [
		".......ooooo..",
		"......oSSSSSo.",
		"......oSdSdSo.",
		"......oSSSSSo.",
		".......oSSSo..",
		"..oooo.oSSSo..",
		".oHHSSooSSSo..",
		"oHHSSSSSSSSo..",
		"oSSSSSSSSSSo..",
		"oSSSSSSSSSSo..",
		".oooooooooo...",
	],
}

static var _cache: Dictionary = {}


## The icon called `icon_name` ("heart", "arm"), or null for "" / unknown names.
static func texture(icon_name: String) -> Texture2D:
	if not MAPS.has(icon_name):
		return null
	if not _cache.has(icon_name):
		var rows: Array = MAPS[icon_name]
		var image := Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
		for y in rows.size():
			for x in rows[y].length():
				var key: String = rows[y][x]
				if PALETTE.has(key):
					image.set_pixel(x, y, PALETTE[key])
		_cache[icon_name] = ImageTexture.create_from_image(image)
	return _cache[icon_name]
