class_name CommandPane
extends VBoxContainer
## The Command pane (D15): tiles for the planet or fleet under the player's command. Planet:
## Planet, Minerals on Hand, Status, Fleets in Orbit, Starbase, Production. Fleet: Fleet,
## Location, Fuel and Cargo, Fleet Composition, Other Fleets Here, Fleet Waypoints, Waypoint Task.
## Every edit is an order through GameSession; the tiles are rebuilt from the view afterwards.

signal goto(kind: String, id: int)
## The waypoint picked in the Fleet Waypoints tile (the map highlights it).
signal waypoint_selected(index: int)
## A tile wants the player to click a planet in the scanner; `done` gets its id.
signal pick_planet_requested(done: Callable)

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
## Width of the Fleet tile's buttons.
const BUTTON_WIDTH := 80
const AMOUNT_WIDTH := 56
## A cargo type with a transport action is shown in green; a damaged ship's bar is red.
const ACTION_SET := Color("007f00")
const DAMAGE := Color("ff0000")
## Production queue text by ProductionEstimate.When: all this year, some this year, later, never,
## skipped this year.
const QUEUE_COLORS := [
	Color("007f00"), Color("0000ff"), Color("000000"), Color("ff0000"), Color("808080")
]
const LIST_HEIGHT := 96

var kind: String = ""
var id: int = -1
var status_text: String = ""

var _tiles: VBoxContainer
var _production: ProductionDialog
var _rename_dialog: RenameDialog
var _cargo: CargoDialog
## Per tile key: collapsed or not; per kind ("planet", "fleet"): the tile keys in pane order. Both
## last for the session, so a tile stays where the player dragged it.
var _collapsed := {}
var _tile_order := {}
var _waypoint := -1
var _pending_rebuild := false
## The Fleet Waypoints list, and whether a warp slider is being dragged: while it is, warp orders
## go out at every step but only the list's rows are refreshed, so the slider stays under the mouse.
var _waypoint_list: RowList
## The Fleet Waypoints details that follow the warp gauge: {leg, time, fuel}.
var _leg_fields := {}
## The cargo type the transport task shows (0..4).
var _cargo_shown := 0
var _merge_dialog: MergeDialog
var _split_dialog: SplitDialog
var _live := false


func _ready() -> void:
	_tiles = VBoxContainer.new()
	_tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_tiles)
	_production = ProductionDialog.new()
	add_child(_production)
	_merge_dialog = MergeDialog.new()
	_merge_dialog.merge_chosen.connect(_merge_with)
	add_child(_merge_dialog)
	_split_dialog = SplitDialog.new()
	_split_dialog.split_chosen.connect(_split_off)
	add_child(_split_dialog)
	_cargo = CargoDialog.new()
	add_child(_cargo)
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


## The fuel and cargo gauges for a fleet_info: fuel in red, cargo in mineral colours (colonists
## white, so the cargo gauge is grey where empty).
static func fill_gauges(info: Dictionary, fuel: Gauge, cargo: Gauge) -> void:
	var c: Array = info["cargo"]
	fuel.show_amount(c[Fleet.CARGO_FUEL], info["fuel_capacity"], ClassicTheme.CARGO_COLORS[4], "mg")
	var segments := []
	var total := 0
	for i in 4:
		segments.append([c[i], ClassicTheme.CARGO_COLORS[i]])
		total += c[i]
	cargo.empty_colour = Gauge.COLONISTS_EMPTY
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
	t.field(
		"Resources/Year",
		"%s of %s" % [thousands(info["resources_production"]), thousands(info["resources"])]
	)
	var scanner: String = info["scanner"]
	t.field("Scanner Type", GameSession.content.display_name(scanner) if scanner != "" else "None")
	if scanner != "":
		var reach: int = GameSession.content.part(scanner)["stats"]["scan_range"]
		t.field("Scanner Range", "%d light years" % reach)
	t.field("Defenses", "%d of %d" % [info["defenses"], info["max_defenses"]])
	var defense: String = info["defense_type"]
	t.field("Defense Type", GameSession.content.display_name(defense) if defense != "" else "None")
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
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(spacer)
	var load := t.button(
		"Cargo", func() -> void: _cargo.open_with_planet(numbers[here.selected], id), r
	)
	load.disabled = numbers.is_empty()
	_starbase_tile(info)
	_production_tile(info)


## The Starbase tile: the starbase's name as the title, its dock, armor, shields and damage, then
## the mass driver: its speed, the destination, Set Dest and the packet speed gauge.
func _starbase_tile(info: Dictionary) -> void:
	var base: Dictionary = info.get("starbase_info", {})
	var t := _tile(base.get("name", "No Starbase"), "starbase")
	if base.is_empty():
		t.line("This planet has no starbase.")
		return
	var dock: int = base["dock"]
	t.field("Dock Capacity", "Unlimited" if dock < 0 else ("None" if dock == 0 else "%dkT" % dock))
	t.field("Armor", "%sdp" % thousands(base["armor"]))
	t.field("Shields", "%sdp" % thousands(base["shields"]))
	t.field("Damage", "None" if base["damage"] == 0 else "%sdp" % thousands(base["damage"]))
	var driver: int = base["driver_warp"]
	t.field("Mass Driver", "Warp %d" % driver if driver > 0 else "None")
	if driver <= 0:
		return
	var target: int = info["mass_driver_target"]
	var dest: String = GameSession.view.planet_info(target)["name"] if target >= 0 else "None"
	t.field("Destination", dest)
	var r := t.row()
	t.button("Set Dest", _pick_driver_target.bind(info), r)
	var speed := WarpGauge.new()
	speed.set_value(info["mass_driver_warp"] if info["mass_driver_warp"] > 0 else driver)
	speed.value_set.connect(func(v: int) -> void: _set_planet(info, {"mass_driver_warp": v}))
	r.add_child(speed)


## The Production tile: the queue coloured by when each item will be built (green: all of it this
## year; blue: some this year; black: later; red: not within a century; grey: an auto item that
## builds nothing this year), auto items in italics, then Completion and Route to, and Change,
## Clear and Route.
func _production_tile(info: Dictionary) -> void:
	var t := _tile("Production")
	var estimate := ProductionEstimate.estimate(GameSession.view.state, GameSession.content, id)
	var when: Array = estimate["items"]
	var rows: Array[Dictionary] = []
	var queue: Array = info["queue"]
	for i in queue.size():
		var q: Dictionary = queue[i]
		var right := "Up to %d" % q["count"] if q["auto"] else str(q["count"])
		var colour := ClassicTheme.TEXT
		if i < when.size():
			colour = QUEUE_COLORS[when[i]]
		rows.append({"left": q["name"], "right": right, "colour": colour, "italic": q["auto"]})
	var list := RowList.new(LIST_HEIGHT)
	list.set_rows(rows, -1)
	list.row_activated.connect(func(_i: int) -> void: _production.open(id))
	t.body.add_child(list)
	var years: int = estimate["years"]
	var done := "Never"
	if queue.is_empty() or years == 0:
		done = "-"
	elif years == 1:
		done = "1 year"
	elif years > 0:
		done = "%d years" % years
	t.field("Completion", done)
	var route: int = info["route"]
	t.field("Route to", GameSession.view.planet_info(route)["name"] if route >= 0 else "None")
	var r := t.row()
	t.button("Change", func() -> void: _production.open(id), r)
	t.button(
		"Clear",
		func() -> void: _order({"type": "production_queue", "planet": id, "items": []}, true),
		r
	)
	t.button("Route", _pick_route.bind(info), r)


func _pick_route(info: Dictionary) -> void:
	status_text = "Click the planet new ships should go to (Escape cancels)."
	_queue_rebuild()
	pick_planet_requested.emit(func(target: int) -> void: _set_planet(info, {"route": target}))


func _pick_driver_target(info: Dictionary) -> void:
	status_text = "Click the planet to send packets to (Escape cancels)."
	_queue_rebuild()
	pick_planet_requested.emit(
		func(target: int) -> void: _set_planet(info, {"mass_driver_target": target})
	)


## A `planet_settings` order: the planet's current settings with `changes`.
func _set_planet(info: Dictionary, changes: Dictionary) -> void:
	var order := {
		"type": "planet_settings",
		"planet": info["id"],
		"leftover_to_research": info["leftover_to_research"],
		"mass_driver_target": info["mass_driver_target"],
		"mass_driver_warp": info["mass_driver_warp"],
		"route": info["route"],
	}
	order.merge(changes, true)
	status_text = ""
	_order(order, true)


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
	if not orbiting.is_empty():
		var xfer := t.button("Xfer", func() -> void: _cargo.open_with_planet(id, info["planet"]), r)
		xfer.disabled = not orbiting["mine"]
		if not orbiting["mine"]:
			xfer.tooltip_text = "Transfers with other players' planets come later."
	else:
		var jettison := t.button("Jettison", func() -> void: pass, r)
		jettison.disabled = true
		jettison.tooltip_text = "Jettisoning cargo comes with salvage (S14)."
	t = _tile("Fuel & Cargo")
	var fuel := t.gauge("Fuel")
	var cargo := t.gauge("Cargo")
	fill_gauges(info, fuel, cargo)
	for g: Gauge in [fuel, cargo]:
		g.mouse_filter = Control.MOUSE_FILTER_STOP
		g.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		g.gui_input.connect(_on_cargo_gauge_input.bind(info))
	var held: Array = info["cargo"]
	for i in 3:
		t.field(MINERALS[i], "%dkT" % held[i], ClassicTheme.CARGO_COLORS[i])
	t.field("Colonists", "%dkT" % held[3], ClassicTheme.CARGO_COLORS[3])
	t = _tile("Fleet Composition")
	var ships := RowList.new(LIST_HEIGHT)
	var ship_rows: Array[Dictionary] = []
	for s: Dictionary in info["ships"]:
		ship_rows.append(
			{"left": s["name"], "right": str(s["count"]), "bar": s["damage"], "bar_colour": DAMAGE}
		)
	ships.set_rows(ship_rows, -1)
	t.body.add_child(ships)
	var plans: Array = view.me().battle_plans
	var plan := OptionButton.new()
	for p: Dictionary in plans:
		plan.add_item(p["name"])
	if info["battle_plan"] < plan.item_count:
		plan.select(info["battle_plan"])
	plan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plan.item_selected.connect(
		func(i: int) -> void:
			_order(
				{
					"type": "fleet_battle_plan",
					"owner": GameSession.PLAYER,
					"fleet": id,
					"plan": i,
				},
				true
			)
	)
	r = t.row()
	var plan_label := Label.new()
	plan_label.text = "Battle Plan:"
	plan_label.theme_type_variation = "BoldLabel"
	r.add_child(plan_label)
	r.add_child(plan)
	var est: int = info["est_range"]
	var range_text := "-"
	if est >= Movement.CANNOT_MOVE:
		range_text = "Infinite"
	elif est >= 0:
		range_text = "%s l.y." % thousands(est)
	t.field("Est. Range", range_text)
	r = t.row()
	t.button("Split", _open_split.bind(info), r)
	t.button("Split All", _split_all.bind(info), r)
	t.button("Merge", _open_merge.bind(info), r)
	t = _tile("Other Fleets Here")
	var numbers: Array[int] = []
	for f in view.fleets():
		if f.number != id and f.x == info["x"] and f.y == info["y"]:
			numbers.append(f.number)
	var others := OptionButton.new()
	for n in numbers:
		others.add_item(view.fleet_name(view.state.fleet(GameSession.PLAYER, n)))
	others.disabled = numbers.is_empty()
	t.body.add_child(others)
	var other_fuel := t.gauge("Fuel")
	var other_cargo := t.gauge("Cargo")
	var show_other := func(i: int) -> void:
		if i >= 0 and i < numbers.size():
			fill_gauges(view.fleet_info(numbers[i]), other_fuel, other_cargo)
	others.item_selected.connect(show_other)
	show_other.call(0)
	r = t.row()
	var buttons: Array[Button] = [
		t.button("Goto", func() -> void: goto.emit("fleet", numbers[others.selected]), r),
		t.button("Merge", func() -> void: _merge_with([numbers[others.selected]]), r),
		t.button("Cargo", func() -> void: _cargo.open_with_fleet(id, numbers[others.selected]), r),
	]
	for b in buttons:
		b.disabled = numbers.is_empty()
	_waypoint_tiles(info)


func _waypoint_tiles(info: Dictionary) -> void:
	var waypoints: Array = info["waypoints"]
	if _waypoint < 0 or _waypoint >= waypoints.size():
		_waypoint = waypoints.size() - 1
	waypoint_selected.emit(_waypoint)
	var t := _tile("Fleet Waypoints")
	var list := RowList.new(LIST_HEIGHT)
	_waypoint_list = list
	var rows: Array[Dictionary] = []
	for wp: Dictionary in waypoints:
		rows.append({"left": wp["label"]})
	list.set_rows(rows, _waypoint)
	list.row_selected.connect(
		func(i: int) -> void:
			_waypoint = i
			_queue_rebuild()
	)
	list.key_pressed.connect(
		func(key: Key) -> void:
			if key == KEY_DELETE or key == KEY_BACKSPACE:
				_delete_waypoint()
	)
	t.body.add_child(list)
	# the leg the details describe: the selected waypoint's, or the next one from waypoint 0
	var leg := _waypoint if _waypoint > 0 else 1
	_leg_fields.clear()
	if leg < waypoints.size():
		var wp: Dictionary = waypoints[leg]
		if _waypoint > 0:
			t.field("Coming From", waypoints[leg - 1]["label"])
		else:
			t.field("Next Way Pt", wp["label"])
		t.field("Distance", "%.2f Light Years" % wp["distance"])
		var gauge := t.gauge("Warp Factor", WarpGauge.new()) as WarpGauge
		gauge.set_value(wp["warp"])
		gauge.value_dragged.connect(
			func(v: int) -> void:
				_live = true
				_change_waypoint_at(leg, wp, v, wp["task"], wp["task_data"])
		)
		gauge.value_set.connect(
			func(v: int) -> void:
				_live = false
				_change_waypoint_at(leg, wp, v, wp["task"], wp["task_data"])
		)
		_leg_fields["time"] = t.field("Travel Time", "")
		_leg_fields["fuel"] = t.field("Est Fuel Usage", "")
		_leg_fields["leg"] = leg
		_fill_leg_fields(waypoints)
	else:
		t.field("Next Way Pt", "None")
	var repeat := CheckBox.new()
	repeat.text = "Repeat Orders"
	repeat.button_pressed = info["repeat"]
	repeat.toggled.connect(
		func(on: bool) -> void:
			_order(
				{"type": "fleet_repeat", "owner": GameSession.PLAYER, "fleet": id, "repeat": on},
				true
			)
	)
	t.body.add_child(repeat)
	if _waypoint < 0:
		return
	var wp_here: Dictionary = waypoints[_waypoint]
	t = _tile("Waypoint Task")
	var task := OptionButton.new()
	for i in TASKS.size():
		task.add_item(TASKS[i][1])
		var needs: String = TASKS[i][2]
		task.set_item_disabled(i, not needs.is_empty() and needs != wp_here["target"])
	task.select(_index_of(TASKS, wp_here["task"]))
	task.item_selected.connect(
		func(i: int) -> void:
			var name: String = TASKS[i][0]
			var data := {}
			if name == "transport":
				data = {"cargo": _empty_cargo()}
			elif name != "none":
				data = {"raw": [0, 0, 0, 0, 0]}
			_change_waypoint(wp_here, wp_here["warp"], name, data)
	)
	t.body.add_child(task)
	match wp_here["task"]:
		"transport":
			_transport_task(t, wp_here)
		"transfer":
			_transfer_choice(t, wp_here)
		"lay_mines", "patrol":
			t.line("Not carried out yet: minefields and battles come later (M7, M9).")


## The leg's travel time (years for that leg) and fuel, the fuel in red when the fleet runs short.
func _fill_leg_fields(waypoints: Array) -> void:
	var leg: int = _leg_fields.get("leg", -1)
	if leg < 1 or leg >= waypoints.size():
		return
	var wp: Dictionary = waypoints[leg]
	var years: int = wp["years"] - (waypoints[leg - 1].get("years", 0) if leg > 1 else 0)
	var time: Label = _leg_fields["time"]
	time.text = "Never" if wp["warp"] == 0 or wp["cannot_move"] else "%d years" % years
	if years == 1 and wp["warp"] > 0 and not wp["cannot_move"]:
		time.text = "1 year"
	var fuel: Label = _leg_fields["fuel"]
	fuel.text = "%dmg" % wp["fuel"]
	var short: bool = wp["short_of_fuel"] or wp["cannot_move"]
	if short:
		fuel.add_theme_color_override("font_color", ClassicTheme.CARGO_COLORS[4])
	else:
		fuel.remove_theme_color_override("font_color")


## While the warp gauge is dragged: the leg's fields from the order preview.
func _refresh_waypoint_rows() -> void:
	var info := GameSession.view.fleet_info(id)
	if info.is_empty() or _leg_fields.is_empty():
		return
	var time: Variant = _leg_fields.get("time")
	if time == null or not is_instance_valid(time):
		return
	_fill_leg_fields(info["waypoints"])


## The transport task, as in the original: a cargo type dropdown (green when that type has an
## action), then that type's action and amount with its unit.
func _transport_task(t: Tile, wp: Dictionary) -> void:
	var cargo: Array = wp["task_data"].get("cargo", _empty_cargo())
	var kind_choice := OptionButton.new()
	for c in CARGO.size():
		kind_choice.add_item(CARGO[c])
	_cargo_shown = clampi(_cargo_shown, 0, CARGO.size() - 1)
	kind_choice.select(_cargo_shown)
	if cargo[_cargo_shown]["action"] != "none":
		kind_choice.add_theme_color_override("font_color", ACTION_SET)
		kind_choice.add_theme_color_override("font_hover_color", ACTION_SET)
	kind_choice.item_selected.connect(
		func(i: int) -> void:
			_cargo_shown = i
			_queue_rebuild()
	)
	t.body.add_child(kind_choice)
	var r := t.row()
	var c := _cargo_shown
	var current: String = cargo[c]["action"]
	var action := OptionButton.new()
	for a: Array in ACTIONS:
		action.add_item(a[1])
	action.select(_index_of(ACTIONS, current))
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(action)
	var amount := LineEdit.new()
	amount.text = str(cargo[c]["amount"])
	amount.custom_minimum_size = Vector2(AMOUNT_WIDTH, 0)
	amount.editable = not NO_AMOUNT.has(current)
	amount.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_child(amount)
	var unit := Label.new()
	unit.text = "%" if PERCENT.has(current) else ("mg" if c == Fleet.CARGO_FUEL else "kT")
	r.add_child(unit)
	action.item_selected.connect(
		func(i: int) -> void: _set_cargo_action(wp, c, ACTIONS[i][0], amount.text.to_int())
	)
	var send_amount := func(_text: String = "") -> void:
		_set_cargo_action(wp, c, ACTIONS[action.selected][0], clampi(amount.text.to_int(), 0, 4095))
	amount.text_submitted.connect(send_amount)
	amount.focus_exited.connect(send_amount)


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
	_change_waypoint_at(_waypoint, wp, warp, task, data)


## Changes waypoint `index` (from its fleet_info row `wp`); repeated edits stay one order.
func _change_waypoint_at(
	index: int, wp: Dictionary, warp: int, task: String, data: Dictionary
) -> void:
	status_text = (
		GameSession
		. amend_order(
			{
				"type": "waypoint_change",
				"owner": GameSession.PLAYER,
				"fleet": id,
				"index": index,
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


## A click in the Fuel & Cargo tile's gauges opens the transfer window: with the planet the fleet
## orbits if it is the player's, else with another of the player's fleets here.
func _on_cargo_gauge_input(event: InputEvent, info: Dictionary) -> void:
	var click: bool = (
		event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	)
	if not click:
		return
	var planet: int = info["planet"]
	if planet >= 0 and GameSession.view.planet_info(planet)["mine"]:
		_cargo.open_with_planet(id, planet)
		return
	for f in GameSession.view.fleets():
		if f.number != id and f.x == info["x"] and f.y == info["y"]:
			_cargo.open_with_fleet(id, f.number)
			return
	status_text = "There is nothing here to transfer cargo with."
	_queue_rebuild()


func _open_merge(info: Dictionary) -> void:
	var numbers: Array[int] = []
	var names := PackedStringArray()
	for f in GameSession.view.fleets():
		if f.number != id and f.x == info["x"] and f.y == info["y"]:
			numbers.append(f.number)
			names.append(GameSession.view.fleet_name(f))
	if numbers.is_empty():
		status_text = "No other fleet of yours is here."
		_queue_rebuild()
		return
	_merge_dialog.open(numbers, names)


func _merge_with(fleets: Array[int]) -> void:
	_order({"type": "fleet_merge", "owner": GameSession.PLAYER, "fleet": id, "fleets": fleets})


func _open_split(info: Dictionary) -> void:
	var total := 0
	for s: Dictionary in info["ships"]:
		total += s["count"]
	if total < 2:
		status_text = "A fleet of one ship can't be split."
		_queue_rebuild()
		return
	_split_dialog.open(info["name"], info["ships"])


## A new fleet (the lowest free number) gets `ships` ([{design, count}]) from this one.
func _split_off(ships: Array) -> void:
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
				"ships": ships,
			}
		)


## Split All: every ship design after the first goes to a fleet of its own.
func _split_all(info: Dictionary) -> void:
	var ships: Array = info["ships"]
	if ships.size() < 2:
		status_text = "This fleet has only one kind of ship."
		_queue_rebuild()
		return
	for i in range(1, ships.size()):
		_split_off([{"design": ships[i]["design"], "count": ships[i]["count"]}])
		if not status_text.is_empty():
			return


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
