class_name Planet
extends ModelObject
## A planet (spec S03, economy fields S08). Mineral lists are ironium, boranium, germanium;
## environment lists are gravity, temperature, radiation.

var id: int = 0
var name: String = ""
var x: int = 0
var y: int = 0
## Player index, or -1 when unowned.
var owner: int = -1
var environment: Array[int] = [50, 50, 50]
## Environment before any terraforming.
var environment_original: Array[int] = [50, 50, 50]
## 0..255 per mineral.
var concentration: Array[int] = [0, 0, 0]
## The fraction byte mining uses, per mineral (S08).
var concentration_fraction: Array[int] = [0, 0, 0]
## kT per mineral.
var surface: Array[int] = [0, 0, 0]
## Units of 100 colonists.
var population: int = 0
## 0..99 single colonists on top of population.
var extra_colonists: int = 0
var mines: int = 0
var factories: int = 0
var defenses: int = 0
var homeworld: bool = false
## A planetary scanner has been built (S15).
var has_scanner: bool = false
var starbase: Starbase = null
## Packet destination planet id (-1 = none) and the mass driver's warp setting (S09, S14).
var mass_driver_target: int = -1
var mass_driver_warp: int = 0
## Route destination for new fleets: planet id or -1 (S11).
var route: int = -1
## Production queue (S09).
var queue: Array = []
## Only resources left over after the queue go to research (S09).
var leftover_to_research: bool = false
## Random-event artifact (S18).
var artifact: Variant = null
var mod_data: Dictionary = {}


func _schema() -> Array:
	return [
		["id", Kind.INT],
		["name", Kind.STRING],
		["x", Kind.INT],
		["y", Kind.INT],
		["owner", Kind.INT],
		["environment", Kind.INT_LIST],
		["environment_original", Kind.INT_LIST],
		["concentration", Kind.INT_LIST],
		["concentration_fraction", Kind.INT_LIST],
		["surface", Kind.INT_LIST],
		["population", Kind.INT],
		["extra_colonists", Kind.INT],
		["mines", Kind.INT],
		["factories", Kind.INT],
		["defenses", Kind.INT],
		["homeworld", Kind.BOOL],
		["has_scanner", Kind.BOOL],
		["starbase", Kind.OBJECT_OR_NULL, Starbase],
		["mass_driver_target", Kind.INT],
		["mass_driver_warp", Kind.INT],
		["route", Kind.INT],
		["queue", Kind.JSON],
		["leftover_to_research", Kind.BOOL],
		["artifact", Kind.JSON],
		["mod_data", Kind.JSON],
	]
