class_name HullSchematic
extends Control
## The ship designer's hull picture (D15): every slot is a box placed by the hull's layout (S04
## "Designer layout", half-slot grid), labelled with what it takes ("Shield or Armor", "up to 2";
## an engine slot "needs" its count) or, once filled, the part and how many; the cargo bay or dock
## is a hatched box. While editing, parts dropped from the component list go into a slot that takes
## them (Ctrl: as many as fit; Shift: four), a part dragged from a slot back to the component
## list is removed, and a right click removes one.

## The design changed (a part added or removed).
signal changed

const CELL := 36
const SLOT_FILL := Color("808080")
const SLOT_FULL := Color("a0a0a0")
const SLOT_HOVER := Color("c0c0ff")
const CARGO_FILL := Color("d8d8d8")
const CARGO_HATCH := Color("a8a8a8")
const LINE := Color.BLACK
const SHIFT_COUNT := 4
const CATEGORY_NAMES := {
	"engine": "Engine",
	"scanner": "Scanner",
	"shield": "Shield",
	"armor": "Armor",
	"beam": "Weapon",
	"torpedo": "Weapon",
	"bomb": "Bomb",
	"mine_layer": "Mine Layer",
	"mining_robot": "Mining",
	"electrical": "Elect",
	"mechanical": "Mech",
	"orbital": "Orbital",
}

var design: Design = null
var editing: bool = false
var _hover := -1


func _init() -> void:
	custom_minimum_size = Vector2(CELL * 11, CELL * 10)
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_design(p_design: Design, p_editing: bool) -> void:
	design = p_design
	editing = p_editing
	queue_redraw()


## The hull's slot boxes and cargo box, centred: {slots: [Rect2], cargo: Rect2 or null}.
func _layout() -> Dictionary:
	var hull := GameSession.content.hull(design.hull)
	var slots: Array = hull["slots"]
	var rects: Array[Rect2] = []
	var bounds := Rect2()
	for i in slots.size():
		var at: Array = slots[i].get("at", [i * 2, 0])
		var r := Rect2(at[0] * CELL, at[1] * CELL, CELL * 2, CELL * 2)
		rects.append(r)
		bounds = r if i == 0 else bounds.merge(r)
	var cargo: Variant = null
	if hull.has("cargo_area"):
		var a: Array = hull["cargo_area"]
		cargo = Rect2(a[0] * CELL, a[1] * CELL, (a[2] - a[0]) * CELL, (a[3] - a[1]) * CELL)
		bounds = bounds.merge(cargo)
	var shift := (size - bounds.size) / 2.0 - bounds.position
	for i in rects.size():
		rects[i].position += shift
	if cargo != null:
		cargo = Rect2(cargo.position + shift, cargo.size)
	return {"slots": rects, "cargo": cargo}


func _draw() -> void:
	if design == null:
		return
	var font := get_theme_default_font()
	var bold := ClassicTheme.bold_font(self)
	var font_size := get_theme_default_font_size() - 2
	var hull := GameSession.content.hull(design.hull)
	var layout := _layout()
	if layout["cargo"] != null:
		var c: Rect2 = layout["cargo"]
		draw_rect(c, CARGO_FILL)
		var step := 6.0
		var x := c.position.x - c.size.y
		while x < c.end.x:
			var a := Vector2(maxf(x, c.position.x), c.position.y + maxf(c.position.x - x, 0.0))
			var b_x := minf(x + c.size.y, c.end.x)
			var b := Vector2(b_x, c.position.y + (b_x - x))
			draw_line(a, b, CARGO_HATCH, 1.0)
			x += step
		draw_rect(c, LINE, false, 1.0)
		var label := "Dock" if hull.get("starbase", false) else "Cargo"
		var amount: int = (
			hull.get("dock", 0) if hull.get("starbase", false) else hull.get("cargo", 0)
		)
		var lines := [label, "Unlimited" if amount < 0 else "%dkT" % amount]
		_text_lines(c, lines, bold, font_size)
	var slots: Array = hull["slots"]
	for i in slots.size():
		var r: Rect2 = layout["slots"][i]
		var entry := design.parts[i] if i < design.parts.size() else DesignSlot.new()
		var fill := SLOT_FULL if not entry.part.is_empty() else SLOT_FILL
		if i == _hover:
			fill = SLOT_HOVER
		draw_rect(r, fill)
		draw_rect(r, LINE, false, 1.0)
		var lines: Array = []
		var most: int = slots[i]["max"]
		if entry.part.is_empty():
			lines.append_array(_accepts_lines(slots[i]["accepts"]))
			var needs := (slots[i]["accepts"] as Array).has("engine")
			lines.append(("needs %d" if needs else "up to %d") % most)
			_text_lines(r, lines, font, font_size)
		else:
			lines.append(GameSession.content.display_name(entry.part))
			lines.append("%d of %d" % [entry.count, most])
			_text_lines(r, lines, bold, font_size)


## What an empty slot takes: one name, "A / or / B", three names, or "General / Purpose" for more.
static func _accepts_lines(accepts: Array) -> Array:
	var names: Array[String] = []
	for c: String in accepts:
		var n: String = CATEGORY_NAMES.get(c, c)
		if not names.has(n):
			names.append(n)
	if names.size() == 2:
		return [names[0], "or", names[1]]
	if names.size() > 3:
		return ["General", "Purpose"]
	return names


## Lines of text centred in a box, each cut to the box's width.
func _text_lines(r: Rect2, lines: Array, font: Font, font_size: int) -> void:
	var h := font.get_height(font_size)
	var top := r.position.y + (r.size.y - h * lines.size()) / 2.0 + font.get_ascent(font_size)
	for k in lines.size():
		var text: String = lines[k]
		while text.length() > 1 and font.get_string_size(text, 0, -1, font_size).x > r.size.x - 4:
			text = text.left(-1)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(
			font,
			Vector2(r.position.x + (r.size.x - w) / 2.0, top + k * h),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			ClassicTheme.TEXT
		)


## The slot under a point, or -1.
func slot_at(at: Vector2) -> int:
	if design == null:
		return -1
	var rects: Array = _layout()["slots"]
	for i in rects.size():
		if (rects[i] as Rect2).has_point(at):
			return i
	return -1


## How many of `part` a drop adds: Ctrl as many as fit, Shift four, else one.
static func drop_count(most: int) -> int:
	if Input.is_key_pressed(KEY_CTRL):
		return most
	if Input.is_key_pressed(KEY_SHIFT):
		return SHIFT_COUNT
	return 1


## Puts `count` of `part` in slot i (replacing another part there); false if the slot doesn't
## take it.
func add_part(i: int, part: String, count: int) -> bool:
	var slots: Array = GameSession.content.hull(design.hull)["slots"]
	if i < 0 or i >= slots.size():
		return false
	var category: String = GameSession.content.part(part)["category"]
	if not (slots[i]["accepts"] as Array).has(category):
		return false
	var entry := design.parts[i]
	if entry.part != part:
		entry.part = part
		entry.count = 0
	entry.count = mini(entry.count + count, int(slots[i]["max"]))
	queue_redraw()
	changed.emit()
	return true


func remove_part(i: int, count: int) -> void:
	if i < 0 or i >= design.parts.size():
		return
	var entry := design.parts[i]
	entry.count = maxi(entry.count - count, 0)
	if entry.count == 0:
		entry.part = ""
	queue_redraw()
	changed.emit()


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not editing or not data is Dictionary:
		return false
	var i := slot_at(at)
	if data.has("part"):
		var category: String = GameSession.content.part(data["part"])["category"]
		var slots: Array = GameSession.content.hull(design.hull)["slots"]
		var ok := i >= 0 and (slots[i]["accepts"] as Array).has(category)
		_set_hover(i if ok else -1)
		return ok
	return data.has("from_slot")


func _drop_data(at: Vector2, data: Variant) -> void:
	_set_hover(-1)
	var i := slot_at(at)
	if data.has("part"):
		var most: int = GameSession.content.hull(design.hull)["slots"][i]["max"]
		add_part(i, data["part"], drop_count(most))
	elif data.has("from_slot") and i != data["from_slot"]:
		var from: int = data["from_slot"]
		var entry := design.parts[from]
		var part := entry.part
		var count := entry.count
		if add_part(i, part, count):
			remove_part(from, count)


func _get_drag_data(at: Vector2) -> Variant:
	if not editing:
		return null
	var i := slot_at(at)
	if i < 0 or design.parts[i].part.is_empty():
		return null
	var preview := Label.new()
	preview.text = GameSession.content.display_name(design.parts[i].part)
	set_drag_preview(preview)
	return {"from_slot": i}


func _gui_input(event: InputEvent) -> void:
	var right: bool = (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	)
	if editing and right:
		remove_part(slot_at(event.position), 1)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_set_hover(-1)


func _set_hover(i: int) -> void:
	if i != _hover:
		_hover = i
		queue_redraw()
