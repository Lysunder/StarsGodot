class_name ScannerToolbar
extends PanelContainer
## The toolbar over the Scanner (D15): the exclusive views (Normal, Surface Minerals, Mineral
## Concentration, Planet Value, Population), the Planet Names overlay, and zoom in and out.

signal view_chosen(view: GalaxyMap.View)
signal names_toggled(on: bool)
signal zoom_requested(factor: float)

const ZOOM_STEP := 1.25
## [label, view, tooltip]
const VIEWS := [
	["Normal", GalaxyMap.View.NORMAL, "Normal view"],
	["Minerals", GalaxyMap.View.SURFACE_MINERALS, "Surface minerals"],
	["Conc.", GalaxyMap.View.CONCENTRATION, "Mineral concentrations"],
	["Value", GalaxyMap.View.VALUE, "Planet value"],
	["Pop.", GalaxyMap.View.POPULATION, "Population"],
]

var _group := ButtonGroup.new()


func _ready() -> void:
	theme_type_variation = "TileBar"
	var row := HBoxContainer.new()
	add_child(row)
	for spec: Array in VIEWS:
		var b := Button.new()
		b.text = spec[0]
		b.tooltip_text = spec[2]
		b.toggle_mode = true
		b.button_group = _group
		b.focus_mode = Control.FOCUS_NONE
		var view: GalaxyMap.View = spec[1]
		b.toggled.connect(
			func(on: bool) -> void:
				if on:
					view_chosen.emit(view)
		)
		b.button_pressed = view == GalaxyMap.View.NORMAL
		row.add_child(b)
	row.add_child(VSeparator.new())
	var names := Button.new()
	names.text = "Names"
	names.tooltip_text = "Planet names"
	names.toggle_mode = true
	names.focus_mode = Control.FOCUS_NONE
	names.toggled.connect(func(on: bool) -> void: names_toggled.emit(on))
	row.add_child(names)
	row.add_child(VSeparator.new())
	for spec: Array in [["+", ZOOM_STEP, "Zoom in"], ["-", 1.0 / ZOOM_STEP, "Zoom out"]]:
		var b := Button.new()
		b.text = spec[0]
		b.tooltip_text = spec[2]
		b.custom_minimum_size = Vector2(24, 0)
		b.focus_mode = Control.FOCUS_NONE
		var factor: float = spec[1]
		b.pressed.connect(func() -> void: zoom_requested.emit(factor))
		row.add_child(b)
