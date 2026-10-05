class_name CommandPane
extends VBoxContainer
## The Command pane (D15): tiles for the planet or fleet under the player's command. Planet:
## Planet, Minerals on Hand, Status, Fleets in Orbit, Starbase, Production. Fleet: Fleet,
## Location, Fuel and Cargo, Fleet Composition, Other Fleets Here, Fleet Waypoints, Waypoint Task.
## Every edit is an order through GameSession; the tiles are rebuilt from the view afterwards.

signal goto(kind: String, id: int)
## The waypoint picked in the Fleet Waypoints tile (the map highlights it).
signal waypoint_selected(index: int)

const MINERALS := ["Ironium", "Boranium", "Germanium"]
const CARGO := ["Ironium", "Boranium", "Germanium", "Colonists", "Fuel"]
## Tasks: [id, label, the target it needs ("" = any)].
const TASKS := [
	["none", "(no task here)", ""],
	["transport", "Transport", ""],
	["colonize", "Colonize", "planet"],
	["remote_mine", "Remote mining", "planet"],
	["merge", "Merge with fleet", "fleet"],
	["scrap", "Scrap fleet", ""],
	["lay_mines", "Lay mines", ""],
	["patrol", "Patrol", ""],
	["route", "Route", "planet"],
	["transfer", "Transfer fleet", ""],
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
## Transport actions that take no amount, and those whose amount is a percentage.
const NO_AMOUNT := ["none", "load_all", "unload_all", "load_optimal"]
const PERCENT := ["fill_percent", "wait_percent"]
const MAX_WARP := 10
## Width of the Fleet tile's buttons.
const BUTTON_WIDTH := 80
const WARP_LABEL_WIDTH := 70
const COLOR_WARNING := Color("800000")
const LIST_HEIGHT := 96

var kind: String = ""
var id: int = -1
var status_text: String = ""

var _tiles: VBoxContainer
var _production: ProductionDialog
var _rename_dialog: RenameDialog
## Per tile key: collapsed or not; per kind ("planet", "fleet"): the tile keys in pane order. Both
## last for the session, so a tile stays where the player dragged it.
var _collapsed := {}
var _tile_order := {}
var _waypoint := -1
var _pending_rebuild := false
## The Fleet Waypoints list, and whether a warp slider is being dragged: while it is, warp orders
## go out at every step but only the list's rows are refreshed, so the slider stays under the mouse.
var _waypoint_list: ItemList
var _live := false


func _ready() -> void:
	_tiles = VBoxContainer.new()
	_tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_tiles)
	_production = ProductionDialog.new()
	add_child(_production)
	_rename_dialog = RenameDialog.new()
	_rename_dialog.name_entered.connect(_rename)
	add_child(_rename_dialog)
	GameSession.changed.connect(_queue_rebuild)


func command(p_kind: String, p_id: int) -> void:
	kind = p_kind
	id = p_id
	_waypoint = -1
	status_text = ""
	_rebuild()


## Picks a waypoint of the fleet under command (from the map).
func select_waypoint(index: int) -> void:
	if kind == "fleet" and index != _waypoint:
		_waypoint = index
		_queue_rebuild()


func _queue_rebuild() -> void:
	if _live:
		_refresh_waypoint_rows()
		return
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
	_apply_tile_order()
	if not status_text.is_empty():
		var l := Label.new()
		l.text = status_text
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Color("800000"))
		_tiles.add_child(l)


## A new tile titled `title`; `key` names the kind of tile when the title changes with the object.
func _tile(title: String, key: String = "") -> Tile:
	var t := Tile.new(title, key)
	t.set_collapsed(_collapsed.get(t.key, false))
	t.collapse_toggled.connect(func(k: String, c: bool) -> void: _collapsed[k] = c)
	t.tile_dropped.connect(_on_tile_dropped)
	_tiles.add_child(t)
	return t


## Puts the tiles in the order the player dragged them into (new kinds of tile keep their place).
func _apply_tile_order() -> void:
	var order: Array = _tile_order.get(kind, [])
	var tiles: Array[Tile] = []
	for child in _tiles.get_children():
		if child is Tile and not child.is_queued_for_deletion():
			tiles.append(child)
			if not order.has(child.key):
				order.append(child.key)
	_tile_order[kind] = order
	tiles.sort_custom(func(a: Tile, b: Tile) -> bool: return order.find(a.key) < order.find(b.key))
	for i in tiles.size():
		_tiles.move_child(tiles[i], i)


func _on_tile_dropped(from_key: String, to_key: String) -> void:
	var order: Array = _tile_order.get(kind, [])
	if not order.has(from_key) or not order.has(to_key):
		return
	order.erase(from_key)
	order.insert(order.find(to_key), from_key)
	_queue_rebuild()


## 28700 -> "28,700".
static func thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(-3)
	return ("-" if n < 0 else "") + digits + out


## The fuel and cargo gauges for a fleet_info: fuel in red, cargo in mineral colours.
static func fill_gauges(info: Dictionary, fuel: Gauge, cargo: Gauge) -> void:
	var c: Array = info["cargo"]
	fuel.show_amount(c[Fleet.CARGO_FUEL], info["fuel_capacity"], ClassicTheme.CARGO_COLORS[4], "mg")
	var segments := []
	var total := 0
	for i in 4:
		segments.append([c[i], ClassicTheme.CARGO_COLORS[i]])
		total += c[i]
	cargo.show_values(
		segments, info["cargo_capacity"], "%d of %dkT" % [total, info["cargo_capacity"]]
	)


## A picture with Prev / Next (and more) buttons in a column on the right (Planet and Fleet
## tiles).
func _picture_row(t: Tile, picture: Control, buttons: Array) -> void:
	var r := t.row()
	r.add_child(picture)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(spacer)
	var column := VBoxContainer.new()
	r.add_child(column)
	for spec: Array in buttons:
		var b := t.button(spec[0], spec[1], column)
		b.custom_minimum_size = Vector2(BUTTON_WIDTH, 0)


func _order(order: Dictionary, replace := false) -> void:
	status_text = GameSession.set_order(order) if replace else GameSession.add_order(order)
	_queue_rebuild()


# --- Planet tiles -------------------------------------------------------------------------------


func _planet_tiles() -> void:
	var view := GameSession.view
	var info := view.planet_info(id)
	var t := _tile(info["name"], "planet")
	_picture_row(
		t,
		FleetIcon.new(true),
		[["Prev", func() -> void: _cycle_planet(-1)], ["Next", func() -> void: _cycle_planet(1)]]
	)
	t = _tile("Minerals on Hand")
	for i in 3:
		t.field(MINERALS[i], "%dkT" % info["surface"][i], ClassicTheme.CARGO_COLORS[i])
	t.field("Mines", "%d of %d" % [info["operable_mines"], info["max_mines"]])
	t.field("Factories", "%d of %d" % [info["operable_factories"], info["max_factories"]])
	t = _tile("Status")
	t.field("Population", thousands(info["population"] * 100))
	t.field("Resources/Year", thousands(info["resources"]))
	t.field("Defenses", "%d of %d" % [info["defenses"], info["max_defenses"]])
	t = _tile("Fleets in Orbit")
	var numbers: Array[int] = []
	for f in view.fleets():
		if f.planet == id:
			numbers.append(f.number)
	var here := OptionButton.new()
	for n in numbers:
		here.add_item(view.fleet_name(view.state.fleet(GameSession.PLAYER, n)))
	t.body.add_child(here)
	var fuel := t.gauge("Fuel")
	var cargo := t.gauge("Cargo")
	var show_fleet := func(i: int) -> void:
		if i >= 0 and i < numbers.size():
			fill_gauges(view.fleet_info(numbers[i]), fuel, cargo)
	here.item_selected.connect(show_fleet)
	show_fleet.call(0)
	var r := t.row()
	var go := t.button("Goto", func() -> void: goto.emit("fleet", numbers[here.selected]), r)
	go.disabled = numbers.is_empty()
	here.disabled = numbers.is_empty()
	t = _tile(info["starbase"] if info["starbase"] != "" else "No Starbase", "starbase")
	if info["starbase"] == "":
		t.line("This planet has no starbase.")
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
	var t := _tile(info["name"], "fleet")
	_picture_row(
		t,
		FleetIcon.new(),
		[
			["Prev", func() -> void: _cycle_fleet(-1)],
			["Next", func() -> void: _cycle_fleet(1)],
			["Rename", _open_rename.bind(info["name"])],
		]
	)
	var orbiting := view.planet_info(info["planet"]) if info["planet"] >= 0 else {}
	t = _tile(
		"Orbiting %s" % orbiting["name"] if info["planet"] >= 0 else "In Deep Space", "location"
	)
	var r := t.row()
	var go := t.button("Goto", func() -> void: goto.emit("planet", info["planet"]), r)
	go.disabled = orbiting.is_empty() or not orbiting["mine"]
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(spacer)
	var transfer := t.button(
		"Xfer" if not orbiting.is_empty() else "Jettison", func() -> void: pass, r
	)
	transfer.disabled = true
	transfer.tooltip_text = "Cargo transfer isn't built yet."
	t = _tile("Fuel & Cargo")
	var fuel := t.gauge("Fuel")
	var cargo := t.gauge("Cargo")
	fill_gauges(info, fuel, cargo)
	var held: Array = info["cargo"]
	for i in 3:
		t.field(MINERALS[i], "%dkT" % held[i], ClassicTheme.CARGO_COLORS[i])
	t.field("Colonists", "%dkT" % held[3], ClassicTheme.CARGO_COLORS[3])
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
	waypoint_selected.emit(_waypoint)
	var t := _tile("Fleet Waypoints")
	t.line("Shift+click in the scanner adds a waypoint after the selected one; drag to move it.")
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	_waypoint_list = list
	for i in waypoints.size():
		list.add_item("")
	_fill_waypoint_rows(waypoints)
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
	if _waypoint < 0:
		return
	var wp: Dictionary = waypoints[_waypoint]
	if _waypoint > 0:
		_warp_slider(t, wp)
	t = _tile("Waypoint Task")
	if _waypoint == 0:
		t.line("Here, before the fleet moves:")
	var task := OptionButton.new()
	for i in TASKS.size():
		task.add_item(TASKS[i][1])
		var needs: String = TASKS[i][2]
		task.set_item_disabled(i, not needs.is_empty() and needs != wp["target"])
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
	match wp["task"]:
		"transport":
			_transport_grid(t, wp)
		"transfer":
			_transfer_choice(t, wp)
		"lay_mines", "patrol":
			t.line("Not carried out yet: minefields and battles come later (M7, M9).")


## The leg's warp as a slider (0 to 10). Every step sends the warp (amend_order keeps it one
## order); while dragging, the label and the waypoint rows follow the slider and the pane is
## rebuilt only when the drag ends.
## Sets each row of the Fleet Waypoints list: label, then warp, years and fuel for each leg, with
## a warning in red (except on the selected row, which keeps the selection colours). Color() is
## ItemList's "no custom colour".
func _fill_waypoint_rows(waypoints: Array) -> void:
	for i in mini(waypoints.size(), _waypoint_list.item_count):
		var wp: Dictionary = waypoints[i]
		var text: String = wp["label"]
		var warn := false
		if i > 0:
			text += "   warp %d, %d yr, fuel %d" % [wp["warp"], wp["years"], wp["fuel"]]
			warn = wp["cannot_move"] or wp["short_of_fuel"]
			if wp["cannot_move"]:
				text += "  (can't move)"
			elif wp["warp"] == 0:
				text += "  (warp 0: stays)"
			elif wp["short_of_fuel"]:
				text += "  (not enough fuel)"
		_waypoint_list.set_item_text(i, text)
		var colour := COLOR_WARNING if warn and i != _waypoint else Color()
		_waypoint_list.set_item_custom_fg_color(i, colour)


## While a warp slider is dragged: the list's rows from the order preview.
func _refresh_waypoint_rows() -> void:
	var info := GameSession.view.fleet_info(id)
	if info.is_empty() or not is_instance_valid(_waypoint_list):
		return
	_fill_waypoint_rows(info["waypoints"])


func _warp_slider(t: Tile, wp: Dictionary) -> void:
	var r := t.row()
	var label := Label.new()
	label.custom_minimum_size = Vector2(WARP_LABEL_WIDTH, 0)
	label.text = _warp_text(wp["warp"])
	r.add_child(label)
	var slider := HSlider.new()
	slider.max_value = MAX_WARP
	slider.step = 1
	slider.tick_count = MAX_WARP + 1
	slider.ticks_on_borders = true
	slider.value = wp["warp"]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(slider)
	slider.drag_started.connect(func() -> void: _live = true)
	slider.drag_ended.connect(
		func(_changed: bool) -> void:
			_live = false
			_queue_rebuild()
	)
	slider.value_changed.connect(
		func(v: float) -> void:
			label.text = _warp_text(int(v))
			_change_waypoint(wp, int(v), wp["task"], wp["task_data"])
	)


static func _warp_text(warp: int) -> String:
	return "Stopped" if warp == 0 else "Warp %d" % warp


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
		var current: String = cargo[c]["action"]
		action.select(_index_of(ACTIONS, current))
		grid.add_child(action)
		var amount := SpinBox.new()
		amount.max_value = 100 if PERCENT.has(current) else 4095
		amount.suffix = "%" if PERCENT.has(current) else ("mg" if c == Fleet.CARGO_FUEL else "kT")
		amount.value = cargo[c]["amount"]
		amount.editable = not NO_AMOUNT.has(current)
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


## The transfer task's receiver: task data word 0 counts the players without the giver (S11).
func _transfer_choice(t: Tile, wp: Dictionary) -> void:
	var others: Array[int] = []
	for p in GameSession.view.state.players.size():
		if p != GameSession.PLAYER:
			others.append(p)
	if others.is_empty():
		t.line("There is no other player to give the fleet to.")
		return
	var raw: Array = wp["task_data"].get("raw", [0, 0, 0, 0, 0])
	var to := OptionButton.new()
	for p in others:
		to.add_item("To player %d" % (p + 1))
	to.select(clampi(int(raw[0]) if not raw.is_empty() else 0, 0, others.size() - 1))
	to.item_selected.connect(
		func(i: int) -> void:
			var words: Array = raw.duplicate()
			words.resize(5)
			for k in 5:
				words[k] = int(words[k]) if words[k] != null else 0
			words[0] = i
			_change_waypoint(wp, wp["warp"], "transfer", {"raw": words})
	)
	t.body.add_child(to)


func _set_cargo_action(wp: Dictionary, c: int, action: String, amount: int) -> void:
	var data: Dictionary = wp["task_data"].duplicate(true)
	var cargo: Array = data.get("cargo", _empty_cargo())
	if PERCENT.has(action):
		amount = mini(amount, 100)
	cargo[c] = {"action": action, "amount": 0 if NO_AMOUNT.has(action) else amount}
	data["cargo"] = cargo
	_change_waypoint(wp, wp["warp"], "transport", data)


func _change_waypoint(wp: Dictionary, warp: int, task: String, data: Dictionary) -> void:
	status_text = (
		GameSession
		. amend_order(
			{
				"type": "waypoint_change",
				"owner": GameSession.PLAYER,
				"fleet": id,
				"index": _waypoint,
				"waypoint": waypoint_order(wp, {"warp": warp, "task": task, "task_data": data}),
			}
		)
	)
	_queue_rebuild()


## A `waypoint_change` waypoint built from a fleet_info waypoint row, with `changes` applied.
static func waypoint_order(wp: Dictionary, changes: Dictionary) -> Dictionary:
	var out := {
		"x": wp["x"],
		"y": wp["y"],
		"target": wp["target"],
		"target_owner": wp["target_owner"],
		"target_id": wp["target_id"],
		"warp": wp["warp"],
		"task": wp["task"],
		"task_data": wp["task_data"],
	}
	out.merge(changes, true)
	return out


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


func _open_rename(current: String) -> void:
	_rename_dialog.open("Rename Fleet", current, OrderRules.NAME_MAX)


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
