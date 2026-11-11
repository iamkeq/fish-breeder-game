class_name SaveFile
extends RefCounted
## Reads and writes a save as JSON. JSON has no whole numbers, so everything
## read back is passed through normalize() to turn 3.0 back into 3.


## Returns false if the file couldn't be written.
static func write(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


## The saved data, or {} if there is no save or it can't be read.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return parse(FileAccess.get_file_as_string(path))


static func parse(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {}
	return normalize(json.data)


## Copies `value`, turning whole-number floats (anywhere inside) into ints.
static func normalize(value):
	if value is float and value == floorf(value) and absf(value) < 1e15:
		return int(value)
	if value is Array:
		return value.map(func(v): return normalize(v))
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = normalize(value[key])
		return result
	return value
