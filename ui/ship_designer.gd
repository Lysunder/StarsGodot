class_name ShipDesigner
extends AcceptDialog
## The Ship & Starbase Designer (M11 step 5; D15, the original's arrangement). On the left: Ships /
## Starbases, then Existing Designs / Available Hull Types, then Copy, Delete and Edit Selected
## Design. At the top the picture with its arrows and a dropdown of the designs or hulls; below it
## the hull schematic, and the totals under it ("Cost of one ...", mass, fuel, armor, shields,
## cargo). Copy (of a design, or of a hull for a new design) and Edit open the design for editing:
## the left column becomes a category filter and the component list, parts are dragged onto the
## schematic (or double-clicked into the first slot that takes them), the name goes in the field
## over it, and OK sends a `design_change` order (Cancel drops the edits). Delete sends a
## `design_delete` order (S11).

const CATEGORY_NAMES := {
	"engine": "Engines",
	"scanner": "Scanners",
	"shield": "Shields",
	"armor": "Armor",
	"beam": "Beam Weapons",
	"torpedo": "Torpedoes",
	"bomb": "Bombs",
	"mine_layer": "Mine Layers",
	"mining_robot": "Mining Robots",
	"electrical": "Electrical",
	"mechanical": "Mechanical",
	"orbital": "Orbital",
}
const MINERALS := ["Ironium", "Boranium", "Germanium"]
const LEFT_WIDTH := 210
const MODE_DESIGNS := 0
const MODE_HULLS := 1

var starbase: bool = false
var list_mode: int = MODE_DESIGNS
## The design shown: a copy of a saved one, a blank one on a hull, or the one being edited.
var design: Design = null
var editing: bool = false
## While editing: the design slot it saves to.
var _edit_slot: int = -1
## What the dropdown lists: design slots (MODE_DESIGNS) or hull ids (MODE_HULLS).
var _choices: Array = []

var _kind_group := ButtonGroup.new()
var _mode_group := ButtonGroup.new()
var _ships: CheckBox
var _designs_radio: CheckBox
var _view_box: VBoxContainer
var _edit_box: VBoxContainer
var _copy: Button
var _delete: Button
var _edit: Button
var _category: OptionButton
var _categories: Array[String] = []
var _parts: RowList
var _part_ids: Array[String] = []
var _part_info: Label
var _picture_number: Label
var _choice: OptionButton
var _name: LineEdit
var _schematic: HullSchematic
var _cost_title: Label
var _cost: Array[Label] = []
var _stats: Array[Label] = []
var _status: Label
var _done: Button
var _cancel: Button
var _confirm_delete: ConfirmationDialog


func _ready() -> void:
	title = "Ship & Starbase Designer"
	get_ok_button().hide()
	min_size = Vector2i(900, 600)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(LEFT_WIDTH, 0)
	row.add_child(left)
	_build_view_box(left)
	_build_edit_box(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	_build_top(right)
	_schematic = HullSchematic.new()
	_schematic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_schematic.changed.connect(_show_stats)
	right.add_child(_schematic)
	_build_stats(right)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("800000"))
	right.add_child(_status)
	_confirm_delete = ConfirmationDialog.new()
	_confirm_delete.confirmed.connect(_on_delete_confirmed)
	add_child(_confirm_delete)
	GameSession.changed.connect(refresh)


func _build_view_box(left: Control) -> void:
	_view_box = VBoxContainer.new()
	left.add_child(_view_box)
	_ships = _radio(_view_box, "Ships", _kind_group, func() -> void: _set_kind(false))
	_radio(_view_box, "Starbases", _kind_group, func() -> void: _set_kind(true))
	_view_box.add_child(Control.new())
	_designs_radio = _radio(
		_view_box, "Existing Designs", _mode_group, func() -> void: _set_mode(MODE_DESIGNS)
	)
	_radio(_view_box, "Available Hull Types", _mode_group, func() -> void: _set_mode(MODE_HULLS))
	_view_box.add_child(Control.new())
	_copy = _button(_view_box, "Copy Selected Design", _on_copy)
	_delete = _button(_view_box, "Delete Selected Design", _on_delete)
	_edit = _button(_view_box, "Edit Selected Design", _on_edit)
	_ships.set_pressed_no_signal(true)
	_designs_radio.set_pressed_no_signal(true)


func _build_edit_box(left: Control) -> void:
	_edit_box = VBoxContainer.new()
	_edit_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_edit_box)
	_category = OptionButton.new()
	_category.item_selected.connect(func(_i: int) -> void: _show_parts())
	_edit_box.add_child(_category)
	_parts = RowList.new(300)
	_parts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_parts.row_selected.connect(_on_part_picked)
	_parts.row_activated.connect(_on_part_activated)
	_parts.drag_payload = _part_payload
	_parts.drop_check = _is_slot_drag
	_parts.drop_take = _take_back
	_edit_box.add_child(_parts)
	_part_info = Label.new()
	_part_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_part_info.custom_minimum_size = Vector2(LEFT_WIDTH, 80)
	_edit_box.add_child(_part_info)


func _build_top(right: Control) -> void:
	var top := HBoxContainer.new()
	right.add_child(top)
	var picture := VBoxContainer.new()
	top.add_child(picture)
	picture.add_child(FleetIcon.new(false))
	var arrows := HBoxContainer.new()
	picture.add_child(arrows)
	_button(arrows, "<", func() -> void: _on_picture(-1))
	_picture_number = Label.new()
	arrows.add_child(_picture_number)
	_button(arrows, ">", func() -> void: _on_picture(1))
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	_choice = OptionButton.new()
	_choice.item_selected.connect(func(_i: int) -> void: _show_choice())
	names.add_child(_choice)
	_name = LineEdit.new()
	_name.placeholder_text = "Design name"
	_name.max_length = OrderRules.NAME_MAX
	_name.text_changed.connect(_on_name)
	names.add_child(_name)
	var buttons := VBoxContainer.new()
	top.add_child(buttons)
	_done = _button(buttons, "Done", _on_done)
	_cancel = _button(buttons, "Cancel", _on_cancel)


func _build_stats(right: Control) -> void:
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 30)
	right.add_child(stats)
	var cost_box := VBoxContainer.new()
	stats.add_child(cost_box)
	_cost_title = _bold(cost_box, "")
	var cost_grid := GridContainer.new()
	cost_grid.columns = 2
	cost_box.add_child(cost_grid)
	for i in 4:
		var name := _bold(cost_grid, MINERALS[i] if i < 3 else "Resources")
		if i < 3:
			name.add_theme_color_override("font_color", ClassicTheme.CARGO_COLORS[i])
		var value := Label.new()
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size = Vector2(70, 0)
		cost_grid.add_child(value)
		_cost.append(value)
	var stat_grid := GridContainer.new()
	stat_grid.columns = 2
	stat_grid.add_theme_constant_override("h_separation", 20)
	stats.add_child(stat_grid)
	for label in ["Mass:", "Max Fuel:", "Armor:", "Shields:", "Cargo:"]:
		_bold(stat_grid, label)
		var value := Label.new()
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size = Vector2(90, 0)
		stat_grid.add_child(value)
		_stats.append(value)


func _radio(parent: Control, text: String, group: ButtonGroup, action: Callable) -> CheckBox:
	var b := CheckBox.new()
	b.text = text
	b.button_group = group
	b.toggled.connect(
		func(on: bool) -> void:
			if on:
				action.call()
	)
	parent.add_child(b)
	return b


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _bold(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "BoldLabel"
	parent.add_child(l)
	return l


func open() -> void:
	editing = false
	_status.text = ""
	popup_centered()
	refresh()


## Rebuilds the dropdown and shows its choice (outside editing).
func refresh() -> void:
	if not visible or not GameSession.has_game() or editing:
		_update_controls()
		return
	var keep: Variant = null
	if _choice.selected >= 0 and _choice.selected < _choices.size():
		keep = _choices[_choice.selected]
	_choice.clear()
	_choices.clear()
	if list_mode == MODE_DESIGNS:
		for d in GameSession.view.designer.designs(starbase):
			var text := d.name
			if d.remaining > 0:
				text += " (%d)" % d.remaining
			_choice.add_item(text)
			_choices.append(d.slot)
	else:
		for id in GameSession.view.designer.available_hulls(starbase):
			_choice.add_item(GameSession.content.display_name(id))
			_choices.append(id)
	var at := _choices.find(keep)
	if at < 0 and not _choices.is_empty():
		at = 0
	if at >= 0:
		_choice.select(at)
	_show_choice()


## The design or hull picked in the dropdown.
func _show_choice() -> void:
	if editing:
		return
	design = null
	var at := _choice.selected
	if at >= 0 and at < _choices.size():
		if list_mode == MODE_DESIGNS:
			design = _saved(int(_choices[at]))
		else:
			design = GameSession.view.designer.blank_design(_choices[at])
			design.name = GameSession.content.display_name(_choices[at])
	_show_design()


## A copy of a saved design, or null.
func _saved(slot: int) -> Design:
	if slot < 0:
		return null
	var me := GameSession.view.me()
	var d := me.starbase_design(slot) if starbase else me.ship_design(slot)
	return d.copy() as Design if d != null else null


func _picked_slot() -> int:
	if list_mode != MODE_DESIGNS or _choice.selected < 0 or _choice.selected >= _choices.size():
		return -1
	return int(_choices[_choice.selected])


func _show_design() -> void:
	_schematic.show_design(design, editing)
	_name.text = design.name if design != null else ""
	_update_controls()
	_show_stats()


func _update_controls() -> void:
	if _view_box == null:
		return
	_view_box.visible = not editing
	_edit_box.visible = editing
	_choice.visible = not editing
	_name.visible = editing
	_cancel.visible = editing
	_done.text = "OK" if editing else "Done"
	if not GameSession.has_game():
		return
	var free := GameSession.view.designer.free_design_slot(starbase) >= 0
	var saved := _saved(_picked_slot())
	_copy.disabled = design == null or not free
	_copy.tooltip_text = "" if free else "Every design slot is taken."
	var has_ships := saved != null and saved.remaining > 0
	_edit.disabled = saved == null or has_ships
	_edit.tooltip_text = "A design with ships can't change; copy it instead." if has_ships else ""
	_delete.disabled = saved == null
	_picture_number.text = ""
	if design != null:
		var first: int = GameSession.content.hull(design.hull).get("pictures", 0)
		_picture_number.text = " %d " % (design.picture - first + 1)


func _show_stats() -> void:
	if design == null:
		_cost_title.text = ""
		for l in _cost + _stats:
			l.text = ""
		return
	var s := GameSession.view.designer.design_stats(design, starbase)
	var label := design.name if not design.name.is_empty() else "design"
	_cost_title.text = "Cost of one %s" % label
	for i in 4:
		_cost[i].text = ("%dkT" % s["cost"][i]) if i < 3 else str(s["cost"][i])
	_stats[0].text = "%skT" % CommandPane.thousands(s["mass"])
	_stats[1].text = "%smg" % CommandPane.thousands(s["fuel"])
	_stats[2].text = "%sdp" % CommandPane.thousands(s["armor"])
	_stats[3].text = "%sdp" % CommandPane.thousands(s["shields"])
	_stats[4].text = "%skT" % CommandPane.thousands(s["cargo"])
	if editing:
		_status.text = s["problem"]


func _set_kind(p_starbase: bool) -> void:
	starbase = p_starbase
	_choice.select(-1)
	refresh()


func _set_mode(p_mode: int) -> void:
	list_mode = p_mode
	_choice.select(-1)
	refresh()


## The category filter for the editing hull: All, then each category its slots take.
func _show_categories() -> void:
	_category.clear()
	_categories.clear()
	var accepted: Array[String] = []
	for slot: Dictionary in GameSession.content.hull(design.hull)["slots"]:
		for c: String in slot["accepts"]:
			if not accepted.has(c):
				accepted.append(c)
	_category.add_item("All")
	_categories.append("")
	for c: String in CATEGORY_NAMES:
		if accepted.has(c):
			_category.add_item(CATEGORY_NAMES[c])
			_categories.append(c)
	_category.select(0)
	_show_parts()


## The component list: the parts of the chosen category (or of every category the hull takes) the
## player can use.
func _show_parts() -> void:
	var at := _category.selected
	var wanted: Array = []
	if at > 0:
		wanted = [_categories[at]]
	else:
		for c in _categories:
			if c != "":
				wanted.append(c)
	_part_ids = GameSession.view.designer.available_parts(wanted)
	var rows: Array[Dictionary] = []
	for id in _part_ids:
		rows.append({"left": GameSession.content.display_name(id)})
	_parts.set_rows(rows, -1)
	_part_info.text = ""


func _part_payload(index: int) -> Variant:
	return {"part": _part_ids[index]}


func _is_slot_drag(data: Variant) -> bool:
	return data is Dictionary and data.has("from_slot")


## A part dragged from a slot back to the component list is removed.
func _take_back(data: Variant) -> void:
	var from: int = data["from_slot"]
	_schematic.remove_part(from, design.parts[from].count)


func _on_part_picked(index: int) -> void:
	var id := _part_ids[index]
	var part := GameSession.content.part(id)
	var cost := ProductionCosts.part_cost(part, GameSession.view.me(), GameSession.content)
	var lines := PackedStringArray([GameSession.content.display_name(id)])
	lines.append(
		"Mass %dkT; I %d B %d G %d R %d" % [part.get("mass", 0), cost[0], cost[1], cost[2], cost[3]]
	)
	var values: Dictionary = part.get("stats", {})
	for key: String in values:
		lines.append("%s %s" % [key.replace("_", " ").capitalize(), str(values[key])])
	_part_info.text = "\n".join(lines)


## Double-clicking a part puts one in the first slot that takes it and has room.
func _on_part_activated(index: int) -> void:
	var slots: Array = GameSession.content.hull(design.hull)["slots"]
	var id := _part_ids[index]
	var category: String = GameSession.content.part(id)["category"]
	for i in slots.size():
		var entry := design.parts[i]
		var fits := (slots[i]["accepts"] as Array).has(category)
		var room := (
			entry.part.is_empty() or (entry.part == id and entry.count < int(slots[i]["max"]))
		)
		if fits and room:
			_schematic.add_part(i, id, 1)
			return


func _on_picture(delta: int) -> void:
	if not editing or design == null:
		return
	var first: int = GameSession.content.hull(design.hull).get("pictures", 0)
	design.picture = first + posmod(design.picture - first + delta, PartRules.PICTURES_PER_HULL)
	_update_controls()


func _on_name(text: String) -> void:
	if editing:
		design.name = text
		_show_stats()


## Copy Selected Design: a copy of the design, or a new design on the hull.
func _on_copy() -> void:
	if design == null:
		return
	var d := design.copy() as Design
	d.name = design.name + " copy" if list_mode == MODE_DESIGNS else ""
	_begin_edit(d, GameSession.view.designer.free_design_slot(starbase))


func _on_edit() -> void:
	var saved := _saved(_picked_slot())
	if saved != null:
		_begin_edit(saved, _picked_slot())


func _begin_edit(d: Design, slot: int) -> void:
	design = d
	_edit_slot = slot
	editing = true
	_status.text = ""
	_show_categories()
	_show_design()
	_name.grab_focus()
	_name.select_all()


## Done (outside editing) closes; OK (editing) saves the design.
func _on_done() -> void:
	if not editing:
		hide()
		return
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
	list_mode = MODE_DESIGNS
	_designs_radio.set_pressed_no_signal(true)
	refresh()
	var at := _choices.find(slot)
	if at >= 0:
		_choice.select(at)
		_show_choice()


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
		text += "\nIts %d ships are removed with it." % saved.remaining
	_confirm_delete.dialog_text = text
	_confirm_delete.popup_centered()


func _on_delete_confirmed() -> void:
	_status.text = (GameSession.add_order(
		{"type": "design_delete", "starbase": starbase, "slot": _picked_slot()}
	))
