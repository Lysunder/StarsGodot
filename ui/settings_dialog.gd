class_name SettingsDialog
extends AcceptDialog
## Settings (M11 step 10; D15), two tabs. Display: the interface font (each bundled font with a
## sample line in it), its size (pixel fonts only at their whole-pixel sizes), the interface size
## (following the window, or a fixed percent) and the colours (Palette: standard, or safe for
## red-green or blue-yellow colour blindness, with a sample of the colours that carry meaning).
## Keys: each shortcut with its key; click one and press the new key (Escape keeps the old one,
## Delete or Backspace clears it; a key taken from another action leaves that one without).
## Every change takes effect at once and is saved (UiSettings, KeyBindings); Close closes.

const SAMPLE := "Ironium 1,234kT  Warp 9  2401  The quick brown fox jumps over the lazy dog."
const AUTOMATIC := "Fit the window"
const WAITING := "Press a key..."
## The colours the palette sample shows: [role, label].
const SWATCHES := [
	[Palette.MINE, "Yours"],
	[Palette.OTHER, "Others'"],
	[Palette.FLEET, "Fleets"],
	[Palette.TEXT_GOOD, "Good"],
	[Palette.TEXT_POOR, "Poor"],
	[Palette.TEXT_BAD, "Bad"],
	[Palette.IRONIUM, "Ironium"],
	[Palette.BORANIUM, "Boranium"],
	[Palette.GERMANIUM, "Germanium"],
]
const SWATCH := Vector2(14, 14)

var _font_group := ButtonGroup.new()
var _fonts: Array[CheckBox] = []
var _size: OptionButton
var _scale: OptionButton
var _palette: OptionButton
var _language: OptionButton
var _locales: PackedStringArray = []
var _swatches: HFlowContainer
var _keys: Array[Button] = []
## The action waiting for its new key (-1 none).
var _capturing: int = -1
var _loading: bool = false


func _ready() -> void:
	title = "Settings"
	ok_button_text = "Close"
	var tabs := TabContainer.new()
	add_child(tabs)
	var display := _build_display()
	display.name = "Display"
	tabs.add_child(display)
	var keys := _build_keys()
	keys.name = "Keys"
	tabs.add_child(keys)
	window_input.connect(_on_window_input)
	visibility_changed.connect(func() -> void: _stop_capture())


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "BoldLabel"
	return l


func _build_display() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(_heading("Font"))
	var frame := PanelContainer.new()
	frame.theme_type_variation = "SunkenField"
	box.add_child(frame)
	var fonts := VBoxContainer.new()
	frame.add_child(fonts)
	for i in ClassicTheme.FONTS.size():
		var spec: Dictionary = ClassicTheme.FONTS[i]
		var r := CheckBox.new()
		r.text = spec["name"]
		r.button_group = _font_group
		r.toggled.connect(
			func(on: bool) -> void:
				if on and not _loading:
					_fill_sizes(i, int(spec["size"]))
					_apply()
		)
		fonts.add_child(r)
		_fonts.append(r)
		# the sample is drawn in that font, so each choice shows itself
		var sample := Label.new()
		sample.text = "    " + SAMPLE
		var theme_id := ClassicTheme.build(i)
		sample.add_theme_font_override("font", theme_id.default_font)
		sample.add_theme_font_size_override("font_size", theme_id.default_font_size)
		fonts.add_child(sample)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	grid.add_child(_heading("Font size"))
	_size = OptionButton.new()
	_size.item_selected.connect(func(_i: int) -> void: _apply())
	grid.add_child(_size)
	grid.add_child(_heading("Interface size"))
	_scale = OptionButton.new()
	_scale.add_item(AUTOMATIC, 0)
	for percent: int in UiSettings.SCALES:
		_scale.add_item("%d%%" % percent, percent)
	_scale.item_selected.connect(func(_i: int) -> void: _apply())
	grid.add_child(_scale)
	grid.add_child(_heading("Colours"))
	_palette = OptionButton.new()
	for label_text: String in Palette.MODE_NAMES:
		_palette.add_item(label_text)
	_palette.item_selected.connect(
		func(i: int) -> void:
			if not _loading:
				UiSettings.save_palette(Palette.MODES[i])
				_apply()
	)
	grid.add_child(_palette)
	grid.add_child(_heading("Language"))
	_language = OptionButton.new()
	_language.item_selected.connect(
		func(i: int) -> void:
			if not _loading:
				UiLocale.save(_locales[i])
				UiLocale.apply(GameSession.content, _locales[i])
				_apply()
	)
	grid.add_child(_language)
	_swatches = HFlowContainer.new()
	box.add_child(_swatches)
	return box


func _build_keys() -> Control:
	var box := VBoxContainer.new()
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for i in KeyBindings.ACTIONS.size():
		grid.add_child(_heading(KeyBindings.ACTIONS[i][1]))
		var b := Button.new()
		b.custom_minimum_size = Vector2(140, 0)
		b.pressed.connect(
			func() -> void:
				_stop_capture()
				_capturing = i
				b.text = WAITING
		)
		grid.add_child(b)
		_keys.append(b)
	var reset := Button.new()
	reset.text = "Reset to the usual keys"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(
		func() -> void:
			KeyBindings.reset()
			_keys_changed()
	)
	box.add_child(reset)
	return box


## Opens on the saved settings.
func open() -> void:
	_loading = true
	var font := UiSettings.font()
	_fonts[font].button_pressed = true
	_fill_sizes(font, UiSettings.font_size(font))
	_scale.select(_scale.get_item_index(UiSettings.scale()))
	_palette.select(Palette.MODES.find(UiSettings.palette()))
	_locales = UiLocale.locales(GameSession.content)
	_language.clear()
	for loc in _locales:
		_language.add_item(UiLocale.display_name(loc))
	_language.select(maxi(_locales.find(GameSession.content.locale), 0))
	_loading = false
	_show_swatches()
	_show_keys()
	popup_centered()


## The size list of font `font`, with `pick` chosen (or the font's usual size).
func _fill_sizes(font: int, pick: int) -> void:
	var spec: Dictionary = ClassicTheme.FONTS[font]
	_size.clear()
	for s: int in spec["sizes"]:
		_size.add_item("%d" % s, s)
	var at := _size.get_item_index(pick)
	_size.select(at if at >= 0 else _size.get_item_index(int(spec["size"])))


func _show_swatches() -> void:
	for child in _swatches.get_children():
		child.queue_free()
	for s: Array in SWATCHES:
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = SWATCH
		swatch.color = Palette.color(s[0])
		row.add_child(swatch)
		var l := Label.new()
		l.text = s[1]
		row.add_child(l)
		_swatches.add_child(row)


func _show_keys() -> void:
	for i in _keys.size():
		_keys[i].text = KeyBindings.text(KeyBindings.key(KeyBindings.ACTIONS[i][0]))


func _picked_font() -> int:
	return _fonts.find(_font_group.get_pressed_button() as CheckBox)


func _apply() -> void:
	if _loading:
		return
	UiSettings.save(_picked_font(), _size.get_selected_id(), _scale.get_selected_id())
	UiSettings.apply(get_tree())
	_show_swatches()
	reset_size()


func _keys_changed() -> void:
	_show_keys()
	# the game screen takes the new keys when the theme is rebuilt
	UiSettings.apply(get_tree())


func _stop_capture() -> void:
	if _capturing >= 0:
		_capturing = -1
		_show_keys()


## While a key is awaited, the next key press becomes the action's key.
func _on_window_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if _capturing < 0 or k == null or not k.pressed or k.echo:
		return
	set_input_as_handled()
	var id: String = KeyBindings.ACTIONS[_capturing][0]
	match k.keycode:
		KEY_ESCAPE:
			_stop_capture()
			return
		KEY_DELETE, KEY_BACKSPACE:
			KeyBindings.set_key(id, 0)
		_:
			var code := KeyBindings.code_of(k)
			if code == 0:
				return
			KeyBindings.set_key(id, code)
	_capturing = -1
	_keys_changed()
