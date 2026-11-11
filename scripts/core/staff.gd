class_name Staff
extends RefCounted
## Small static helpers for shop staff. A hire is a plain dictionary
## `{id, name, task, hired_day, color}`; later updates can add more keys
## (stats, skills) without touching the save format.


## A new hire's dictionary.
static func make_member(id: int, member_name: String, task: String, hired_day: int, color: String) -> Dictionary:
	return {"id": id, "name": member_name, "task": task, "hired_day": hired_day, "color": color}


## The first name on the list nobody on the team has. If every name is taken
## it numbers the first one ("Pip 2") so hiring never fails.
static func pick_name(names: Array, team: Array) -> String:
	var used := {}
	for m in team:
		used[m["name"]] = true
	for n in names:
		if not used.has(str(n)):
			return str(n)
	return "%s %d" % [names[0], team.size() + 1]


## A colour for the avatar, cycling through the list by hire number.
static func pick_color(colors: Array, id: int) -> String:
	return str(colors[(maxi(id, 1) - 1) % colors.size()])


## The team member doing `task`, or {} if nobody is.
static func for_task(team: Array, task: String) -> Dictionary:
	for m in team:
		if m["task"] == task:
			return m
	return {}


## "Pip fed 14 fry" style sentence for the day summary. `detail` is extra
## wording the job adds ("5 fish food ($10)" for the Stock clerk).
static func night_text(member_name: String, task: String, actions: int, detail: String) -> String:
	if actions <= 0:
		return "%s had nothing to do tonight." % member_name
	match task:
		"feeder":
			return "%s fed %d fry%s" % [member_name, actions, detail]
		"decorator":
			return "%s hung %d decoration%s" % [member_name, actions, "" if actions == 1 else "s"]
		"stocker":
			return "%s restocked %s" % [member_name, detail]
	return "%s did %d jobs" % [member_name, actions]
