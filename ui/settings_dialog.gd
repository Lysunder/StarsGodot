class_name SettingsDialog
extends AcceptDialog
## Settings (M11 step 10; D15): the interface font (each bundled font with a sample line in it), its
## size (pixel fonts only at their whole-pixel sizes), and the interface size (following the window,
## or a fixed percent). Every change takes effect at once and is saved (UiSettings); Close closes.

const SAMPLE := "Ironium 1,234kT  Warp 9  2401  The quick brown fox jumps over the lazy dog."
const AUTOMATIC := "Fit the window"

var _font_group := ButtonGroup.new()
var _fonts: Array[CheckBox] = []
var _samples: Array[Label] = []
var _size: OptionButton
var _scale: OptionButton
var _loading: bool = false


func _ready() -> void:
	title = "Settings"
	ok_button_text = "Close"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
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
		var theme := ClassicTheme.build(i)
		sample.add_theme_font_override("font", theme.default_font)
		sample.add_theme_font_size_override("font_size", theme.default_font_size)
		fonts.add_child(sample)
		_samples.append(sample)
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


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "BoldLabel"
	return l


## Opens on the saved settings.
func open() -> void:
	_loading = true
	var font := UiSettings.font()
	_fonts[font].button_pressed = true
	_fill_sizes(font, UiSettings.font_size(font))
	_scale.select(_scale.get_item_index(UiSettings.scale()))
	_loading = false
	popup_centered()


## The size list of font `font`, with `pick` chosen (or the font's usual size).
func _fill_sizes(font: int, pick: int) -> void:
	var spec: Dictionary = ClassicTheme.FONTS[font]
	_size.clear()
	for s: int in spec["sizes"]:
		_size.add_item("%d" % s, s)
	var at := _size.get_item_index(pick)
	_size.select(at if at >= 0 else _size.get_item_index(int(spec["size"])))


func _picked_font() -> int:
	return _fonts.find(_font_group.get_pressed_button() as CheckBox)


func _apply() -> void:
	if _loading:
		return
	var font := _picked_font()
	UiSettings.save(font, _size.get_selected_id(), _scale.get_selected_id())
	UiSettings.apply(get_tree())
	reset_size()
