class_name Race
extends ModelObject
## A race definition (spec S06). Habitability per axis (gravity, temperature, radiation): low,
## center and high in 0..100; an immune axis has -1 in all three.

const LEFTOVER := ["surface_minerals", "concentrations", "mines", "factories", "defenses"]

var name: String = ""
var plural_name: String = ""
## Primary trait content id, e.g. "trait.prt.joat".
var primary_trait: String = ""
## Lesser trait content ids, sorted.
var lesser_traits: Array[String] = []
var hab_low: Array[int] = [15, 15, 15]
var hab_center: Array[int] = [50, 50, 50]
var hab_high: Array[int] = [85, 85, 85]
## Maximum yearly growth, percent.
var growth_rate: int = 15
## One resource per (value x 100) colonists.
var resources_per_colonist: int = 10
var factory_output: int = 10
var factory_cost: int = 10
var factories_operated: int = 10
var mine_output: int = 10
var mine_cost: int = 5
var mines_operated: int = 10
## Per tech field, in field order: 0 expensive, 1 normal, 2 cheap (S05).
var research_costs: Array[int] = [1, 1, 1, 1, 1, 1]
var leftover_points: String = "surface_minerals"
var techs_start_at_3: bool = false
var cheap_factories: bool = false
var mod_data: Dictionary = {}


func _schema() -> Array:
	return [
		["name", Kind.STRING],
		["plural_name", Kind.STRING],
		["primary_trait", Kind.STRING],
		["lesser_traits", Kind.STRING_LIST],
		["hab_low", Kind.INT_LIST],
		["hab_center", Kind.INT_LIST],
		["hab_high", Kind.INT_LIST],
		["growth_rate", Kind.INT],
		["resources_per_colonist", Kind.INT],
		["factory_output", Kind.INT],
		["factory_cost", Kind.INT],
		["factories_operated", Kind.INT],
		["mine_output", Kind.INT],
		["mine_cost", Kind.INT],
		["mines_operated", Kind.INT],
		["research_costs", Kind.INT_LIST],
		["leftover_points", Kind.ENUM, LEFTOVER],
		["techs_start_at_3", Kind.BOOL],
		["cheap_factories", Kind.BOOL],
		["mod_data", Kind.JSON],
	]


func is_immune(axis: int) -> bool:
	return hab_low[axis] == -1
