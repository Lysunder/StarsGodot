class_name ShipDesigner
extends AcceptDialog
## The ship and starbase designer (M11 step 5). On the left, the player's designs; picking one
## shows it. New, Copy and Edit open it for editing: a name, a hull, a picture, the hull's slots
## and the parts the selected slot takes, with the design's totals updating as parts go in. Save
## sends a `design_change` order, Delete a `design_delete` order (S11); the order preview shows the
## result at once, so a saved design is in the production lists straight away.

const CATEGORY_NAMES := {
	"engine": "Engine",
	"scanner": "Scanner",
	"shield": "Shield",
	"armor": "Armor",
	"beam": "Beam weapon",
	"torpedo": "Torpedo",
	"bomb": "Bomb",
	"mine_layer": "Mine layer",
	"mining_robot": "Mining robot",
	"electrical": "Electrical",
	"mechanical": "Mechanical",
	"orbital": "Orbital",
}
const MINERALS := ["Ironium", "Boranium", "Germanium"]
const LIST_WIDTH := 200
const SLOTS_WIDTH := 300

var starbase: bool = false
## The design shown: a copy of a saved one, or the one being edited.
var design: Design = null
## While editing: the design slot it saves to (a new design takes the first free slot).
var editing: bool = false
var _edit_slot: int = -1

var _kind: OptionButton
var _list: ItemList
var _new: Button
var _copy: Button
var _edit: Button
var _delete: Button
var _name: LineEdit
var _hull: OptionButton
var _hull_ids: Array[String] = []
var _picture: Label
var _slots: ItemList
var _parts: ItemList
var _part_ids: Array[String] = []
var _part_info: Label
var _stats: Label
var _status: Label
var _save: Button
var _cancel: Button
var _confirm_delete: ConfirmationDialog


func _ready() -> void:
	title = "Ship Design"
	ok_button_text = "Close"
	min_size = Vector2i(980, 540)
	var box := VBoxContainer.new()
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	_kind = OptionButton.new()
	_kind.add_item("Ship designs")
	_kind.add_item("Starbase designs")
	_kind.item_selected.connect(_on_kind)
	top.add_child(_kind)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(columns)
	columns.add_child(_designs_column())
	columns.add_child(_slots_column())
	columns.add_child(_parts_column())
	_stats = Label.new()
	box.add_child(_stats)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("800000"))
	box.add_child(_status)
	_confirm_delete = ConfirmationDialog.new()
	_confirm_delete.confirmed.connect(_on_delete_confirmed)
	add_child(_confirm_delete)
	GameSession.changed.connect(refresh)


func _designs_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_design_picked)
	col.add_child(_list)
	var buttons := GridContainer.new()
	buttons.columns = 2
	col.add_child(buttons)
	_new = _button(buttons, "New", _on_new)
	_copy = _button(buttons, "Copy", _on_copy)
	_edit = _button(buttons, "Edit", _on_edit)
	_delete = _button(buttons, "Delete", _on_delete)
	return col


func _slots_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(SLOTS_WIDTH, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 2
	col.add_child(grid)
	grid.add_child(_label("Name"))
	_name = LineEdit.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_changed.connect(_on_name)
	grid.add_child(_name)
	grid.add_child(_label("Hull"))
	_hull = OptionButton.new()
	_hull.item_selected.connect(_on_hull)
	grid.add_child(_hull)
	grid.add_child(_label("Picture"))
	var pictures := HBoxContainer.new()
	grid.add_child(pictures)
	_button(pictures, "<", _on_picture.bind(-1))
	_picture = Label.new()
	pictures.add_child(_picture)
	_button(pictures, ">", _on_picture.bind(1))
	col.add_child(_label("Slots"))
	_slots = ItemList.new()
	_slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slots.item_selected.connect(func(_i: int) -> void: _show_parts())
	col.add_child(_slots)
	var row := HBoxContainer.new()
	col.add_child(row)
	_button(row, "Remove one", _on_remove)
	_button(row, "Empty slot", _on_empty)
	var actions := HBoxContainer.new()
	col.add_child(actions)
	_save = _button(actions, "Save design", _on_save)
	_cancel = _button(actions, "Cancel", _on_cancel)
	return col


func _parts_column() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_label("Parts for the selected slot"))
	_parts = ItemList.new()
	_parts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_parts.item_selected.connect(_on_part_picked)
	_parts.item_activated.connect(func(_i: int) -> void: _on_add())
	col.add_child(_parts)
	_button(col, "<< Add to slot", _on_add)
	_part_info = Label.new()
	_part_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_part_info.custom_minimum_size = Vector2(0, 90)
	col.add_child(_part_info)
	return col


func _button(parent: Control, text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func open() -> void:
	editing = false
	_status.text = ""
	popup_centered()
	refresh()


## Rebuilds the designs list and the shown design.
func refresh() -> void:
	if not visible or not GameSession.has_game():
		return
	var view := GameSession.view
	var designs := view.designer.designs(starbase)
	var picked := _picked_slot()
	_list.clear()
	for d in designs:
		var text := d.name
		if d.remaining > 0:
			text += " (%d)" % d.remaining
		_list.add_item(text)
		_list.set_item_metadata(_list.item_count - 1, d.slot)
	if not editing:
		var show := -1
		for i in _list.item_count:
			if _list.get_item_metadata(i) == picked:
				show = i
		if show < 0 and _list.item_count > 0:
			show = 0
		if show >= 0:
			_list.select(show)
			design = _saved(int(_list.get_item_metadata(show)))
		else:
			design = null
	_show_design()


func _picked_slot() -> int:
	var at := _list.get_selected_items()
	if at.is_empty():
		return -1
	return int(_list.get_item_metadata(at[0]))


## A copy of a saved design, or null.
func _saved(slot: int) -> Design:
	var me := GameSession.view.me()
	var d := me.starbase_design(slot) if starbase else me.ship_design(slot)
	return d.copy() as Design if d != null else null


## Shows `design`, editable or not.
func _show_design() -> void:
	var has := design != null
	var saved := _saved(_picked_slot()) if has and not editing else null
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if editing else Control.MOUSE_FILTER_STOP
	_kind.disabled = editing
	_new.disabled = editing or GameSession.view.designer.free_design_slot(starbase) < 0
	_copy.disabled = editing or not has or GameSession.view.designer.free_design_slot(starbase) < 0
	_edit.disabled = editing or saved == null or saved.remaining > 0
	_edit.tooltip_text = (
		"A design with ships can't change; copy it instead." if _edit.disabled else ""
	)
	_delete.disabled = editing or saved == null
	_name.editable = editing
	_hull.disabled = not editing
	_save.disabled = not editing
	_cancel.disabled = not editing
	_name.text = design.name if has else ""
	_hull.clear()
	_hull_ids.clear()
	if has:
		var hulls: Array[String] = [design.hull]
		if editing:
			hulls = GameSession.view.designer.available_hulls(starbase)
		if not hulls.has(design.hull):
			hulls.append(design.hull)
		for id: String in hulls:
			_hull_ids.append(id)
			_hull.add_item(GameSession.content.display_name(id))
		_hull.select(_hull_ids.find(design.hull))
	_show_slots()
	_show_stats()


func _show_slots() -> void:
	var picked := _slots.get_selected_items()
	_slots.clear()
	if design == null:
		_picture.text = ""
		_show_parts()
		return
	var hull := GameSession.content.hull(design.hull)
	var first: int = hull.get("pictures", 0)
	_picture.text = " %d of %d " % [design.picture - first + 1, PartRules.PICTURES_PER_HULL]
	var slots: Array = hull["slots"]
	for i in slots.size():
		var accepts := PackedStringArray()
		for c: String in slots[i]["accepts"]:
			accepts.append(CATEGORY_NAMES.get(c, c))
		var entry := design.parts[i] if i < design.parts.size() else DesignSlot.new()
		var held := "empty"
		if not entry.part.is_empty():
			held = "%s × %d" % [GameSession.content.display_name(entry.part), entry.count]
		_slots.add_item("%d. %s (up to %d): %s" % [i + 1, "/".join(accepts), slots[i]["max"], held])
	if not picked.is_empty() and picked[0] < _slots.item_count:
		_slots.select(picked[0])
	elif _slots.item_count > 0:
		_slots.select(0)
	_show_parts()


## The parts the selected slot takes (only while editing).
func _show_parts() -> void:
	_parts.clear()
	_part_ids.clear()
	_part_info.text = ""
	var at := _slots.get_selected_items()
	if not editing or design == null or at.is_empty():
		return
	var slot: Dictionary = GameSession.content.hull(design.hull)["slots"][at[0]]
	for id in GameSession.view.designer.available_parts(slot["accepts"]):
		_part_ids.append(id)
		_parts.add_item(GameSession.content.display_name(id))


func _on_part_picked(index: int) -> void:
	var id := _part_ids[index]
	var part := GameSession.content.part(id)
	var cost := ProductionCosts.part_cost(part, GameSession.view.me(), GameSession.content)
	var lines := PackedStringArray([GameSession.content.display_name(id)])
	lines.append("Mass %d kT; cost %s" % [part.get("mass", 0), _cost_text(cost)])
	var stats := PackedStringArray()
	var values: Dictionary = part.get("stats", {})
	for key: String in values:
		stats.append("%s %s" % [key.replace("_", " ").capitalize(), str(values[key])])
	if not stats.is_empty():
		lines.append(", ".join(stats))
	_part_info.text = "\n".join(lines)


func _show_stats() -> void:
	if design == null:
		_stats.text = "No designs yet."
		return
	var s := GameSession.view.designer.design_stats(design, starbase)
	var lines := PackedStringArray()
	lines.append(
		(
			"Cost %s   Mass %d kT   Armor %d   Shields %d"
			% [_cost_text(s["cost"]), s["mass"], s["armor"], s["shields"]]
		)
	)
	if not starbase:
		var ranges := PackedStringArray()
		for w in (s["ranges"] as Array).size():
			var ly: int = s["ranges"][w]
			var text := "-" if ly <= 0 else ("∞" if ly >= Movement.CANNOT_MOVE else str(ly))
			ranges.append("%d:%s" % [w + 1, text])
		lines.append(
			(
				"Fuel %d mg   Cargo %d kT   Range (ly) at warp %s"
				% [s["fuel"], s["cargo"], " ".join(ranges)]
			)
		)
	_stats.text = "\n".join(lines)
	if editing:
		_status.text = s["problem"]


func _cost_text(cost: Array) -> String:
	var parts := PackedStringArray()
	for i in 3:
		parts.append("%s %d" % [MINERALS[i].left(1), cost[i]])
	parts.append("R %d" % cost[ProductionCosts.RESOURCES])
	return " ".join(parts)


func _on_kind(index: int) -> void:
	starbase = index == 1
	_list.deselect_all()
	_status.text = ""
	refresh()


func _on_design_picked(index: int) -> void:
	if editing:
		return
	design = _saved(int(_list.get_item_metadata(index)))
	_status.text = ""
	_show_design()


func _on_new() -> void:
	var hulls := GameSession.view.designer.available_hulls(starbase)
	if hulls.is_empty():
		_status.text = "No hull available."
		return
	_begin_edit(
		GameSession.view.designer.blank_design(hulls[0]),
		GameSession.view.designer.free_design_slot(starbase)
	)


func _on_copy() -> void:
	if design == null:
		return
	var d := design.copy() as Design
	d.name = design.name + " copy"
	_begin_edit(d, GameSession.view.designer.free_design_slot(starbase))


func _on_edit() -> void:
	if design != null:
		_begin_edit(design.copy() as Design, _picked_slot())


func _begin_edit(d: Design, slot: int) -> void:
	design = d
	_edit_slot = slot
	editing = true
	_status.text = ""
	_show_design()
	_name.grab_focus()


func _on_name(text: String) -> void:
	if editing:
		design.name = text
		_show_stats()


func _on_hull(index: int) -> void:
	if not editing or _hull_ids[index] == design.hull:
		return
	var fresh := GameSession.view.designer.blank_design(_hull_ids[index])
	fresh.name = design.name
	design = fresh
	_show_slots()
	_show_stats()


func _on_picture(delta: int) -> void:
	if not editing:
		return
	var first: int = GameSession.content.hull(design.hull).get("pictures", 0)
	var n := PartRules.PICTURES_PER_HULL
	design.picture = first + posmod(design.picture - first + delta, n)
	_show_slots()


## Adds the picked part to the selected slot: one more of the same part, or a fresh slot of a
## different part. Shift fills the slot.
func _on_add() -> void:
	var at := _slots.get_selected_items()
	var picked := _parts.get_selected_items()
	if not editing or at.is_empty() or picked.is_empty():
		return
	var i: int = at[0]
	var most: int = GameSession.content.hull(design.hull)["slots"][i]["max"]
	var entry := design.parts[i]
	var id := _part_ids[picked[0]]
	if entry.part != id:
		entry.part = id
		entry.count = 0
	var step := most if Input.is_key_pressed(KEY_SHIFT) else 1
	entry.count = mini(entry.count + step, most)
	_show_slots()
	_show_stats()


func _on_remove() -> void:
	var at := _slots.get_selected_items()
	if not editing or at.is_empty():
		return
	var entry := design.parts[at[0]]
	entry.count = maxi(entry.count - 1, 0)
	if entry.count == 0:
		entry.part = ""
	_show_slots()
	_show_stats()


func _on_empty() -> void:
	var at := _slots.get_selected_items()
	if not editing or at.is_empty():
		return
	design.parts[at[0]] = DesignSlot.new()
	_show_slots()
	_show_stats()


func _on_save() -> void:
	var problem: String = GameSession.view.designer.design_stats(design, starbase)["problem"]
	if not problem.is_empty():
		_status.text = problem
		return
	if _edit_slot < 0:
		_status.text = "Every design slot is taken."
		return
	var slot := _edit_slot
	var reason := (
		GameSession
		. add_order(
			{
				"type": "design_change",
				"starbase": starbase,
				"slot": slot,
				"design": design.to_dict(),
			}
		)
	)
	if not reason.is_empty():
		_status.text = reason
		return
	editing = false
	_status.text = ""
	_select_slot(slot)


func _on_cancel() -> void:
	editing = false
	_status.text = ""
	refresh()


func _on_delete() -> void:
	var saved := _saved(_picked_slot())
	if saved == null:
		return
	var text := "Delete the design %s?" % saved.name
	if saved.remaining > 0:
		text += "\nIts %d ships are scrapped with it." % saved.remaining
	_confirm_delete.dialog_text = text
	_confirm_delete.popup_centered()


func _on_delete_confirmed() -> void:
	_status.text = GameSession.add_order(
		{"type": "design_delete", "starbase": starbase, "slot": _picked_slot()}
	)


## Selects the design in `slot` and shows it.
func _select_slot(slot: int) -> void:
	refresh()
	for i in _list.item_count:
		if int(_list.get_item_metadata(i)) == slot:
			_list.select(i)
			design = _saved(slot)
			_show_design()
