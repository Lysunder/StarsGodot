class_name HoldPopup
extends PanelContainer
## A popup shown only while a mouse button is held (D15, the original's summary popups): a raised
## panel drawn above everything near the mouse, ignoring the mouse itself so the press keeps
## going to the control that opened it, which hides it when the button is let go.

const OFFSET := Vector2(12, 12)
const MARGIN := 4.0


func _init() -> void:
	top_level = true
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = "TileBody"
	visible = false


## Shows `content` (replacing what was shown) near `at`, kept inside the window.
func open(content: Control, at: Vector2) -> void:
	for child in get_children():
		child.queue_free()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	reset_size()
	visible = true
	await get_tree().process_frame
	if not visible:
		return
	reset_size()
	var screen := get_viewport_rect().size
	var pos := at + OFFSET
	pos.x = clampf(pos.x, MARGIN, maxf(screen.x - size.x - MARGIN, MARGIN))
	pos.y = clampf(pos.y, MARGIN, maxf(screen.y - size.y - MARGIN, MARGIN))
	global_position = pos


func close() -> void:
	visible = false
	for child in get_children():
		child.queue_free()
