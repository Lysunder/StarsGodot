extends Control
## The main scene: applies the Classic 95 theme (D15) and the interface settings (UiSettings: the
## font and the scale, which by default follows the window), then shows the main menu and the game
## screen.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_window().title = tr("StarsGodot %s") % BuildInfo.label()
	UiSettings.apply(get_tree())
	get_tree().root.size_changed.connect(func() -> void: UiSettings.rescale(get_tree()))
	get_tree().node_added.connect(_on_node_added)
	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.name = "Background"
	add_child(background)
	_show_menu()


## Dialogs are viewports of their own: draw their bevels unfiltered too, so the pixel edges stay
## sharp (the project's default filter only reaches the main window).
func _on_node_added(node: Node) -> void:
	if node is Window:
		(node as Window).canvas_item_default_texture_filter = (
			Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		)


func _show_menu() -> void:
	_clear()
	var menu := MainMenu.new()
	menu.start_game.connect(_show_game)
	add_child(menu)


func _show_game() -> void:
	_clear()
	var screen := GameScreen.new()
	screen.quit_requested.connect(_show_menu)
	add_child(screen)


func _clear() -> void:
	for child in get_children():
		if child.name != "Background":
			child.queue_free()
