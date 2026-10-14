class_name BattlePlansDialog
extends AcceptDialog
## Battle Plans (D15, the original's arrangement): the plan chosen at the top with Rename; its
## primary and secondary targets, tactic and whom it attacks below, and a Dump Cargo box; Delete,
## Copy and Close along the side. Every change is a battle plan order at once (S11
## `battle_plan_change`, `battle_plan_delete`); plan 0, the default, can't be deleted.

const TARGETS := [
	"None / disengage",
	"Any",
	"Starbase",
	"Armed ships",
	"Bombers and freighters",
	"Unarmed ships",
	"Fuel transports",
	"Freighters",
]
const TACTICS := [
	"Disengage",
	"Disengage if challenged",
	"Minimize damage to self",
	"Maximize net damage",
	"Maximize damage ratio",
	"Maximize damage",
]
const ATTACKS := ["Nobody", "Enemies", "Neutrals and enemies", "Everyone"]
const COLUMN_WIDTH := 240
const PLANS_MAX := 16

var _plan: OptionButton
var _primary: OptionButton
var _secondary: OptionButton
var _tactic: OptionButton
var _attack: OptionButton
var _dump: CheckBox
var _delete: Button
var _copy: Button
var _rename: RenameDialog
var _loading := false


func _ready() -> void:
	title = "Battle Plans"
	ok_button_text = "Close"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	row.add_child(left)
	left.add_child(_label("Plan:"))
	var plan_row := HBoxContainer.new()
	left.add_child(plan_row)
	_plan = OptionButton.new()
	_plan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plan.item_selected.connect(func(_i: int) -> void: _show())
	plan_row.add_child(_plan)
	var rename := Button.new()
	rename.text = "Rename..."
	rename.pressed.connect(func() -> void: _rename.open("Rename Battle Plan", _current().name, 31))
	plan_row.add_child(rename)
	_primary = _choice(left, "Primary target:", TARGETS)
	_secondary = _choice(left, "Secondary target:", TARGETS)
	_tactic = _choice(left, "Tactic:", TACTICS)
	_attack = _choice(left, "Attack who:", [])
	_dump = CheckBox.new()
	_dump.text = "Dump cargo"
	_dump.toggled.connect(func(_on: bool) -> void: _send())
	left.add_child(_dump)
	var right := VBoxContainer.new()
	row.add_child(right)
	_delete = Button.new()
	_delete.text = "Delete"
	_delete.pressed.connect(_on_delete)
	right.add_child(_delete)
	_copy = Button.new()
	_copy.text = "Copy"
	_copy.pressed.connect(_on_copy)
	right.add_child(_copy)
	_rename = RenameDialog.new()
	add_child(_rename)
	_rename.name_entered.connect(_on_renamed)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _choice(box: VBoxContainer, text: String, items: Array) -> OptionButton:
	box.add_child(_label(text))
	var o := OptionButton.new()
	for item: String in items:
		o.add_item(item)
	o.item_selected.connect(func(_i: int) -> void: _send())
	box.add_child(o)
	return o


func open() -> void:
	_fill(0)
	popup_centered()


func _plans() -> Array:
	return GameSession.view.me().battle_plans


func _current() -> Dictionary:
	return _plans()[_plan.selected]


## Lists the plans (keeping `select`), and whom a plan can attack: the four groups, then each other
## player by name.
func _fill(select: int) -> void:
	_loading = true
	_plan.clear()
	for p: Dictionary in _plans():
		_plan.add_item(p["name"])
	_plan.select(clampi(select, 0, _plan.item_count - 1))
	_attack.clear()
	for a: String in ATTACKS:
		_attack.add_item(a)
	var players := GameSession.view.state.players
	for i in players.size():
		if i != GameSession.PLAYER:
			_attack.add_item(players[i].race.plural_name, BattlePlans.ATTACK_PLAYER + i)
	_loading = false
	_show()


func _show() -> void:
	_loading = true
	var p := _current()
	_primary.select(p["primary_target"])
	_secondary.select(p["secondary_target"])
	_tactic.select(p["tactic"])
	_attack.select(_attack.get_item_index(p["attack"]))
	_dump.set_pressed_no_signal(p.get("dump_cargo", false))
	_delete.disabled = _plan.selected == 0
	_copy.disabled = _plans().size() >= PLANS_MAX
	_loading = false


func _plan_order(p: Dictionary) -> void:
	var reason := GameSession.add_order({"type": "battle_plan_change", "plan": p})
	if not reason.is_empty():
		push_warning(reason)


func _send() -> void:
	if _loading:
		return
	var p := _current().duplicate()
	p["primary_target"] = _primary.selected
	p["secondary_target"] = _secondary.selected
	p["tactic"] = _tactic.selected
	p["attack"] = _attack.get_item_id(_attack.selected)
	p["dump_cargo"] = _dump.button_pressed
	_plan_order(p)
	_fill(_plan.selected)


func _on_renamed(text: String) -> void:
	var p := _current().duplicate()
	p["name"] = text
	p["dump_cargo"] = p.get("dump_cargo", false)
	_plan_order(p)
	_fill(_plan.selected)


## Copy: a new plan at the end like the chosen one, named after it.
func _on_copy() -> void:
	var p := _current().duplicate()
	p["number"] = _plans().size()
	p["name"] = ("Copy of " + p["name"]).left(31)
	p["dump_cargo"] = p.get("dump_cargo", false)
	_plan_order(p)
	_fill(p["number"])


func _on_delete() -> void:
	var number := _plan.selected
	var reason := GameSession.add_order({"type": "battle_plan_delete", "number": number})
	if not reason.is_empty():
		push_warning(reason)
	_fill(number - 1)
