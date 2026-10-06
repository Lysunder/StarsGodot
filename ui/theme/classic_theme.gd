class_name ClassicTheme
extends RefCounted
## The "Classic 95" theme (D15): gray bevelled controls, white sunken fields and lists, navy title
## bars and selection, one of the bundled fonts in FONTS (all SIL OFL 1.1, under `art/fonts/`)
## with a system sans as fallback. Every bevel is drawn here from our own colour constants.

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
## Cargo colours, in cargo order (ironium, boranium, germanium, colonists, fuel): the mineral names
## in tiles and dialogs and the segments of fuel and cargo gauges.
const CARGO_COLORS := [
	Color("0000ff"),
	Color("007f00"),
	Color("ffff00"),
	Color("ffffff"),
	Color("ff0000"),
]
## How much a bold label thickens the font (FontVariation embolden).
const EMBOLDEN := 0.8
## The bundled UI fonts. Pixel fonts are drawn without smoothing at a size that keeps their pixels
## whole: one W95FA pixel is 80 of its 1000 units (12.5 px is exact, 13 the nearest size); Terminus
## carries hand-drawn bitmaps at even sizes.
const FONTS := [
	{"name": "W95FA", "path": "res://art/fonts/w95fa/W95FA.otf", "size": 13, "pixel": true},
	{
		"name": "Terminus",
		"path": "res://art/fonts/terminus/TerminusTTF-4.49.3.ttf",
		"size": 14,
		"pixel": true,
	},
	{
		"name": "Cascadia Mono",
		"path": "res://art/fonts/cascadia_mono/CascadiaMono-Regular.ttf",
		"size": 13,
		"pixel": false,
	},
]
## The font used until the player picks another: Cascadia Mono.
const DEFAULT_FONT := 2
const FALLBACK_NAMES := ["Tahoma", "MS Sans Serif", "Microsoft Sans Serif", "Segoe UI", "Arial"]
const SETTINGS_PATH := "user://settings.cfg"
const BEVEL := 2
const IMAGE_SIZE := 8
## The slider's grabber (a small raised block) and its track's height, in pixels.
const GRABBER_SIZE := Vector2i(11, 21)
const TRACK_HEIGHT := 4
## Side of a dropdown's arrow button, in pixels.
const DROPDOWN_BUTTON := 16
## Side of a check box or radio button, in pixels.
const CHECK_SIZE := 13


## The font the player picked last (an index into FONTS), from the settings file.
static func saved_font() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return DEFAULT_FONT
	return clampi(int(cfg.get_value("ui", "font", DEFAULT_FONT)), 0, FONTS.size() - 1)


static func save_font(index: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("ui", "font", index)
	cfg.save(SETTINGS_PATH)


## Builds the whole theme with font FONTS[font_index].
static func build(font_index: int = DEFAULT_FONT) -> Theme:
	var t := Theme.new()
	var spec: Dictionary = FONTS[clampi(font_index, 0, FONTS.size() - 1)]
	var smoothing := TextServer.FONT_ANTIALIASING_GRAY
	if spec["pixel"]:
		smoothing = TextServer.FONT_ANTIALIASING_NONE
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(FALLBACK_NAMES)
	fallback.antialiasing = smoothing
	var font: Font = fallback
	var file := load(spec["path"]) as FontFile
	if file != null:
		file = file.duplicate() as FontFile
		file.antialiasing = smoothing
		if spec["pixel"]:
			file.hinting = TextServer.HINTING_NONE
			file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		file.fallbacks = [fallback]
		font = file
	t.default_font = font
	t.default_font_size = spec["size"]
	var bold := FontVariation.new()
	bold.base_font = font
	bold.variation_embolden = EMBOLDEN
	t.set_type_variation("BoldLabel", "Label")
	t.set_font("font", "BoldLabel", bold)
	t.set_type_variation("BoldButton", "Button")
	t.set_font("font", "BoldButton", bold)
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
	t.set_stylebox("hovered_selected", "ItemList", navy)
	t.set_stylebox("hovered_selected_focus", "ItemList", navy)
	t.set_stylebox("cursor", "ItemList", none)
	t.set_stylebox("cursor_unfocused", "ItemList", none)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_hovered_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", TEXT_SELECTED)
	t.set_color("font_hovered_selected_color", "ItemList", TEXT_SELECTED)
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
	# a dropdown is a white sunken field with a small raised arrow button at its right end
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(st, "OptionButton", field if st != "focus" else none)
		if st != "focus":
			t.set_stylebox(st + "_mirrored", "OptionButton", field)
	_text_colours(t, "OptionButton")
	t.set_icon("arrow", "OptionButton", _dropdown_arrow())
	t.set_constant("arrow_margin", "OptionButton", 1)
	t.set_constant("modulate_arrow", "OptionButton", 0)
	var check_off := ImageTexture.create_from_image(_check_image(false, false))
	var check_on := ImageTexture.create_from_image(_check_image(true, false))
	var radio_off := ImageTexture.create_from_image(_check_image(false, true))
	var radio_on := ImageTexture.create_from_image(_check_image(true, true))
	for type in ["CheckBox", "CheckButton"]:
		for suffix in ["", "_disabled"]:
			t.set_icon("unchecked" + suffix, type, check_off)
			t.set_icon("checked" + suffix, type, check_on)
			t.set_icon("radio_unchecked" + suffix, type, radio_off)
			t.set_icon("radio_checked" + suffix, type, radio_on)
	var sunken_field := _bevel(false, FACE)
	sunken_field.set_content_margin_all(BEVEL + 1)
	t.set_type_variation("SunkenField", "PanelContainer")
	t.set_stylebox("panel", "SunkenField", sunken_field)
	var list_box := _bevel(false, FIELD)
	list_box.set_content_margin_all(BEVEL)
	t.set_type_variation("RowListBox", "ScrollContainer")
	t.set_stylebox("panel", "RowListBox", list_box)
	var bar := _bevel(true, FACE)
	bar.set_content_margin_all(1)
	bar.set_content_margin(SIDE_LEFT, BEVEL + 2)
	t.set_type_variation("TileBar", "PanelContainer")
	t.set_stylebox("panel", "TileBar", bar)
	var tile_body := _bevel(true, FACE)
	tile_body.set_content_margin_all(BEVEL + 2)
	t.set_type_variation("TileBody", "PanelContainer")
	t.set_stylebox("panel", "TileBody", tile_body)
	var track := _bevel(false, FACE)
	track.set_content_margin(SIDE_TOP, TRACK_HEIGHT / 2)
	track.set_content_margin(SIDE_BOTTOM, TRACK_HEIGHT / 2)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", none)
	t.set_stylebox("grabber_area_highlight", "HSlider", none)
	var grabber := ImageTexture.create_from_image(
		_bevel_image(GRABBER_SIZE.x, GRABBER_SIZE.y, true, FACE)
	)
	for icon in ["grabber", "grabber_highlight", "grabber_disabled"]:
		t.set_icon(icon, "HSlider", grabber)
	var tick := Image.create(1, 4, false, Image.FORMAT_RGBA8)
	tick.fill(DARK)
	t.set_icon("tick", "HSlider", ImageTexture.create_from_image(tick))
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
	var img := _bevel_image(IMAGE_SIZE, IMAGE_SIZE, raised, face)
	var s := StyleBoxTexture.new()
	s.texture = ImageTexture.create_from_image(img)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		s.set_texture_margin(side, BEVEL)
		s.set_content_margin(side, BEVEL + 3)
	s.set_content_margin(SIDE_TOP, BEVEL + 1)
	s.set_content_margin(SIDE_BOTTOM, BEVEL + 1)
	return s


## The bold variant of the theme's font (for drawing text in custom controls).
static func bold_font(control: Control) -> Font:
	return control.get_theme_font("font", "BoldLabel")


## The collapse button's arrow: a bar and an up-pointing triangle (collapse), or the same turned
## over (expand), black on transparent.
static func collapse_icon(collapsed: bool) -> ImageTexture:
	var img := Image.create(9, 7, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in 9:
		img.set_pixel(x, 0, DARK)
	for row in 4:
		for x in range(4 - row, 5 + row):
			img.set_pixel(x, 2 + row, DARK)
	if collapsed:
		img.flip_y()
	return ImageTexture.create_from_image(img)


## A 13 × 13 check box (a white sunken square, with a black tick when on) or radio button (a
## sunken white circle, with a black dot when on).
static func _check_image(on: bool, radio: bool) -> Image:
	if not radio:
		var img := _bevel_image(CHECK_SIZE, CHECK_SIZE, false, FIELD)
		if on:
			# a tick: down-right from (3, 5) to (5, 7), then up-right to (9, 3), three pixels thick
			for i in 3:
				for k in 3:
					img.set_pixel(3 + i, 5 + i + k - 1, DARK)
			for i in 5:
				for k in 3:
					img.set_pixel(5 + i, 7 - i + k - 1, DARK)
		return img
	var img := Image.create(CHECK_SIZE, CHECK_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (CHECK_SIZE - 1) / 2.0
	for y in CHECK_SIZE:
		for x in CHECK_SIZE:
			var d := Vector2(x - c, y - c)
			var r := d.length()
			if r <= c - 1.0:
				img.set_pixel(x, y, FIELD)
			elif r <= c + 0.3:
				# the rim: dark on the upper left, light on the lower right, like a sunken bevel
				img.set_pixel(x, y, SHADOW if d.x + d.y < 0 else HIGHLIGHT)
			if on and r <= 2.0:
				img.set_pixel(x, y, DARK)
	return img


## The dropdown button: a raised 16 × 16 block with a small black triangle pointing down.
static func _dropdown_arrow() -> ImageTexture:
	var img := _bevel_image(DROPDOWN_BUTTON, DROPDOWN_BUTTON, true, FACE)
	var mid := DROPDOWN_BUTTON / 2 - 1
	for row in 4:
		for x in range(mid - 3 + row, mid + 4 - row):
			img.set_pixel(x, 6 + row, DARK)
	return ImageTexture.create_from_image(img)


## A w × h image of a two-pixel bevel: raised (light top left, dark bottom right) or sunken.
static func _bevel_image(w: int, h: int, raised: bool, face: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(face)
	var outer_tl := HIGHLIGHT if raised else SHADOW
	var inner_tl := LIGHT if raised else DARK
	var outer_br := DARK if raised else HIGHLIGHT
	var inner_br := SHADOW if raised else LIGHT
	for x in w:
		img.set_pixel(x, h - 1, outer_br)
	for y in h:
		img.set_pixel(w - 1, y, outer_br)
	for x in range(1, w - 1):
		img.set_pixel(x, h - 2, inner_br)
	for y in range(1, h - 1):
		img.set_pixel(w - 2, y, inner_br)
	for x in w - 1:
		img.set_pixel(x, 0, outer_tl)
	for y in h - 1:
		img.set_pixel(0, y, outer_tl)
	for x in range(1, w - 2):
		img.set_pixel(x, 1, inner_tl)
	for y in range(1, h - 2):
		img.set_pixel(1, y, inner_tl)
	return img


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
