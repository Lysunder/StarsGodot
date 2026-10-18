class_name RelationsDialog
extends AcceptDialog
## Player Relations (D15, the original's arrangement): the other players in a list on the left, and
## Friend, Neutral and Enemy for the one chosen on the right. Every change is a `player_relations`
## order at once (S11); Close closes.

const RELATIONS := ["friend", "neutral", "enemy"]
const LIST_SIZE := Vector2(220, 160)

var _list: ItemList
var _buttons: Array[CheckBox] = []
var _group := ButtonGroup.new()
var _loading := false


func _ready() -> void:
	title = "Player Relations"
	ok_button_text = "Close"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var left := VBoxContainer.new()
	row.add_child(left)
	var label := Label.new()
	label.text = "Player:"
	left.add_child(label)
	_list = ItemList.new()
	_list.custom_minimum_size = LIST_SIZE
	_list.item_selected.connect(func(_i: int) -> void: _show())
	left.add_child(_list)
	var right := VBoxContainer.new()
	row.add_child(right)
	for r: String in RELATIONS:
		var b := CheckBox.new()
		b.text = r.capitalize()
		b.button_group = _group
		b.toggled.connect(
			func(on: bool) -> void:
				if on and not _loading:
					_send(r)
		)
		right.add_child(b)
		_buttons.append(b)


func open() -> void:
	_list.clear()
	var players := GameSession.view.state.players
	for i in players.size():
		if i != GameSession.player:
			_list.add_item(players[i].race.display_plural())
			_list.set_item_metadata(_list.item_count - 1, i)
	if _list.item_count > 0:
		_list.select(0)
	_show()
	popup_centered()


func _chosen() -> int:
	var picked := _list.get_selected_items()
	return -1 if picked.is_empty() else int(_list.get_item_metadata(picked[0]))


func _show() -> void:
	_loading = true
	var p := _chosen()
	var relations := GameSession.view.me().relations
	for i in RELATIONS.size():
		_buttons[i].disabled = p < 0
		_buttons[i].set_pressed_no_signal(p >= 0 and relations[p] == RELATIONS[i])
	_loading = false


func _send(relation: String) -> void:
	var p := _chosen()
	if p < 0:
		return
	var relations: Array = GameSession.view.me().relations.duplicate()
	relations[p] = relation
	var reason := GameSession.set_order({"type": "player_relations", "relations": relations})
	if not reason.is_empty():
		push_warning(reason)
	_show()
