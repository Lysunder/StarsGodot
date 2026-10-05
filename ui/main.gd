extends Control
## The main scene: applies the Classic 95 theme (D15), scales the UI with the window, then shows
## the main menu and the game screen.

## The UI is laid out for this window size; larger or smaller windows scale it.
const BASE_SIZE := Vector2(1280, 720)
## Scale factors snap to this step, so the pixel font stays as even as possible.
const SCALE_STEP := 0.25
const SCALE_MIN := 0.5
const SCALE_MAX := 4.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.theme = ClassicTheme.build(ClassicTheme.saved_font())
	get_tree().root.size_changed.connect(_rescale)
	_rescale()
	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.name = "Background"
	add_child(background)
	_show_menu()


## The whole UI scales by the window's size relative to BASE_SIZE (the smaller ratio), in steps.
func _rescale() -> void:
	var root := get_tree().root
	var ratio := minf(root.size.x / BASE_SIZE.x, root.size.y / BASE_SIZE.y)
	var factor := clampf(snappedf(ratio, SCALE_STEP), SCALE_MIN, SCALE_MAX)
	if not is_equal_approx(root.content_scale_factor, factor):
		root.content_scale_factor = factor


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
