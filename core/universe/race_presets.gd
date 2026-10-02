class_name RacePresets
extends RefCounted
## The race wizard's presets (content type `race_preset`, spec S06 "Race files and presets").

const FIELDS := [
	"primary_trait",
	"lesser_traits",
	"hab_low",
	"hab_center",
	"hab_high",
	"growth_rate",
	"resources_per_colonist",
	"factory_output",
	"factory_cost",
	"factories_operated",
	"mine_output",
	"mine_cost",
	"mines_operated",
	"research_costs",
	"leftover_points",
	"techs_start_at_3",
	"cheap_factories",
	"random",
]


## Preset ids in their `order`.
static func ids(content: ContentRegistry) -> Array[String]:
	var pairs := []
	for id in content.ids("race_preset"):
		pairs.append([int(content.get_def("race_preset", id)["order"]), id])
	pairs.sort()
	var out: Array[String] = []
	for p: Array in pairs:
		out.append(p[1])
	return out


## A new race from a preset, without a name (the player names it). Fields the preset leaves out
## keep a new Race's values (the default preset's).
static func make(content: ContentRegistry, id: String) -> Race:
	var def := content.get_def("race_preset", id)
	var race := Race.new()
	for field: String in FIELDS:
		if not def.has(field):
			continue
		var value: Variant = def[field]
		if value is Array:
			(race.get(field) as Array).assign(value)
		else:
			race.set(field, value)
	return race
