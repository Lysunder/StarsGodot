class_name ProductionDialog
extends AcceptDialog
## The production dialog (D15; opened by the Production tile's Change button): the planet's queue
## on the left, what it can build on the right. Edits send one `production_queue` order with the
## whole new queue. Shift adds or removes 10, Ctrl 100.

const STEP_SHIFT := 10
const STEP_CTRL := 100
## A new auto item asks for this many units unless Shift or Ctrl asks for more.
const AUTO_DEFAULT_COUNT := 5

var planet_id: int = -1

var _queue: ItemList
var _inventory: ItemList
var _leftover: CheckBox
var _status: Label


func _ready() -> void:
	ok_button_text = "Done"
	min_size = Vector2i(560, 380)
	var box := VBoxContainer.new()
	add_child(box)
	var lists := HBoxContainer.new()
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(lists)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_child(left)
	left.add_child(_label("Production queue"))
	_queue = ItemList.new()
	_queue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_queue)
	var middle := VBoxContainer.new()
	lists.add_child(middle)
	middle.add_child(_label(""))
	for spec: Array in [
		["<< Add", _on_add],
		["Remove >>", _on_remove],
		["Item up", _on_up],
		["Item down", _on_down],
		["Clear", _on_clear],
	]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		middle.add_child(b)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_child(right)
	right.add_child(_label("Can build"))
	_inventory = ItemList.new()
	_inventory.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inventory.item_activated.connect(func(_i: int) -> void: _on_add())
	right.add_child(_inventory)
	_leftover = CheckBox.new()
	_leftover.text = "Contribute only leftover resources to research"
	_leftover.toggled.connect(_on_leftover)
	box.add_child(_leftover)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("800000"))
	box.add_child(_status)
	GameSession.changed.connect(refresh)


func open(id: int) -> void:
	planet_id = id
	_status.text = ""
	title = "Production: %s" % GameSession.view.planet_info(id)["name"]
	refresh()
	popup_centered()


func refresh() -> void:
	if planet_id < 0 or not visible or not GameSession.has_game():
		return
	var info := GameSession.view.planet_info(planet_id)
	if not info.get("mine", false):
		hide()
		return
	var selected := _queue.get_selected_items()
	_queue.clear()
	for row: Dictionary in info["queue"]:
		var text := "%s × %d" % [row["name"], row["count"]]
		if row["auto"]:
			text = "%s (auto) up to %d" % [row["name"], row["count"]]
		elif row["progress"] > 0:
			text += "  (%d%%)" % row["progress"]
		_queue.add_item(text)
	if not selected.is_empty() and selected[0] < _queue.item_count:
		_queue.select(selected[0])
	_leftover.set_pressed_no_signal(info["leftover_to_research"])
	var picked := _inventory.get_selected_items()
	_inventory.clear()
	for item: Dictionary in GameSession.view.production_inventory(planet_id):
		_inventory.add_item(item["label"])
	if not picked.is_empty() and picked[0] < _inventory.item_count:
		_inventory.select(picked[0])


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


## The current pending queue as order items.
func _current_items() -> Array:
	var items := []
	for q in GameSession.preview.state.planet(planet_id).queue:
		items.append(q.to_dict())
	return items


func _send(items: Array) -> void:
	_status.text = GameSession.set_order(
		{"type": "production_queue", "planet": planet_id, "items": items}
	)


func _step() -> int:
	if Input.is_key_pressed(KEY_CTRL):
		return STEP_CTRL
	if Input.is_key_pressed(KEY_SHIFT):
		return STEP_SHIFT
	return 1


func _on_add() -> void:
	var picked := _inventory.get_selected_items()
	if picked.is_empty():
		return
	var item: Dictionary = GameSession.view.production_inventory(planet_id)[picked[0]]
	var items := _current_items()
	var entry := {
		"item": item["item"],
		"design": item["design"],
		"starbase": item["starbase"],
		"count": _step(),
		"progress": 0,
	}
	var auto: bool = (
		item["item"] != ""
		and bool(GameSession.content.get_def("production_item", item["item"]).get("auto", false))
	)
	if auto:
		entry["count"] = maxi(entry["count"], AUTO_DEFAULT_COUNT)
	var at := _queue.get_selected_items()
	var index: int = at[0] + 1 if not at.is_empty() else items.size()
	if index > 0 and index - 1 < items.size():
		var prev: Dictionary = items[index - 1]
		var same: bool = (
			prev["item"] == entry["item"]
			and prev["design"] == entry["design"]
			and prev["starbase"] == entry["starbase"]
		)
		if same:
			prev["count"] += entry["count"]
			_send(items)
			return
	items.insert(index, entry)
	_send(items)
	_queue.select(mini(index, _queue.item_count - 1))


func _on_remove() -> void:
	var at := _queue.get_selected_items()
	if at.is_empty():
		return
	var items := _current_items()
	var row: Dictionary = items[at[0]]
	row["count"] -= _step()
	if row["count"] <= 0:
		items.remove_at(at[0])
	_send(items)


func _on_up() -> void:
	_move(-1)


func _on_down() -> void:
	_move(1)


func _move(delta: int) -> void:
	var at := _queue.get_selected_items()
	if at.is_empty():
		return
	var items := _current_items()
	var to: int = at[0] + delta
	if to < 0 or to >= items.size():
		return
	var row: Variant = items[at[0]]
	items.remove_at(at[0])
	items.insert(to, row)
	_send(items)
	_queue.select(to)


func _on_clear() -> void:
	_send([])


func _on_leftover(on: bool) -> void:
	var pl := GameSession.preview.state.planet(planet_id)
	_status.text = (
		GameSession
		. set_order(
			{
				"type": "planet_settings",
				"planet": planet_id,
				"leftover_to_research": on,
				"mass_driver_target": pl.mass_driver_target,
				"mass_driver_warp": pl.mass_driver_warp,
				"route": pl.route,
			}
		)
	)
