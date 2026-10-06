class_name CargoDialog
extends AcceptDialog
## Cargo transfer by hand (D15; the original's `TRANSFERDLG@1048:3580`): the fleet on the left, the
## planet or other fleet on the right, each under its name, one row per cargo type (fuel, ironium,
## boranium, germanium, colonists). Between the two sides each row has arrow buttons that move
## cargo left or right: 1 per click, 10 with Shift, 100 with Ctrl, 1000 with both, repeating while
## held. Dragging in a fleet's gauge sets how much of that cargo it carries. Moves are limited by
## what the giver has and the receiver's room (a planet takes any minerals and colonists but no
## fuel). OK sends one `cargo_transfer` order with the net amounts (S11); Cancel drops them.

signal transferred(reason: String)

## Rows top to bottom, as cargo indices (Fleet.CARGO_*).
const ROWS := [4, 0, 1, 2, 3]
const NAMES := ["Ironium", "Boranium", "Germanium", "Colonists", "Fuel"]
const STEP_SHIFT := 10
const STEP_CTRL := 100
const STEP_BOTH := 1000
const REPEAT_DELAY := 0.35
const REPEAT_EVERY := 0.06
const SIDE_WIDTH := 240

var fleet_number: int = -1
## {"planet": id} or {"fleet": number, "owner": owner}.
var other: Dictionary = {}

## Amounts per cargo type: the fleet's and the other side's as edited, and the fleet's at the
## start.
var _fleet: Array[int] = [0, 0, 0, 0, 0]
var _other: Array[int] = [0, 0, 0, 0, 0]
var _start: Array[int] = [0, 0, 0, 0, 0]
## Capacities: [cargo, fuel] for each side; -1 for "no limit" (a planet's cargo); 0 fuel at a
## planet (no fuel moves there).
var _fleet_room: Array[int] = [0, 0]
var _other_room: Array[int] = [0, 0]
var _other_is_fleet := false

var _left_title: Label
var _right_title: Label
var _left: Array[Control] = []
var _right: Array[Control] = []
var _arrows: Array[Button] = []
var _status: Label
var _repeat: Timer
var _held: Callable = Callable()


func _ready() -> void:
	title = "Transfer Cargo"
	get_ok_button().hide()
	var box := VBoxContainer.new()
	add_child(box)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	box.add_child(grid)
	_left_title = _header(grid)
	grid.add_child(Control.new())
	grid.add_child(Control.new())
	grid.add_child(Control.new())
	_right_title = _header(grid)
	for c: int in ROWS:
		var left := Gauge.new()
		left.custom_minimum_size = Vector2(SIDE_WIDTH, Gauge.HEIGHT)
		left.mouse_filter = Control.MOUSE_FILTER_STOP
		left.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		left.gui_input.connect(_on_gauge_input.bind(left, c, true))
		grid.add_child(left)
		_left.append(left)
		for spec: Array in [["<", 1], [">", -1]]:
			var b := Button.new()
			b.text = spec[0]
			b.custom_minimum_size = Vector2(26, 0)
			var direction: int = spec[1]
			b.button_down.connect(_press.bind(c, direction))
			b.button_up.connect(_release)
			grid.add_child(b)
			_arrows.append(b)
		var name := Label.new()
		name.text = NAMES[c]
		name.theme_type_variation = "BoldLabel"
		name.add_theme_color_override("font_color", ClassicTheme.CARGO_COLORS[c])
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.custom_minimum_size = Vector2(90, 0)
		grid.add_child(name)
		var right_slot := VBoxContainer.new()
		grid.add_child(right_slot)
		_right.append(right_slot)
	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_color_override("font_color", Color("800000"))
	bottom.add_child(_status)
	for spec: Array in [["OK", _on_ok], ["Cancel", hide]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(70, 0)
		b.pressed.connect(spec[1])
		bottom.add_child(b)
	_repeat = Timer.new()
	_repeat.timeout.connect(_on_repeat)
	add_child(_repeat)


func _header(parent: Control) -> Label:
	var frame := PanelContainer.new()
	frame.theme_type_variation = "TileBar"
	parent.add_child(frame)
	var l := Label.new()
	l.theme_type_variation = "BoldLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	frame.add_child(l)
	return l


## Opens the window between a fleet and the planet it orbits.
func open_with_planet(p_fleet: int, planet_id: int) -> void:
	_open(p_fleet, {"planet": planet_id})


## Opens the window between two of the player's fleets at the same place.
func open_with_fleet(p_fleet: int, other_fleet: int) -> void:
	_open(p_fleet, {"fleet": other_fleet, "owner": GameSession.PLAYER})


func _open(p_fleet: int, p_other: Dictionary) -> void:
	fleet_number = p_fleet
	other = p_other
	_status.text = ""
	var view := GameSession.view
	var info := view.fleet_info(fleet_number)
	_fleet = (info["cargo"] as Array).duplicate()
	_start = _fleet.duplicate()
	_fleet_room = [info["cargo_capacity"], info["fuel_capacity"]]
	_left_title.text = info["name"]
	_other_is_fleet = other.has("fleet")
	if _other_is_fleet:
		var o := view.fleet_info(other["fleet"])
		_other = (o["cargo"] as Array).duplicate()
		_other_room = [o["cargo_capacity"], o["fuel_capacity"]]
		_right_title.text = o["name"]
	else:
		var p := view.planet_info(other["planet"])
		var surface: Array = p["surface"]
		_other = [surface[0], surface[1], surface[2], p["population"], 0]
		_other_room = [-1, 0]
		_right_title.text = p["name"]
	for i in ROWS.size():
		var slot := _right[i] as VBoxContainer
		for child in slot.get_children():
			child.queue_free()
		var c: int = ROWS[i]
		if _other_is_fleet:
			var g := Gauge.new()
			g.custom_minimum_size = Vector2(SIDE_WIDTH, Gauge.HEIGHT)
			g.mouse_filter = Control.MOUSE_FILTER_STOP
			g.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			g.gui_input.connect(_on_gauge_input.bind(g, c, false))
			slot.add_child(g)
		else:
			var l := Label.new()
			l.custom_minimum_size = Vector2(SIDE_WIDTH, Gauge.HEIGHT)
			slot.add_child(l)
		var no_fuel := c == Fleet.CARGO_FUEL and not _other_is_fleet
		_arrows[i * 2].disabled = no_fuel
		_arrows[i * 2 + 1].disabled = no_fuel
	_show()
	popup_centered()
	reset_size()


## Free room for cargo type c: on the fleet side or the other.
func _room(c: int, fleet_side: bool) -> int:
	var amounts := _fleet if fleet_side else _other
	var rooms := _fleet_room if fleet_side else _other_room
	if c == Fleet.CARGO_FUEL:
		return rooms[1] - amounts[4]
	if rooms[0] < 0:
		return 1 << 30
	return rooms[0] - (amounts[0] + amounts[1] + amounts[2] + amounts[3])


## Moves up to `amount` of cargo type c: positive into the fleet, negative out of it.
func move(c: int, amount: int) -> void:
	if c == Fleet.CARGO_FUEL and not _other_is_fleet:
		return
	if amount > 0:
		amount = mini(amount, mini(_other[c], _room(c, true)))
	else:
		amount = -mini(-amount, mini(_fleet[c], _room(c, false)))
	if amount == 0:
		return
	_fleet[c] += amount
	_other[c] -= amount
	_show()


func _step() -> int:
	var shift := Input.is_key_pressed(KEY_SHIFT)
	var ctrl := Input.is_key_pressed(KEY_CTRL)
	if shift and ctrl:
		return STEP_BOTH
	if ctrl:
		return STEP_CTRL
	if shift:
		return STEP_SHIFT
	return 1


func _press(c: int, direction: int) -> void:
	_held = func() -> void: move(c, direction * _step())
	_held.call()
	_repeat.start(REPEAT_DELAY)


func _release() -> void:
	_repeat.stop()
	_held = Callable()


func _on_repeat() -> void:
	if _held.is_valid():
		_held.call()
		_repeat.start(REPEAT_EVERY)


## Dragging in a fleet's gauge sets that cargo's amount on that side.
func _on_gauge_input(event: InputEvent, gauge: Gauge, c: int, fleet_side: bool) -> void:
	var dragging: bool = (
		event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)
	)
	var pressed: bool = (
		event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	)
	if not (dragging or pressed):
		return
	var rooms := _fleet_room if fleet_side else _other_room
	var capacity: int = rooms[1] if c == Fleet.CARGO_FUEL else rooms[0]
	var share := clampf((event.position.x - 1.0) / maxf(gauge.size.x - 2.0, 1.0), 0.0, 1.0)
	var target := roundi(share * capacity)
	var have: int = _fleet[c] if fleet_side else _other[c]
	move(c, (target - have) * (1 if fleet_side else -1))


func _show() -> void:
	for i in ROWS.size():
		var c: int = ROWS[i]
		_show_side(_left[i], c, _fleet, _fleet_room)
		var slot := _right[i] as VBoxContainer
		if slot.get_child_count() == 0:
			continue
		var widget := slot.get_child(slot.get_child_count() - 1)
		if widget is Gauge:
			_show_side(widget, c, _other, _other_room)
		elif widget is Label:
			var unit := "mg" if c == Fleet.CARGO_FUEL else "kT"
			(widget as Label).text = (
				"-" if c == Fleet.CARGO_FUEL else "%s%s" % [CommandPane.thousands(_other[c]), unit]
			)


func _show_side(widget: Control, c: int, amounts: Array[int], rooms: Array[int]) -> void:
	var gauge := widget as Gauge
	gauge.empty_colour = Gauge.COLONISTS_EMPTY if c == Fleet.CARGO_COLONISTS else Gauge.EMPTY
	if c == Fleet.CARGO_FUEL:
		gauge.show_values(
			[[amounts[4], ClassicTheme.CARGO_COLORS[4]]],
			rooms[1],
			"%d of %dmg" % [amounts[4], rooms[1]]
		)
		return
	gauge.show_values([[amounts[c], ClassicTheme.CARGO_COLORS[c]]], rooms[0], "%dkT" % amounts[c])


func _on_ok() -> void:
	var amounts: Array[int] = []
	var any := false
	for c in 5:
		amounts.append(_fleet[c] - _start[c])
		any = any or amounts[c] != 0
	if not any:
		hide()
		return
	var reason := (
		GameSession
		. add_order(
			{
				"type": "cargo_transfer",
				"owner": GameSession.PLAYER,
				"fleet": fleet_number,
				"other": other,
				"amounts": amounts,
			}
		)
	)
	if not reason.is_empty():
		_status.text = reason
		return
	hide()
	transferred.emit(reason)
