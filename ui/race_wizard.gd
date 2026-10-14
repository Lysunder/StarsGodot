class_name RaceWizard
extends AcceptDialog
## The race wizard (M11 step 9; D15, the original's six steps, `RunRaceWizard@10d8:0000`): 1 the
## names, a preset to start from and what leftover points buy; 2 the primary racial trait; 3 the
## lesser racial traits; 4 habitability and growth (HabEditor); 5 the economy; 6 research costs.
## Every step shows the advantage points left (RaceMath, S06); Back, Next, Finish and Cancel along
## the bottom. Finish checks the race (`RaceMath.wizard_problems`) and hands it over; the Random
## preset makes a race rolled when the game is created, so its other steps are skipped.

signal race_finished(race: Race)

const STEPS := [
	"Name and Starting Point",
	"Primary Racial Trait",
	"Lesser Racial Traits",
	"Habitability and Growth",
	"Economy",
	"Research Costs",
]
const LEFTOVER_LABELS := [
	"Surface minerals", "Mineral concentrations", "Mines", "Factories", "Defenses"
]
const RESEARCH_LABELS := ["75% more", "Normal", "50% less"]
const CUSTOM := "custom"
const NAME_MAX := 31
const PAGE_SIZE := Vector2(700, 430)
const DESCRIPTION_WIDTH := 300
const BAD := Color("a00000")
## Economy rows: [race field, label, spin multiplier].
const ECONOMY_ROWS := [
	["resources_per_colonist", "Colonists needed for one resource a year:", 100],
	["factory_output", "Resources 10 factories make a year:", 1],
	["factory_cost", "Resources to build a factory:", 1],
	["factories_operated", "Factories that 10,000 colonists can run:", 1],
	["mine_output", "Kilotons of each mineral 10 mines dig a year:", 1],
	["mine_cost", "Resources to build a mine:", 1],
	["mines_operated", "Mines that 10,000 colonists can run:", 1],
]

var race: Race
var step: int = 0

var _content: ContentRegistry
var _loading: bool = false
var _pages: Array[Control] = []
var _heading: Label
var _points: Label
var _status: Label
var _back: Button
var _next: Button
var _finish: Button
var _name: LineEdit
var _plural: LineEdit
var _preset_group := ButtonGroup.new()
var _presets: Array[CheckBox] = []
var _preset_ids: Array[String] = []
var _leftover: OptionButton
var _prt_group := ButtonGroup.new()
var _prts: Array[CheckBox] = []
var _prt_ids: Array[String] = []
var _prt_text: Label
var _lrts: Array[CheckBox] = []
var _lrt_ids: Array[String] = []
var _lrt_text: Label
var _hab: HabEditor
var _economy: Array[SpinBox] = []
var _economy_labels: Array[Label] = []
var _cheap: CheckBox
var _research: Array[Array] = []
var _start_at_3: CheckBox


func _ready() -> void:
	_content = GameSession.content
	get_ok_button().hide()
	var box := VBoxContainer.new()
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	_heading = Label.new()
	_heading.theme_type_variation = "BoldLabel"
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_heading)
	_points = Label.new()
	_points.theme_type_variation = "BoldLabel"
	top.add_child(_points)
	var frame := PanelContainer.new()
	frame.theme_type_variation = "SunkenField"
	frame.custom_minimum_size = PAGE_SIZE
	box.add_child(frame)
	var stack := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		stack.add_theme_constant_override("margin_" + side, 8)
	frame.add_child(stack)
	for build: Callable in [
		_build_names, _build_prt, _build_lrt, _build_hab, _build_economy, _build_research
	]:
		var page: Control = build.call()
		stack.add_child(page)
		_pages.append(page)
	_status = Label.new()
	_status.add_theme_color_override("font_color", BAD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(PAGE_SIZE.x, 0)
	box.add_child(_status)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(bottom)
	_button(bottom, "Cancel", hide)
	_back = _button(bottom, "< Back", func() -> void: _go(step - 1))
	_next = _button(bottom, "Next >", func() -> void: _go(step + 1))
	_finish = _button(bottom, "Finish", _on_finish)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(80, 0)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _label(text: String, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	if bold:
		l.theme_type_variation = "BoldLabel"
	return l


func _description() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(DESCRIPTION_WIDTH, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return l


## Trait ids of a kind ("primary" or "lesser") in their order.
func _traits(kind: String) -> Array[String]:
	var pairs := []
	for id in _content.ids("trait"):
		var def := _content.get_def("trait", id)
		if def.get("kind", "") == kind:
			pairs.append([int(def.get("order", 0)), id])
	pairs.sort()
	var out: Array[String] = []
	for p: Array in pairs:
		out.append(p[1])
	return out


func _build_names() -> Control:
	var page := VBoxContainer.new()
	var grid := GridContainer.new()
	grid.columns = 2
	page.add_child(grid)
	grid.add_child(_label("Race name:"))
	_name = LineEdit.new()
	_name.max_length = NAME_MAX
	_name.custom_minimum_size = Vector2(240, 0)
	_name.text_changed.connect(
		func(t: String) -> void:
			race.name = t.strip_edges()
			_refresh_points()
	)
	grid.add_child(_name)
	grid.add_child(_label("Plural race name:"))
	_plural = LineEdit.new()
	_plural.max_length = NAME_MAX
	_plural.text_changed.connect(func(t: String) -> void: race.plural_name = t.strip_edges())
	grid.add_child(_plural)
	page.add_child(HSeparator.new())
	page.add_child(_label("Start from:", true))
	var presets := GridContainer.new()
	presets.columns = 2
	page.add_child(presets)
	_preset_ids = RacePresets.ids(_content)
	_preset_ids.append(CUSTOM)
	for id in _preset_ids:
		var r := CheckBox.new()
		r.button_group = _preset_group
		r.text = "Custom" if id == CUSTOM else _content.display_name(id)
		r.toggled.connect(
			func(on: bool) -> void:
				if on and not _loading:
					_use_preset(id)
		)
		presets.add_child(r)
		_presets.append(r)
	page.add_child(HSeparator.new())
	var leftover := HBoxContainer.new()
	page.add_child(leftover)
	leftover.add_child(_label("Spend up to 50 leftover advantage points on:"))
	_leftover = OptionButton.new()
	for l: String in LEFTOVER_LABELS:
		_leftover.add_item(l)
	_leftover.item_selected.connect(
		func(i: int) -> void:
			race.leftover_points = Race.LEFTOVER[i]
			_changed()
	)
	leftover.add_child(_leftover)
	return page


func _build_prt() -> Control:
	var page := HBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	var list := VBoxContainer.new()
	page.add_child(list)
	_prt_ids = _traits("primary")
	for id in _prt_ids:
		var r := CheckBox.new()
		r.button_group = _prt_group
		r.text = _content.display_name(id)
		r.toggled.connect(
			func(on: bool) -> void:
				if on and not _loading:
					race.primary_trait = id
					_changed()
				if on:
					_prt_text.text = _content.string_for(id + ".description")
		)
		list.add_child(r)
		_prts.append(r)
	_prt_text = _description()
	page.add_child(_prt_text)
	return page


func _build_lrt() -> Control:
	var page := VBoxContainer.new()
	var grid := GridContainer.new()
	grid.columns = 2
	page.add_child(grid)
	_lrt_ids = _traits("lesser")
	for id in _lrt_ids:
		var c := CheckBox.new()
		c.text = _content.display_name(id)
		c.toggled.connect(
			func(on: bool) -> void:
				_lrt_text.text = (
					_content.display_name(id) + ": " + _content.string_for(id + ".description")
				)
				if _loading:
					return
				if on and not race.lesser_traits.has(id):
					race.lesser_traits.append(id)
					race.lesser_traits.sort()
				elif not on:
					race.lesser_traits.erase(id)
				_changed()
		)
		c.mouse_entered.connect(
			func() -> void:
				_lrt_text.text = (
					_content.display_name(id) + ": " + _content.string_for(id + ".description")
				)
		)
		grid.add_child(c)
		_lrts.append(c)
	page.add_child(HSeparator.new())
	_lrt_text = _description()
	page.add_child(_lrt_text)
	return page


func _build_hab() -> Control:
	_hab = HabEditor.new()
	_hab.changed.connect(_changed)
	return _hab


func _build_economy() -> Control:
	var page := VBoxContainer.new()
	var grid := GridContainer.new()
	grid.columns = 2
	page.add_child(grid)
	for row: Array in ECONOMY_ROWS:
		var field: String = row[0]
		var times: int = row[2]
		var label := _label(row[1])
		grid.add_child(label)
		_economy_labels.append(label)
		var spin := SpinBox.new()
		spin.custom_minimum_size = Vector2(90, 0)
		spin.min_value = _content.constant("constant.race.%s_min" % field) * times
		spin.max_value = _content.constant("constant.race.%s_max" % field) * times
		spin.step = times
		spin.value_changed.connect(
			func(v: float) -> void:
				if _loading:
					return
				race.set(field, int(v) / times)
				_changed()
		)
		grid.add_child(spin)
		_economy.append(spin)
	_cheap = CheckBox.new()
	_cheap.text = "Factories need 1kT less germanium to build"
	_cheap.toggled.connect(
		func(on: bool) -> void:
			if not _loading:
				race.cheap_factories = on
				_changed()
	)
	page.add_child(_cheap)
	return page


func _build_research() -> Control:
	var page := VBoxContainer.new()
	var grid := GridContainer.new()
	grid.columns = 4
	page.add_child(grid)
	var fields := _content.ids("tech_field")
	var ordered := []
	for id in fields:
		ordered.append([int(_content.get_def("tech_field", id).get("order", 0)), id])
	ordered.sort()
	for f in ordered.size():
		grid.add_child(_label(_content.display_name(ordered[f][1]), true))
		var group := ButtonGroup.new()
		var row: Array[CheckBox] = []
		# the radios left to right: expensive (0), normal (1), cheap (2), as the race stores them
		for cost in 3:
			var r := CheckBox.new()
			r.button_group = group
			r.text = RESEARCH_LABELS[cost]
			r.toggled.connect(
				func(on: bool) -> void:
					if on and not _loading:
						race.research_costs[f] = cost
						_changed()
			)
			grid.add_child(r)
			row.append(r)
		_research.append(row)
	page.add_child(HSeparator.new())
	_start_at_3 = CheckBox.new()
	_start_at_3.text = "Fields that cost 75% more start at tech 3"
	_start_at_3.toggled.connect(
		func(on: bool) -> void:
			if not _loading:
				race.techs_start_at_3 = on
				_changed()
	)
	page.add_child(_start_at_3)
	return page


## Opens the wizard on a copy of `base` (a preset or a saved race) at step 1.
func open(base: Race) -> void:
	race = base.copy() as Race
	_status.text = ""
	_load_all()
	_go(0)
	popup_centered()


func _use_preset(id: String) -> void:
	if id == CUSTOM:
		return
	var keep_name := race.name
	var keep_plural := race.plural_name
	race = RacePresets.make(_content, id)
	race.name = keep_name
	race.plural_name = keep_plural
	_load_all()
	_go(step)


## Any change after a preset makes the race a custom one.
func _changed() -> void:
	if not race.random:
		_loading = true
		_presets[_preset_ids.size() - 1].button_pressed = true
		_loading = false
	_refresh_points()


func _load_all() -> void:
	_loading = true
	_name.text = race.name
	_plural.text = race.plural_name
	var preset := _matching_preset()
	_presets[_preset_ids.find(preset)].button_pressed = true
	_leftover.select(Race.LEFTOVER.find(race.leftover_points))
	var prt := _prt_ids.find(race.primary_trait)
	if prt >= 0:
		_prts[prt].button_pressed = true
	for i in _lrt_ids.size():
		_lrts[i].button_pressed = race.lesser_traits.has(_lrt_ids[i])
	_lrt_text.text = ""
	_hab.show_race(race)
	for i in ECONOMY_ROWS.size():
		_economy[i].value = int(race.get(ECONOMY_ROWS[i][0])) * int(ECONOMY_ROWS[i][2])
	_cheap.button_pressed = race.cheap_factories
	for f in _research.size():
		(_research[f][race.research_costs[f]] as CheckBox).button_pressed = true
	_start_at_3.button_pressed = race.techs_start_at_3
	_loading = false
	_refresh_points()


## The preset the race is exactly (ignoring its names), else "custom".
func _matching_preset() -> String:
	for id in _preset_ids:
		if id == CUSTOM:
			continue
		var p := RacePresets.make(_content, id)
		p.name = race.name
		p.plural_name = race.plural_name
		p.logo = race.logo
		if p.to_dict() == race.to_dict():
			return id
	return CUSTOM


func _go(to: int) -> void:
	step = clampi(to, 0, STEPS.size() - 1)
	if race.random:
		step = 0
	for i in _pages.size():
		_pages[i].visible = i == step
	title = "Race Wizard - Step %d of %d" % [step + 1, STEPS.size()]
	_heading.text = STEPS[step]
	_back.disabled = step == 0
	_next.disabled = step == STEPS.size() - 1 or race.random
	if step == 4:
		var ar := RaceMath.trait_param(race, _content, "colony.skips_auto_factories", 0) != 0
		_cheap.disabled = ar
		_economy_labels[0].text = (
			"Orbital economy, resources grow with √(colonists × Energy tech ÷ this):"
			if ar
			else ECONOMY_ROWS[0][1]
		)
	_refresh_points()


func _refresh_points() -> void:
	if race.random:
		_points.text = "Advantage points left: chosen when the game starts"
		_points.remove_theme_color_override("font_color")
		return
	var left := RaceMath.advantage_points(race, _content)
	_points.text = "Advantage points left: %d" % left
	if left < 0:
		_points.add_theme_color_override("font_color", BAD)
	else:
		_points.remove_theme_color_override("font_color")


func _on_finish() -> void:
	if race.plural_name == "" and race.name != "":
		race.plural_name = race.name
	var problems := RaceMath.wizard_problems(race, _content)
	if not problems.is_empty():
		if race.name == "" and not race.random:
			_status.text = "Give your race a name in step 1."
		elif RaceMath.advantage_points(race, _content) < 0:
			_status.text = "The race spends more advantage points than it has."
		else:
			_status.text = "The race can't be used yet: " + "; ".join(problems)
		return
	hide()
	race_finished.emit(race)
