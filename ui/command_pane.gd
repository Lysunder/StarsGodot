class_name CommandPane
extends VBoxContainer
## The Command pane (D15): tiles for the planet or fleet under the player's command. Planet:
## Planet, Minerals on Hand, Status, Fleets in Orbit, Starbase, Production. Fleet: Fleet,
## Location, Fuel and Cargo, Fleet Composition, Other Fleets Here, Fleet Waypoints, Waypoint Task.
## Every edit is an order through GameSession; the tiles are rebuilt from the view afterwards.

signal goto(kind: String, id: int)

const MINERALS := ["Ironium", "Boranium", "Germanium"]
const CARGO := ["Ironium", "Boranium", "Germanium", "Colonists", "Fuel"]
const TASKS := [
	["none", "(no task here)"],
	["transport", "Transport"],
	["colonize", "Colonize"],
	["remote_mine", "Remote mining"],
	["merge", "Merge with fleet"],
	["scrap", "Scrap fleet"],
	["route", "Route"],
]
const ACTIONS := [
	["none", "No action"],
	["load_all", "Load all available"],
	["unload_all", "Unload all"],
	["load", "Load exactly"],
	["unload", "Unload exactly"],
	["fill_percent", "Fill up to %"],
	["wait_percent", "Wait for %"],
	["load_optimal", "Load optimal"],
	["set_amount", "Set amount to"],
	["set_waypoint", "Set waypoint to"],
]
const MAX_WARP := 10
const LIST_HEIGHT := 96

var kind: String = ""
var id: int = -1
var status_text: String = ""

var _tiles: VBoxContainer
var _production: ProductionDialog
var _waypoint := -1
var _pending_rebuild := false


func _ready() -> void:
	_tiles = VBoxContainer.new()
	_tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_tiles)
	_production = ProductionDialog.new()
	add_child(_production)
	GameSession.changed.connect(_queue_rebuild)


func command(p_kind: String, p_id: int) -> void:
	kind = p_kind
	id = p_id
	_waypoint = -1
	status_text = ""
	_rebuild()


func _queue_rebuild() -> void:
	if not _pending_rebuild:
		_pending_rebuild = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_pending_rebuild = false
	for child in _tiles.get_children():
		child.queue_free()
	if not GameSession.has_game():
		return
	match kind:
		"planet":
			_planet_tiles()
		"fleet":
			_fleet_tiles()
	if not status_text.is_empty():
		var l := Label.new()
		l.text = status_text
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Color("800000"))
		_tiles.add_child(l)


func _tile(title: String) -> Tile:
	var t := Tile.new(title)
	_tiles.add_child(t)
	return t


func _order(order: Dictionary, replace := false) -> void:
	status_text = GameSession.set_order(order) if replace else GameSession.add_order(order)
	_queue_rebuild()


# --- Planet tiles -------------------------------------------------------------------------------


func _planet_tiles() -> void:
	var view := GameSession.view
	var info := view.planet_info(id)
	var t := _tile("Planet")
	t.line(info["name"] + ("  (homeworld)" if info["homeworld"] else ""))
	var r := t.row()
	t.button("Prev", func() -> void: _cycle_planet(-1), r)
	t.button("Next", func() -> void: _cycle_planet(1), r)
	t = _tile("Minerals on Hand")
	for i in 3:
		t.line("%s: %d kT" % [MINERALS[i], info["surface"][i]])
	t.line("Mines: %d of %d" % [info["operable_mines"], info["max_mines"]])
	t.line("Factories: %d of %d" % [info["operable_factories"], info["max_factories"]])
	t = _tile("Status")
	t.line("Population: %d" % (info["population"] * 100))
	t.line("Resources/year: %d" % info["resources"])
	t.line("Defenses: %d of %d" % [info["defenses"], info["max_defenses"]])
	t = _tile("Fleets in Orbit")
	var numbers: Array[int] = []
	for f in view.fleets():
		if f.planet == id:
			numbers.append(f.number)
	if numbers.is_empty():
		t.line("None")
	else:
		var here := OptionButton.new()
		for n in numbers:
			here.add_item(view.fleet_name(view.state.fleet(GameSession.PLAYER, n)))
		t.body.add_child(here)
		t.button("Goto", func() -> void: goto.emit("fleet", numbers[here.selected]))
	t = _tile("Starbase")
	t.line(info["starbase"] if info["starbase"] != "" else "No starbase")
	t = _tile("Production")
	var queue := ItemList.new()
	queue.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	for row: Dictionary in info["queue"]:
		queue.add_item(
			(
				"%s (auto) up to %d" % [row["name"], row["count"]]
				if row["auto"]
				else "%s × %d" % [row["name"], row["count"]]
			)
		)
	t.body.add_child(queue)
	r = t.row()
	t.button("Change", func() -> void: _production.open(id), r)
	t.button(
		"Clear",
		func() -> void: _order({"type": "production_queue", "planet": id, "items": []}, true),
		r
	)


func _cycle_planet(delta: int) -> void:
	var ids: Array[int] = []
	for pl in GameSession.view.planets():
		if pl["mine"]:
			ids.append(pl["id"])
	if ids.is_empty():
		return
	var at := maxi(ids.find(id), 0)
	goto.emit("planet", ids[posmod(at + delta, ids.size())])


# --- Fleet tiles --------------------------------------------------------------------------------


func _fleet_tiles() -> void:
	var view := GameSession.view
	var info := view.fleet_info(id)
	if info.is_empty():
		_tile("Fleet").line("This fleet no longer exists.")
		return
	var t := _tile("Fleet")
	t.line(info["name"])
	var r := t.row()
	t.button("Prev", func() -> void: _cycle_fleet(-1), r)
	t.button("Next", func() -> void: _cycle_fleet(1), r)
	var rename := LineEdit.new()
	rename.placeholder_text = "New name"
	rename.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(rename)
	t.button("Rename", func() -> void: _rename(rename.text), r)
	t = _tile("Location")
	if info["planet"] >= 0:
		var pl := view.planet_info(info["planet"])
		t.line("Orbiting %s" % pl["name"])
		if pl["mine"]:
			t.button("Goto", func() -> void: goto.emit("planet", info["planet"]))
	else:
		t.line("Space (%d, %d)" % [info["x"], info["y"]])
	t = _tile("Fuel and Cargo")
	var cargo: Array = info["cargo"]
	t.line("Fuel: %d of %d mg" % [cargo[4], info["fuel_capacity"]])
	(
		t
		. line(
			(
				"Cargo: %d of %d kT  (Fe %d, Bo %d, Ge %d, colonists %d)"
				% [
					cargo[0] + cargo[1] + cargo[2] + cargo[3],
					info["cargo_capacity"],
					cargo[0],
					cargo[1],
					cargo[2],
					cargo[3] * 100,
				]
			)
		)
	)
	t = _tile("Fleet Composition")
	for s: Dictionary in info["ships"]:
		t.line("%d × %s" % [s["count"], s["name"]])
	r = t.row()
	t.button("Split off one", _split, r)
	t = _tile("Other Fleets Here")
	var numbers: Array[int] = []
	for f in view.fleets():
		if f.number != id and f.x == info["x"] and f.y == info["y"]:
			numbers.append(f.number)
	if numbers.is_empty():
		t.line("None")
	else:
		var others := OptionButton.new()
		for n in numbers:
			others.add_item(view.fleet_name(view.state.fleet(GameSession.PLAYER, n)))
		t.body.add_child(others)
		r = t.row()
		t.button("Goto", func() -> void: goto.emit("fleet", numbers[others.selected]), r)
		t.button("Merge all here", _merge, r)
	_waypoint_tiles(info)


func _waypoint_tiles(info: Dictionary) -> void:
	var waypoints: Array = info["waypoints"]
	if _waypoint < 0 or _waypoint >= waypoints.size():
		_waypoint = waypoints.size() - 1
	var t := _tile("Fleet Waypoints")
	t.line("Shift+click in the scanner to add a waypoint.")
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	for i in waypoints.size():
		var wp: Dictionary = waypoints[i]
		var text: String = wp["label"]
		if i > 0:
			text += "   warp %d, %d yr, fuel %d" % [wp["warp"], wp["years"], wp["fuel"]]
		list.add_item(text)
	if _waypoint >= 0:
		list.select(_waypoint)
	list.item_selected.connect(
		func(i: int) -> void:
			_waypoint = i
			_queue_rebuild()
	)
	t.body.add_child(list)
	var r := t.row()
	var repeat := CheckBox.new()
	repeat.text = "Repeat orders"
	repeat.button_pressed = info["repeat"]
	repeat.toggled.connect(
		func(on: bool) -> void:
			_order(
				{"type": "fleet_repeat", "owner": GameSession.PLAYER, "fleet": id, "repeat": on},
				true
			)
	)
	r.add_child(repeat)
	t.button("Delete", _delete_waypoint, r)
	if _waypoint <= 0:
		return
	var wp: Dictionary = waypoints[_waypoint]
	r = t.row()
	var warp_label := Label.new()
	warp_label.text = "Warp"
	r.add_child(warp_label)
	var warp := SpinBox.new()
	warp.max_value = MAX_WARP
	warp.value = wp["warp"]
	warp.value_changed.connect(
		func(v: float) -> void: _change_waypoint(wp, int(v), wp["task"], wp["task_data"])
	)
	r.add_child(warp)
	t = _tile("Waypoint Task")
	var task := OptionButton.new()
	for task_def: Array in TASKS:
		task.add_item(task_def[1])
	task.select(_index_of(TASKS, wp["task"]))
	task.item_selected.connect(
		func(i: int) -> void:
			var name: String = TASKS[i][0]
			var data := {}
			if name == "transport":
				data = {"cargo": _empty_cargo()}
			elif name != "none":
				data = {"raw": [0, 0, 0, 0, 0]}
			_change_waypoint(wp, wp["warp"], name, data)
	)
	t.body.add_child(task)
	if wp["task"] == "transport":
		_transport_grid(t, wp)


func _transport_grid(t: Tile, wp: Dictionary) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	t.body.add_child(grid)
	var cargo: Array = wp["task_data"].get("cargo", _empty_cargo())
	for c in CARGO.size():
		var label := Label.new()
		label.text = CARGO[c]
		grid.add_child(label)
		var action := OptionButton.new()
		for a: Array in ACTIONS:
			action.add_item(a[1])
		action.select(_index_of(ACTIONS, cargo[c]["action"]))
		grid.add_child(action)
		var amount := SpinBox.new()
		amount.max_value = 4095
		amount.value = cargo[c]["amount"]
		grid.add_child(amount)
		var cargo_type := c
		action.item_selected.connect(
			func(i: int) -> void:
				_set_cargo_action(wp, cargo_type, ACTIONS[i][0], int(amount.value))
		)
		amount.value_changed.connect(
			func(v: float) -> void:
				_set_cargo_action(wp, cargo_type, ACTIONS[action.selected][0], int(v))
		)


func _set_cargo_action(wp: Dictionary, c: int, action: String, amount: int) -> void:
	var data: Dictionary = wp["task_data"].duplicate(true)
	var cargo: Array = data.get("cargo", _empty_cargo())
	cargo[c] = {"action": action, "amount": amount}
	data["cargo"] = cargo
	_change_waypoint(wp, wp["warp"], "transport", data)


func _change_waypoint(wp: Dictionary, warp: int, task: String, data: Dictionary) -> void:
	var waypoint := {
		"x": wp["x"],
		"y": wp["y"],
		"target": wp["target"],
		"target_owner": GameSession.PLAYER if wp["target"] == "fleet" else -1,
		"target_id": wp["target_id"],
		"warp": warp,
		"task": task,
		"task_data": data,
	}
	_order(
		{
			"type": "waypoint_change",
			"owner": GameSession.PLAYER,
			"fleet": id,
			"index": _waypoint,
			"waypoint": waypoint,
		}
	)


func _delete_waypoint() -> void:
	if _waypoint <= 0:
		status_text = "The first waypoint is where the fleet is."
		_queue_rebuild()
		return
	_order(
		{
			"type": "waypoint_delete",
			"owner": GameSession.PLAYER,
			"fleet": id,
			"index": _waypoint,
			"count": 1,
		}
	)
	_waypoint -= 1


func _rename(text: String) -> void:
	_order(
		{
			"type": "fleet_rename",
			"owner": GameSession.PLAYER,
			"fleet": id,
			"name": text.strip_edges()
		},
		true
	)


func _merge() -> void:
	_order({"type": "fleet_merge", "owner": GameSession.PLAYER, "fleet": id, "fleets": []})


## Splits one ship of the first design off into a new fleet.
func _split() -> void:
	var info := GameSession.view.fleet_info(id)
	var total := 0
	for s: Dictionary in info["ships"]:
		total += s["count"]
	if total < 2:
		status_text = "A fleet of one ship can't be split."
		_queue_rebuild()
		return
	var used := {}
	for f in GameSession.view.fleets():
		used[f.number] = true
	var free := 0
	while used.has(free):
		free += 1
	_order({"type": "fleet_split", "owner": GameSession.PLAYER, "fleet": id})
	if status_text.is_empty():
		_order(
			{
				"type": "fleet_move_ships",
				"owner": GameSession.PLAYER,
				"fleet": free,
				"other": id,
				"ships": [{"design": info["ships"][0]["design"], "count": 1}],
			}
		)


func _cycle_fleet(delta: int) -> void:
	var numbers: Array[int] = []
	for f in GameSession.view.fleets():
		numbers.append(f.number)
	if numbers.is_empty():
		return
	var at := maxi(numbers.find(id), 0)
	goto.emit("fleet", numbers[posmod(at + delta, numbers.size())])


static func _empty_cargo() -> Array:
	var cargo := []
	for c in CARGO.size():
		cargo.append({"action": "none", "amount": 0})
	return cargo


static func _index_of(table: Array, key: String) -> int:
	for i in table.size():
		if table[i][0] == key:
			return i
	return 0
