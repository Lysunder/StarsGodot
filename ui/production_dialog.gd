class_name ProductionDialog
extends AcceptDialog
## The production window (D15, the original's arrangement): the items the planet can build on the
## left with the cost of one under them, the buttons in the middle (Item Up, Add ->, <- Remove,
## Clear, Item Down), the queue on the right (its first row "-- Top of the Queue --" adds at the
## top; rows coloured like the Production tile) with the cost of the picked queue item under it
## (all its units), how far its first unit is and when it will be done, and along the bottom
## "Contribute only leftover resources to research", Prev, Next, OK and Cancel. Edits are kept
## here until OK (or Prev / Next, which keep them and move to another planet); then one
## `production_queue` and, if the box changed, one `planet_settings` order are sent.
## Shift adds or removes 10, Ctrl 100.
## The diamond under the buttons lists the production templates: picking one replaces the queue's
## auto-build items with the template's (after the other items) and sets the box from it;
## "Customize..." opens the templates window (S09 "Production templates").

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
var _queue_title: Label
var _queue_cost: Array[Label] = []
var _completion: Label
## ProductionEstimate of the edited queue.
var _estimate: Dictionary = {}
var _leftover: CheckBox
var _status: Label
var _templates_menu: PopupMenu
var _templates: ProductionTemplatesDialog
## What each template menu item applies (index in the menu -> template), "Customize..." last.
var _menu_templates: Array[Dictionary] = []


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
	left.add_child(_cost_grid(_cost))
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
	var diamond := Button.new()
	diamond.text = "◆"
	diamond.tooltip_text = "Production templates"
	diamond.add_theme_color_override("font_color", Color("0000c0"))
	diamond.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
	diamond.pressed.connect(func() -> void: _show_templates(diamond))
	middle.add_child(diamond)
	var right := VBoxContainer.new()
	lists.add_child(right)
	right.add_child(_label("Production Queue", true))
	_queue = RowList.new(int(LIST_SIZE.y))
	_queue.custom_minimum_size = LIST_SIZE
	_queue.row_activated.connect(func(_i: int) -> void: _on_remove())
	_queue.row_selected.connect(func(_i: int) -> void: _show_queue_cost())
	right.add_child(_queue)
	_queue_title = _label("", true)
	right.add_child(_queue_title)
	right.add_child(_cost_grid(_queue_cost))
	_completion = _label("", false)
	right.add_child(_completion)
	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	_leftover = CheckBox.new()
	_leftover.text = "Contribute only leftover resources to research"
	_leftover.toggled.connect(
		func(on: bool) -> void:
			_leftover_on = on
			_show_queue()
	)
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
	_templates_menu = PopupMenu.new()
	_templates_menu.id_pressed.connect(_on_template)
	add_child(_templates_menu)
	_templates = ProductionTemplatesDialog.new()
	add_child(_templates)
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
	title = tr("%s Production") % info["name"]
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


## A cost box: each mineral and resources with its value label (appended to `values`).
func _cost_grid(values: Array[Label]) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	for i in 4:
		var label_text := _label(MINERALS[i] if i < 3 else "Resources", true)
		if i < 3:
			label_text.add_theme_color_override("font_color", Palette.cargo(i))
		grid.add_child(label_text)
		var value := _label("", false)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size = Vector2(70, 0)
		grid.add_child(value)
		values.append(value)
	return grid


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
## with the edited queue and leftover box.
func _show_queue() -> void:
	var copy := GameSession.preview.state.copy() as GameState
	var planet := copy.planet(planet_id)
	# the box changes what the planet spends, so the completion years follow it (issue #12)
	planet.leftover_to_research = _leftover_on
	planet.queue.clear()
	var errors := PackedStringArray()
	for d: Dictionary in _items:
		var q := ModelObject.object_from(QueueItem, d, "", errors) as QueueItem
		if q != null:
			planet.queue.append(q)
	_estimate = ProductionEstimate.estimate(copy, GameSession.content, planet_id)
	var when: Array = _estimate["items"]
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
					"right": (tr("Up to %d") % q.count) if auto else str(q.count),
					"italic": auto,
					"colour": CommandPane.queue_color(when[i]) if i < when.size() else Color.BLACK,
				}
			)
		)
	_queue.set_rows(rows)
	_show_queue_cost()


## "Cost of one <item>" for the picked item, per mineral and resources.
func _show_cost() -> void:
	var picked := _inventory.selected
	if picked < 0 or picked >= _inventory_items.size():
		_cost_title.text = ""
		for l in _cost:
			l.text = ""
		return
	var item := _inventory_items[picked]
	_cost_title.text = tr("Cost of one %s") % item["label"]
	var cost := GameSession.view.unit_cost(planet_id, item)
	for i in 4:
		_cost[i].text = ("%dkT" % cost[i]) if i < 3 else str(cost[i])


## The picked queue item: the cost of all its units, then "N% done" (its first unit) and when it
## will be done.
func _show_queue_cost() -> void:
	var i := _queue_index()
	if i < 0 or i >= _items.size():
		_queue_title.text = ""
		_completion.text = ""
		for l in _queue_cost:
			l.text = ""
		return
	var item: Dictionary = _items[i]
	var count := int(item["count"])
	var view := GameSession.view
	var q := ModelObject.object_from(QueueItem, item, "", PackedStringArray()) as QueueItem
	var label_text := view.queue_item_name(view.player, q)
	_queue_title.text = tr("Cost of %d × %s") % [count, label_text]
	var cost := view.unit_cost(planet_id, item)
	for m in 4:
		var total := cost[m] * count
		_queue_cost[m].text = ("%dkT" % total) if m < 3 else str(total)
	var done := tr("%d%% done, completion: ") % int(item["progress"])
	_completion.text = done + completion_text(_estimate, i, _is_auto(item))


## When queue item `i` will be done, from a ProductionEstimate: "3 years", "2 - 5 years" (first
## unit to last), "4 - ? years" (not all within the estimate), "Never", or for an auto item
## "As needed" ("Skipped" when it builds nothing this year).
static func completion_text(estimate: Dictionary, i: int, auto: bool) -> String:
	var when: Array = estimate.get("items", [])
	if i >= when.size():
		return ""
	if auto:
		return "Skipped" if when[i] == ProductionEstimate.When.SKIPPED else "As needed"
	var first: int = estimate["first"][i]
	var last: int = estimate["last"][i]
	if first == 0:
		return "Never"
	if last == 0:
		return TranslationServer.translate("%d - ? years") % first
	if first != last:
		return TranslationServer.translate("%d - %d years") % [first, last]
	return "1 year" if first == 1 else TranslationServer.translate("%d years") % first


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
	# no more factories, mines or defenses than the planet can use (issue #16)
	var room := _room(item)
	if room == 0:
		_status.text = tr("The planet has no room for more of these: %s.") % item["label"]
		return
	if room > 0:
		entry["count"] = mini(entry["count"], room)
	_status.text = ""
	var at := _queue_index()
	if at >= 0 and at < _items.size():
		var row: Dictionary = _items[at]
		var same: bool = (
			row["item"] == entry["item"]
			and row["design"] == entry["design"]
			and row["starbase"] == entry["starbase"]
		)
		if same:
			# one queue item holds at most the queue limit of units (the order refuses more)
			var most := _queue_limit()
			if row["count"] >= most:
				_status.text = tr("A queue item holds at most %d.") % most
				return
			row["count"] = mini(row["count"] + entry["count"], most)
			_show_queue()
			return
	entry["count"] = mini(entry["count"], _queue_limit())
	_items.insert(at + 1, entry)
	_queue.selected = at + 2
	_show_queue()


func _queue_limit() -> int:
	return int(GameSession.content.constant("constant.limits.queue_count"))


## How many more of inventory item `item` the planet can use after those in the edited queue
## (-1: no limit).
func _room(item: Dictionary) -> int:
	if item["item"] == "":
		return -1
	var queued := 0
	for d: Dictionary in _items:
		if d["item"] == item["item"]:
			queued += int(d["count"])
	var pl := GameSession.preview.state.planet(planet_id)
	return ProductionList.room(pl, GameSession.view.me(), GameSession.content, item["item"], queued)


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


## The template menu under the diamond: each template in use, then "Customize...".
func _show_templates(at: Control) -> void:
	_templates_menu.clear()
	_menu_templates = ProductionTemplatesDialog.in_use()
	for i in _menu_templates.size():
		_templates_menu.add_item(_menu_templates[i]["name"], i)
	_templates_menu.add_separator()
	_templates_menu.add_item("Customize...", _menu_templates.size())
	_templates_menu.position = Vector2i(at.get_screen_position() + Vector2(0, at.size.y))
	_templates_menu.reset_size()
	_templates_menu.popup()


func _on_template(id: int) -> void:
	if id >= _menu_templates.size():
		_templates.open(_items.duplicate(true), _leftover_on)
		return
	var t := _menu_templates[id]
	var race := GameSession.view.me().race
	_items = ProductionTemplates.apply(_items, t["queue"], race, GameSession.content)
	_leftover_on = t["leftover_to_research"]
	_leftover.set_pressed_no_signal(_leftover_on)
	_queue.selected = 0
	_show_queue()


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
