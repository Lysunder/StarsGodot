class_name HabEditor
extends VBoxContainer
## The race wizard's habitability page body (D15; the original's arrangement): per axis a row with
## its name, a left arrow, the black bar with the habitable range as a coloured band (drag it to
## move the range), a right arrow and the range in the game's units; under it buttons to widen or
## narrow the range and the "Immune" box. Shift makes an arrow step 10. Then the growth rate with
## its arrows and the share of planets the race can live on (RaceEditing).

## The race changed.
signal changed

const LABELS := ["Gravity", "Temperature", "Radiation"]
const BAR_SIZE := Vector2(300, 22)
const LABEL_WIDTH := 100
const RANGE_WIDTH := 170

var race: Race
var _bars: Array[HabBar] = []
var _ranges: Array[Label] = []
var _immune: Array[CheckBox] = []
var _arrows: Array[Button] = []
var _growth: Label
var _odds: Label


func _init() -> void:
	add_theme_constant_override("separation", 4)
	for axis in 3:
		var row := HBoxContainer.new()
		add_child(row)
		var label_text := Label.new()
		label_text.text = LABELS[axis]
		label_text.theme_type_variation = "BoldLabel"
		label_text.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
		row.add_child(label_text)
		row.add_child(_arrow("◄", func() -> void: _adjust(axis, -1, 0)))
		var bar := HabBar.new(axis)
		bar.custom_minimum_size = BAR_SIZE
		bar.dragged.connect(
			func(at: int) -> void:
				RaceEditing.drag(race, axis, at)
				_changed()
		)
		row.add_child(bar)
		_bars.append(bar)
		row.add_child(_arrow("►", func() -> void: _adjust(axis, 1, 0)))
		var range_label := Label.new()
		range_label.custom_minimum_size = Vector2(RANGE_WIDTH, 0)
		row.add_child(range_label)
		_ranges.append(range_label)
		var under := HBoxContainer.new()
		add_child(under)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
		under.add_child(pad)
		var widen := _arrow("◄ Widen ►", func() -> void: _adjust(axis, 0, 1))
		under.add_child(widen)
		var immune := CheckBox.new()
		immune.text = "Immune to " + LABELS[axis]
		immune.toggled.connect(
			func(on: bool) -> void:
				RaceEditing.set_immune(race, axis, on)
				_changed()
		)
		under.add_child(immune)
		_immune.append(immune)
		var narrow := _arrow("► Narrow ◄", func() -> void: _adjust(axis, 0, -1))
		under.add_child(narrow)
		add_child(HSeparator.new())
	var growth := HBoxContainer.new()
	add_child(growth)
	_growth = Label.new()
	growth.add_child(_growth)
	growth.add_child(_arrow("▲", func() -> void: _grow(1)))
	growth.add_child(_arrow("▼", func() -> void: _grow(-1)))
	_odds = Label.new()
	add_child(_odds)


func _arrow(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	_arrows.append(b)
	return b


func _step() -> int:
	return 10 if Input.is_key_pressed(KEY_SHIFT) else 1


func _adjust(axis: int, shift: int, widen: int) -> void:
	RaceEditing.adjust(race, axis, shift * _step(), widen * _step())
	_changed()


func _grow(by: int) -> void:
	race.growth_rate = clampi(race.growth_rate + by, 1, 20)
	_changed()


func _changed() -> void:
	refresh()
	changed.emit()


## Shows `race` (edited in place); `editable` false shows it only.
func show_race(p_race: Race, editable: bool = true) -> void:
	race = p_race
	for b in _arrows:
		b.disabled = not editable
	for c in _immune:
		c.disabled = not editable
	for bar in _bars:
		bar.editable = editable
	refresh()


func refresh() -> void:
	for axis in 3:
		var immune := race.is_immune(axis)
		_immune[axis].set_pressed_no_signal(immune)
		_bars[axis].race = race
		_bars[axis].queue_redraw()
		_ranges[axis].text = (
			"Immune"
			if immune
			else (
				"%s to %s"
				% [
					EnvironmentUnits.format(axis, race.hab_low[axis]),
					EnvironmentUnits.format(axis, race.hab_high[axis]),
				]
			)
		)
	_growth.text = tr("Most colonist growth a year: %d%%") % race.growth_rate
	var odds := RaceEditing.habitable_odds(race)
	if odds == 0:
		_odds.text = "Every planet will be habitable to your race."
	elif odds == 1:
		_odds.text = "Nearly every planet will be habitable to your race."
	else:
		_odds.text = tr("About 1 planet in %d will be habitable to your race.") % odds
