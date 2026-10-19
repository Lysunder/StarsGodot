class_name ModManager
extends AcceptDialog
## The Mods window (plan M14; MODDING.md §12): every mod found in the base game's folder and the
## player's (`user://mods`), with a box to turn it on, its version and kind, and whether it has
## scripts. Up and Down set the order mods load in (the loader still puts each after what it
## needs). Turning on a mod with scripts asks once for trust in that version (its scripts' hash).
## OK loads the content with the chosen mods: when they load, the choice is saved and takes
## effect; when not, the problems are shown and nothing changes. The base game is always on.

signal mods_changed

const COLUMNS := ["On", "Mod", "Version", "Kind", "Scripts"]
const LIST_SIZE := Vector2(560, 260)
const COLUMN_WIDTH := 80

var _tree: Tree
var _details: Label
var _status: Label
var _trust: ConfirmationDialog
## Every mod found but the base game, in the list's order: {manifest, source, on, hash}.
var _mods: Array[Dictionary] = []
## Trust as it stands in the window (saved with OK).
var _trusted := {}
## The mod waiting for the trust question's answer.
var _asking := -1


func _ready() -> void:
	title = "Mods"
	ok_button_text = "OK"
	add_cancel_button("Cancel")
	var box := VBoxContainer.new()
	add_child(box)
	_tree = Tree.new()
	_tree.columns = COLUMNS.size()
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.custom_minimum_size = LIST_SIZE
	for i in COLUMNS.size():
		_tree.set_column_title(i, COLUMNS[i])
		_tree.set_column_expand(i, i == 1)
		if i != 1:
			_tree.set_column_custom_minimum_width(i, COLUMN_WIDTH)
	_tree.item_edited.connect(_on_edited)
	_tree.item_selected.connect(_on_selected)
	box.add_child(_tree)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_button(buttons, "Up", func() -> void: _move(-1))
	_button(buttons, "Down", func() -> void: _move(1))
	_button(buttons, "Open Mods Folder", _open_folder)
	_button(buttons, "Reload", open)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.custom_minimum_size = Vector2(LIST_SIZE.x, 0)
	box.add_child(_details)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(LIST_SIZE.x, 0)
	_status.add_theme_color_override("font_color", Color("800000"))
	box.add_child(_status)
	_trust = ConfirmationDialog.new()
	_trust.title = "Trust this mod?"
	_trust.ok_button_text = "Trust and turn on"
	_trust.confirmed.connect(_on_trusted)
	_trust.canceled.connect(func() -> void: _asking = -1)
	add_child(_trust)
	confirmed.connect(_apply)


## Shows the window with the mods found now and the player's saved choice.
func open() -> void:
	_find()
	_fill()
	_status.text = ""
	if not is_visible():
		popup_centered()


## The mods in the folders: the saved order first, then the rest by id.
func _find() -> void:
	_mods.clear()
	_trusted = ModSettings.trusted().duplicate()
	var found := {}
	for source in ModSettings.sources():
		var m := ModManifest.from_json(source.read_text(ModManifest.FILE), source.root())
		if not m.errors.is_empty() or m.id == ModLoader.CORE_ID or found.has(m.id):
			continue
		var scripts := not m.entry.is_empty()
		found[m.id] = {
			"manifest": m,
			"source": source,
			"on": false,
			"hash": ModLoader.script_hash(source) if scripts else "",
		}
	for id in ModSettings.enabled():
		if found.has(id):
			found[id]["on"] = true
			_mods.append(found[id])
			found.erase(id)
	var rest: Array = found.keys()
	rest.sort()
	for id: String in rest:
		_mods.append(found[id])


func _fill() -> void:
	var selected := _selected_index()
	_tree.clear()
	var root := _tree.create_item()
	for i in _mods.size():
		var entry: Dictionary = _mods[i]
		var m: ModManifest = entry["manifest"]
		var row := _tree.create_item(root)
		row.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		row.set_editable(0, true)
		row.set_checked(0, entry["on"])
		row.set_text(1, m.name)
		row.set_text(2, m.version)
		row.set_text(3, m.kind.capitalize())
		row.set_text(4, "yes" if not str(entry["hash"]).is_empty() else "")
		row.set_metadata(0, i)
	if _mods.is_empty():
		_details.text = "No mods found. Put mod folders in %s." % ModSettings.mods_dir
	elif selected >= 0 and selected < _mods.size():
		root.get_child(selected).select(1)


func _selected_index() -> int:
	var row := _tree.get_selected() if _tree != null else null
	return int(row.get_metadata(0)) if row != null else -1


func _on_selected() -> void:
	var i := _selected_index()
	if i < 0:
		return
	var m: ModManifest = _mods[i]["manifest"]
	var lines := PackedStringArray([m.description])
	if not m.authors.is_empty():
		lines.append("By " + ", ".join(m.authors))
	if not m.depends.is_empty():
		lines.append("Needs: " + ", ".join(PackedStringArray(m.depends.keys())))
	if not m.conflicts.is_empty():
		lines.append("Conflicts with: " + ", ".join(m.conflicts))
	if not str(_mods[i]["hash"]).is_empty():
		var trusted: bool = _trusted.get(m.id, "") == _mods[i]["hash"]
		lines.append("Contains scripts" + (" (trusted)." if trusted else " (not trusted yet)."))
	_details.text = "\n".join(lines)


func _on_edited() -> void:
	var row := _tree.get_edited()
	if not set_on(int(row.get_metadata(0)), row.is_checked(0)):
		row.set_checked(0, false)


## Turns mod `i` (in the list) on or off; false when it waits for the trust question instead (a
## mod with scripts whose version hasn't been trusted).
func set_on(i: int, on: bool) -> bool:
	var entry: Dictionary = _mods[i]
	var m: ModManifest = entry["manifest"]
	if on and not str(entry["hash"]).is_empty() and _trusted.get(m.id, "") != entry["hash"]:
		_asking = i
		_trust.dialog_text = (
			(
				"%s %s contains scripts. Scripts in a mod can do anything the game can,\n"
				% [m.name, m.version]
			)
			+ "including reading and changing your files. Turn it on only if you trust where it came\n"
			+ "from. You will be asked again if the mod's scripts change."
		)
		_trust.popup_centered()
		return false
	entry["on"] = on
	return true


func _on_trusted() -> void:
	if _asking < 0:
		return
	var entry: Dictionary = _mods[_asking]
	_trusted[(entry["manifest"] as ModManifest).id] = entry["hash"]
	entry["on"] = true
	_asking = -1
	_fill()


func _move(step: int) -> void:
	var i := _selected_index()
	var j := i + step
	if i < 0 or j < 0 or j >= _mods.size():
		return
	var entry: Dictionary = _mods[i]
	_mods[i] = _mods[j]
	_mods[j] = entry
	_fill()
	_tree.get_root().get_child(j).select(1)


func _open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(ModSettings.mods_dir)
	OS.shell_open(ProjectSettings.globalize_path(ModSettings.mods_dir))


## The mods turned on, in the list's order.
func chosen() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in _mods:
		if entry["on"]:
			out.append((entry["manifest"] as ModManifest).id)
	return out


## OK: the chosen mods are tried; saved and loaded when they load, else the problems are shown
## and the window stays open.
func _apply() -> void:
	var loader := ModLoader.new()
	loader.trusted = _trusted
	var r := loader.load_mods(ModSettings.sources(), chosen())
	if not r.ok():
		_status.text = "These mods can't be used together:\n" + r.error_text()
		popup_centered.call_deferred()
		return
	ModSettings.save(chosen(), _trusted)
	GameSession.reload_content()
	_status.text = ""
	mods_changed.emit()


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)
	return b
