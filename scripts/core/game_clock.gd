class_name GameClock
extends RefCounted
## Shop-hours clock. Time only moves while the shop is open and not paused.
## Real seconds are passed in, so tests never wait on a real clock.

var open_hour: int = 9
var min_open_hours: float = 4.0
var hard_close_hour: int = 21
var real_seconds_per_hour: float = 60.0

## In-game minutes since midnight.
var minutes: float = 0.0
var is_open: bool = false
var paused: bool = false


func _init(settings: Dictionary = {}) -> void:
	open_hour = int(settings.get("open_hour", open_hour))
	min_open_hours = float(settings.get("min_open_hours", min_open_hours))
	hard_close_hour = int(settings.get("hard_close_hour", hard_close_hour))
	real_seconds_per_hour = float(settings.get("real_seconds_per_hour", real_seconds_per_hour))
	minutes = open_hour * 60.0


func open_shop() -> void:
	minutes = open_hour * 60.0
	is_open = true
	paused = false


## Moves time forward and returns how many in-game minutes passed.
## Closes the shop by itself at the hard-close hour.
func advance(real_seconds: float) -> float:
	if not is_open or paused or real_seconds <= 0.0:
		return 0.0
	var before := minutes
	var close_at := hard_close_hour * 60.0
	minutes = minf(minutes + real_seconds * 60.0 / real_seconds_per_hour, close_at)
	if minutes >= close_at:
		is_open = false
	return minutes - before


func earliest_close_minutes() -> float:
	return (open_hour + min_open_hours) * 60.0


func can_close() -> bool:
	return is_open and minutes >= earliest_close_minutes()


func close_shop() -> bool:
	if not can_close():
		return false
	is_open = false
	return true


func hour() -> int:
	return int(minutes) / 60


func time_string() -> String:
	return format_minutes(minutes)


static func format_minutes(total_minutes: float) -> String:
	return "%02d:%02d" % [int(total_minutes) / 60, int(total_minutes) % 60]
