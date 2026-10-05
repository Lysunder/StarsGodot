class_name ClassicTheme
extends RefCounted
## The "Classic 95" theme (D15): gray bevelled controls, white sunken fields and lists, navy title
## bars and selection, the W95FA pixel font (SIL OFL 1.1, `art/fonts/w95fa/`) with a system sans as
## fallback. Every bevel is drawn here from our own colour constants.

const FACE := Color("c0c0c0")
const LIGHT := Color("dfdfdf")
const HIGHLIGHT := Color("ffffff")
const SHADOW := Color("808080")
const DARK := Color("000000")
const FIELD := Color("ffffff")
const NAVY := Color("000080")
const TEXT := Color("000000")
const TEXT_DISABLED := Color("808080")
const TEXT_SELECTED := Color("ffffff")
const FONT_PATH := "res://art/fonts/w95fa/W95FA.otf"
const FALLBACK_NAMES := ["Tahoma", "MS Sans Serif", "Microsoft Sans Serif", "Segoe UI", "Arial"]
## One font pixel is 80 of W95FA's 1000 units, so 12.5 px is pixel-exact; 13 is the nearest size.
const FONT_SIZE := 13
const BEVEL := 2
const IMAGE_SIZE := 8


## Builds the whole theme.
static func build() -> Theme:
	var t := Theme.new()
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(FALLBACK_NAMES)
	fallback.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	var font: Font = fallback
	var file := load(FONT_PATH) as FontFile
	if file != null:
		file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		file.hinting = TextServer.HINTING_NONE
		file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		file.fallbacks = [fallback]
		font = file
	t.default_font = font
	t.default_font_size = FONT_SIZE
	var raised := _bevel(true, FACE)
	var sunken := _bevel(false, FACE)
	var field := _bevel(false, FIELD)
	var flat := _flat(FACE)
	var navy := _flat(NAVY)
	var none := StyleBoxEmpty.new()
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, raised)
		t.set_stylebox("hover", type, raised)
		t.set_stylebox("pressed", type, sunken)
		t.set_stylebox("disabled", type, raised)
		t.set_stylebox("focus", type, none)
		_text_colours(t, type)
	for type in ["CheckBox", "CheckButton"]:
		for s in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
			t.set_stylebox(s, type, none)
		_text_colours(t, type)
	for type in ["Label"]:
		t.set_color("font_color", type, TEXT)
	for type in ["LineEdit", "SpinBox", "TextEdit"]:
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, none)
		t.set_stylebox("read_only", type, field)
		t.set_color("font_color", type, TEXT)
		t.set_color("caret_color", type, TEXT)
		t.set_color("selection_color", type, NAVY)
	t.set_stylebox("panel", "ItemList", field)
	t.set_stylebox("focus", "ItemList", none)
	t.set_stylebox("selected", "ItemList", navy)
	t.set_stylebox("selected_focus", "ItemList", navy)
	t.set_stylebox("hovered", "ItemList", none)
	t.set_stylebox("cursor", "ItemList", none)
	t.set_stylebox("cursor_unfocused", "ItemList", none)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_hovered_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", TEXT_SELECTED)
	for type in ["Panel", "PanelContainer"]:
		t.set_stylebox("panel", type, flat)
	t.set_stylebox("panel", "PopupMenu", raised)
	t.set_stylebox("hover", "PopupMenu", navy)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", TEXT_SELECTED)
	t.set_color("font_disabled_color", "PopupMenu", TEXT_DISABLED)
	t.set_stylebox("normal", "MenuBar", none)
	t.set_stylebox("hover", "MenuBar", navy)
	t.set_stylebox("pressed", "MenuBar", navy)
	t.set_color("font_color", "MenuBar", TEXT)
	t.set_color("font_hover_color", "MenuBar", TEXT_SELECTED)
	t.set_color("font_pressed_color", "MenuBar", TEXT_SELECTED)
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, _flat(LIGHT))
		t.set_stylebox("scroll_focus", type, _flat(LIGHT))
		t.set_stylebox("grabber", type, raised)
		t.set_stylebox("grabber_highlight", type, raised)
		t.set_stylebox("grabber_pressed", type, raised)
	t.set_stylebox("embedded_border", "Window", _window_frame())
	t.set_stylebox("embedded_unfocused_border", "Window", _window_frame())
	t.set_color("title_color", "Window", TEXT_SELECTED)
	t.set_constant("title_height", "Window", 20)
	t.set_stylebox("panel", "AcceptDialog", flat)
	for type in ["HSplitContainer", "VSplitContainer"]:
		t.set_constant("separation", type, 4)
	return t


static func _text_colours(t: Theme, type: String) -> void:
	t.set_color("font_color", type, TEXT)
	t.set_color("font_hover_color", type, TEXT)
	t.set_color("font_pressed_color", type, TEXT)
	t.set_color("font_focus_color", type, TEXT)
	t.set_color("font_hover_pressed_color", type, TEXT)
	t.set_color("font_disabled_color", type, TEXT_DISABLED)


static func _flat(colour: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = colour
	s.content_margin_left = 3
	s.content_margin_right = 3
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	return s


## A two-pixel bevel around a face: raised (light top-left, dark bottom-right) or sunken.
static func _bevel(raised: bool, face: Color) -> StyleBoxTexture:
	var img := Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(face)
	var outer_tl := HIGHLIGHT if raised else SHADOW
	var inner_tl := LIGHT if raised else DARK
	var outer_br := DARK if raised else HIGHLIGHT
	var inner_br := SHADOW if raised else LIGHT
	var last := IMAGE_SIZE - 1
	for i in IMAGE_SIZE:
		img.set_pixel(i, last, outer_br)
		img.set_pixel(last, i, outer_br)
	for i in range(1, last):
		img.set_pixel(i, last - 1, inner_br)
		img.set_pixel(last - 1, i, inner_br)
	for i in last:
		img.set_pixel(i, 0, outer_tl)
		img.set_pixel(0, i, outer_tl)
	for i in range(1, last - 1):
		img.set_pixel(i, 1, inner_tl)
		img.set_pixel(1, i, inner_tl)
	var s := StyleBoxTexture.new()
	s.texture = ImageTexture.create_from_image(img)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		s.set_texture_margin(side, BEVEL)
		s.set_content_margin(side, BEVEL + 3)
	s.set_content_margin(SIDE_TOP, BEVEL + 1)
	s.set_content_margin(SIDE_BOTTOM, BEVEL + 1)
	return s


## A dialog's frame: a raised border with a navy title strip.
static func _window_frame() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = FACE
	s.border_color = SHADOW
	s.set_border_width_all(2)
	s.border_width_top = 22
	s.border_color = NAVY
	s.expand_margin_left = 2
	s.expand_margin_right = 2
	s.expand_margin_bottom = 2
	s.expand_margin_top = 22
	return s
