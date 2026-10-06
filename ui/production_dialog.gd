class_name ProductionDialog
extends AcceptDialog
## The production window (D15, the original's arrangement): the items the planet can build on the
## left with the cost of one under them, the buttons in the middle (Item Up, Add ->, <- Remove,
## Clear, Item Down), the queue on the right (its first row "-- Top of the Queue --" adds at the
## top; rows coloured like the Production tile), and along the bottom "Contribute only leftover
## resources to research", Prev, Next, OK and Cancel. Edits are kept here until OK (or Prev /
## Next, which keep them and move to another planet); then one `production_queue` and, if the
## box changed, one `planet_settings` order are sent. Shift adds or removes 10, Ctrl 100.

const STEP_SHIFT := 10
const STEP_CTRL := 100
## A new auto item asks for this many units unless Shift or Ctrl asks for more.
const AUTO_DEFAULT_COUNT := 5
const LIST_SIZE := Vector2(250, 260)
const TOP_ROW := "-- Top of the Queue --"
const MINERALS := ["Ironium", "Boranium", "Germanium"]

var planet_id: int = -1

## The queue being edited (order item dictionaries) and the leftover box.
var _items: Array = []
var _leftover_on: bool = false
var _inventory_items: Array[Dictionary] = []
var _inventory: RowList
var _queue: RowList
var _cost_title: Label
var _cost: Array[Label] = []
var _leftover: CheckBox
var _status: Label


func _ready() -> void:
	# OK and Cancel sit in the bottom row with Prev and Next, as in the original
	get_ok_button().hide()
	var box := VBoxContainer.new()
	add_child(box)
	var lists := HBoxContainer.new()
	box.add_child(lists)
	var left := VBoxContainer.new()
	lists.add_child(left)
	left.add_child(_label("Available Items", true))
	_inventory = RowList.new(int(LIST_SIZE.y))
	_inventory.custom_minimum_size = LIST_SIZE
	_inventory.row_selected.connect(func(_i: int) -> void: _show_cost())
	_inventory.row_activated.connect(func(_i: int) -> void: _on_add())
	left.add_child(_inventory)
	_cost_title = _label("", true)
	left.add_child(_cost_title)
	var cost_grid := GridContainer.new()
	cost_grid.columns = 2
	left.add_child(cost_grid)
	for i in 4:
		var name := _label(MINERALS[i] if i < 3 else "Resources", true)
		if i < 3:
			name.add_theme_color_override("font_color", ClassicTheme.CARGO_COLORS[i])
		cost_grid.add_child(name)
		var value := _label("", false)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size = Vector2(70, 0)
		cost_grid.add_child(value)
		_cost.append(value)
	var middle := VBoxContainer.new()
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	lists.add_child(middle)
	for spec: Array in [
		["Item Up", _on_up],
		["Add ->", _on_add],
		["<- Remove", _on_remove],
		["Clear", _on_clear],
		["Item Down", _on_down],
	]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(84, 0)
		b.pressed.connect(spec[1])
		middle.add_child(b)
	var right := VBoxContainer.new()
	lists.add_child(right)
	right.add_child(_label("Production Queue", true))
	_queue = RowList.new(int(LIST_SIZE.y))
	_queue.custom_minimum_size = LIST_SIZE
	_queue.row_activated.connect(func(_i: int) -> void: _on_remove())
	right.add_child(_queue)
	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	_leftover = CheckBox.new()
	_leftover.text = "Contribute only leftover resources to research"
	_leftover.toggled.connect(func(on: bool) -> void: _leftover_on = on)
	bottom.add_child(_leftover)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	for spec: Array in [
		["Prev", func() -> void: _switch(-1)],
		["Next", func() -> void: _switch(1)],
		["OK", _on_ok],
		["Cancel", _on_cancel_like],
	]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(64, 0)
		b.pressed.connect(spec[1])
		bottom.add_child(b)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("800000"))
	box.add_child(_status)
	canceled.connect(_on_cancel_like)


## Opens the window on a planet, with its pending queue.
func open(id: int) -> void:
	_load(id)
	popup_centered()


func _load(id: int) -> void:
	planet_id = id
	_status.text = ""
	var info := GameSession.view.planet_info(id)
	title = "%s Production" % info["name"]
	_items.clear()
	for q in GameSession.preview.state.planet(id).queue:
		_items.append(q.to_dict())
	_leftover_on = info["leftover_to_research"]
	_leftover.set_pressed_no_signal(_leftover_on)
	_inventory_items = GameSession.view.production_inventory(id)
	var rows: Array[Dictionary] = []
	for item: Dictionary in _inventory_items:
		rows.append({"left": item["label"], "italic": _is_auto(item)})
	_inventory.set_rows(rows, 0 if not rows.is_empty() else -1)
	_queue.selected = 0
	_show_queue()
	_show_cost()


func _label(text: String, bold: bool) -> Label:
	var l := Label.new()
	l.text = text
	if bold:
		l.theme_type_variation = "BoldLabel"
	return l


func _is_auto(item: Dictionary) -> bool:
	return (
		item["item"] != ""
		and bool(GameSession.content.get_def("production_item", item["item"]).get("auto", false))
	)


## The queue rows: the top-of-queue marker, then the items coloured by ProductionEstimate on a copy
## with the edited queue.
func _show_queue() -> void:
	var copy := GameSession.preview.state.copy() as GameState
	var planet := copy.planet(planet_id)
	planet.queue.clear()
	var errors := PackedStringArray()
	for d: Dictionary in _items:
		var q := ModelObject.object_from(QueueItem, d, "", errors) as QueueItem
		if q != null:
			planet.queue.append(q)
	var when: Array = ProductionEstimate.estimate(copy, GameSession.content, planet_id)["items"]
	var rows: Array[Dictionary] = [{"left": TOP_ROW}]
	var view := GameSession.view
	for i in planet.queue.size():
		var q := planet.queue[i]
		var auto := not q.is_design() and _is_auto({"item": q.item})
		(
			rows
			. append(
				{
					"left": view.queue_item_name(view.player, q),
					"right": ("Up to %d" % q.count) if auto else str(q.count),
					"italic": auto,
					"colour": CommandPane.QUEUE_COLORS[when[i]] if i < when.size() else Color.BLACK,
				}
			)
		)
	_queue.set_rows(rows)


## "Cost of one <item>" for the picked item, per mineral and resources.
func _show_cost() -> void:
	var picked := _inventory.selected
	if picked < 0 or picked >= _inventory_items.size():
		_cost_title.text = ""
		for l in _cost:
			l.text = ""
		return
	var item := _inventory_items[picked]
	_cost_title.text = "Cost of one %s" % item["label"]
	var cost := GameSession.view.unit_cost(planet_id, item)
	for i in 4:
		_cost[i].text = ("%dkT" % cost[i]) if i < 3 else str(cost[i])


func _step() -> int:
	if Input.is_key_pressed(KEY_CTRL):
		return STEP_CTRL
	if Input.is_key_pressed(KEY_SHIFT):
		return STEP_SHIFT
	return 1


## The queue index the selected row stands for (the top row is index -1).
func _queue_index() -> int:
	return _queue.selected - 1


func _on_add() -> void:
	var picked := _inventory.selected
	if picked < 0 or picked >= _inventory_items.size():
		return
	var item := _inventory_items[picked]
	var entry := {
		"item": item["item"],
		"design": item["design"],
		"starbase": item["starbase"],
		"count": _step(),
		"progress": 0,
	}
	if _is_auto(item):
		entry["count"] = maxi(entry["count"], AUTO_DEFAULT_COUNT)
	var at := _queue_index()
	if at >= 0 and at < _items.size():
		var row: Dictionary = _items[at]
		var same: bool = (
			row["item"] == entry["item"]
			and row["design"] == entry["design"]
			and row["starbase"] == entry["starbase"]
		)
		if same:
			row["count"] += entry["count"]
			_show_queue()
			return
	_items.insert(at + 1, entry)
	_queue.selected = at + 2
	_show_queue()


func _on_remove() -> void:
	var at := _queue_index()
	if at < 0 or at >= _items.size():
		return
	var row: Dictionary = _items[at]
	row["count"] -= _step()
	if row["count"] <= 0:
		_items.remove_at(at)
		_queue.selected = at
	_show_queue()


func _on_up() -> void:
	_move(-1)


func _on_down() -> void:
	_move(1)


func _move(delta: int) -> void:
	var at := _queue_index()
	var to := at + delta
	if at < 0 or to < 0 or to >= _items.size():
		return
	var row: Variant = _items[at]
	_items.remove_at(at)
	_items.insert(to, row)
	_queue.selected = to + 1
	_show_queue()


func _on_clear() -> void:
	_items.clear()
	_queue.selected = 0
	_show_queue()


func _on_ok() -> void:
	if _commit():
		hide()


## Cancel: the edits are dropped (nothing was sent).
func _on_cancel_like() -> void:
	_items.clear()
	hide()


## Sends the edits; returns false (and shows why) when an order is rejected.
func _commit() -> bool:
	var reason := GameSession.set_order(
		{"type": "production_queue", "planet": planet_id, "items": _items.duplicate(true)}
	)
	var info := GameSession.view.planet_info(planet_id)
	if reason.is_empty() and _leftover_on != info["leftover_to_research"]:
		var pl := GameSession.preview.state.planet(planet_id)
		reason = (
			GameSession
			. set_order(
				{
					"type": "planet_settings",
					"planet": planet_id,
					"leftover_to_research": _leftover_on,
					"mass_driver_target": pl.mass_driver_target,
					"mass_driver_warp": pl.mass_driver_warp,
					"route": pl.route,
				}
			)
		)
	if not reason.is_empty():
		_status.text = reason
		return false
	return true


## Prev / Next: keep the edits, then show the player's previous or next planet (in the Planet
## report's order).
func _switch(step: int) -> void:
	if not _commit():
		return
	var ids := ReportSettings.planet_order()
	if ids.is_empty():
		return
	var at := maxi(ids.find(planet_id), 0)
	_load(ids[posmod(at + step, ids.size())])
