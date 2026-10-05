class_name MessagesPane
extends PanelContainer
## The Messages pane (D15). There is no message system yet (S21): for now it lists the year's
## notes the UI itself makes (a new year, orders the host rejected).

var _list: ItemList


func _ready() -> void:
	_list = ItemList.new()
	add_child(_list)


func clear() -> void:
	_list.clear()


func add(text: String) -> void:
	_list.add_item(text)
