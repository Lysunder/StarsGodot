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
## What other players see of an owned planet (S15 "Estimates"): its population in units of 400
## colonists (0..4090; 0 when it has none or its owner hides it), and how well its defenses cover
## it, 1..15 (0 without defenses).
var population_estimate: int = 0
var defense_estimate: int = 0
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
var queue: Array[QueueItem] = []
## Only resources left over after the queue go to research (S09).
var leftover_to_research: bool = false
## Random-event artifact (S18).
var artifact: Variant = null
var mod_data: Dictionary = {}

## Turn-only mark: the players whose fleets bombed out the planet this turn (fix B37: they see
## it as the one-fleet message makes the original show it, S17).
var bombed_out_by: Dictionary = {}


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
		["population_estimate", Kind.INT],
		["defense_estimate", Kind.INT],
		["homeworld", Kind.BOOL],
		["has_scanner", Kind.BOOL],
		["starbase", Kind.OBJECT_OR_NULL, Starbase],
		["mass_driver_target", Kind.INT],
		["mass_driver_warp", Kind.INT],
		["route", Kind.INT],
		["queue", Kind.OBJECT_LIST, QueueItem],
		["leftover_to_research", Kind.BOOL],
		["artifact", Kind.JSON],
		["mod_data", Kind.JSON],
	]


## Field by field (the hot path of copying a game; test_model_copies checks it holds every
## schema field).
func _copy_into(out: ModelObject) -> void:
	var o := out as Planet
	o.id = id
	o.name = name
	o.x = x
	o.y = y
	o.owner = owner
	o.environment.assign(environment)
	o.environment_original.assign(environment_original)
	o.concentration.assign(concentration)
	o.concentration_fraction.assign(concentration_fraction)
	o.surface.assign(surface)
	o.population = population
	o.extra_colonists = extra_colonists
	o.mines = mines
	o.factories = factories
	o.defenses = defenses
	o.population_estimate = population_estimate
	o.defense_estimate = defense_estimate
	o.homeworld = homeworld
	o.has_scanner = has_scanner
	o.starbase = null if starbase == null else starbase.copy() as Starbase
	o.mass_driver_target = mass_driver_target
	o.mass_driver_warp = mass_driver_warp
	o.route = route
	for q in queue:
		o.queue.append(q.copy() as QueueItem)
	o.leftover_to_research = leftover_to_research
	o.artifact = (
		artifact.duplicate(true) if artifact is Dictionary or artifact is Array else artifact
	)
	o.mod_data = mod_data.duplicate(true)
