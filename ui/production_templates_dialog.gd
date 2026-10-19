class_name ProductionTemplatesDialog
extends ConfirmationDialog
## Customize Production Templates (D15; the original's `ZIPPRODDLG@10c8:2d26` arrangement): the
## four templates as a column of choices (the default one for new colonies, then the player's
## three own, "(empty)" until used), the chosen template's auto-build items below with its research
## setting, and Import, Delete and Rename. Import takes the production window's auto-build items and
## its "leftover resources" box (asking for a name for an own template); the default template can't
## be renamed or deleted (importing an empty queue clears it). OK sends the changes: the default as
## a `player_defaults` order, the others as one `production_templates` order (S11).

## Templates changed.
signal saved

const LIST_SIZE := Vector2(300, 200)
const DEFAULT_NAME := "Default"

## Index 0 the default, then the own templates: {name, leftover_to_research, queue} (an own one
## with no name is unused).
var _templates: Array[Dictionary] = []
var _chosen: int = 0
## The production window's queue and box, for Import.
var _source_queue: Array = []
var _source_leftover: bool = false
var _buttons: Array[CheckBox] = []
var _group := ButtonGroup.new()
var _items: ItemList
var _research: Label
var _delete: Button
var _rename_button: Button
var _rename: RenameDialog
## Import waits for the name of an own template.
var _importing: bool = false


func _ready() -> void:
	title = "Production Templates"
	ok_button_text = "OK"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var left := VBoxContainer.new()
	row.add_child(left)
	var group := VBoxContainer.new()
	left.add_child(group)
	for i in ProductionTemplates.CUSTOM + 1:
		var b := CheckBox.new()
		b.button_group = _group
		b.toggled.connect(
			func(on: bool) -> void:
				if on:
					_choose(i)
		)
		group.add_child(b)
		_buttons.append(b)
	_items = ItemList.new()
	_items.custom_minimum_size = LIST_SIZE
	left.add_child(_items)
	_research = Label.new()
	left.add_child(_research)
	var side := VBoxContainer.new()
	row.add_child(side)
	var import := Button.new()
	import.text = "Import"
	import.pressed.connect(_on_import)
	side.add_child(import)
	_delete = Button.new()
	_delete.text = "Delete"
	_delete.pressed.connect(_on_delete)
	side.add_child(_delete)
	_rename_button = Button.new()
	_rename_button.text = "Rename"
	_rename_button.pressed.connect(
		func() -> void:
			_importing = false
			_rename.open(
				"Rename Template", _templates[_chosen]["name"], ProductionTemplates.NAME_MAX
			)
	)
	side.add_child(_rename_button)
	_rename = RenameDialog.new()
	_rename.name_entered.connect(_on_named)
	add_child(_rename)
	confirmed.connect(_save)


## Opens on the player's templates; Import will take `queue` (queue item dictionaries) and
## `leftover` (the production window's edits).
func open(queue: Array, leftover: bool) -> void:
	_source_queue = queue
	_source_leftover = leftover
	var me := GameSession.preview.state.player(GameSession.player)
	_templates.clear()
	var default_queue: Array = []
	for q in me.default_queue:
		default_queue.append(q.to_dict())
	(
		_templates
		. append(
			{
				"name": DEFAULT_NAME,
				"leftover_to_research": me.default_leftover_to_research,
				"queue": default_queue,
			}
		)
	)
	for i in ProductionTemplates.CUSTOM:
		if i < me.production_templates.size():
			_templates.append((me.production_templates[i] as Dictionary).duplicate(true))
		else:
			_templates.append({"name": "", "leftover_to_research": false, "queue": []})
	_buttons[0].set_pressed_no_signal(true)
	_choose(0)
	popup_centered()


## Every template in use, for the production window's menu: [{index, name, leftover_to_research,
## queue}], the default first.
static func in_use() -> Array[Dictionary]:
	var me := GameSession.preview.state.player(GameSession.player)
	var default_queue: Array = []
	for q in me.default_queue:
		default_queue.append(q.to_dict())
	var out: Array[Dictionary] = [
		{
			"index": 0,
			"name": DEFAULT_NAME,
			"leftover_to_research": me.default_leftover_to_research,
			"queue": default_queue,
		}
	]
	for i in me.production_templates.size():
		var t: Dictionary = me.production_templates[i]
		(
			out
			. append(
				{
					"index": i + 1,
					"name": t["name"],
					"leftover_to_research": t["leftover_to_research"],
					"queue": t["queue"],
				}
			)
		)
	return out


func _label_of(i: int) -> String:
	var label_text: String = _templates[i]["name"]
	return label_text if label_text != "" else "(empty %d)" % i


func _choose(i: int) -> void:
	_chosen = i
	for k in _buttons.size():
		_buttons[k].text = _label_of(k)
	_items.clear()
	var t := _templates[i]
	var used: bool = i == 0 or t["name"] != ""
	var view := GameSession.view
	for d: Dictionary in t["queue"]:
		var q := QueueItem.new(d["item"], int(d["count"]))
		_items.add_item("%s  (up to %d)" % [view.queue_item_name(view.player, q), q.count])
	if _items.item_count == 0:
		_items.add_item("No auto-build items")
		_items.set_item_disabled(0, true)
	_research.text = ""
	if used:
		_research.text = (
			"Only leftover resources go to research"
			if t["leftover_to_research"]
			else "Contributes to research"
		)
	_delete.disabled = i == 0 or not used
	_rename_button.disabled = i == 0 or not used


func _on_import() -> void:
	if _chosen == 0:
		_import(DEFAULT_NAME)
		return
	_importing = true
	var label_text: String = _templates[_chosen]["name"]
	_rename.open(
		"Name the Template",
		label_text if label_text != "" else "Template %d" % _chosen,
		ProductionTemplates.NAME_MAX
	)


func _on_named(text: String) -> void:
	if text == "":
		text = "Template %d" % _chosen
	if _importing:
		_import(text)
	else:
		_templates[_chosen]["name"] = text
		_choose(_chosen)


func _import(label_text: String) -> void:
	_templates[_chosen] = {
		"name": label_text,
		"leftover_to_research": _source_leftover,
		"queue": ProductionTemplates.import_queue(_source_queue, GameSession.content),
	}
	_choose(_chosen)


func _on_delete() -> void:
	if _chosen == 0:
		return
	_templates[_chosen] = {"name": "", "leftover_to_research": false, "queue": []}
	_choose(_chosen)


## OK: the default as `player_defaults` when it changed, the own templates (used ones, in order)
## as `production_templates` when they changed.
func _save() -> void:
	var me := GameSession.preview.state.player(GameSession.player)
	var current := in_use()
	var reason := ""
	var d := _templates[0]
	if (
		d["queue"] != current[0]["queue"]
		or d["leftover_to_research"] != current[0]["leftover_to_research"]
	):
		reason = (
			GameSession
			. set_order(
				{
					"type": "player_defaults",
					"leftover_to_research": d["leftover_to_research"],
					"queue": d["queue"],
				}
			)
		)
	var own: Array = []
	for i in range(1, _templates.size()):
		if _templates[i]["name"] != "":
			own.append(_templates[i])
	if reason.is_empty() and own != me.production_templates:
		reason = GameSession.set_order({"type": "production_templates", "templates": own})
	if not reason.is_empty():
		push_warning(reason)
	saved.emit()
